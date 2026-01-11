# WarDragon iOS - Complete Data Flow Architecture

## System Overview

```
                        ┌─────────────────────────────────────────┐
                        │     WarDragon Hardware Platform         │
                        │  ┌────────────┐  ┌──────────────────┐   │
                        │  │  RID WiFi  │  │   ANTSDR E200    │   │
                        │  │ Bluetooth  │  │   (FPV Scanner)  │   │
                        │  └──────┬─────┘  └────────┬─────────┘   │
                        │         │                 │             │
                        │  ┌──────▼─────────────────▼──────-───┐  │
                        │  │      zmq_decoder.py Process       │  │
                        │  └──────┬──────────────┬──────┬──────┘  │
                        └─────────┼──────────────┼──────┼─────────┘
                                  │              │      │
                         ZMQ PUB  │              │      │  ZMQ PUB
                         Port 4224│              │      │  Port 4226
                         (Telemetry)             │      │  (FPV/Spectrum)
                                  │     ZMQ PUB  │      │
                                  │     Port 4225│      │
                                  │     (Status) │      │
                                  │              │      │
══════════════════════════════════┼══════════════┼══════┼═══════════════════
                                  │              │      │
                    OPTION A: Direct ZMQ (Native iOS) RECOMMENDED
                                  │              │      │
                         ┌────────▼──────────────▼──────▼────────┐
                         │     iOS WarDragon App (Swift)         │
                         │  ┌──────────────────────────────────┐ │
                         │  │        ZMQHandler                │ │
                         │  │  ┌──────────────────────────┐    │ │
                         │  │  │ Telemetry Socket (4224)  │    │ │
                         │  │  │ - Drone BLE/Wi-Fi frames │    │ │
                         │  │  │ - MAC addresses          │    │ │
                         │  │  │ - RSSI values            │    │ │
                         │  │  │ - Location data          │    │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  │  ┌────────────▼─────────────┐    │ │
                         │  │  │ Status Socket (4225)     │    │ │
                         │  │  │ - GPS coordinates        │    │ │
                         │  │  │ - CPU/Memory stats       │    │ │
                         │  │  │ - ANTSDR temperatures    │    │ │
                         │  │  │ - System uptime          │    │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  │  ┌────────────▼─────────────┐    │ │
                         │  │  │ Spectrum Socket (4226)   │    │ │
                         │  │  │ - FPV signal detections  │    │ │
                         │  │  │ - Frequency/bandwidth    │    │ │
                         │  │  │ - Signal strength        │    │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  └───────────────┼──────────────────┘ │
                         │                  │                    │
                         │  ┌───────────────▼──────────────────┐ │
                         │  │       CoTViewModel               │ │
                         │  │  ┌──────────────────────────┐    │ │
                         │  │  │ Drone Tracking Engine    │    │ │
                         │  │  │ - Parse ZMQ messages     │    │ │
                         │  │  │ - Track MAC addresses    │    │ │
                         │  │  │ - Signature correlation  │    │ │
                         │  │  │ - Spoof detection        │    │ │
                         │  │  │ - Inactivity cleanup     │    │ │
                         │  │  │   (60s timeout)          │    │ │
                         │  │  │ - Max limits             │    │ │
                         │  │  │   (30 drones, 100 aircraft)   │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  └───────────────┼──────────────────┘ │
                         │                  │                    │
                         │  ┌───────────────▼──────────────────┐ │
                         │  │   Additional Data Sources        │ │
                         │  │  ┌──────────────────────────┐    │ │
                         │  │  │ ADSBClient               │    │ │
                         │  │  │ - dump1090 aircraft.json │    │ │
                         │  │  │ - Poll interval: 2s      │    │ │
                         │  │  │ - Altitude filtering     │    │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  │  ┌────────────▼─────────────┐    │ │
                         │  │  │ KismetClient             │    │ │
                         │  │  │ - Wi-Fi devices          │    │ │
                         │  │  │ - Bluetooth devices      │    │ │
                         │  │  │ - REST API polling       │    │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  └───────────────┼──────────────────┘ │
                         │                  │                    │
                         │  ┌───────────────▼──────────────────┐ │
                         │  │   Output Publishers              │ │
                         │  │  ┌──────────────────────────┐    │ │
                         │  │  │ TAKClient                │    │ │
                         │  │  │ - TCP/UDP/TLS modes      │    │ │
                         │  │  │ - P12 certificate auth   │    │ │
                         │  │  │ - Auto-reconnect         │    │ │
                         │  │  │ - Rate limiting          │    │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  │  ┌────────────▼─────────────┐    │ │
                         │  │  │ MQTTClient               │    │ │
                         │  │  │ - Per-drone topics       │    │ │
                         │  │  │ - Aggregate topic        │    │ │
                         │  │  │ - Home Assistant         │    │ │
                         │  │  │ - QoS 0/1/2              │    │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  │  ┌────────────▼─────────────┐    │ │
                         │  │  │ LatticeClient            │    │ │
                         │  │  │ - Anduril platform       │    │ │
                         │  │  │ - Entity publishing      │    │ │
                         │  │  └────────────┬─────────────┘    │ │
                         │  └───────────────┼──────────────────┘ │
                         │                  │                    │
                         │  ┌───────────────▼──────────────────┐ │
                         │  │   APIServer (Read-only)          │ │
                         │  │   HTTP Port 8088                 │ │
                         │  │  ┌──────────────────────────┐    │ │
                         │  │  │ GET /status              │    │ │
                         │  │  │ GET /drones              │    │ │
                         │  │  │ GET /aircraft            │    │ │
                         │  │  │ GET /signals             │    │ │
                         │  │  │ GET /config              │    │ │
                         │  │  │ GET /health              │    │ │
                         │  │  │ GET /update/check        │    │ │
                         │  │  └──────────────────────────┘    │ │
                         │  └──────────────────────────────────┘ │
                         └───────────────┬───────────────────────┘
                                         │
             ┌───────────────────────────┼───────────────────────────┐
             │                           │                           │
             ▼                           ▼                           ▼
    ┌────────────────┐        ┌──────────────────┐       ┌──────────────────┐
    │  TAK Server    │        │   MQTT Broker    │       │  Lattice Cloud   │
    │                │        │                  │       │                  │
    │ - ATAK tablets │        │ - Home Assistant │       │ - Anduril C2     │
    │ - WinTAK       │        │ - Node-RED       │       │ - Entity mgmt    │
    │ - iTAK         │        │ - Custom scripts │       │ - Sensor fusion  │
    └────────────────┘        └──────────────────┘       └──────────────────┘

══════════════════════════════════════════════════════════════════════════════

                    OPTION B: DragonSync Middleware (Advanced)

══════════════════════════════════════════════════════════════════════════════

         ┌───────────────────────────────────────────────────────┐
         │              dragonsync.py (Python)                   │
         │  ┌─────────────────────────────────────────────────┐  │
         │  │            ZMQ Subscribers                      │  │
         │  │  - Telemetry (4224)                             │  │
         │  │  - Status (4225)                                │  │
         │  │  - FPV Signals (4226)                           │  │
         │  └──────────────────┬──────────────────────────────┘  │
         │                     │                                 │
         │  ┌──────────────────▼──────────────────────────────┐  │
         │  │         DroneManager                            │  │
         │  │  - Per-drone rate limiting (1 Hz)               │  │
         │  │  - Max drones: 30 (configurable)                │  │
         │  │  - Inactivity timeout: 60s                      │  │
         │  │  - FAA RID database lookups                     │  │
         │  │  - Serial number enrichment                     │  │
         │  └──────────────────┬──────────────────────────────┘  │
         │                     │                                 │
         │  ┌──────────────────▼──────────────────────────────┐  │
         │  │         SignalManager (FPV)                     │  │
         │  │  - TTL cache: 60s                               │  │
         │  │  - Max signals: 200                             │  │
         │  │  - Confirm-only mode                            │  │
         │  │  - Frequency correlation                        │  │
         │  └──────────────────┬──────────────────────────────┘  │
         │                     │                                 │
         │  ┌──────────────────▼──────────────────────────────┐  │
         │  │         AircraftManager (ADS-B)                 │  │
         │  │  - dump1090 JSON polling                        │  │
         │  │  - Cache TTL: 120s                              │  │
         │  │  - Altitude filtering                           │  │
         │  └──────────────────┬──────────────────────────────┘  │
         │                     │                                 │
         │  ┌──────────────────▼──────────────────────────────┐  │
         │  │         SystemStatus                            │  │
         │  │  - GPS coordinates                              │  │
         │  │  - System metrics                               │  │
         │  │  - ANTSDR temperatures                          │  │
         │  └──────────────────┬──────────────────────────────┘  │
         │                     │                                 │
         │  ┌──────────────────▼──────────────────────────────┐  │
         │  │         CotMessenger                            │  │
         │  │  - Format CoT XML                               │  │
         │  │  - TAK client (TCP/UDP/TLS)                     │  │
         │  │  - Multicast sender/receiver                    │  │
         │  └──────────────────┬──────────────────────────────┘  │
         │                     │                                 │
         │  ┌──────────────────▼──────────────────────────────┐  │
         │  │         Output Sinks                            │  │
         │  │  - MqttSink (per-drone + aggregate )            │  │
         │  │  - LatticeSink (Anduril platform)               │  │
         │  └──────────────────┬──────────────────────────────┘  │
         │                     │                                 │
         │  ┌──────────────────▼──────────────────────────────┐  │
         │  │      Flask API Server (Port 8088)               │  │
         │  │   GET /status - System health                   │  │
         │  │   GET /drones - Active drone list               │  │
         │  │   GET /signals - FPV detections                 │  │
         │  │   GET /aircraft - ADS-B tracks                  │  │
         │  │   GET /config - Configuration                   │  │
         │  │   GET /update/check - Version info              │  │
         │  └─────────────────┬───────────────────────────────┘  │
         └────────────────────┼──────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
    ┌──────────┐      ┌──────────────┐    ┌─────────────────┐
    │TAK Server│      │  MQTT Broker │    │ iOS App (API)   │
    └──────────┘      └──────────────┘    │ HTTP polling    │
                                          │ Display only    │
                                          └─────────────────┘

══════════════════════════════════════════════════════════════════════════════

                        Message Flow Details

══════════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────────┐
│                     Drone Detection Flow (Option A)                         │
└─────────────────────────────────────────────────────────────────────────────┘

1. WarDragon Hardware
   └─> Receives BLE advertisement from DJI Mavic
       MAC: 60:60:1F:12:34:56
       RSSI: -65 dBm
       Manufacturer: DJI (via OUI lookup)

2. zmq_decoder
   └─> Parses BLE packet
       Extracts: MAC, RSSI, timestamp, location (if present)
       Publishes to ZMQ port 4224

3. ZMQHandler (iOS)
   └─> Receives JSON message
       {
         "mac": "60:60:1F:12:34:56",
         "rssi": -65,
         "lat": 37.7749,
         "lon": -122.4194,
         "alt": 50.0,
         "timestamp": "2026-01-08T12:00:00Z"
       }

4. CoTViewModel
   └─> Creates/updates CoTMessage
       UID: "drone-60601F123456"
       Manufacturer: "DJI" (prefix lookup)
       Checks inactivity (60s timeout)
       Rate limit check (global)
       Max drones check (30 limit)

5. Output Publishers
   ├─> TAKClient
   │   └─> Generates CoT XML:
   │       <event type="a-f-A-M-H-Q" uid="drone-60601F123456">
   │         <point lat="37.7749" lon="-122.4194" hae="50.0"/>
   │         <detail>
   │           <contact callsign="DJI Mavic"/>
   │           <remarks>RSSI: -65 dBm</remarks>
   │         </detail>
   │       </event>
   │   └─> Sends via TCP/UDP/TLS to TAK server
   │
   ├─> MQTTClient
   │   └─> Publishes JSON to:
   │       Topic: wardragon/drones/60601F123456
   │       {
   │         "mac": "60:60:1F:12:34:56",
   │         "manufacturer": "DJI",
   │         "rssi": -65,
   │         ...
   │       }
   │   └─> If first detection, sends HA discovery config
   │
   └─> LatticeClient
       └─> Creates entity in Lattice:
           {
             "entityId": "drone-60601F123456",
             "type": "UAV",
             "location": [37.7749, -122.4194, 50.0],
             "properties": {"manufacturer": "DJI"}
           }

6. APIServer
   └─> Exposes via HTTP:
       GET /drones returns active drone list
       GET /status shows system health
       GET /signals shows FPV detections

┌─────────────────────────────────────────────────────────────────────────────┐
│                   System Status Flow (Option A)                             │
└─────────────────────────────────────────────────────────────────────────────┘

1. WarDragon Hardware
   └─> Monitors system health
       CPU: 45%, Memory: 60%, Temp: 55°C
       GPS: 37.7749, -122.4194
       ANTSDR: Pluto 45°C, Zynq 50°C

2. zmq_decoder
   └─> Publishes status to ZMQ port 4225
       {
         "serial_number": "WD12345",
         "gps_data": {...},
         "system_stats": {...},
         "ant_sdr_temps": {...}
       }

3. ZMQHandler (iOS)
   └─> Receives status message
       Forwards to StatusViewModel

4. StatusViewModel
   └─> Stores StatusMessage
       Updates lastStatusMessageReceived
       Checks warning thresholds

5. CoTViewModel (NEW!)
   └─> Auto-triggers publishSystemStatusToTAK()
       Generates system status CoT XML

6. TAKClient
   └─> Sends system status to TAK:
       <event type="a-f-G-E-S" uid="wardragon-WD12345">
         <point lat="37.7749" lon="-122.4194"/>
         <detail>
           <contact callsign="WarDragon-WD12345"/>
           <system_health>
             <cpu_usage>45.0</cpu_usage>
             <memory_percent>60.0</memory_percent>
             <temperature_c>55.0</temperature_c>
             <pluto_temp_c>45.0</pluto_temp_c>
             <zynq_temp_c>50.0</zynq_temp_c>
           </system_health>
         </detail>
       </event>

7. TAK Server
   └─> Displays WarDragon unit on map
       Shows system health metrics
       Updates every 120s (stale time)

┌─────────────────────────────────────────────────────────────────────────────┐
│                  ADS-B Aircraft Flow (Option A)                             │
└─────────────────────────────────────────────────────────────────────────────┘

1. External ADS-B Receiver
   └─> dump1090 generates aircraft.json
       http://192.168.1.100:8080/data/aircraft.json

2. ADSBClient (iOS)
   └─> Polls every 2 seconds
       Parses JSON for aircraft list
       Filters by altitude (if configured)

3. CoTViewModel
   └─> Creates CoTMessage for each aircraft
       UID: "aircraft-A12345" (ICAO hex)
       Tracks separately from drones
       Max 100 aircraft limit

4. Output Publishers
   └─> Publishes to TAK/MQTT/Lattice
       Same flow as drones but different UID prefix

┌─────────────────────────────────────────────────────────────────────────────┐
│                   Rate Limiting Strategy                                    │
└─────────────────────────────────────────────────────────────────────────────┘

iOS (Global Limits):
├─> Drone publish: 1 Hz per drone (RateLimiterManager)
├─> MQTT: 10 msg/s, burst 20 in 5s
├─> TAK: 5 msg/s
└─> Webhooks: 20 msg/min

DragonSync (Per-Drone Limits):
├─> Drone publish: 1 Hz per drone (DroneManager)
├─> Rate tracking per UID
├─> Last-sent timestamp cache
└─> Burst protection

Both approaches work well in practice!

┌─────────────────────────────────────────────────────────────────────────────┐
│                   Inactivity Cleanup (60s)                                  │
└─────────────────────────────────────────────────────────────────────────────┘

Timer fires every 10 seconds:
├─> Iterate all tracked drones
├─> Check last update timestamp
├─> If > 60s old:
│   └─> Remove from parsedMessages
│   └─> Send "inactive" status to TAK (optional)
│   └─> Clean up from MQTT/Lattice
└─> Matches Python DragonSync behavior

══════════════════════════════════════════════════════════════════════════════
                              End of Data Flow
══════════════════════════════════════════════════════════════════════════════
