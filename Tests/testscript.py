#!/usr/bin/env python3
"""
DragonSync Enhanced Test Data Broadcaster
Supports testing: Multicast CoT, ZMQ, MQTT, TAK Server, and ADS-B readsb simulation
"""

import socket
import time
import math
import os
import random
import json
import string
import struct
import zmq
from datetime import datetime, timezone, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

# Try to import paho-mqtt, provide fallback if not available
try:
    import paho.mqtt.client as mqtt
    MQTT_AVAILABLE = True
except ImportError:
    MQTT_AVAILABLE = False
    print("⚠️  paho-mqtt not installed. MQTT features disabled.")
    print("   Install with: pip3 install paho-mqtt")

class Config:
    def __init__(self):
        # Multicast/ZMQ settings
        self.multicast_group = '224.0.0.1'
        self.cot_port = 6969
        self.status_port = 6969
        self.broadcast_mode = 'multicast'
        self.zmq_host = '224.0.0.1'
        
        # MQTT settings
        self.mqtt_broker = 'localhost'
        self.mqtt_port = 1883
        self.mqtt_username = None
        self.mqtt_password = None
        self.mqtt_base_topic = 'wardragon'
        self.mqtt_use_tls = False
        
        # TAK Server settings
        self.tak_host = 'localhost'
        self.tak_port = 8087
        self.tak_protocol = 'tcp'  # tcp, udp, or tls
        
        # ADS-B settings
        self.adsb_port = 8080  # HTTP port for readsb-compatible API
        
