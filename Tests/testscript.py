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
    print(" paho-mqtt not installed. MQTT features disabled.")
    print("   Install with: pip3 install paho-mqtt")

# Try to import requests for OpenSky API testing
try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False
    print(" requests not installed. OpenSky API testing disabled.")
    print("   Install with: pip3 install requests")

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
        
        # OpenSky Network settings
        self.opensky_username = None  # Optional: for authenticated requests
        self.opensky_password = None
        
class DroneMessageGenerator:
    def __init__(self):
        self.lat_range = (37.2, 37.3)
        self.lon_range = (-115.8, -115.7)  
        self.msg_index = 0
        self.start_time = time.time()
        
        # Track drone states for realistic movement and consistent IDs
        self.drone_states = {}
        # Realistic serial numbers matching actual drone formats
        self.drone_ids = [
            "112624150A90E3AE1EC0",  # ESP32 format (20 chars hex)
            "3NZDJ1Y0010ABC",         # DJI format
            "1869600XXYYZZ"           # Ruko/Generic format
        ]
        self.current_drone_index = 0
        self.current_drone_id = self.drone_ids[0]
        
        # CAA registration IDs for testing
        self.caa_ids = ["123456", "789ABC", "XYZ999"]
        self.current_caa_index = 0


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
        
        self.current_drone_index = (self.current_drone_index + 1) % len(self.drone_ids)
        uid = self.drone_ids[self.current_drone_index]
        self.current_drone_id = uid
        
        mac = self.random_mac()
        rssi = -60 + int(10 * math.sin(t))
        desc = f"Anzu Raptor {uid}"
        
        # NEW BACKEND/ENRICHMENT FIELDS
        freq = round(random.uniform(5725000000, 5875000000), 2)  # Frequency in Hz (5.8GHz FPV band)
        seen_by = f"wardragon-{random.randint(100, 199)}"  # WarDragon kit ID
        rid_make = random.choice(["DJI", "Autel", "Skydio", "Parrot"])
        rid_model = random.choice(["Mavic 3", "Mini 4 Pro", "Air 3", "EVO II", "X2"])
        rid_source = random.choice(["FAA", "EASA", "CAA"])
        
        # Match exact DragonSync format
        xml = f"""<?xml version='1.0' encoding='UTF-8'?>
<event version="2.0" uid="{uid}" type="a-u-A-M-H-R" time="{time_str}" start="{start_str}" stale="{stale_str}" how="m-g">
    <point lat="{lat:.6f}" lon="{lon:.6f}" hae="{alt:.1f}" ce="35.0" le="999999"/>
    <detail>
        <contact callsign="{uid}"/>
        <precisionlocation geopointsrc="gps" altsrc="gps"/>
        <track course="{course:.1f}" speed="{speed:.1f}"/>
        <remarks>MAC: {mac}, RSSI: {rssi}dBm; ID Type: Serial Number (ANSI/CTA-2063-A); UA Type: Helicopter or Multirotor (2); Operator ID: TestOperator; Speed: {speed:.1f} m/s; Vert Speed: {vspeed:.1f} m/s; Altitude: {alt:.1f} m; AGL: {height_agl:.1f} m; Direction: {course:.1f}°; Index: {random.randint(1, 100)}; Runtime: {int(time.time() - self.start_time)}s; Freq: {freq} Hz; Seen By: {seen_by}; Observed At: {unix_timestamp}; RID Time: {time_str}; RID: {rid_make} {rid_model} ({rid_source})</remarks>
        <color argb="-256"/>
    </detail>
</event>"""
        
        # Debug: Print track info periodically
        if int(time.time() * 10) % 50 == 0:
            print(f"  DEBUG:  Drone XML: UID={uid} Lat={lat:.6f} Lon={lon:.6f} Course={course:.1f}° Speed={speed:.1f}m/s")
        
        return xml

    def generate_pilot_cot(self):
        """Generate separate pilot CoT message matching DragonSync format"""
        time_str, start_str, stale_str = self.get_timestamps()
        
        # Pilot moves in a walking pattern (slow, realistic movement)
        # Use slower time scale so pilot moves visibly but slowly
        t = time.time() * 0.02  # Much slower than drone
        
        center_lat = (self.lat_range[0] + self.lat_range[1]) / 2
        center_lon = (self.lon_range[0] + self.lon_range[1]) / 2
        
        # Pilot walks in a small oval pattern (realistic for someone tracking a drone)
        # Movement radius: ~200-300 meters
        pilot_lat = center_lat + 0.002 * math.sin(t)  # ~200m north-south
        pilot_lon = center_lon + 0.002 * math.cos(t * 0.7)  # ~200m east-west
        pilot_alt = 50 + 2 * math.sin(t * 0.3)  # Small altitude changes (terrain)
        
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
        
        # Home point moves slowly (pilot might relocate their "home" base)
        # Use very slow time scale - home point shouldn't move much
        t = time.time() * 0.01  # Even slower than pilot
        
        center_lat = (self.lat_range[0] + self.lat_range[1]) / 2
        center_lon = (self.lon_range[0] + self.lon_range[1]) / 2
        
        # Home point drifts slowly (pilot might be in a vehicle or moving base station)
        # Very small movement: ~100m over long period
        home_lat = center_lat + 0.001 * math.sin(t)  # ~100m drift
        home_lon = center_lon + 0.001 * math.cos(t)  # ~100m drift
        home_alt = 100 + 5 * math.sin(t * 0.5)  # Minor altitude variations
        
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
        """Generate an FPV detection message compatible with fpv_mdn_receiver.py output
        
        Format matches actual hardware output from fpvparser.py:
        - Frequency: 5.6-5.9 GHz range (FPV video frequencies in MHz)
        - RSSI: 1200-1400 range (actual observed raw values from hardware)
        - Source: inst-node format (e.g., "01-97e8")
        - Distance: Uses empirical RSSI-based calculation matching fpvparser.py
        """
        now = datetime.now(timezone.utc)
        timestamp = now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        
        # Realistic FPV frequencies in MHz (5.6-5.9 GHz band used by FPV drones)
        # Common channels: 5621, 5645, 5665, 5685, 5705, 5725, 5745, 5765, 5785, 5805, 5825, 5845, 5865, 5885
        frequency = random.choice([5621, 5645, 5665, 5685, 5705, 5725, 5745, 5765, 5785, 5805, 5825, 5845, 5865, 5885])
        
        # FPV video bandwidth (typically 20-40 MHz)
        bandwidth = f"{random.choice([20, 40])}MHz"
        
        # Realistic RSSI values from actual hardware (raw ADC values around 1200-1400)
        rssi = random.randint(1200, 1400)
        
        # Source node in inst-node format (matches hardware output)
        source_inst = f"{random.randint(1, 5):02d}"
        source_node = f"{random.randint(1000, 9999):04x}"  # Use hex like hardware does (e.g., "97e8")
        detection_source = f"{source_inst}-{source_node}"
        
        # Calculate distance using empirical formula from fpvparser.py
        # Higher RSSI = stronger signal = closer distance
        if rssi >= 2000:
            distance = 10.0
        elif rssi >= 1800:
            distance = 25.0
        elif rssi >= 1600:
            distance = 50.0
        elif rssi >= 1400:
            distance = 100.0
        elif rssi >= 1200:
            # Linear interpolation: rssi 1400 -> 100m, rssi 1200 -> 200m
            distance = 300 - (rssi - 1200) * 0.5
        elif rssi >= 1000:
            distance = 500.0
        else:
            distance = 1000.0
        
        # Initialize or reuse existing detection
        if not hasattr(self, 'current_fpv_detection'):
            self.current_fpv_detection = {
                'frequency': frequency,
                'source_inst': source_inst,
                'source_node': source_node,
                'detection_source': detection_source,
                'rssi': rssi,
                'time': 0
            }
        else:
            frequency = self.current_fpv_detection['frequency']
            source_inst = self.current_fpv_detection['source_inst']
            source_node = self.current_fpv_detection['source_node']
            detection_source = self.current_fpv_detection['detection_source']
            rssi = self.current_fpv_detection['rssi']
            # Recalculate distance with current RSSI
            if rssi >= 1400:
                distance = 100.0
            elif rssi >= 1200:
                distance = 300 - (rssi - 1200) * 0.5
            else:
                distance = 200.0
            
        # Format matches fpv_mdn_receiver.py detection_messages output
        # This is what's published to ZMQ after "detection_messages = [{"FPV Detection": ...}]"
        detection_message = [
            {
                "FPV Detection": {
                    "timestamp": timestamp,
                    "manufacturer": source_inst,  # Instance ID from hardware
                    "device_type": f"FPV{frequency}MHz",  # e.g., "FPV5621MHz"
                    "frequency": frequency,  # Raw frequency in MHz
                    "bandwidth": bandwidth,
                    "signal_strength": rssi,  # Raw RSSI value (1200-1400 range)
                    "detection_source": detection_source,  # e.g., "01-97e8"
                    "status": "NEW CONTACT LOCK",
                    "estimated_distance": distance  # Distance in meters based on RSSI
                }
            }
        ]
        
        return json.dumps(detection_message)
    
    def generate_fpv_update_message(self):
        """Generate an FPV update message in the format of LOCK UPDATE messages
        
        This matches the actual AUX_ADV_IND format from fpv_mdn_receiver.py
        Format is used for ongoing signal strength updates after initial detection
        """
        now = datetime.now(timezone.utc)
        timestamp = now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        
        if not hasattr(self, 'current_fpv_detection'):
            return None
        
        # Get cached detection info
        detection_source = self.current_fpv_detection['detection_source']
        frequency = self.current_fpv_detection['frequency']
        
        # Simulate realistic RSSI fluctuation (±20-30 units is typical for FPV hardware)
        rssi_variation = random.uniform(-30, 30)
        rssi = self.current_fpv_detection['rssi'] + rssi_variation
        # Clamp to reasonable range (1000-1600)
        rssi = max(1000, min(1600, rssi))
        self.current_fpv_detection['rssi'] = rssi
        
        # Recalculate distance based on new RSSI (matching fpvparser.py formula)
        if rssi >= 2000:
            distance = 10.0
        elif rssi >= 1800:
            distance = 25.0
        elif rssi >= 1600:
            distance = 50.0
        elif rssi >= 1400:
            distance = 100.0
        elif rssi >= 1200:
            distance = 300 - (rssi - 1200) * 0.5
        elif rssi >= 1000:
            distance = 500.0
        else:
            distance = 1000.0
        
        # Increment time counter (matches hardware behavior)
        self.current_fpv_detection['time'] += 10  # Hardware updates every ~10 seconds
        
        # Format matches actual fpv_mdn_receiver.py zmq_formatted_msg output
        update_message = {
            "AUX_ADV_IND": {
                "rssi": rssi,  # Raw ADC value (not dBm)
                "aa": 2391391958,  # Fixed advertising address (matches hardware: 0x8e89bed6)
                "time": timestamp
            }, 
            "aext": {
                "AdvA": f"{detection_source} random"  # Source node identifier
            },
            "AdvData": "020116faff0d01",  # OpenDroneID header (matches hardware)
            "location": {
                "lat": 0.0,  # FPV detector doesn't have location data
                "lon": 0.0
            },
            "distance": distance,  # Estimated distance in meters
            "frequency": frequency  # Keep original frequency in MHz
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
        
        # Calculate course: direction of motion
        dx = math.cos(t * 2) * radius_lon
        dy = math.cos(t) * radius_lat
        course = (math.degrees(math.atan2(dx, dy))) % 360
        
        # Cycle through drone IDs for multiple drones
        self.current_drone_index = (self.current_drone_index + 1) % len(self.drone_ids)
        uid = self.drone_ids[self.current_drone_index]
        self.current_drone_id = uid
        
        # Other fields
        mac = self.random_mac()
        rssi = -60 + int(10 * math.sin(t))
        desc = f"DJI {uid}"
        
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
        print("MQTT testing requires paho-mqtt: pip3 install paho-mqtt")
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
                print("Connected to MQTT broker successfully!")
            else:
                print(f"Connection failed with code: {rc}")
        
        def on_publish(client, userdata, mid):
            print(f"📤 Message published (ID: {mid})")
        
        client.on_connect = on_connect
        client.on_publish = on_publish
        
        print("\nDEBUG:  Connecting...")
        client.connect(config.mqtt_broker, config.mqtt_port, 60)
        client.loop_start()
        time.sleep(2)
        
        # Publish test messages
        print("\nDEBUG:  Publishing test messages...")
        
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
        
        print("\nTest messages published successfully!")
        print(f"\n📊 Published to:")
        print(f"   • {drone_topic}")
        print(f"   • {status_topic}")
        print(f"   • {system_topic}")
        
        time.sleep(1)
        client.loop_stop()
        client.disconnect()
        
    except Exception as e:
        print(f"\nError: {e}")
    
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
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(10)
            
            print(f"\nDEBUG:  Connecting to {config.tak_host}:{config.tak_port}...")
            sock.connect((config.tak_host, config.tak_port))
            print(" Connected successfully!")
            
            print("\nDEBUG:  Sending test CoT XML...")
            cot_xml = generator.generate_drone_cot_with_track()
            sock.sendall(cot_xml.encode('utf-8'))
            print(" CoT message sent!")
            
            time.sleep(1)
            
            print("DEBUG:  Sending system status CoT...")
            status_xml = generator.generate_status_message()
            sock.sendall(status_xml.encode('utf-8'))
            print(" Status message sent!")
            
            sock.close()
            
        elif config.tak_protocol == 'udp':
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            
            print(f"\nDEBUG:  Sending via UDP to {config.tak_host}:{config.tak_port}...")
            print("(UDP is connectionless - no handshake needed)\n")
            
            cot_xml = generator.generate_drone_cot_with_track()
            bytes_sent = sock.sendto(cot_xml.encode('utf-8'), (config.tak_host, config.tak_port))
            print(f" CoT message sent! ({bytes_sent} bytes)")
            print(f"   UID: {generator.current_drone_id}")
            
            time.sleep(0.5)
            
            status_xml = generator.generate_status_message()
            bytes_sent = sock.sendto(status_xml.encode('utf-8'), (config.tak_host, config.tak_port))
            print(f" Status message sent! ({bytes_sent} bytes)")
            
            time.sleep(0.5)
            
            pilot_xml = generator.generate_pilot_cot()
            bytes_sent = sock.sendto(pilot_xml.encode('utf-8'), (config.tak_host, config.tak_port))
            print(f" Pilot message sent! ({bytes_sent} bytes)")
            
            time.sleep(0.5)
            
            home_xml = generator.generate_home_cot()
            bytes_sent = sock.sendto(home_xml.encode('utf-8'), (config.tak_host, config.tak_port))
            print(f" Home message sent! ({bytes_sent} bytes)")
            
            sock.close()
        
        print(f"\n TAK server test completed successfully!")
        print(f"\n💡 Check your TAK clients (ATAK/WinTAK/iTAK) for new contacts")
        print(f"   Look for UIDs starting with: {generator.current_drone_id}")
        
    except socket.timeout:
        print("\nConnection timeout")
    except ConnectionRefusedError:
        print("\nConnection refused - is TAK server running?")
    except socket.gaierror:
        print(f"\nCannot resolve hostname: {config.tak_host}")
    except Exception as e:
        print(f"\nError: {e}")
    
    input("\n\nPress Enter to continue...")

# ============================================================================
# ADS-B READSB SIMULATION
# ============================================================================
class ADSBSimulator:
    def __init__(self, count=6):
        self.aircraft = []
        # Center of operations (e.g., Area 51)
        self.center_lat = 37.24
        self.center_lon = -115.81
        
        for i in range(count):
            self.aircraft.append({
                "hex": f"{random.randint(0x100000, 0xFFFFFF):06X}",
                "flight": f"TEST{i+1:02d}",
                "pattern": i % 3,  # Cycle through Circle, Figure-8, and Ellipse
                "lane": 0.04 + (i * 0.03),  # Each plane gets a 0.03 degree "lane" separation
                "speed": 0.05 + (random.uniform(0.02, 0.05)),
                "alt": 10000 + (i * 3000), # Separated by 3000ft altitude increments
                "phase": random.uniform(0, math.pi * 2) # Random start point in the loop
            })
            
    def get_aircraft_json(self):
        t = time.time()
        current_aircraft = []
        
        for ac in self.aircraft:
            move_t = (t * ac["speed"]) + ac["phase"]
            lane = ac["lane"]
            
            # Pattern 0: Perfect Circle
            if ac["pattern"] == 0:
                lat_off = lane * math.sin(move_t)
                lon_off = lane * math.cos(move_t)
                
            # Pattern 1: Figure-8 (Lissajous)
            elif ac["pattern"] == 1:
                lat_off = lane * math.sin(move_t)
                lon_off = (lane * 1.5) * math.sin(2 * move_t) / 2
                
            # Pattern 2: Wide Ellipse
            else:
                lat_off = (lane * 0.7) * math.sin(move_t)
                lon_off = (lane * 1.8) * math.cos(move_t)
                
            # Calculate Heading (Track)
            # We use a small look-ahead delta to see where the plane is going
            dt = 0.01
            if ac["pattern"] == 0:
                next_lat = lane * math.sin(move_t + dt)
                next_lon = lane * math.cos(move_t + dt)
            elif ac["pattern"] == 1:
                next_lat = lane * math.sin(move_t + dt)
                next_lon = (lane * 1.5) * math.sin(2 * (move_t + dt)) / 2
            else:
                next_lat = (lane * 0.7) * math.sin(move_t + dt)
                next_lon = (lane * 1.8) * math.cos(move_t + dt)
                
            track = math.degrees(math.atan2(next_lon - lon_off, next_lat - lat_off)) % 360
            
            current_aircraft.append({
                "hex": ac["hex"],
                "flight": ac["flight"],
                "alt_baro": ac["alt"],
                "gs": 200 + (ac["lane"] * 1000), # Further out planes fly faster
                "track": round(track, 1),
                "lat": round(self.center_lat + lat_off, 6),
                "lon": round(self.center_lon + lon_off, 6),
                "seen": 0.1,
                "rssi": -18.5,
                "category": "A1"
            })
            
        return {
            "now": time.time(),
            "messages": 123456,
            "aircraft": current_aircraft
        }

class ReadsbHTTPHandler(BaseHTTPRequestHandler):
    simulator = None # Assigned during server startup
    
    def do_GET(self):
        if self.path == '/data/aircraft.json':
            if ReadsbHTTPHandler.simulator:
                data = ReadsbHTTPHandler.simulator.get_aircraft_json()
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()
            
    def log_message(self, format, *args):
        pass # Keep console clean


def start_adsb_server(config):
    """Start simulated ADS-B readsb HTTP server with persistent aircraft"""
    clear_screen()
    print("DEBUG:   Starting Persistent ADS-B Simulator")
    print(f"\nEndpoint: http://localhost:{config.adsb_port}/data/aircraft.json")
    
    try:
        # Initialize the persistent data
        simulator = ADSBSimulator(count=5)
        ReadsbHTTPHandler.simulator = simulator
        
        server = HTTPServer(('0.0.0.0', config.adsb_port), ReadsbHTTPHandler)
        print("\n Server started! Aircraft are now flying in circles.")
        print("   Press Ctrl+C to stop\n")
        
        server.serve_forever()
        
    except KeyboardInterrupt:
        print("\n\nServer stopped")
        server.shutdown()
    except Exception as e:
        print(f"\nError: {e}")
        
    input("\nPress Enter to continue...")

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

def configure_mqtt_settings(config):
    """Configure MQTT broker settings"""
    clear_screen()
    print("DEBUG:  MQTT Configuration")
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
    print("DEBUG:  TAK Server Configuration")
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
    print("DEBUG:  ADS-B Configuration")
    print(f"\nCurrent Settings:")
    print(f"  HTTP Port: {config.adsb_port}")
    
    print("\n1. Change Port")
    print("2. Back")
    
    choice = input("\nEnter choice (1-2): ")
    
    if choice == '1':
        try:
            new_port = int(input(f"Enter port [{config.adsb_port}]: "))
            config.adsb_port = new_port
            print(f"Port updated to {config.adsb_port}")
        except ValueError:
            print("Invalid port number")
    
    input("\nPress Enter to continue...")

def configure_opensky_settings(config):
    """Configure OpenSky Network settings"""
    clear_screen()
    print("DEBUG:  OpenSky Network Configuration")
    print(f"\nCurrent Settings:")
    print(f"  Username: {config.opensky_username or 'Not set (anonymous)'}")
    print(f"  Password: {'*' * len(config.opensky_password) if config.opensky_password else 'Not set'}")
    
    print("\n📝 Note: OpenSky Network allows anonymous requests but has rate limits.")
    print("   Authenticated requests get higher rate limits and more features.")
    print("   Register at: https://opensky-network.org\n")
    
    print("1. Set/Change Username")
    print("2. Set/Change Password")
    print("3. Clear Credentials (use anonymous)")
    print("4. Back")
    
    choice = input("\nEnter choice (1-4): ")
    
    if choice == '1':
        username = input("Enter OpenSky username (blank to cancel): ").strip()
        if username:
            config.opensky_username = username
            print(f"Username set to: {username}")
    elif choice == '2':
        password = input("Enter OpenSky password (blank to cancel): ").strip()
        if password:
            config.opensky_password = password
            print("Password updated")
    elif choice == '3':
        config.opensky_username = None
        config.opensky_password = None
        print("Credentials cleared - will use anonymous access")
    
    input("\nPress Enter to continue...")

# ============================================================================
# OPENSKY NETWORK TEST FUNCTIONS
# ============================================================================

def get_approximate_location():
    """Try to get approximate location from IP geolocation (requires internet)"""
    try:
        # Using a free IP geolocation service
        response = requests.get('http://ip-api.com/json/', timeout=5)
        if response.status_code == 200:
            data = response.json()
            if data.get('status') == 'success':
                return {
                    'lat': data.get('lat'),
                    'lon': data.get('lon'),
                    'city': data.get('city'),
                    'country': data.get('country')
                }
    except:
        pass
    return None

def test_opensky_api(config):
    """Test OpenSky Network API and display live aircraft data"""
    if not REQUESTS_AVAILABLE:
        print("OpenSky testing requires requests: pip3 install requests")
        input("\nPress Enter to continue...")
        return
    
    clear_screen()
    print("DEBUG:   OpenSky Network API Test")
    print("\nOpenSky provides LIVE aircraft data from real ADS-B receivers worldwide.")
    print("Note: This is separate from the local ADS-B readsb simulator.\n")
    
    # Try to get user's location
    print("🔍 Attempting to detect your location...")
    location = get_approximate_location()
    
    if location:
        print(f"Detected: {location['city']}, {location['country']}")
        print(f"   Coordinates: {location['lat']:.2f}, {location['lon']:.2f}")
        default_lat = location['lat']
        default_lon = location['lon']
    else:
        print(" Could not detect location, using Area 51 region as default")
        default_lat = 37.25
        default_lon = -115.75
    
    # Get user's area of interest
    print("\nEnter geographic bounds to search for aircraft:")
    print("(Leave blank to use detected/default location)\n")
    
    try:
        lat_input = input(f"Center Latitude [{default_lat}]: ").strip()
        lon_input = input(f"Center Longitude [{default_lon}]: ").strip()
        radius_input = input("Radius in degrees [0.5]: ").strip()
        
        center_lat = float(lat_input) if lat_input else default_lat
        center_lon = float(lon_input) if lon_input else default_lon
        radius = float(radius_input) if radius_input else 0.5
        
        # Calculate bounding box
        lamin = center_lat - radius
        lamax = center_lat + radius
        lomin = center_lon - radius
        lomax = center_lon + radius
        
        print(f"\n🔍 Searching for aircraft in area:")
        print(f"   Latitude: {lamin:.2f} to {lamax:.2f}")
        print(f"   Longitude: {lomin:.2f} to {lomax:.2f}")
        
        # Build OpenSky API URL
        # API documentation: https://openskynetwork.github.io/opensky-api/rest.html
        url = f"https://opensky-network.org/api/states/all?lamin={lamin}&lomin={lomin}&lamax={lamax}&lomax={lomax}"
        
        print(f"\nDEBUG:  Fetching data from OpenSky Network...")
        print(f"   URL: {url}")
        
        # Make API request with authentication if available
        auth = None
        if config.opensky_username and config.opensky_password:
            auth = (config.opensky_username, config.opensky_password)
            print(f"   Using authenticated access as: {config.opensky_username}")
        else:
            print(f"   Using anonymous access (rate limited)")
        
        response = requests.get(url, timeout=10, auth=auth)
        
        if response.status_code == 200:
            data = response.json()
            
            if not data or 'states' not in data or not data['states']:
                print("\n No aircraft found in this area")
                print("   Try a different location or larger radius")
                print("   Note: Not all areas have ADS-B coverage")
            else:
                aircraft_count = len(data['states'])
                timestamp = data.get('time', 'unknown')
                
                print(f"\nSuccessfully retrieved data!")
                print(f"   Timestamp: {datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S UTC')}")
                print(f"   Aircraft found: {aircraft_count}")
                print("\n" + "="*80)
                
                # Display aircraft details
                for i, state in enumerate(data['states'][:10]):  # Limit to first 10
                    icao24 = state[0] or "Unknown"
                    callsign = (state[1] or "").strip() or "N/A"
                    origin_country = state[2] or "Unknown"
                    longitude = state[5]
                    latitude = state[6]
                    baro_altitude = state[7]
                    velocity = state[9]
                    true_track = state[10]
                    
                    print(f"\nDEBUG:   Aircraft #{i+1}:")
                    print(f"   ICAO24: {icao24}")
                    print(f"   Callsign: {callsign}")
                    print(f"   Country: {origin_country}")
                    
                    if latitude and longitude:
                        print(f"   Position: {latitude:.6f}, {longitude:.6f}")
                    else:
                        print(f"   Position: Not available")
                    
                    if baro_altitude:
                        print(f"   Altitude: {baro_altitude:.0f} m ({baro_altitude * 3.28084:.0f} ft)")
                    else:
                        print(f"   Altitude: Not available")
                    
                    if velocity:
                        print(f"   Speed: {velocity:.1f} m/s ({velocity * 1.94384:.1f} knots)")
                    else:
                        print(f"   Speed: Not available")
                    
                    if true_track:
                        print(f"   Heading: {true_track:.1f}°")
                    else:
                        print(f"   Heading: Not available")
                
                if aircraft_count > 10:
                    print(f"\n   ... and {aircraft_count - 10} more aircraft")
                
                print("\n" + "="*80)
                
                # Offer to convert to CoT format
                convert = input("\nDEBUG:  Convert to CoT XML format? (y/n): ").lower()
                if convert == 'y':
                    print("\nDEBUG:  Generating CoT messages...")
                    cot_messages = []
                    
                    for state in data['states']:
                        if state[6] and state[5]:  # Has valid lat/lon
                            lat = state[6]
                            lon = state[5]
                            alt = state[7] or 0
                            speed = (state[9] or 0) * 1.94384  # m/s to knots
                            track = state[10] or 0
                            callsign = (state[1] or "").strip() or state[0]
                            
                            now = datetime.now(timezone.utc)
                            time_str = now.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
                            stale_str = (now + timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
                            
                            cot = f"""<?xml version='1.0' encoding='UTF-8'?>
<event version="2.0" uid="ADSB-{state[0]}" type="a-f-A-C-F" time="{time_str}" start="{time_str}" stale="{stale_str}" how="m-g">
    <point lat="{lat:.6f}" lon="{lon:.6f}" hae="{alt:.1f}" ce="100.0" le="999999"/>
    <detail>
        <contact callsign="{callsign}"/>
        <track course="{track:.1f}" speed="{speed:.1f}"/>
        <remarks>OpenSky Network: {state[2]}, ICAO24: {state[0]}</remarks>
        <color argb="-256"/>
    </detail>
</event>"""
                            cot_messages.append(cot)
                    
                    print(f"Generated {len(cot_messages)} CoT messages")
                    print(f"\nSample CoT message:")
                    print(cot_messages[0] if cot_messages else "No messages generated")
                    
                    # Offer to broadcast
                    if cot_messages:
                        broadcast = input(f"\n📤 Broadcast these to {config.broadcast_mode}? (y/n): ").lower()
                        if broadcast == 'y':
                            if config.broadcast_mode == 'multicast':
                                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                                ttl = struct.pack('b', 1)
                                sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, ttl)
                                
                                for cot in cot_messages:
                                    sock.sendto(cot.encode(), (config.multicast_group, config.cot_port))
                                    time.sleep(0.1)
                                
                                sock.close()
                                print(f"Broadcast {len(cot_messages)} messages via multicast")
                            else:
                                context = zmq.Context()
                                sock = context.socket(zmq.PUB)
                                sock.bind(f"tcp://{config.zmq_host}:{config.cot_port}")
                                time.sleep(0.5)  # Let socket bind
                                
                                for cot in cot_messages:
                                    sock.send_string(cot)
                                    time.sleep(0.1)
                                
                                context.destroy()
                                print(f"Broadcast {len(cot_messages)} messages via ZMQ")
        
        elif response.status_code == 401:
            print("\nAuthentication failed")
            print("   OpenSky API requires authentication for some queries")
            print("   You may need to register at https://opensky-network.org")
        
        elif response.status_code == 404:
            print("\nAPI endpoint not found")
            print("   Check that you have internet connectivity")
        
        else:
            print(f"\nAPI request failed with status code: {response.status_code}")
            print(f"   Response: {response.text}")
    
    except requests.exceptions.Timeout:
        print("\nRequest timed out")
        print("   Check your internet connection")
    
    except requests.exceptions.ConnectionError:
        print("\nConnection error")
        print("   Check your internet connection")
        print("   OpenSky Network may be unavailable")
    
    except ValueError as e:
        print(f"\nInvalid input: {e}")
    
    except Exception as e:
        print(f"\nError: {e}")
    
    input("\n\nPress Enter to continue...")

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

def quick_test_mode(config, generator):
    """Quick test mode - broadcasts directly to app without external services"""
    clear_screen()
    print("🚀 QUICK TEST MODE - Direct to WarDragon App")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("\nThis mode broadcasts test data directly to your app.")
    print("Built-in simulated services - no external setup required!")
    print("\nWhat to test:")
    print("  1. Complete Drone Scenario (All XML - Drone/Pilot/Home/Status)")
    print("  2. FPV Detection Scenario")
    print("  3. Mixed Drone + FPV Scenario")
    print("  4. Simulated Flight Path (Continuous)")
    print("  5. Everything At Once (Drone + FPV + MQTT + TAK + ADS-B)")
    print("  6. Back to Main Menu")
    
    choice = input("\nEnter choice (1-6): ")
    
    if choice == '6':
        return
    
    # Determine mode from config
    if choice in ['1', '2', '3', '4', '5']:
        interval = 2.0  # Default to 2 seconds
        
        # Setup simulated services for option 5
        mqtt_client = None
        tak_socket = None
        adsb_server = None
        adsb_thread = None
        
        if choice == '5':
            print("\nDEBUG:  Setting up simulated services...")
            
            # Setup MQTT if available
            if MQTT_AVAILABLE:
                try:
                    mqtt_client = mqtt.Client(client_id=f"wardragon_quicktest_{random.randint(1000,9999)}")
                    if config.mqtt_username and config.mqtt_password:
                        mqtt_client.username_pw_set(config.mqtt_username, config.mqtt_password)
                    mqtt_client.connect(config.mqtt_broker, config.mqtt_port, 60)
                    mqtt_client.loop_start()
                    print("MQTT client connected")
                except Exception as e:
                    print(f" MQTT connection failed: {e}")
                    mqtt_client = None
            
            # Setup TAK socket
            try:
                if config.tak_protocol in ['tcp', 'tls']:
                    tak_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    tak_socket.connect((config.tak_host, config.tak_port))
                else:
                    tak_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                print(f"TAK {config.tak_protocol.upper()} connection established")
            except Exception as e:
                print(f" TAK connection failed: {e}")
                tak_socket = None
            
            # Setup ADS-B HTTP server in background thread
            try:
                from http.server import HTTPServer
                adsb_server = HTTPServer(('0.0.0.0', config.adsb_port), ReadsbHTTPHandler)
                adsb_thread = threading.Thread(target=adsb_server.serve_forever, daemon=True)
                adsb_thread.start()
                print(f"ADS-B server started on port {config.adsb_port}")
            except Exception as e:
                print(f" ADS-B server failed: {e}")
                adsb_server = None
        
        print(f"\n⚙️  Using {config.broadcast_mode.upper()} mode")
        print(f"DEBUG:  Broadcasting to: {config.multicast_group if config.broadcast_mode == 'multicast' else config.zmq_host}:{config.cot_port}")
        
        if choice == '5':
            print(f"\n🔌 Additional Services Active:")
            if mqtt_client:
                print(f"   • MQTT → {config.mqtt_broker}:{config.mqtt_port}")
            if tak_socket:
                print(f"   • TAK → {config.tak_host}:{config.tak_port}")
            if adsb_server:
                print(f"   • ADS-B → http://localhost:{config.adsb_port}/data/aircraft.json")
        
        print(f"\nYour app should now show detections!")
        print("\nPress Ctrl+C to stop\n")
        
        # Setup sockets
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
        
        try:
            counter = 0
            while True:
                counter += 1
                timestamp = time.strftime('%H:%M:%S')
                
                if choice == '1':  # Complete Drone Scenario
                    # Send drone
                    drone_msg = generator.generate_drone_cot_with_track()
                    if config.broadcast_mode == 'multicast':
                        cot_sock.sendto(drone_msg.encode(), (config.multicast_group, config.cot_port))
                    else:
                        cot_sock.send_string(drone_msg)
                    
                    time.sleep(0.1)
                    
                    # Send pilot
                    pilot_msg = generator.generate_pilot_cot()
                    if config.broadcast_mode == 'multicast':
                        cot_sock.sendto(pilot_msg.encode(), (config.multicast_group, config.cot_port))
                    else:
                        cot_sock.send_string(pilot_msg)
                    
                    time.sleep(0.1)
                    
                    # Send home
                    home_msg = generator.generate_home_cot()
                    if config.broadcast_mode == 'multicast':
                        cot_sock.sendto(home_msg.encode(), (config.multicast_group, config.cot_port))
                    else:
                        cot_sock.send_string(home_msg)
                    
                    time.sleep(0.1)
                    
                    # Send status
                    status_msg = generator.generate_status_message()
                    if config.broadcast_mode == 'multicast':
                        status_sock.sendto(status_msg.encode(), (config.multicast_group, config.status_port))
                    else:
                        status_sock.send_string(status_msg)
                    
                    print(f"[{timestamp}] Update #{counter}: ✓ Drone ✓ Pilot ✓ Home ✓ Status")
                
                elif choice == '2':  # FPV Detection Scenario
                    if counter == 1:
                        # Initial FPV detection
                        fpv_init = generator.generate_fpv_detection_message()
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(fpv_init.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(fpv_init)
                        print(f"[{timestamp}] FPV Detection: New signal detected!")
                    else:
                        # FPV updates
                        fpv_update = generator.generate_fpv_update_message()
                        if fpv_update:
                            if config.broadcast_mode == 'multicast':
                                cot_sock.sendto(fpv_update.encode(), (config.multicast_group, config.cot_port))
                            else:
                                cot_sock.send_string(fpv_update)
                            print(f"[{timestamp}] FPV Update #{counter-1}: Signal strength updated")
                
                elif choice == '3':  # Mixed Scenario
                    # Send drone
                    drone_msg = generator.generate_drone_cot_with_track()
                    if config.broadcast_mode == 'multicast':
                        cot_sock.sendto(drone_msg.encode(), (config.multicast_group, config.cot_port))
                    else:
                        cot_sock.send_string(drone_msg)
                    
                    time.sleep(0.1)
                    
                    # Send FPV
                    if counter == 1:
                        fpv_msg = generator.generate_fpv_detection_message()
                    else:
                        fpv_msg = generator.generate_fpv_update_message()
                    
                    if fpv_msg:
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(fpv_msg.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(fpv_msg)
                    
                    time.sleep(0.1)
                    
                    # Send status
                    status_msg = generator.generate_status_message()
                    if config.broadcast_mode == 'multicast':
                        status_sock.sendto(status_msg.encode(), (config.multicast_group, config.status_port))
                    else:
                        status_sock.send_string(status_msg)
                    
                    print(f"[{timestamp}] Update #{counter}: ✓ Drone ✓ FPV ✓ Status")
                
                elif choice == '4':  # Simulated Flight Path
                    # Generate ONLY the drone message with track data
                    # Do NOT send pilot/home messages - these are filtered by WarDragon
                    drone_msg = generator.generate_drone_cot_with_track()
                    status_msg = generator.generate_status_message()
                    
                    if config.broadcast_mode == 'multicast':
                        cot_sock.sendto(drone_msg.encode(), (config.multicast_group, config.cot_port))
                        time.sleep(0.05)
                        status_sock.sendto(status_msg.encode(), (config.multicast_group, config.status_port))
                    else:
                        cot_sock.send_string(drone_msg)
                        time.sleep(0.05)
                        status_sock.send_string(status_msg)
                    
                    # Extract position and track data for debug display
                    import re
                    lat_match = re.search(r'lat="([^"]+)"', drone_msg)
                    lon_match = re.search(r'lon="([^"]+)"', drone_msg)
                    course_match = re.search(r'course="([^"]+)"', drone_msg)
                    speed_match = re.search(r'speed="([^"]+)"', drone_msg)
                    uid_match = re.search(r'uid="([^"]+)"', drone_msg)
                    
                    if lat_match and lon_match and course_match and speed_match:
                        uid = uid_match.group(1) if uid_match else "unknown"
                        print(f"[{timestamp}] 🛸 Update #{counter}: UID={uid} Pos=({lat_match.group(1)}, {lon_match.group(1)}) Course={course_match.group(1)}° Speed={speed_match.group(1)}m/s")
                    else:
                        print(f"[{timestamp}] Flight update #{counter}: Complete message sent")
                
                elif choice == '5':  # Everything At Once
                    # 1. Send primary CoT messages (Drone, Pilot, Home, Status)
                    drone_msg = generator.generate_drone_cot_with_track()
                    pilot_msg = generator.generate_pilot_cot()
                    home_msg = generator.generate_home_cot()
                    status_msg = generator.generate_status_message()
                    
                    if config.broadcast_mode == 'multicast':
                        cot_sock.sendto(drone_msg.encode(), (config.multicast_group, config.cot_port))
                        time.sleep(0.05)
                        cot_sock.sendto(pilot_msg.encode(), (config.multicast_group, config.cot_port))
                        time.sleep(0.05)
                        cot_sock.sendto(home_msg.encode(), (config.multicast_group, config.cot_port))
                        time.sleep(0.05)
                        status_sock.sendto(status_msg.encode(), (config.multicast_group, config.status_port))
                    else:
                        cot_sock.send_string(drone_msg)
                        time.sleep(0.05)
                        cot_sock.send_string(pilot_msg)
                        time.sleep(0.05)
                        cot_sock.send_string(home_msg)
                        time.sleep(0.05)
                        status_sock.send_string(status_msg)
                    
                    # 2. Send FPV message
                    if counter == 1:
                        fpv_msg = generator.generate_fpv_detection_message()
                    else:
                        fpv_msg = generator.generate_fpv_update_message()
                    
                    if fpv_msg:
                        time.sleep(0.05)
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(fpv_msg.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(fpv_msg)
                    
                    # 3. Publish to MQTT
                    if mqtt_client:
                        try:
                            # Parse drone position from XML
                            import re
                            lat_match = re.search(r'lat="([^"]+)"', drone_msg)
                            lon_match = re.search(r'lon="([^"]+)"', drone_msg)
                            alt_match = re.search(r'hae="([^"]+)"', drone_msg)
                            
                            drone_data = {
                                "mac": generator.random_mac(),
                                "latitude": float(lat_match.group(1)) if lat_match else 37.25,
                                "longitude": float(lon_match.group(1)) if lon_match else -115.75,
                                "altitude": float(alt_match.group(1)) if alt_match else 100.0,
                                "rssi": random.randint(-80, -40),
                                "timestamp": datetime.now(timezone.utc).isoformat(),
                                "manufacturer": "DJI",
                                "uaType": "Helicopter"
                            }
                            
                            mqtt_topic = f"{config.mqtt_base_topic}/drones/QUICKTEST_{counter}"
                            mqtt_client.publish(mqtt_topic, json.dumps(drone_data), qos=1)
                        except Exception as e:
                            pass  # Silent fail for MQTT
                    
                    # 4. Send to TAK server
                    if tak_socket:
                        try:
                            if config.tak_protocol in ['tcp', 'tls']:
                                tak_socket.sendall(drone_msg.encode('utf-8'))
                            else:
                                tak_socket.sendto(drone_msg.encode('utf-8'), (config.tak_host, config.tak_port))
                        except Exception as e:
                            pass  # Silent fail for TAK
                    
                    # 5. ADS-B is handled by the background HTTP server
                    # Extract position for display
                    import re
                    lat_match = re.search(r'lat="([^"]+)"', drone_msg)
                    lon_match = re.search(r'lon="([^"]+)"', drone_msg)
                    
                    services = []
                    services.append("CoT")
                    if fpv_msg:
                        services.append("FPV")
                    if mqtt_client:
                        services.append("MQTT")
                    if tak_socket:
                        services.append("TAK")
                    if adsb_server:
                        services.append("ADS-B")
                    
                    if lat_match and lon_match:
                        print(f"[{timestamp}] Update #{counter}: {' + '.join(services)} → ({lat_match.group(1)}, {lon_match.group(1)})")
                    else:
                        print(f"[{timestamp}] Update #{counter}: {' + '.join(services)} sent")
                
                time.sleep(interval)
                
        except KeyboardInterrupt:
            print("\n\nTest stopped")
            
            # Cleanup multicast/ZMQ
            if config.broadcast_mode == 'multicast':
                cot_sock.close()
                status_sock.close()
            else:
                context.destroy()
            
            # Cleanup additional services
            if mqtt_client:
                try:
                    mqtt_client.loop_stop()
                    mqtt_client.disconnect()
                    print("MQTT disconnected")
                except:
                    pass
            
            if tak_socket:
                try:
                    tak_socket.close()
                    print("TAK connection closed")
                except:
                    pass
            
            if adsb_server:
                try:
                    adsb_server.shutdown()
                    print("ADS-B server stopped")
                except:
                    pass
        
        input("\nPress Enter to continue...")

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
        print(f"  OpenSky: {'Authenticated (' + config.opensky_username + ')' if config.opensky_username else 'Anonymous (rate limited)'}")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        print("\n🚀 QUICK TEST (No External Services Required)")
        print("  X. Quick Test Mode - Test App Directly")
        
        print("\nDEBUG:  MULTICAST/ZMQ TESTS")
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
        
        print("\nDEBUG:   ADS-B TESTS")
        print("  A. Start ADS-B Readsb Simulator (Local HTTP Server)")
        
        print("\n🌐 OPENSKY NETWORK TESTS")
        print("  O. Test OpenSky API (Live Internet Aircraft Data)")
        
        print("\n⚙️  CONFIGURATION")
        print("  C. Configure Multicast/ZMQ Settings")
        print("  Q. Configure MQTT Settings")
        print("  K. Configure TAK Settings")
        print("  B. Configure ADS-B Settings")
        print("  S. Configure OpenSky Network Settings")
        
        print("\n  0. Exit")
        
        choice = input("\nEnter your choice: ").upper()
        
        if choice == '0':
            print("\n👋 Goodbye!")
            break
        
        # Quick Test Mode
        if choice == 'X':
            quick_test_mode(config, generator)
            continue
        
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
        elif choice == 'S':
            configure_opensky_settings(config)
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
        
        # OpenSky test
        elif choice == 'O':
            test_opensky_api(config)
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
                            
                        print(f"DEBUG:  Sent DragonSync Drone CoT (with track) at {time.strftime('%H:%M:%S')}")
                        print(f"Message preview: {message[:200]}...\n")
                    
                    elif choice == '2':  # DragonSync Pilot CoT
                        message = generator.generate_pilot_cot()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(message)
                            
                        print(f"DEBUG:  Sent DragonSync Pilot CoT at {time.strftime('%H:%M:%S')}")
                        print(f"Message preview: {message[:200]}...\n")
                    
                    elif choice == '3':  # DragonSync Home CoT
                        message = generator.generate_home_cot()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(message)
                            
                        print(f"DEBUG:  Sent DragonSync Home/Takeoff CoT at {time.strftime('%H:%M:%S')}")
                        print(f"Message preview: {message[:200]}...\n")
                    
                    elif choice == '4':  # DragonSync Status with Track
                        message = generator.generate_status_message()
                        
                        if config.broadcast_mode == 'multicast':
                            status_sock.sendto(message.encode(), (config.multicast_group, config.status_port))
                        else:
                            status_sock.send_string(message)
                            
                        print(f"DEBUG:  Sent DragonSync Status (with track) at {time.strftime('%H:%M:%S')}")
                        print(f"Message preview: {message[:200]}...\n")
                    
                    elif choice == '5':  # ESP32 Format
                        message = generator.generate_esp32_format()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(message)
                            
                        print(f"DEBUG:  Sent ESP32 format message at {time.strftime('%H:%M:%S')}")
                    
                    elif choice == '6':  # FPV Detection Messages
                        init_message = generator.generate_fpv_detection_message()
                        
                        if config.broadcast_mode == 'multicast':
                            cot_sock.sendto(init_message.encode(), (config.multicast_group, config.cot_port))
                        else:
                            cot_sock.send_string(init_message)
                            
                        print(f"DEBUG:  Sent FPV Detection message at {time.strftime('%H:%M:%S')}")
                        
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
                                print(f"DEBUG:  Sent FPV Update message #{update_count} at {time.strftime('%H:%M:%S')}")
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
                            
                        print(f"DEBUG:  Sent Complete DragonSync XML Message Set at {time.strftime('%H:%M:%S')}")
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
                        
                        print(f"DEBUG:  Sent Complete ESP32/ZMQ JSON Message Set at {time.strftime('%H:%M:%S')}")
                        print(f"   ✓ ESP32 RID Telemetry JSON")
                        print(f"   ✓ FPV Detection JSON")
                        print(f"   ✓ FPV Update JSON\n")

                    time.sleep(interval)

            except KeyboardInterrupt:
                print("\n\nBroadcast stopped")
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
        print(f"\nAn error occurred: {e}")
        
