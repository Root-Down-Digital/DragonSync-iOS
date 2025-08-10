#if !defined(ARDUINO_ARCH_ESP32)
#error "This program requires an ESP32"
#endif

#include <Arduino.h>
#include <esp_wifi.h>
#include <esp_event.h>
#include <nvs_flash.h>
#include <WiFi.h>
#include <WebServer.h>
#include <esp_timer.h>
#include <WiFiServer.h>
#include <WiFiClient.h>
#include "opendroneid.h"
#include "odid_wifi.h"

static ODID_UAS_Data UAS_data;
static QueueHandle_t droneDataQueue;
static TaskHandle_t ProcessorTask;

struct queued_packet {
  wifi_promiscuous_pkt_t packet;
  uint8_t payload[512]; // Adjust size as we need
  int length;
};

struct uav_data
{
  uint8_t mac[6];
  uint8_t padding[1];
  int8_t rssi;  
  char op_id[ODID_ID_SIZE + 1];
  char uav_id[ODID_ID_SIZE + 1];
  double lat_d;
  double long_d;
  double base_lat_d;
  double base_long_d;
  int altitude_msl;
  int height_agl;
  int speed;
  int heading;
  int speed_vertical;
  int altitude_pressure;
  int horizontal_accuracy;
  int vertical_accuracy;
  int baro_accuracy;
  int speed_accuracy;
  int timestamp;
  int status;
  int height_type;
  int operator_location_type;
  int classification_type;
  int area_count;
  int area_radius;
  int area_ceiling;
  int area_floor;
  int operator_altitude_geo;
  uint32_t system_timestamp;
  int operator_id_type;
  uint8_t ua_type;
  uint8_t auth_type;
  uint8_t auth_page;
  uint8_t auth_length;
  uint32_t auth_timestamp;
  char auth_data[ODID_AUTH_PAGE_NONZERO_DATA_SIZE + 1];
  uint8_t desc_type;
  char description[ODID_STR_SIZE + 1];
};

const char* ap_ssid = "Dr4g0net";
const char* ap_password = "wardragon1234";

WebServer server(80);
WiFiServer telemetryServer(4224);

TaskHandle_t ScannerTask;
TaskHandle_t WebServerTask;
TaskHandle_t ZMQTask;

static String latestDroneData = "";
static int packetCount = 0;
static unsigned long last_status = 0;
static SemaphoreHandle_t dataMutex;

std::vector<WiFiClient> telemetryClients;
static SemaphoreHandle_t clientMutex;

static esp_err_t scanner_event_handler(void *, system_event_t *);
static void callback(void *, wifi_promiscuous_pkt_type_t);
static void parse_odid(struct uav_data *, ODID_UAS_Data *);
static void parse_french_id(struct uav_data *, uint8_t *);
static void store_mac(struct uav_data *uav, uint8_t *payload);
static String create_json_response(struct uav_data *UAV, int index);
static void update_latest_data(struct uav_data *UAV, int index);
static void publishToZMQClients(const String& data, bool isStatus);
static String create_status_json();
static void sendZMTPGreeting(WiFiClient& client);
static void sendZMTPMessage(WiFiClient& client, const String& message);
static void publishToZMTPClients(const String& data);
static float getESP32Temperature();
static String create_status_json();
WiFiServer statusServer(4225);
TaskHandle_t StatusTask;