class DroneMessageGenerator:
    def __init__(self):
        self.lat_range = (37.2, 37.3)
        self.lon_range = (-115.8, -115.7)  
        self.msg_index = 0
        self.start_time = time.time()
        
        # Track drone states for realistic movement and consistent IDs
        self.drone_states = {}
        self.current_drone_id = f"{random.randint(100, 100)}"


    def random_mac(self):
        return ":".join(f"{random.randint(0, 255):02X}" for _ in range(6))
        
    def get_timestamps(self):
        now = datetime.now(timezone.utc)
        time_str = now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        stale = (now + timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        return time_str, time_str, stale

    def generate_drone_cot_with_track(self):
        """Generate main drone CoT message with track information matching DragonSync format"""
        time_str, start_str, stale_str = self.get_timestamps()
        now = datetime.now(timezone.utc)
        unix_timestamp = now.timestamp()
        
        # Use time to generate smooth flight pattern
        t = time.time() * 0.1
        
        # Center point of flight area 
        center_lat = (self.lat_range[0] + self.lat_range[1]) / 2
        center_lon = (self.lon_range[0] + self.lon_range[1]) / 2
        
        # Radius of flight pattern
        radius_lat = (self.lat_range[1] - self.lat_range[0]) / 3
        radius_lon = (self.lon_range[1] - self.lon_range[0]) / 3
        
        # Figure-8 pattern
        lat = center_lat + radius_lat * math.sin(t)
        lon = center_lon + radius_lon * math.sin(t * 2)
        
        # Smooth altitude changes
        alt = 300 + 50 * math.sin(t * 0.5)
        height_agl = alt - 100
        
        # Speed and direction calculations based on movement
        dx = math.cos(t * 2) * radius_lon
        dy = math.cos(t) * radius_lat
        speed = 15 + 5 * math.cos(t)
        vspeed = 2.5 * math.cos(t * 0.5)
        
        # Calculate course (direction of movement)
        course = (math.degrees(math.atan2(dx, dy))) % 360
    #       course = random.randint(0,360)
        mac = self.random_mac()
        # Fixed values
    #       mac = "E0:4E:7A:9A:67:99"
        rssi = -60 + int(10 * math.sin(t))
        desc = f"DJI {random.randint(100, 199)}"
        uid = f"{random.randint(100, 100)}"
        
        # NEW BACKEND/ENRICHMENT FIELDS
        freq = round(random.uniform(5725000000, 5875000000), 2)  # Frequency in Hz (5.8GHz FPV band)
        seen_by = f"wardragon-{random.randint(100, 199)}"  # WarDragon kit ID
        rid_make = random.choice(["DJI", "Autel", "Skydio", "Parrot"])
        rid_model = random.choice(["Mavic 3", "Mini 4 Pro", "Air 3", "EVO II", "X2"])
        rid_source = random.choice(["FAA", "EASA", "CAA"])
        
        # Match exact DragonSync format
        return f"""<?xml version='1.0' encoding='UTF-8'?>
<event version="2.0" uid="{uid}" type="a-u-A-M-H-R" time="{time_str}" start="{start_str}" stale="{stale_str}" how="m-g">
    <point lat="{lat:.6f}" lon="{lon:.6f}" hae="{alt:.1f}" ce="35.0" le="999999"/>
    <detail>
        <contact callsign="{uid}"/>
        <precisionlocation geopointsrc="gps" altsrc="gps"/>
        <track course="{course:.1f}" speed="{speed:.1f}"/>
        <remarks>MAC: {mac}, RSSI: {rssi}dBm; ID Type: Serial Number (ANSI/CTA-2063-A); UA Type: Helicopter or Multirotor (2); Operator ID: TestOperator; Speed: {speed:.1f} m/s; Vert Speed: {vspeed:.1f} m/s; Altitude: {alt:.1f} m; AGL: {height_agl:.1f} m; Course: {course:.1f}°; Index: {random.randint(1, 100)}; Runtime: {int(time.time() - self.start_time)}s; Freq: {freq} Hz; Seen By: {seen_by}; Observed At: {unix_timestamp}; RID Time: {time_str}; RID: {rid_make} {rid_model} ({rid_source})</remarks>
        <color argb="-256"/>
    </detail>
</event>"""

    def generate_pilot_cot(self):
        """Generate separate pilot CoT message matching DragonSync format"""
        time_str, start_str, stale_str = self.get_timestamps()
        
        # Pilot stays in relatively fixed location
        pilot_lat = (self.lat_range[0] + self.lat_range[1]) / 2 + random.uniform(-0.001, 0.001)
        pilot_lon = (self.lon_range[0] + self.lon_range[1]) / 2 + random.uniform(-0.001, 0.001)
        pilot_alt = 50 + random.uniform(-5, 5)  # Ground level with some variation
        
        # Extract base ID from drone ID
        base_id = self.current_drone_id.replace("drone-", "")
        pilot_uid = f"pilot-{base_id}"
        
        return f"""<?xml version='1.0' encoding='UTF-8'?>
<event version="2.0" uid="{pilot_uid}" type="b-m-p-s-m" time="{time_str}" start="{start_str}" stale="{stale_str}" how="m-g">
    <point lat="{pilot_lat:.6f}" lon="{pilot_lon:.6f}" hae="{pilot_alt:.1f}" ce="35.0" le="999999"/>
    <detail>
        <contact callsign="{pilot_uid}"/>
        <precisionlocation geopointsrc="gps" altsrc="gps"/>
        <usericon iconsetpath="com.atakmap.android.maps.public/Civilian/Person.png"/>
        <remarks>Pilot location for drone {self.current_drone_id}</remarks>
    </detail>
</event>"""

    def generate_home_cot(self):
        """Generate separate home/takeoff point CoT message matching DragonSync format"""
        time_str, start_str, stale_str = self.get_timestamps()
        
        # Home point is fixed
        home_lat = (self.lat_range[0] + self.lat_range[1]) / 2
        home_lon = (self.lon_range[0] + self.lon_range[1]) / 2
        home_alt = 100  # Fixed takeoff altitude
        
        # Extract base ID from drone ID
        base_id = self.current_drone_id.replace("drone-", "")
        home_uid = f"home-{base_id}"
        
        return f"""<?xml version='1.0' encoding='UTF-8'?>
<event version="2.0" uid="{home_uid}" type="b-m-p-s-m" time="{time_str}" start="{start_str}" stale="{stale_str}" how="m-g">
    <point lat="{home_lat:.6f}" lon="{home_lon:.6f}" hae="{home_alt:.1f}" ce="35.0" le="999999"/>
    <detail>
        <contact callsign="{home_uid}"/>
        <precisionlocation geopointsrc="gps" altsrc="gps"/>
        <usericon iconsetpath="com.atakmap.android.maps.public/Civilian/House.png"/>
        <remarks>Home location for drone {self.current_drone_id}</remarks>
    </detail>
</event>"""

    def generate_fpv_detection_message(self):
        """Generate an FPV detection message compatible with fpv_mdn_receiver.py output"""
        now = datetime.now(timezone.utc)
        timestamp = now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        
        frequency = random.choice([5547, 5645, 5740, 5880])
        bandwidth = f"{random.choice([20, 40])}MHz"
        rssi = random.randint(1290, 3500)
        
        source_inst = f"{random.randint(1, 5):02d}"
        source_node = f"{random.randint(1000, 9999)}"
        detection_source = f"{source_inst}-{source_node}"
        
        if not hasattr(self, 'current_fpv_detection'):
            self.current_fpv_detection = {
                'frequency': frequency,
                'source_inst': source_inst,
                'source_node': source_node,
                'detection_source': detection_source,
                'rssi': rssi
            }
        else:
            frequency = self.current_fpv_detection['frequency']
            source_inst = self.current_fpv_detection['source_inst']
            source_node = self.current_fpv_detection['source_node']
            detection_source = self.current_fpv_detection['detection_source']
            rssi = self.current_fpv_detection['rssi']
            
        detection_message = [
            {
                "FPV Detection": {
                    "timestamp": timestamp,
                    "manufacturer": source_inst,
                    "device_type": f"FPV{frequency:.1f}MHz",
                    "frequency": frequency,
                    "bandwidth": bandwidth,
                    "signal_strength": rssi,
                    "detection_source": detection_source
                }
            }
        ]
        
        return json.dumps(detection_message)
    
    def generate_fpv_update_message(self):
        """Generate an FPV update message in the format of LOCK UPDATE messages"""
        now = datetime.now(timezone.utc)
        timestamp = now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        
        if not hasattr(self, 'current_fpv_detection'):
            return None
        
        detection_source = self.current_fpv_detection['detection_source']
        rssi = self.current_fpv_detection['rssi'] + random.uniform(-5, 5)
        self.current_fpv_detection['rssi'] = rssi
        
        update_message = {
            "AUX_ADV_IND": {
                "rssi": rssi, 
                "aa": 2391391958,
                "time": timestamp
            }, 
            "aext": {
                "AdvA": f"{detection_source} random"
            },
            "frequency": 5475
        }
        
        return json.dumps(update_message)

    def generate_complete_message(self, mode="zmq"):
        now = datetime.now(timezone.utc)
        timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
        unix_timestamp = now.timestamp()
        
        latitude = round(random.uniform(*self.lat_range), 6)
        longitude = round(random.uniform(*self.lon_range), 6)
        rssi = random.randint(-90, -40)
        
        message = [
            {
                "Basic ID": {
                    "protocol_version": "F3411.19",
                    "id_type": "Serial Number (ANSI/CTA-2063-A)",
                    "ua_type": "Helicopter (or Multirotor)",
                    "id": f"{random.randint(10000000, 99999999)}{random.choice(string.ascii_uppercase)}291",
                    "MAC": "8e:3b:93:22:33:fa",
                    "rssi": rssi
                }
            },
            {
                "Location/Vector Message": {
                    "latitude": latitude,
                    "longitude": longitude,
                    "geodetic_altitude": round(random.uniform(50.0, 400.0), 2),
                    "height_agl": round(random.uniform(20.0, 200.0), 2),
                    "speed": round(random.uniform(0.0, 30.0), 1),
                    "vert_speed": round(random.uniform(-5.0, 5.0), 1),
                    "timestamp": timestamp,
                }
            }
        ]
        
        # NEW BACKEND/ENRICHMENT FIELDS (from dragonsync.py/drone.py)
        message.append({
            "freq": round(random.uniform(5725000000, 5875000000), 2),  # Frequency in Hz (5.8GHz FPV band)
            "seen_by": f"wardragon-{random.randint(100, 199)}",  # WarDragon kit ID
            "observed_at": unix_timestamp,  # Unix timestamp
            "rid_timestamp": timestamp,  # ISO8601 timestamp
            "rid": {  # FAA RID enrichment from faa-rid-lookup
                "tracking": random.choice(["Active", "Lost", "Unknown"]),
                "status": random.choice(["Valid", "Expired", "Unknown"]),
                "make": random.choice(["DJI", "Autel", "Skydio", "Parrot", "Unknown"]),
                "model": random.choice(["Mavic 3", "Mini 4 Pro", "Air 3", "EVO II", "X2", "Unknown"]),
                "source": random.choice(["FAA", "EASA", "CAA", "Unknown"]),
                "lookup_success": random.choice([True, False])
            }
        })
        
        if mode == "zmq":
            return json.dumps(message, indent=4)
        elif mode == "multicast":
            return json.dumps(message)

    def generate_esp32_format(self):
        """Generate a telemetry message in ESP32-compatible format following a figure-8 flight path"""
        now = datetime.now(timezone.utc)
        timestamp = now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        unix_timestamp = now.timestamp()
        
        # time parameter for smooth pattern
        t = time.time() * 0.1
        
        # Center point of flight area
        center_lat = (self.lat_range[0] + self.lat_range[1]) / 2
        center_lon = (self.lon_range[0] + self.lon_range[1]) / 2
        
        # Radius of the figure-8 pattern
        radius_lat = (self.lat_range[1] - self.lat_range[0]) / 3
        radius_lon = (self.lon_range[1] - self.lon_range[0]) / 3
        
        # Figure-8 coordinates
        latitude = round(center_lat + radius_lat * math.sin(t), 6)
        longitude = round(center_lon + radius_lon * math.sin(2 * t), 6)
        
        # Smooth altitude changes around 300m ±50m
        alt = round(300 + 50 * math.sin(0.5 * t), 1)
        height_agl = round(alt - 100, 1)
        
        # Compute movement deltas for speed and course
        let_dx = radius_lon * math.cos(2 * t)
        let_dy = radius_lat * math.cos(t)
        speed = round(15 + 5 * math.cos(t), 1)
        vspeed = round(2.5 * math.cos(0.5 * t), 2)
        
        # Calculate course: direction of motion, then turn 90° left
        course = (math.degrees(math.atan2(let_dx, let_dy)) - 90) % 360
        
        # Other fields
        mac = self.random_mac()
        rssi = -60 + int(10 * math.sin(t))
        desc = f"DJI {random.randint(100, 199)}"
        uid = f"{random.randint(103, 103)}"
        
        message = {
            "index": 10,
            "runtime": round(now.timestamp()),
            "Basic ID": {
                "id": uid,
                "id_type": "Serial Number (ANSI/CTA-2063-A)",
                "ua_type": 0,
                "MAC": mac,
                "RSSI": rssi
            },
            "Location/Vector Message": {
                "latitude": latitude,
                "longitude": longitude,
                "speed": speed,
                "vert_speed": vspeed,
                "geodetic_altitude": alt,
                "height_agl": height_agl,
                "status": 2,
                "op_status": "Ground",
                "height_type": "Above Takeoff",
                "ew_dir_segment": "East",
                "speed_multiplier": "0.25",
                "direction": round(course, 1),
                "alt_pressure": 100,
                "horiz_acc": 10,
                "vert_acc": 4,
                "baro_acc": 6,
                "speed_acc": 3
            },
            "Self-ID Message": {
                "description_type": 0,
                "description": desc
            },
            "System Message": {
                "latitude": center_lat,
                "longitude": center_lon,
                "operator_lat": center_lat,
                "operator_lon": center_lon,
                "operator_id": "NotMe",
                "home_lat": center_lat,
                "home_lon": center_lon,
                "operator_alt_geo": 20,
                "classification": 1,
                "timestamp": round(now.timestamp() * 1000)
            },
            "Operator ID Message": {
                "protocol_version": "F3411.22",
                "operator_id_type": "Operator ID",
                "operator_id": "NotMe"
            },
            # NEW BACKEND/ENRICHMENT FIELDS
            "freq": round(random.uniform(5725000000, 5875000000), 2),  # Frequency in Hz (5.8GHz FPV band)
            "seen_by": f"wardragon-{random.randint(100, 199)}",  # WarDragon kit ID
            "observed_at": unix_timestamp,  # Unix timestamp
            "rid_timestamp": timestamp,  # ISO8601 timestamp
            "rid": {  # FAA RID enrichment from faa-rid-lookup
                "make": random.choice(["DJI", "Autel", "Skydio", "Parrot"]),
                "model": random.choice(["Mavic 3", "Mini 4 Pro", "Air 3", "EVO II", "X2"]),
                "source": random.choice(["faa", "dronedb", "caa"])
            }
        }
        
        return json.dumps(message, indent=4)
    

    def generate_status_message(self):
        """Generate system status message matching DragonSync wardragon_monitor.py format"""
        runtime = int(time.time() - self.start_time)
        current_time = datetime.now(timezone.utc)
        time_str = current_time.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        stale_str = (current_time + timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        unix_timestamp = current_time.timestamp()
        
        # System location with movement
        lat = (self.lat_range[0] + self.lat_range[1]) / 2 + random.uniform(-0.0001, 0.0001)
        lon = (self.lon_range[0] + self.lon_range[1]) / 2 + random.uniform(-0.0001, 0.0001)
        alt = 50 + random.uniform(-5, 5)
        
        # GPS data including speed and track for the track element
        speed = round(random.uniform(0, 25), 2)  # Speed in m/s
        track = round(random.uniform(0, 360), 1)  # Track/course in degrees
        
        # Generate system stats
        serial_number = f"wardragon-{random.randint(100,102)}"
        cpu_usage = round(random.uniform(0, 100), 1)
        
        # Memory in MB
        total_memory = 8192 * 1024
        available_memory = round(random.uniform(total_memory * 0.3, total_memory * 0.8), 2)
        
        # Disk in MB
        total_disk = 512000 * 1024
        used_disk = round(random.uniform(total_disk * 0.1, total_disk * 0.9), 2)
        
        # Temperatures
        temperature = round(random.uniform(30, 70), 1)
        pluto_temp = round(random.uniform(40, 60), 1)
        zynq_temp = round(random.uniform(35, 55), 1)
        
        # Backend enrichment fields (even though system status doesn't use all of these, include for consistency)
        freq = round(random.uniform(5725000000, 5875000000), 2)
        seen_by = serial_number
        rid_make = random.choice(["DJI", "Autel", "Skydio", "Parrot"])
        rid_model = random.choice(["Mavic 3", "Mini 4 Pro", "Air 3", "EVO II", "X2"])
        rid_source = random.choice(["FAA", "EASA", "CAA"])
        
        message = f"""<?xml version='1.0' encoding='UTF-8'?>
<event version="2.0" uid="{serial_number}" type="a-f-G-E-S" time="{time_str}" start="{time_str}" stale="{stale_str}" how="m-g">
    <point lat="{lat:.6f}" lon="{lon:.6f}" hae="{alt:.1f}" ce="35.0" le="999999"/>
    <detail>
        <contact endpoint="" phone="" callsign="{serial_number}"/>
        <precisionlocation geopointsrc="gps" altsrc="gps"/>
        <remarks>CPU Usage: {cpu_usage}%, Memory Total: {total_memory:.2f} MB, Memory Available: {available_memory:.2f} MB, Disk Total: {total_disk:.2f} MB, Disk Used: {used_disk:.2f} MB, Temperature: {temperature}°C, Uptime: {runtime} seconds, Pluto Temp: {pluto_temp}°C, Zynq Temp: {zynq_temp}°C; Seen By: {seen_by}; Observed At: {unix_timestamp}</remarks>
        <color argb="-256"/>
        <track course="{track}" speed="{speed:.2f}"/>
    </detail>
</event>"""
        
        return message

    def print_sample_fpv_json(self):
        """Print a sample FPV detection JSON message for testing"""
        sample_data = {
            "timestamp": "2025-05-01T14:22:33.123Z",
            "model": "Mpdds1+DJI O2",
            "mode": 0,
            "bandwidth_low": 10,
            "bandwidth_high": 20,
            "freq": 2421.175779,
            "rssi": -32.025200
        }
        
        fpv_detection = {
            "FPV Detection": {
                "timestamp": sample_data["timestamp"],
                "device_type": sample_data["model"],
                "frequency": round(sample_data["freq"], 2),
                "bandwidth": f"{sample_data['bandwidth_low']}/{sample_data['bandwidth_high']}M",
                "signal_strength": round(sample_data["rssi"]),
                "detection_source": sample_data["model"]
            }
        }
        
        json_message = json.dumps([fpv_detection], indent=2)
        print("ANT FPV Detection JSON:")
        print(json_message)
        
        return json_message

def setup_zmq():
    context = zmq.Context()
    cot_socket = context.socket(zmq.PUB)
    status_socket = context.socket(zmq.PUB)
    return context, cot_socket, status_socket

# ============================================================================
# MQTT TEST FUNCTIONS
# ============================================================================

def test_mqtt_connection(config):
    """Test MQTT broker connectivity and publish sample messages"""
    if not MQTT_AVAILABLE:
        print("❌ MQTT testing requires paho-mqtt: pip3 install paho-mqtt")
        input("\nPress Enter to continue...")
        return
    
    clear_screen()
    print("🔌 MQTT Broker Connection Test")
    print(f"\nBroker: {config.mqtt_broker}:{config.mqtt_port}")
    print(f"Base Topic: {config.mqtt_base_topic}")
    
    try:
        client = mqtt.Client(client_id=f"wardragon_test_{random.randint(1000,9999)}")
        
        if config.mqtt_username and config.mqtt_password:
            client.username_pw_set(config.mqtt_username, config.mqtt_password)
        
        if config.mqtt_use_tls:
            client.tls_set()
        
        # Connection callback
        def on_connect(client, userdata, flags, rc):
            if rc == 0:
                print("✅ Connected to MQTT broker successfully!")
            else:
                print(f"❌ Connection failed with code: {rc}")
        
        def on_publish(client, userdata, mid):
            print(f"📤 Message published (ID: {mid})")
        
        client.on_connect = on_connect
        client.on_publish = on_publish
        
        print("\n🔄 Connecting...")
        client.connect(config.mqtt_broker, config.mqtt_port, 60)
        client.loop_start()
        time.sleep(2)
        
        # Publish test messages
        print("\n📡 Publishing test messages...")
        
        # 1. Test drone detection
        drone_topic = f"{config.mqtt_base_topic}/drones/TEST_DRONE"
        drone_payload = json.dumps({
            "mac": "AA:BB:CC:DD:EE:FF",
            "latitude": 37.25,
            "longitude": -115.75,
            "altitude": 150.0,
            "rssi": -65,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "manufacturer": "DJI",
            "uaType": "Helicopter"
        })
        client.publish(drone_topic, drone_payload, qos=1)
        time.sleep(0.5)
        
        # 2. Test system status
        status_topic = f"{config.mqtt_base_topic}/status"
        status_payload = json.dumps({
            "status": "online",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "device": "wardragon_test"
        })
        client.publish(status_topic, status_payload, qos=1, retain=True)
        time.sleep(0.5)
        
        # 3. Test system stats
        system_topic = f"{config.mqtt_base_topic}/system"
        system_payload = json.dumps({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "cpuUsage": 25.5,
            "memoryUsed": 45.2,
            "dronesTracked": 1,
            "uptime": "1h 23m"
        })
        client.publish(system_topic, system_payload, qos=0)
        
        print("\n✅ Test messages published successfully!")
        print(f"\n📊 Published to:")
        print(f"   • {drone_topic}")
        print(f"   • {status_topic}")
        print(f"   • {system_topic}")
        
        time.sleep(1)
        client.loop_stop()
        client.disconnect()
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
    
    input("\n\nPress Enter to continue...")

# ============================================================================
# TAK SERVER TEST FUNCTIONS
# ============================================================================

def test_tak_connection(config, generator):
    """Test TAK server connectivity and send CoT messages"""
    clear_screen()
    print("🎯 TAK Server Connection Test")
    print(f"\nServer: {config.tak_host}:{config.tak_port}")
    print(f"Protocol: {config.tak_protocol.upper()}")
    
    try:
        if config.tak_protocol in ['tcp', 'tls']:
            # TCP/TLS connection
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(10)
            
            print(f"\n🔄 Connecting to {config.tak_host}:{config.tak_port}...")
            sock.connect((config.tak_host, config.tak_port))
            print("✅ Connected successfully!")
            
            # Send test CoT message
            print("\n📡 Sending test CoT XML...")
            cot_xml = generator.generate_drone_cot_with_track()
            sock.sendall(cot_xml.encode('utf-8'))
            print("✅ CoT message sent!")
            
            time.sleep(1)
            
            # Send status message
            print("📡 Sending system status CoT...")
            status_xml = generator.generate_status_message()
            sock.sendall(status_xml.encode('utf-8'))
            print("✅ Status message sent!")
            
            sock.close()
            
        elif config.tak_protocol == 'udp':
            # UDP connection
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            
            print(f"\n📡 Sending via UDP to {config.tak_host}:{config.tak_port}...")
            
            # Send test messages
            cot_xml = generator.generate_drone_cot_with_track()
            sock.sendto(cot_xml.encode('utf-8'), (config.tak_host, config.tak_port))
            print("✅ CoT message sent!")
            
            time.sleep(0.5)
            
            status_xml = generator.generate_status_message()
            sock.sendto(status_xml.encode('utf-8'), (config.tak_host, config.tak_port))
            print("✅ Status message sent!")
            
            sock.close()
        
        print("\n✅ TAK server test completed successfully!")
        
    except socket.timeout:
        print("\n❌ Connection timeout")
    except ConnectionRefusedError:
        print("\n❌ Connection refused - is TAK server running?")
    except Exception as e:
        print(f"\n❌ Error: {e}")
    
    input("\n\nPress Enter to continue...")

# ============================================================================
# ADS-B READSB SIMULATION
# ============================================================================

class ReadsbHTTPHandler(BaseHTTPRequestHandler):
    """HTTP handler that serves readsb-compatible aircraft.json"""
    
    def do_GET(self):
        if self.path == '/data/aircraft.json':
            # Generate realistic aircraft data
            now = time.time()
            
            aircraft = []
            for i in range(random.randint(3, 8)):
                # Generate ICAO hex
                hex_id = ''.join(random.choices('0123456789ABCDEF', k=6))
                
                # Position around Area 51
                lat = 37.25 + random.uniform(-0.2, 0.2)
                lon = -115.75 + random.uniform(-0.2, 0.2)
                
                aircraft.append({
                    "hex": hex_id,
                    "flight": f"N{random.randint(100,999)}AB",
                    "alt_baro": random.randint(5000, 35000),
                    "gs": random.randint(150, 500),
                    "track": random.randint(0, 359),
                    "lat": round(lat, 6),
                    "lon": round(lon, 6),
                    "seen": round(random.uniform(0, 10), 1),
                    "rssi": round(random.uniform(-25, -10), 1),
                    "category": random.choice(["A1", "A2", "A3", "A5"]),
                    "squawk": f"{random.randint(1000, 7777):04d}"
                })
            
            response = {
                "now": now,
                "messages": random.randint(10000, 50000),
                "aircraft": aircraft
            }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress logging
        pass

def start_adsb_server(config):
    """Start simulated ADS-B readsb HTTP server"""
    clear_screen()
    print("✈️  Starting ADS-B Readsb Simulator")
    print(f"\nHTTP Server: http://localhost:{config.adsb_port}")
    print(f"Endpoint: /data/aircraft.json")
    
    try:
        server = HTTPServer(('0.0.0.0', config.adsb_port), ReadsbHTTPHandler)
        print("\n✅ Server started successfully!")
        print("\n📡 Serving random aircraft data...")
        print("   Press Ctrl+C to stop\n")
        
        server.serve_forever()
        
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped")
        server.shutdown()
    except OSError as e:
        if "Address already in use" in str(e):
            print(f"\n❌ Port {config.adsb_port} already in use")
        else:
            print(f"\n❌ Error: {e}")
    
    input("\nPress Enter to continue...")

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

def configure_mqtt_settings(config):
    """Configure MQTT broker settings"""
    clear_screen()
    print("🔧 MQTT Configuration")
    print(f"\nCurrent Settings:")
    print(f"  Broker: {config.mqtt_broker}:{config.mqtt_port}")
    print(f"  Base Topic: {config.mqtt_base_topic}")
    print(f"  TLS: {'Enabled' if config.mqtt_use_tls else 'Disabled'}")
    
    print("\n1. Change Broker Host")
    print("2. Change Port")
    print("3. Set Username/Password")
    print("4. Change Base Topic")
    print("5. Toggle TLS")
    print("6. Back")
    
    choice = input("\nEnter choice (1-6): ")
    
    if choice == '1':
        config.mqtt_broker = input("Enter broker host: ")
    elif choice == '2':
        try:
            config.mqtt_port = int(input("Enter port: "))
        except ValueError:
            print("Invalid port")
    elif choice == '3':
        config.mqtt_username = input("Username (blank for none): ") or None
        if config.mqtt_username:
            config.mqtt_password = input("Password: ") or None
    elif choice == '4':
        config.mqtt_base_topic = input("Enter base topic: ")
    elif choice == '5':
        config.mqtt_use_tls = not config.mqtt_use_tls

def configure_tak_settings(config):
    """Configure TAK server settings"""
    clear_screen()
    print("🔧 TAK Server Configuration")
    print(f"\nCurrent Settings:")
    print(f"  Server: {config.tak_host}:{config.tak_port}")
    print(f"  Protocol: {config.tak_protocol.upper()}")
    
    print("\n1. Change Host")
    print("2. Change Port")
    print("3. Change Protocol (TCP/UDP/TLS)")
    print("4. Back")
    
    choice = input("\nEnter choice (1-4): ")
    
    if choice == '1':
        config.tak_host = input("Enter host: ")
    elif choice == '2':
        try:
            config.tak_port = int(input("Enter port: "))
        except ValueError:
            print("Invalid port")
    elif choice == '3':
        protocol = input("Enter protocol (tcp/udp/tls): ").lower()
        if protocol in ['tcp', 'udp', 'tls']:
            config.tak_protocol = protocol

def configure_adsb_settings(config):
    """Configure ADS-B settings"""
    clear_screen()
    print("🔧 ADS-B Configuration")
    print(f"\nCurrent Settings:")
    print(f"  HTTP Port: {config.adsb_port}")
    
    print("\n1. Change Port")
    print("2. Back")
    
    choice = input("\nEnter choice (1-2): ")
    
    if choice == '1':
        try:
            config.adsb_port = int(input("Enter port: "))
        except ValueError:
            print("Invalid port")

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')
    
def get_valid_number(prompt, min_val, max_val):
    while True:
        try:
            value = float(input(prompt))
            if min_val <= value <= max_val:
                return value
            print(f"Please enter a number between {min_val} and {max_val}")
        except ValueError:
            print("Please enter a valid number")
            
def configure_settings(config):
    clear_screen()
    print("📝 Configure Settings")
    print("\n1. Change Broadcast Mode")
    print("2. Change Host/Group")
    print("3. Change CoT Port")
    print("4. Change Status Port")
    print("5. Back to Main Menu")
    
    choice = input("\nEnter your choice (1-5): ")
    
    if choice == '1':
        mode = input("Enter broadcast mode (multicast/zmq): ").lower()
        if mode in ['multicast', 'zmq']:
            config.broadcast_mode = mode
            
    elif choice == '2':
        if config.broadcast_mode == 'multicast':
            config.multicast_group = input("Enter multicast group (e.g., 0.0.0.0): ")
        else:
            config.zmq_host = input("Enter ZMQ host (e.g., 127.0.0.1): ")
            
    elif choice == '3':
        try:
            config.cot_port = int(input("Enter CoT port: "))
        except ValueError:
            print("Invalid port number")
            
    elif choice == '4':
        try:
            config.status_port = int(input("Enter Status port: "))
        except ValueError:
            print("Invalid port number")

def main_menu():
    config = Config()
    generator = DroneMessageGenerator()
    
    while True:
        clear_screen()
        print("🐉 WarDragon Enhanced Test Suite 🐉")
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("CURRENT SETTINGS:")
        print(f"  Multicast/ZMQ: {config.broadcast_mode} @ {config.multicast_group if config.broadcast_mode == 'multicast' else config.zmq_host}:{config.cot_port}")
        print(f"  MQTT: {config.mqtt_broker}:{config.mqtt_port} | Topic: {config.mqtt_base_topic}")
        print(f"  TAK: {config.tak_protocol.upper()}://{config.tak_host}:{config.tak_port}")
        print(f"  ADS-B: HTTP Port {config.adsb_port}")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        print("\n📡 MULTICAST/ZMQ TESTS")
        print("  1. Multicast: DragonSync Drone CoT XML (with Track)")
        print("  2. Multicast: DragonSync Pilot CoT XML")
        print("  3. Multicast: DragonSync Home/Takeoff CoT XML")
        print("  4. Multicast: DragonSync Status XML (with Track)")
        print("  5. ZMQ: ESP32 JSON Format (RID Telemetry)")
        print("  6. ZMQ: FPV Detection Messages")
        print("  7. Multicast: Broadcast All DragonSync XML Messages")
        print("  8. ZMQ: Broadcast All ESP32 JSON + FPV")
        
        print("\n🔌 MQTT TESTS")
        print("  M. Test MQTT Connection & Publish")
        
        print("\n🎯 TAK SERVER TESTS")
        print("  T. Test TAK Server Connection & Send CoT")
        
        print("\n✈️  ADS-B TESTS")
        print("  A. Start ADS-B Readsb Simulator")
        
        print("\n⚙️  CONFIGURATION")
        print("  C. Configure Multicast/ZMQ Settings")
        print("  Q. Configure MQTT Settings")
        print("  K. Configure TAK Settings")
        print("  B. Configure ADS-B Settings")
        
        print("\n  0. Exit")
        
        choice = input("\nEnter your choice: ").upper()
        
        if choice == '0':
            print("\n👋 Goodbye!")
            break
        
        # Configuration menus
        if choice == 'C':
            configure_settings(config)
            continue
        elif choice == 'Q':
            configure_mqtt_settings(config)
            continue
        elif choice == 'K':
            configure_tak_settings(config)
            continue
        elif choice == 'B':
            configure_adsb_settings(config)
            continue
        
        # MQTT test
        elif choice == 'M':
            test_mqtt_connection(config)
            continue
        
        # TAK test
        elif choice == 'T':
            test_tak_connection(config, generator)
            continue
        
        # ADS-B test
        elif choice == 'A':
            start_adsb_server(config)
            continue
        
        if choice in ['1', '2', '3', '4', '5', '6', '7', '8']:
            interval = get_valid_number("\nEnter broadcast interval in seconds (0.1-60): ", 0.1, 60)
            
            if config.broadcast_mode == 'multicast':
                cot_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                status_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                
                ttl = struct.pack('b', 1)
                cot_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                status_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                cot_sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, ttl)
                status_sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, ttl)
            else:
                context, cot_sock, status_sock = setup_zmq()
                cot_sock.bind(f"tcp://{config.zmq_host}:{config.cot_port}")
                status_sock.bind(f"tcp://{config.zmq_host}:{config.status_port}")
                
            clear_screen()
            print(f"🚀 Broadcasting messages every {interval} seconds via {config.broadcast_mode}")
            print(f"CoT messages to: {config.cot_port}")
            print(f"Status messages to: {config.status_port}")
            print("Press Ctrl+C to return to menu\n")
            
            try:
                while True:
                    if choice == '1':  # DragonSync Drone CoT with Track
                        message = generator.generate_drone_cot_with_track()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(message)
                            
                        print(f"📡 Sent DragonSync Drone CoT (with track) at {time.strftime('%H:%M:%S')}")
                        print(f"Message preview: {message[:200]}...\n")
                    
                    elif choice == '2':  # DragonSync Pilot CoT
                        message = generator.generate_pilot_cot()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(message)
                            
                        print(f"📡 Sent DragonSync Pilot CoT at {time.strftime('%H:%M:%S')}")
                        print(f"Message preview: {message[:200]}...\n")
                    
                    elif choice == '3':  # DragonSync Home CoT
                        message = generator.generate_home_cot()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(message)
                            
                        print(f"📡 Sent DragonSync Home/Takeoff CoT at {time.strftime('%H:%M:%S')}")
                        print(f"Message preview: {message[:200]}...\n")
                    
                    elif choice == '4':  # DragonSync Status with Track
                        message = generator.generate_status_message()
                        
                        if config.broadcast_mode == 'multicast':
                            status_sock.sendto(message.encode(), (config.multicast_group, config.status_port))
                        else:
                            status_sock.send_string(message)
                            
                        print(f"📡 Sent DragonSync Status (with track) at {time.strftime('%H:%M:%S')}")
                        print(f"Message preview: {message[:200]}...\n")
                    
                    elif choice == '5':  # ESP32 Format
                        message = generator.generate_esp32_format()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(message)
                            
                        print(f"📡 Sent ESP32 format message at {time.strftime('%H:%M:%S')}")
                    
                    elif choice == '6':  # FPV Detection Messages
                        init_message = generator.generate_fpv_detection_message()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(init_message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(init_message)
                            
                        print(f"📡 Sent FPV Detection message at {time.strftime('%H:%M:%S')}")
                        
                        try:
                            update_count = 0
                            while True:
                                time.sleep(interval)
                                update_message = generator.generate_fpv_update_message()
                                
                                if config.broadcast_mode == 'multicast':
                                    cot_sock.sendto(update_message.encode(), (config.multicast_group, config.cot_port))
                                else:
                                    cot_sock.send_string(update_message)
                                    
                                update_count += 1
                                print(f"📡 Sent FPV Update message #{update_count} at {time.strftime('%H:%M:%S')}")
                        except KeyboardInterrupt:
                            break
                    
                    elif choice == '7':  # Broadcast All DragonSync XML Messages (Multicast)
                        # Send drone CoT
                        drone_message = generator.generate_drone_cot_with_track()
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(drone_message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(drone_message)
                        
                        time.sleep(0.1)  # Small delay between messages
                        
                        # Send pilot CoT
                        pilot_message = generator.generate_pilot_cot()
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(pilot_message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(pilot_message)
                        
                        time.sleep(0.1)
                        
                        # Send home CoT
                        home_message = generator.generate_home_cot()
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(home_message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(home_message)
                        
                        time.sleep(0.1)
                        
                        # Send status message
                        status_message = generator.generate_status_message()
                        if config.broadcast_mode == 'multicast':
                            status_sock.sendto(status_message.encode(), (config.multicast_group, config.status_port))
                        else:
                            status_sock.send_string(status_message)
                            
                        print(f"📡 Sent Complete DragonSync XML Message Set at {time.strftime('%H:%M:%S')}")
                        print(f"   ✓ Drone CoT XML (with track)")
                        print(f"   ✓ Pilot CoT XML")
                        print(f"   ✓ Home CoT XML") 
                        print(f"   ✓ Status CoT XML (with track)\n")
                    
                    elif choice == '8':  # Broadcast All ESP32 JSON + FPV (ZMQ)
                        # Send ESP32 RID telemetry JSON
                        esp32_message = generator.generate_esp32_format()
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(esp32_message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(esp32_message)
                        
                        time.sleep(0.1)
                        
                        # Send FPV detection
                        fpv_message = generator.generate_fpv_detection_message()
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(fpv_message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(fpv_message)
                        
                        time.sleep(0.1)
                        
                        # Send FPV update
                        fpv_update = generator.generate_fpv_update_message()
                        if fpv_update:
                            if config.broadcast_mode == 'multicast':
                                cot_sock.sendto(fpv_update.encode(), (config.multicast_group, config.cot_port))
                            else:
                                cot_sock.send_string(fpv_update)
                        
                        print(f"📡 Sent Complete ESP32/ZMQ JSON Message Set at {time.strftime('%H:%M:%S')}")
                        print(f"   ✓ ESP32 RID Telemetry JSON")
                        print(f"   ✓ FPV Detection JSON")
                        print(f"   ✓ FPV Update JSON\n")

                    time.sleep(interval)

            except KeyboardInterrupt:
                print("\n\n🛑 Broadcast stopped")
                if config.broadcast_mode == 'multicast':
                    cot_sock.close()
                    status_sock.close()
                else:
                    context.destroy()
                input("\nPress Enter to return to menu...")
                
if __name__ == "__main__":
    try:
        main_menu()
    except KeyboardInterrupt:
        print("\n\n👋 Program terminated by user")
    except Exception as e:
        print(f"\n❌ An error occurred: {e}")