void ZMQTaskCode(void *pvParameters) {
  Serial.println("ZMTP task starting on core " + String(xPortGetCoreID()));
  
  clientMutex = xSemaphoreCreateMutex();
  
  telemetryServer.begin();
  telemetryServer.setNoDelay(true);
  
  Serial.println("ZMTP telemetry server started on port 4224");
  
  unsigned long lastStatusPublish = 0;
  
  for(;;) {
    WiFiClient newTelemetryClient = telemetryServer.available();
    if (newTelemetryClient) {
      Serial.println("New telemetry client connected");
      newTelemetryClient.setNoDelay(true);
      sendZMTPGreeting(newTelemetryClient);
      if (xSemaphoreTake(clientMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        telemetryClients.push_back(newTelemetryClient);
        xSemaphoreGive(clientMutex);
      }
    }

    // Clean up disconnected clients
    if (xSemaphoreTake(clientMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
      for (auto it = telemetryClients.begin(); it != telemetryClients.end();) {
        if (!it->connected()) {
          it->stop();
          it = telemetryClients.erase(it);
          Serial.println("Telemetry client disconnected");
        } else {
          ++it;
        }
      }
      xSemaphoreGive(clientMutex);
    }
    
    unsigned long currentTime = millis();
    if (currentTime - lastStatusPublish > 30000) {  // Every 30 seconds
      String statusJson = create_status_json();
      publishToZMTPClients(statusJson);  // Send esp32 system stats
      lastStatusPublish = currentTime;
    }
    
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

static void sendZMTPGreeting(WiFiClient& client) {
  if (!client.connected()) return;
  
  // ZMTP greeting: anonymous identity (empty string)
  uint8_t greeting[2] = {0x01, 0x00}; // length=1, flags=0 (final frame)
  client.write(greeting, 2);
  client.flush();
}

static void sendZMTPMessage(WiFiClient& client, const String& message) {
  if (!client.connected()) return;
  
  uint32_t msgLen = message.length();
  
  // ZMTP frame format: [length][flags][body]
  if (msgLen < 255) {
    // Short frame: length as single byte
    uint8_t shortLen = (uint8_t)(msgLen + 1); // +1 for flags byte
    uint8_t flags = 0x00; // Final frame, no more frames
    
    client.write(&shortLen, 1);
    client.write(&flags, 1);
    client.write((const uint8_t*)message.c_str(), msgLen);
  } else {
    // Long frame: 0xFF + 8-byte length
    uint8_t longMarker = 0xFF;
    uint64_t longLen = msgLen + 1; // +1 for flags byte
    uint8_t flags = 0x00; // Final frame
    
    client.write(&longMarker, 1);
    
    // Write 64-bit length in network byte order
    for (int i = 7; i >= 0; i--) {
      uint8_t byte = (longLen >> (i * 8)) & 0xFF;
      client.write(&byte, 1);
    }
    
    client.write(&flags, 1);
    client.write((const uint8_t*)message.c_str(), msgLen);
  }
  
  client.flush();
}

static void publishToZMTPClients(const String& data) {
  if (xSemaphoreTake(clientMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
    for (auto it = telemetryClients.begin(); it != telemetryClients.end();) {
      if (it->connected()) {
        sendZMTPMessage(*it, data);
        ++it;
      } else {
        it->stop();
        it = telemetryClients.erase(it);
      }
    }
    xSemaphoreGive(clientMutex);
  }
}

static String create_status_json() {
  unsigned long uptime_seconds = esp_timer_get_time() / 1000000UL;
  float esp32_temp_c = getESP32Temperature();
  float esp32_temp_f = (esp32_temp_c * 9.0/5.0) + 32.0;
  
  String json = "{";
  json += "\"serial_number\":\"Dr4g0net\",";
  json += "\"system_stats\":{";
  json += "\"memory\":{";
  json += "\"total\":" + String(ESP.getHeapSize()) + ",";
  json += "\"available\":" + String(ESP.getFreeHeap()) + ",";
  json += "\"used\":" + String(ESP.getHeapSize() - ESP.getFreeHeap()) + ",";
  json += "\"percent\":" + String((float)(ESP.getHeapSize() - ESP.getFreeHeap()) / ESP.getHeapSize() * 100.0, 1);
  json += "},";
  json += "\"uptime\":" + String(uptime_seconds) + ",";
  json += "\"esp32_temperature_c\":" + String(esp32_temp_c, 1) + ",";
  json += "\"esp32_temperature_f\":" + String(esp32_temp_f, 1) + ",";
  json += "\"temperature\":" + String(esp32_temp_c, 1) + ",";  // for the app to grab temp
  json += "\"packet_count\":" + String(packetCount) + ",";
  json += "\"cpu_freq\":" + String(ESP.getCpuFreqMHz()) + ",";
  json += "\"flash_size\":" + String(ESP.getFlashChipSize() / 1024) + ",";
  json += "\"sdk_version\":\"" + String(ESP.getSdkVersion()) + "\"";
  json += "}";
  json += "}";
  
  return json;
}

void StatusTaskCode(void *pvParameters) {
  Serial.println("Status server task starting on core " + String(xPortGetCoreID()));
  
  statusServer.begin();
  statusServer.setNoDelay(true);
  
  Serial.println("Status server started on port 4225");
  
  std::vector<WiFiClient> statusClients;
  
  for(;;) {
    // Accept new clients
    WiFiClient newStatusClient = statusServer.available();
    if (newStatusClient) {
      Serial.println("New status client connected");
      newStatusClient.setNoDelay(true);
      sendZMTPGreeting(newStatusClient);
      statusClients.push_back(newStatusClient);
    }
    
    // Clean up disconnected clients
    for (auto it = statusClients.begin(); it != statusClients.end();) {
      if (!it->connected()) {
        it->stop();
        it = statusClients.erase(it);
        Serial.println("Status client disconnected");
      } else {
        ++it;
      }
    }
    
    // Send status updates to all connected clients
    if (!statusClients.empty()) {
      String statusJson = create_status_json();
      for (auto& client : statusClients) {
        if (client.connected()) {
          sendZMTPMessage(client, statusJson);
        }
      }
    }
    
    vTaskDelay(pdMS_TO_TICKS(10000)); // Update status every 10 seconds
  }
}

void ScannerTaskCode(void *pvParameters) {
  Serial.println("Scanner task starting on core " + String(xPortGetCoreID()));
  
  vTaskDelay(pdMS_TO_TICKS(5000));
  
  esp_wifi_set_promiscuous(true);
  esp_wifi_set_promiscuous_rx_cb(&callback);
  esp_wifi_set_channel(6, WIFI_SECOND_CHAN_NONE);

  for(;;) {
    unsigned long current_millis = millis();
    
    if ((current_millis - last_status) > 60000UL) {
      Serial.println("Heartbeat: Scanner active on core " + String(xPortGetCoreID()));
      last_status = current_millis;
    }
    
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

void WebServerTaskCode(void *pvParameters) {
  Serial.println("Web server task starting on core " + String(xPortGetCoreID()));
  
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ap_ssid, ap_password);
  
  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(IP);
  Serial.println("Connect to WiFi: " + String(ap_ssid));
  Serial.println("Password: " + String(ap_password));
  Serial.println("Open browser to: http://" + IP.toString());
  Serial.println("ZMTP Telemetry: tcp://" + IP.toString() + ":4224");
  
  server.on("/", [](){
String html = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dr4g0net</title>
    <style>
        :root {
            --bg-color: #0a0a0a;
            --text-color: #00ff41;
            --accent-color: #00ff41;
            --panel-bg: #111111;
            --panel-border: #00ff41;
            --header-color: #00ff41;
            --data-color: #00ff41;
            --warning-color: #ff3e3e;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Courier New', monospace;
        }
        
        body {
            background-color: var(--bg-color);
            color: var(--text-color);
            padding: 20px;
            line-height: 1.6;
            background-image: 
                radial-gradient(rgba(0, 255, 65, 0.1) 1px, transparent 1px),
                radial-gradient(rgba(0, 255, 65, 0.1) 1px, transparent 1px);
            background-size: 50px 50px;
            background-position: 0 0, 25px 25px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            margin-bottom: 30px;
            border-bottom: 1px solid var(--accent-color);
            padding-bottom: 15px;
            position: relative;
        }
        
        .header h1 {
            font-size: 2.5rem;
            letter-spacing: 2px;
            text-transform: uppercase;
            margin-bottom: 5px;
            text-shadow: 0 0 10px var(--accent-color);
        }
        
        .header p {
            font-size: 1rem;
            opacity: 0.8;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .panel {
            background-color: var(--panel-bg);
            border: 1px solid var(--panel-border);
            border-radius: 4px;
            padding: 20px;
            box-shadow: 0 0 10px rgba(0, 255, 65, 0.2);
            position: relative;
            overflow: hidden;
        }
        
        .panel::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 2px;
            background: linear-gradient(90deg, transparent, var(--accent-color), transparent);
        }
        
        .panel h2 {
            margin-bottom: 15px;
            font-size: 1.2rem;
            text-transform: uppercase;
            letter-spacing: 1px;
            border-bottom: 1px solid rgba(0, 255, 65, 0.3);
            padding-bottom: 5px;
        }
        
        .stat {
            display: flex;
            justify-content: space-between;
            margin-bottom: 10px;
            font-size: 0.9rem;
        }
        
        .stat-label {
            opacity: 0.8;
        }
        
        .stat-value {
            font-weight: bold;
        }
        
        .drone-data {
            background-color: var(--panel-bg);
            border: 1px solid var(--panel-border);
            border-radius: 4px;
            padding: 20px;
            font-family: 'Courier New', monospace;
            white-space: pre-wrap;
            max-height: 400px;
            overflow-y: auto;
            margin-bottom: 20px;
            box-shadow: 0 0 10px rgba(0, 255, 65, 0.2);
        }
        
        .drone-data::-webkit-scrollbar {
            width: 8px;
        }
        
        .drone-data::-webkit-scrollbar-track {
            background: var(--panel-bg);
        }
        
        .drone-data::-webkit-scrollbar-thumb {
            background-color: var(--accent-color);
            border-radius: 4px;
        }
        
        .button {
            background-color: transparent;
            color: var(--accent-color);
            border: 1px solid var(--accent-color);
            padding: 10px 20px;
            cursor: pointer;
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 1px;
            transition: all 0.3s ease;
            border-radius: 4px;
            margin-bottom: 20px;
        }
        
        .button:hover {
            background-color: var(--accent-color);
            color: var(--bg-color);
            box-shadow: 0 0 15px var(--accent-color);
        }
        
        .connection-info {
            margin-bottom: 20px;
        }
        
        .connection-info h2 {
            margin-bottom: 15px;
            font-size: 1.2rem;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .connection-detail {
            display: flex;
            margin-bottom: 10px;
        }
        
        .connection-label {
            width: 150px;
            opacity: 0.8;
        }
        
        .connection-value {
            font-weight: bold;
        }
        
        .blink {
            animation: blink 1.5s infinite;
        }
        
        @keyframes blink {
            0% { opacity: 1; }
            50% { opacity: 0.3; }
            100% { opacity: 1; }
        }
        
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 10px;
            background-color: var(--accent-color);
            box-shadow: 0 0 10px var(--accent-color);
        }
        
        .status-active {
            animation: pulse 1.5s infinite;
        }
        
        @keyframes pulse {
            0% { box-shadow: 0 0 0 0 rgba(0, 255, 65, 0.7); }
            70% { box-shadow: 0 0 0 10px rgba(0, 255, 65, 0); }
            100% { box-shadow: 0 0 0 0 rgba(0, 255, 65, 0); }
        }
        
        .footer {
            text-align: center;
            margin-top: 30px;
            font-size: 0.8rem;
            opacity: 0.6;
        }
        
        @media (max-width: 768px) {
            .grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Dr4g0n3t</h1>
            <p>WiFi RID Scanner</p>
        </div>
        
        <div class="panel connection-info">
            <h2>ZMQ Connection Info</h2>
            <div class="connection-detail">
                <div class="connection-label">IP Address:</div>
                <div class="connection-value">192.168.4.1</div>
            </div>
            <div class="connection-detail">
                <div class="connection-label">Telemetry Port:</div>
                <div class="connection-value">4224</div>
            </div>
            <div class="connection-detail">
                <div class="connection-label">Status Port:</div>
                <div class="connection-value">4225</div>
            </div>
        </div>
        
        <div class="grid">
            <div class="panel">
                <h2>System Status</h2>
                <div class="stat">
                    <div class="stat-label">Status:</div>
                    <div class="stat-value"><span class="status-indicator status-active"></span>Active</div>
                </div>
                <div class="stat">
                    <div class="stat-label">Temperature:</div>
                    <div class="stat-value" id="temperature">--°F</div>
                </div>
                <div class="stat">
                    <div class="stat-label">Free Memory:</div>
                    <div class="stat-value" id="memory">-- KB</div>
                </div>
                <div class="stat">
                    <div class="stat-label">CPU Frequency:</div>
                    <div class="stat-value" id="cpu-freq">-- MHz</div>
                </div>
                <div class="stat">
                    <div class="stat-label">SDK Version:</div>
                    <div class="stat-value" id="sdk-version">--</div>
                </div>
            </div>
            
            <div class="panel">
                <h2>Detection Stats</h2>
                <div class="stat">
                    <div class="stat-label">Packets Detected:</div>
                    <div class="stat-value" id="packets">0</div>
                </div>
                <div class="stat">
                    <div class="stat-label">Last Detection:</div>
                    <div class="stat-value" id="last-detection">Never</div>
                </div>
                <div class="stat">
                    <div class="stat-label">Detection Rate:</div>
                    <div class="stat-value" id="detection-rate">0 pkts/min</div>
                </div>
            </div>
            
            <div class="panel">
                <h2>System Info</h2>
                <div class="stat">
                    <div class="stat-label">Uptime:</div>
                    <div class="stat-value" id="uptime">--:--:--</div>
                </div>
                <div class="stat">
                    <div class="stat-label">Flash Size:</div>
                    <div class="stat-value" id="flash-size">-- KB</div>
                </div>
                <div class="stat">
                    <div class="stat-label">Memory Usage:</div>
                    <div class="stat-value" id="memory-usage">--%</div>
                </div>
            </div>
        </div>
        
        <button class="button" onclick="refreshData()">Refresh Data</button>
        
        <div class="panel">
            <h2>Latest Drone Data</h2>
            <div class="drone-data" id="droneData">No drone data received yet</div>
        </div>
        
        <div class="footer">
            Dr4g0n3t v1.1 | WiFi Remote ID Scanner
        </div>
    </div>

    <script>
        let lastPacketCount = 0;
        let lastPacketTime = Date.now();
        let detectionRate = 0;
        
        function formatUptime(seconds) {
            const hours = Math.floor(seconds / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            const secs = seconds % 60;
            return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
        }
        
        function formatBytes(bytes, decimals = 2) {
            if (bytes === 0) return '0 Bytes';
            
            const k = 1024;
            const dm = decimals < 0 ? 0 : decimals;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            
            return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
        }
        
        function refreshData() {
            fetch('/data')
                .then(response => response.json())
                .then(data => {
                    const currentPackets = parseInt(data.packets);
                    const now = Date.now();
                    
                    // Update packet detection rate
                    if (currentPackets > lastPacketCount) {
                        const newPackets = currentPackets - lastPacketCount;
                        const timeElapsed = (now - lastPacketTime) / 1000 / 60; // in minutes
                        detectionRate = newPackets / timeElapsed;
                        document.getElementById('last-detection').textContent = 'Just now';
                    }
                    
                    lastPacketCount = currentPackets;
                    lastPacketTime = now;
                    
                    // Update UI elements
                    document.getElementById('packets').textContent = data.packets;
                    document.getElementById('uptime').textContent = formatUptime(data.uptime);
                    document.getElementById('memory').textContent = formatBytes(data.memory);
                    document.getElementById('temperature').textContent = data.temperature + '°F';
                    document.getElementById('detection-rate').textContent = detectionRate.toFixed(1) + ' pkts/min';
                    document.getElementById('memory-usage').textContent = ((data.memory_total - data.memory) / data.memory_total * 100).toFixed(1) + '%';
                    document.getElementById('cpu-freq').textContent = data.cpu_freq + ' MHz';
                    document.getElementById('flash-size').textContent = formatBytes(data.flash_size);
                    document.getElementById('sdk-version').textContent = data.sdk_version || '--';
                    
                    if (data.latestDrone && data.latestDrone !== 'No drone data received yet') {
                        document.getElementById('droneData').textContent = data.latestDrone;
                    }
                })
                .catch(error => {
                    console.error('Error:', error);
                });
        }
        
        // Initial refresh
        refreshData();
        
        // Set up periodic refresh
        setInterval(refreshData, 2000);
    </script>
</body>
</html>
)rawliteral";
    server.send(200, "text/html", html);
  });

  server.on("/data", [](){
  String response = "{";
  response += "\"packets\":" + String(packetCount) + ",";
  response += "\"uptime\":" + String(esp_timer_get_time() / 1000000UL) + ",";
  response += "\"memory\":" + String(ESP.getFreeHeap()) + ",";
  response += "\"memory_total\":" + String(ESP.getHeapSize()) + ",";
  response += "\"cpu_freq\":" + String(ESP.getCpuFreqMHz()) + ",";
  response += "\"flash_size\":" + String(ESP.getFlashChipSize()) + ",";
  response += "\"sdk_version\":\"" + String(ESP.getSdkVersion()) + "\",";
  
  // Convert temperature to Fahrenheit
  float temp_c = getESP32Temperature();
  float temp_f = (temp_c * 9.0/5.0) + 32.0;
  response += "\"temperature\":" + String(temp_f, 1) + ",";
  
  if (xSemaphoreTake(dataMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
    String escapedData = latestDroneData;
    escapedData.replace("\"", "\\\"");
    escapedData.replace("\n", "\\n");
    escapedData.replace("\r", "\\r");
    response += "\"latestDrone\":\"" + escapedData + "\"";
    xSemaphoreGive(dataMutex);
  } else {
    response += "\"latestDrone\":\"Data locked\"";
  }
  
  response += "}";
  server.send(200, "application/json", response);
});

  server.on("/stream", [](){
    if (xSemaphoreTake(dataMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
      server.send(200, "application/json", latestDroneData);
      xSemaphoreGive(dataMutex);
    } else {
      server.send(503, "application/json", "{\"error\":\"Data unavailable\"}");
    }
  });

  server.begin();
  Serial.println("Web server started successfully on core " + String(xPortGetCoreID()));
  
  for(;;) {
    server.handleClient();
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

void ProcessorTaskCode(void *pvParameters) {
  Serial.println("Processor task starting on core " + String(xPortGetCoreID()));
  struct queued_packet qp;
  
  for(;;) {
    if (xQueueReceive(droneDataQueue, &qp, pdMS_TO_TICKS(100)) == pdTRUE) {
      // Now we can do heavy processing safely
      struct uav_data currentUAV;
      memset(&currentUAV, 0, sizeof(currentUAV));
      
      store_mac(&currentUAV, qp.payload);
      currentUAV.rssi = qp.packet.rx_ctrl.rssi;
      
      static const uint8_t nan_dest[6] = {0x51, 0x6f, 0x9a, 0x01, 0x00, 0x00};
      
      if (memcmp(nan_dest, &qp.payload[4], 6) == 0) {
        if (odid_wifi_receive_message_pack_nan_action_frame(&UAS_data, 
            (char *)currentUAV.op_id, qp.payload, qp.length) == 0) {
          parse_odid(&currentUAV, &UAS_data);
          packetCount++;
          update_latest_data(&currentUAV, packetCount);
        }
      }
      else if (qp.payload[0] == 0x80) {
        int offset = 36;
        bool printed = false;
        
        while (offset < qp.length && !printed) {
          int typ = qp.payload[offset];
          int len = qp.payload[offset + 1];
          uint8_t *val = &qp.payload[offset + 2];
          
          if ((typ == 0xdd) && (val[0] == 0x6a) && (val[1] == 0x5c) && (val[2] == 0x35)) {
            parse_french_id(&currentUAV, &qp.payload[offset]);
            packetCount++;
            update_latest_data(&currentUAV, packetCount);
            printed = true;
          }
          else if ((typ == 0xdd) &&
                   (((val[0] == 0x90 && val[1] == 0x3a && val[2] == 0xe6)) ||
                    ((val[0] == 0xfa && val[1] == 0x0b && val[2] == 0xbc)))) {
            int j = offset + 7;
            if (j < qp.length) {
              memset(&UAS_data, 0, sizeof(UAS_data));
              odid_message_process_pack(&UAS_data, &qp.payload[j], qp.length - j);
              parse_odid(&currentUAV, &UAS_data);
              packetCount++;
              update_latest_data(&currentUAV, packetCount);
              printed = true;
            }
          }
          
          offset += len + 2;
        }
      }
    }
    
    vTaskDelay(pdMS_TO_TICKS(1));
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("{ \"message\": \"Starting ESP32 WiFi Remote ID Scanner with ZMQ Publisher\" }");
  
  dataMutex = xSemaphoreCreateMutex();
  
  // Create queue for packet processing
  droneDataQueue = xQueueCreate(50, sizeof(struct queued_packet));
  if (droneDataQueue == NULL) {
    Serial.println("Failed to create drone data queue!");
    return;
  }
  
  delay(200);
  
  xTaskCreatePinnedToCore(
    ProcessorTaskCode,
    "ProcessorTask",
    16384,  // Increased stack size for processing
    NULL,
    2,      // Higher priority
    &ProcessorTask,
    1       // Core 1
  );
  
  xTaskCreatePinnedToCore(
    WebServerTaskCode,
    "WebServerTask",
    8192,
    NULL,
    1,
    &WebServerTask,
    1
  );
  
  vTaskDelay(pdMS_TO_TICKS(3000));
  delay(200);
  
  xTaskCreatePinnedToCore(
    ZMQTaskCode,
    "ZMQTask",
    8192,
    NULL,
    1,
    &ZMQTask,
    1
  );

  xTaskCreatePinnedToCore(
    StatusTaskCode,
    "StatusTask",
    8192,
    NULL,
    1,
    &StatusTask,
    1
  );
  
  vTaskDelay(pdMS_TO_TICKS(3000));
  delay(200);
  
  xTaskCreatePinnedToCore(
    ScannerTaskCode,
    "ScannerTask",
    8192,
    NULL,
    2,
    &ScannerTask,
    0
  );
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
  delay(10);
}

static void callback(void *buffer, wifi_promiscuous_pkt_type_t type) {
  if (type != WIFI_PKT_MGMT)
    return;

  wifi_promiscuous_pkt_t *packet = (wifi_promiscuous_pkt_t *)buffer;
  
  // Quick filter check
  uint8_t *payload = packet->payload;
  static const uint8_t nan_dest[6] = {0x51, 0x6f, 0x9a, 0x01, 0x00, 0x00};
  
  bool is_drone_packet = false;
  if (memcmp(nan_dest, &payload[4], 6) == 0) {
    is_drone_packet = true;
  } else if (payload[0] == 0x80) {
    // Quick check for vendor specific elements
    int offset = 36;
    if (offset < packet->rx_ctrl.sig_len) {
      int typ = payload[offset];
      if (typ == 0xdd) {
        is_drone_packet = true;
      }
    }
  }
  
  if (is_drone_packet) {
    // Queue the packet for processing
    struct queued_packet qp;
    memcpy(&qp.packet, packet, sizeof(wifi_promiscuous_pkt_t));
    int copy_len = packet->rx_ctrl.sig_len;
    if (copy_len > sizeof(qp.payload)) {
      copy_len = sizeof(qp.payload);
    }
    memcpy(qp.payload, payload, copy_len);
    qp.length = packet->rx_ctrl.sig_len;
    
    // Non-blocking send to queue
    xQueueSendFromISR(droneDataQueue, &qp, NULL);
  }
}

static float getESP32Temperature() {
  return temperatureRead();  // Returns temp in Celsius
}

static void update_latest_data(struct uav_data *UAV, int index) {
  String jsonData = create_json_response(UAV, index);
  
  Serial.print(jsonData);
  Serial.print("\r\n");
  
  if (xSemaphoreTake(dataMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
    latestDroneData = jsonData;
    xSemaphoreGive(dataMutex);
  }
  
  publishToZMTPClients(jsonData);  // Simplified call
}


static void parse_odid(struct uav_data *UAV, ODID_UAS_Data *UAS_data2) {
  memset(UAV->op_id, 0, sizeof(UAV->op_id));
  memset(UAV->uav_id, 0, sizeof(UAV->uav_id));
  memset(UAV->description, 0, sizeof(UAV->description));
  memset(UAV->auth_data, 0, sizeof(UAV->auth_data));

  if (UAS_data2->BasicIDValid[0]) {
    strncpy(UAV->uav_id, (char *)UAS_data2->BasicID[0].UASID, ODID_ID_SIZE);
  }

  if (UAS_data2->LocationValid) {
    UAV->lat_d = UAS_data2->Location.Latitude;
    UAV->long_d = UAS_data2->Location.Longitude;
    UAV->altitude_msl = (int)UAS_data2->Location.AltitudeGeo;
    UAV->height_agl = (int)UAS_data2->Location.Height;
    UAV->speed = (int)UAS_data2->Location.SpeedHorizontal;
    UAV->heading = (int)UAS_data2->Location.Direction;
    UAV->speed_vertical = (int)UAS_data2->Location.SpeedVertical;
    UAV->altitude_pressure = (int)UAS_data2->Location.AltitudeBaro;
    UAV->height_type = UAS_data2->Location.HeightType;
    UAV->horizontal_accuracy = UAS_data2->Location.HorizAccuracy;
    UAV->vertical_accuracy = UAS_data2->Location.VertAccuracy;
    UAV->baro_accuracy = UAS_data2->Location.BaroAccuracy;
    UAV->speed_accuracy = UAS_data2->Location.SpeedAccuracy;
    UAV->timestamp = (int)UAS_data2->Location.TimeStamp;
    UAV->status = UAS_data2->Location.Status;
  }

  if (UAS_data2->SystemValid) {
    UAV->base_lat_d = UAS_data2->System.OperatorLatitude;
    UAV->base_long_d = UAS_data2->System.OperatorLongitude;
    UAV->operator_location_type = UAS_data2->System.OperatorLocationType;
    UAV->classification_type = UAS_data2->System.ClassificationType;
    UAV->area_count = UAS_data2->System.AreaCount;
    UAV->area_radius = UAS_data2->System.AreaRadius;
    UAV->area_ceiling = UAS_data2->System.AreaCeiling;
    UAV->area_floor = UAS_data2->System.AreaFloor;
    UAV->operator_altitude_geo = UAS_data2->System.OperatorAltitudeGeo;
    UAV->system_timestamp = UAS_data2->System.Timestamp;
  }

  if (UAS_data2->AuthValid[0]) {
    UAV->auth_type = UAS_data2->Auth[0].AuthType;
    UAV->auth_page = UAS_data2->Auth[0].DataPage;
    UAV->auth_length = UAS_data2->Auth[0].Length;
    UAV->auth_timestamp = UAS_data2->Auth[0].Timestamp;
    memcpy(UAV->auth_data, UAS_data2->Auth[0].AuthData, sizeof(UAV->auth_data) - 1);
  }

  if (UAS_data2->SelfIDValid) {
    UAV->desc_type = UAS_data2->SelfID.DescType;
    strncpy(UAV->description, UAS_data2->SelfID.Desc, ODID_STR_SIZE);
  }

  if (UAS_data2->OperatorIDValid) {
    UAV->operator_id_type = UAS_data2->OperatorID.OperatorIdType;
    strncpy(UAV->op_id, (char *)UAS_data2->OperatorID.OperatorId, ODID_ID_SIZE);
  }

  UAV->ua_type = UAS_data2->BasicID[0].UAType;
}

static void parse_french_id(struct uav_data *UAV, uint8_t *payload) {
  union {
    uint32_t u32;
    int32_t i32;
  } uav_lat, uav_long, base_lat, base_long;
  
  union {
    uint16_t u16;
    int16_t i16;
  } alt, height;

  int j = 9;
  int frame_length = payload[1];

  while (j < frame_length) {
    uint8_t t = payload[j];
    uint8_t l = payload[j + 1];
    uint8_t *v = &payload[j + 2];

    switch (t) {
    case 2:
      for (int i = 0; (i < (l - 6)) && (i < ODID_ID_SIZE); ++i) {
        UAV->op_id[i] = (char)v[i + 6];
      }
      break;
    case 3:
      for (int i = 0; (i < l) && (i < ODID_ID_SIZE); ++i) {
        UAV->uav_id[i] = (char)v[i];
      }
      break;
    case 4:
      for (int i = 0; i < 4; ++i) {
        uav_lat.u32 <<= 8;
        uav_lat.u32 |= v[i];
      }
      break;
    case 5:
      for (int i = 0; i < 4; ++i) {
        uav_long.u32 <<= 8;
        uav_long.u32 |= v[i];
      }
      break;
    case 6:
      alt.u16 = (((uint16_t)v[0]) << 8) | (uint16_t)v[1];
      break;
    case 7:
      height.u16 = (((uint16_t)v[0]) << 8) | (uint16_t)v[1];
      break;
    case 8:
      for (int i = 0; i < 4; ++i) {
        base_lat.u32 <<= 8;
        base_lat.u32 |= v[i];
      }
      break;
    case 9:
      for (int i = 0; i < 4; ++i) {
        base_long.u32 <<= 8;
        base_long.u32 |= v[i];
      }
      break;
    case 10:
      UAV->speed = v[0];
      break;
    case 11:
      UAV->heading = (((uint16_t)v[0]) << 8) | (uint16_t)v[1];
      break;
    default:
      break;
    }

    j += l + 2;
  }

 UAV->base_lat_d = 1.0e-5 * (double)base_lat.i32;
 UAV->base_long_d = 1.0e-5 * (double)base_long.i32;
 UAV->altitude_msl = alt.i16;
 UAV->height_agl = height.i16;
}

static void store_mac(struct uav_data *uav, uint8_t *payload) {
 memcpy(uav->mac, &payload[10], 6);
}

static String create_json_response(struct uav_data *UAV, int index) {
 unsigned long uptime_seconds = esp_timer_get_time() / 1000000UL;

 char lat[16], lon[16], op_lat[16], op_lon[16];
 dtostrf(UAV->lat_d, 11, 6, lat);
 dtostrf(UAV->long_d, 11, 6, lon);
 dtostrf(UAV->base_lat_d, 11, 6, op_lat);
 dtostrf(UAV->base_long_d, 11, 6, op_lon);

 char mac_str[18];
 snprintf(mac_str, sizeof(mac_str), "%02x:%02x:%02x:%02x:%02x:%02x",
          UAV->mac[0], UAV->mac[1], UAV->mac[2],
          UAV->mac[3], UAV->mac[4], UAV->mac[5]);

 String json = "{";
 json += "\"index\":" + String(index) + ",";
 json += "\"runtime\":" + String(uptime_seconds) + ",";
 json += "\"Basic ID\":{";
 json += "\"id\":\"" + String(strlen(UAV->uav_id) > 0 ? UAV->uav_id : "NONE") + "\",";
 json += "\"id_type\":\"Serial Number (ANSI/CTA-2063-A)\",";
 json += "\"ua_type\":" + String(UAV->ua_type) + ",";
 json += "\"MAC\":\"" + String(mac_str) + "\",";
 json += "\"RSSI\":" + String(UAV->rssi);
 json += "},";
 json += "\"Location/Vector Message\":{";
 json += "\"latitude\":" + String(lat) + ",";
 json += "\"longitude\":" + String(lon) + ",";
 json += "\"speed\":" + String(UAV->speed) + ",";
 json += "\"vert_speed\":" + String(UAV->speed_vertical) + ",";
 json += "\"geodetic_altitude\":" + String(UAV->altitude_msl) + ",";
 json += "\"height_agl\":" + String(UAV->height_agl) + ",";
 json += "\"status\":" + String(UAV->status) + ",";
 json += "\"direction\":" + String(UAV->heading) + ",";
 json += "\"alt_pressure\":" + String(UAV->altitude_pressure) + ",";
 json += "\"height_type\":" + String(UAV->height_type) + ",";
 json += "\"horiz_acc\":" + String(UAV->horizontal_accuracy) + ",";
 json += "\"vert_acc\":" + String(UAV->vertical_accuracy) + ",";
 json += "\"baro_acc\":" + String(UAV->baro_accuracy) + ",";
 json += "\"speed_acc\":" + String(UAV->speed_accuracy) + ",";
 json += "\"timestamp\":" + String(UAV->timestamp);
 json += "},";
 json += "\"Self-ID Message\":{";
 json += "\"text\":\"UAV " + String(mac_str) + " operational\",";
 json += "\"description_type\":" + String(UAV->desc_type) + ",";
 json += "\"description\":\"" + String(UAV->description) + "\"";
 json += "},";
 json += "\"System Message\":{";
 json += "\"latitude\":" + String(op_lat) + ",";
 json += "\"longitude\":" + String(op_lon) + ",";
 json += "\"operator_lat\":" + String(op_lat) + ",";
 json += "\"operator_lon\":" + String(op_lon) + ",";
 json += "\"area_count\":" + String(UAV->area_count) + ",";
 json += "\"area_radius\":" + String(UAV->area_radius) + ",";
 json += "\"area_ceiling\":" + String(UAV->area_ceiling) + ",";
 json += "\"area_floor\":" + String(UAV->area_floor) + ",";
 json += "\"operator_alt_geo\":" + String(UAV->operator_altitude_geo) + ",";
 json += "\"classification\":" + String(UAV->classification_type) + ",";
 json += "\"timestamp\":" + String(UAV->system_timestamp);
 json += "},";
 json += "\"Auth Message\":{";
 json += "\"type\":" + String(UAV->auth_type) + ",";
 json += "\"page\":" + String(UAV->auth_page) + ",";
 json += "\"length\":" + String(UAV->auth_length) + ",";
 json += "\"timestamp\":" + String(UAV->auth_timestamp) + ",";
 json += "\"data\":\"" + String(UAV->auth_data) + "\"";
 json += "}";
 json += "}";

 return json;
}