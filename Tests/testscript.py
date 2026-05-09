#!/usr/bin/env python3
"""
DragonSync iOS — droneid-go + DragonSync scenario broadcaster.

Every JSON / XML shape in this script is sourced from:
  - droneid-go binary `json:"..."` struct tags (alphafox02/droneid-go)
  - DragonSync core/telemetry_parser.py
  - DragonSync core/drone.py to_cot_xml / to_pilot_cot_xml / to_home_cot_xml / to_dict
  - DragonSync utils/cot_builder.py build_drone_cot / build_pilot_cot / build_home_cot
  - DragonSync sinks/mqtt_sink.py (MQTT JSON wire format)

Scenarios (each can be broadcast independently or combined):
  wifi      WiFi RID frame, single dict (transport=wifi, frequency_mhz, full envelope)
  ble       BLE RID burst, BT split array with AUX_ADV_IND + aext (transport=ble)
  uart      UART/ESP32 frame, consolidated array (transport=uart)
  dji       DJI DroneID with Frequency Message + home location (transport=dji)
  area      Area beacon: System.area_count/radius/floor/ceiling
  auth      Multi-page Auth Message (page 0..N-1)
  caa       CAA-Assigned Registration ID variant
  utm       UTM(USS)-Assigned ID variant
  session   Specific Session ID variant
  multi     BLE array burst with 3 distinct drones in one frame
  health    droneid-go health/heartbeat snapshot (top-level service state)
  status    WarDragon monitor system status JSON (port 4225)
  spoof:K   Spoof scenario, K in {rssi, speed, teleport, altitude}
  cot       DragonSync drone CoT XML (multicast 239.2.3.1:6969, build_drone_cot format)
  pilot     DragonSync pilot CoT (uid=pilot-..., type=b-m-p-s-m)
  home      DragonSync home/takeoff CoT (uid=home-..., type=b-m-p-s-m)
  adsb      DragonSync ADS-B CoT (a-f-A) for aircraft track
  status_cot WarDragon monitor status CoT XML (uid=wardragon-..., type=b-m-p-s-m)
  mqtt_dict DragonSync to_dict() JSON shape (the MQTT/Lattice/API wire format)

Usage:
  ./testscript.py --scenario wifi
  ./testscript.py --scenario all --rate 5
  ./testscript.py --scenario cot --scenario pilot --scenario home
  ./testscript.py --scenario health --health-rate 0.2
  ./testscript.py --zmq-bind 0.0.0.0:4224 --status-bind 0.0.0.0:4225 --scenario all
  ./testscript.py --scenario mqtt_dict --mqtt-broker localhost
"""

import argparse
import json
import math
import random
import socket
import sys
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
from xml.sax.saxutils import escape as xml_escape

try:
    import zmq
except ImportError:
    print("ERROR: pyzmq not installed. pip install pyzmq", file=sys.stderr)
    sys.exit(1)

try:
    import paho.mqtt.client as mqtt
    MQTT_AVAILABLE = True
except ImportError:
    MQTT_AVAILABLE = False


# =====================================================================
# Source-verified enum tables
# =====================================================================

ID_TYPES = [
    "Serial Number (ANSI/CTA-2063-A)",
    "CAA Assigned Registration ID",
    "UTM (USS) Assigned ID",
    "Specific Session ID",
]

UA_TYPE_BY_NAME = {
    "None": 0, "Aeroplane": 1, "Helicopter": 2, "Gyroplane": 3,
    "Hybrid Lift": 4, "Ornithopter": 5, "Glider": 6, "Kite": 7,
    "Free Balloon": 8, "Captive Balloon": 9, "Airship": 10,
    "Free Fall": 11, "Rocket": 12, "Tethered Powered Aircraft": 13,
    "Ground Obstacle": 14, "Other": 15,
}

OP_STATUS = ["Undeclared", "Ground", "Airborne", "Emergency", "Remote ID System Failure"]
HEIGHT_TYPES = ["Above Takeoff", "AGL"]
CLASSIFICATION_TYPES = ["Undeclared", "EU"]
OPERATOR_LOCATION_TYPES = ["Takeoff", "Live GNSS", "Fixed Location"]
OPERATOR_ID_TYPES = ["Operator ID", "CAA Assigned Operator ID"]
SELF_ID_TEXT_TYPES = [0, 1, 2]
AUTH_TYPES = [
    "None", "UAS ID Signature", "Operator ID Signature",
    "Message Set Signature", "Network Remote ID", "Specific Authentication",
    "Private Use", "MFG Spec",
]
ACCURACY_STRINGS = ["<1m", "<3m", "<10m", "<30m", "<100m", "Unknown"]
PROTOCOL_VERSIONS = ["F3411.19", "F3411.22a"]


# =====================================================================
# Config
# =====================================================================

@dataclass
class Config:
    zmq_bind: str = "0.0.0.0:4224"
    status_bind: str = "0.0.0.0:4225"
    multicast_group: str = "239.2.3.1"
    multicast_port: int = 6969
    mqtt_broker: str = ""
    mqtt_port: int = 1883
    mqtt_topic: str = "wardragon/drone"
    rate_hz: float = 1.0
    health_rate_hz: float = 0.1
    status_rate_hz: float = 0.033
    scenarios: list = field(default_factory=lambda: ["wifi"])
    duration_s: float = 0.0
    seed: int = 0
    lat_center: float = 37.25
    lon_center: float = -115.75


# =====================================================================
# DroneSim — per-drone state for realistic continuity
# =====================================================================

class DroneSim:
    def __init__(self, drone_id, mac, ua_name, transport, cfg, id_type=None, caa_id=None):
        self.id = drone_id
        self.id_type = id_type or ID_TYPES[0]
        self.caa_id = caa_id
        self.mac = mac
        self.ua_type_name = ua_name
        self.ua_type = UA_TYPE_BY_NAME[ua_name]
        self.transport = transport
        self.cfg = cfg
        self.heading = random.uniform(0, 360)
        self.speed = random.uniform(2, 18)
        self.altitude = random.uniform(20, 120)
        self.height_agl = self.altitude
        self.lat = cfg.lat_center + random.uniform(-0.02, 0.02)
        self.lon = cfg.lon_center + random.uniform(-0.02, 0.02)
        self.home_lat = self.lat
        self.home_lon = self.lon
        self.operator_lat = self.lat - random.uniform(-0.001, 0.001)
        self.operator_lon = self.lon - random.uniform(-0.001, 0.001)
        self.index = random.randint(1, 200)
        self.runtime = random.randint(60, 1800)
        self.first_seen = time.time()
        self.frequency_mhz = {"wifi": 2412.0, "ble": 2402.0, "uart": 0.0, "dji": 5765.0}.get(transport, 0.0)
        self.protocol_version = random.choice(PROTOCOL_VERSIONS)
        self.rssi_baseline = random.randint(-78, -45)
        self.rssi = self.rssi_baseline
        self.operator_id_value = f"FAA{random.randint(1000, 9999)}-{random.randint(100,999)}"
        self.operator_id_type_value = random.choice(OPERATOR_ID_TYPES)

    def step(self, dt):
        self.heading = (self.heading + random.uniform(-8, 8)) % 360
        self.speed = max(0.0, self.speed + random.uniform(-1.5, 1.5))
        rad = math.radians(self.heading)
        d_lat = (self.speed * dt * math.cos(rad)) / 111000.0
        cos_lat = max(0.01, math.cos(math.radians(self.lat)))
        d_lon = (self.speed * dt * math.sin(rad)) / (111000.0 * cos_lat)
        self.lat += d_lat
        self.lon += d_lon
        self.altitude = max(0.0, self.altitude + random.uniform(-2, 2))
        self.height_agl = max(0.0, self.altitude)
        self.runtime += int(dt)
        self.index += 1
        self.rssi = max(-110, min(-20, self.rssi_baseline + random.randint(-3, 3)))


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def stale_iso(seconds=600):
    return (datetime.now(timezone.utc) + timedelta(seconds=seconds)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def random_mac():
    return ":".join(f"{random.randint(0, 255):02X}" for _ in range(6))


def random_aa():
    return random.randint(0, 0xFFFFFFFF)


# =====================================================================
# droneid-go ZMQ payload builders (envelope + sub-messages)
# =====================================================================

def build_basic_id(d, include_transport=True, include_frequency_mhz=True):
    obj = {
        "id": d.id,
        "id_type": d.id_type,
        "MAC": d.mac,
        "RSSI": d.rssi,
        "ua_type": d.ua_type_name,
        "protocol_version": d.protocol_version,
    }
    if include_transport:
        obj["transport"] = d.transport
    if include_frequency_mhz and d.frequency_mhz > 0:
        obj["frequency_mhz"] = d.frequency_mhz
    return obj


def build_location(d, include_canonical_accuracy=True):
    loc = {
        "latitude": round(d.lat, 7),
        "longitude": round(d.lon, 7),
        "geodetic_altitude": round(d.altitude, 1),
        "speed": round(d.speed, 2),
        "vert_speed": round(random.uniform(-2, 2), 2),
        "height_agl": round(d.height_agl, 1),
        "height_type": random.choice(HEIGHT_TYPES),
        "pressure_altitude": round(d.altitude + random.uniform(-3, 3), 1),
        "ew_dir_segment": random.choice(["E", "W"]),
        "speed_multiplier": random.choice(["0.25", "0.75"]),
        "op_status": random.choice(OP_STATUS),
        "direction": int(d.heading),
        "timestamp": int(time.time()),
        "status": random.randint(0, 4),
        "alt_pressure": round(d.altitude - 1.5, 1),
        "protocol_version": d.protocol_version,
    }
    if include_canonical_accuracy:
        loc.update({
            "horizontal_accuracy": random.choice(ACCURACY_STRINGS),
            "vertical_accuracy": random.choice(ACCURACY_STRINGS),
            "baro_accuracy": random.choice(ACCURACY_STRINGS),
            "speed_accuracy": random.choice(ACCURACY_STRINGS),
            "timestamp_accuracy": random.choice(["0.1s", "0.2s", "0.5s", "1.0s"]),
        })
    return loc


def build_system(d, include_area=False):
    sys_msg = {
        "latitude": round(d.operator_lat, 7),
        "longitude": round(d.operator_lon, 7),
        "operator_lat": round(d.operator_lat, 7),
        "operator_lon": round(d.operator_lon, 7),
        "home_lat": round(d.home_lat, 7),
        "home_lon": round(d.home_lon, 7),
        "operator_altitude_geo": round(d.altitude - 5.0, 1),
        "classification_type": random.choice(CLASSIFICATION_TYPES),
        "operator_location_type": random.choice(OPERATOR_LOCATION_TYPES),
        "timestamp": int(time.time()),
    }
    if include_area:
        sys_msg.update({
            "area_count": random.randint(1, 8),
            "area_radius": random.randint(50, 500),
            "area_floor": round(random.uniform(0, 30), 1),
            "area_ceiling": round(random.uniform(80, 400), 1),
        })
    return sys_msg


def build_self_id(d):
    return {
        "text": f"UAV {d.mac.lower()} operational",
        "text_type": random.choice(SELF_ID_TEXT_TYPES),
        "description": "DragonSync iOS test broadcast",
    }


def build_operator_id(d):
    return {
        "operator_id": d.operator_id_value,
        "operator_id_type": d.operator_id_type_value,
        "protocol_version": d.protocol_version,
    }


def build_auth_page(page_index, page_count, _d):
    payload = "".join(random.choices("0123456789ABCDEF", k=46 if page_index > 0 else 34))
    return {
        "auth_type": random.choice(AUTH_TYPES),
        "auth_data": payload,
        "page": page_index,
        "page_count": page_count,
        "length": len(payload) // 2,
        "timestamp": int(time.time()),
    }


def build_aux_adv_ind(d):
    return {
        "aa": random_aa(),
        "chan": 37 + random.randint(0, 2),
        "phy": random.choice([1, 2, 3]),
        "rssi": d.rssi,
        "addr": d.mac,
    }


def build_aext(d):
    return {
        "AdvA": f"{d.mac} (random)",
        "AdvData": "".join(random.choices("0123456789abcdef", k=64)),
        "AdvDataInfo": {
            "did": random.randint(0, 4095),
            "sid": random.randint(0, 15),
            "mac": d.mac,
        },
        "AdvMode": random.choice(["Connectable", "Non-Connectable", "Scannable"]),
    }


# =====================================================================
# droneid-go ZMQ scenarios
# =====================================================================

def scenario_wifi(d):
    return {
        "Basic ID": build_basic_id(d),
        "Location/Vector Message": build_location(d),
        "System Message": build_system(d),
        "Self-ID Message": build_self_id(d),
        "Operator ID Message": build_operator_id(d),
        "index": d.index,
        "runtime": d.runtime,
    }


def scenario_ble(d):
    aux = build_aux_adv_ind(d)
    aext = build_aext(d)
    return [
        {"Basic ID": build_basic_id(d), "AUX_ADV_IND": aux, "aext": aext},
        {"Location/Vector Message": build_location(d), "AUX_ADV_IND": aux, "aext": aext},
        {"System Message": build_system(d), "AUX_ADV_IND": aux, "aext": aext},
        {"Self-ID Message": build_self_id(d), "AUX_ADV_IND": aux, "aext": aext},
        {"Operator ID Message": build_operator_id(d), "AUX_ADV_IND": aux, "aext": aext},
    ]


def scenario_uart(d):
    return [{
        "Basic ID": build_basic_id(d),
        "Location/Vector Message": build_location(d),
        "System Message": build_system(d),
        "Self-ID Message": build_self_id(d),
        "Operator ID Message": build_operator_id(d),
        "index": d.index,
        "runtime": d.runtime,
    }]


def scenario_dji(d):
    obj = scenario_wifi(d)
    obj["Frequency Message"] = {"frequency": d.frequency_mhz}
    obj["System Message"]["home_lat"] = round(d.home_lat, 7)
    obj["System Message"]["home_lon"] = round(d.home_lon, 7)
    obj["Basic ID"]["transport"] = "dji"
    obj.pop("index", None)
    obj.pop("runtime", None)
    return obj


def scenario_area(d):
    obj = scenario_wifi(d)
    obj["System Message"] = build_system(d, include_area=True)
    return obj


def scenario_auth(d, page_count=4):
    return [
        {"Basic ID": build_basic_id(d),
         "Auth Message": build_auth_page(p, page_count, d),
         "index": d.index, "runtime": d.runtime}
        for p in range(page_count)
    ]


def scenario_caa(d_template):
    d = DroneSim(
        drone_id=f"GBR-{uuid.uuid4().hex[:8].upper()}",
        mac=d_template.mac, ua_name=d_template.ua_type_name,
        transport=d_template.transport, cfg=d_template.cfg,
        id_type="CAA Assigned Registration ID",
    )
    return scenario_wifi(d)


def scenario_utm(d_template):
    d = DroneSim(
        drone_id=f"USS-{uuid.uuid4().hex[:12]}",
        mac=d_template.mac, ua_name=d_template.ua_type_name,
        transport=d_template.transport, cfg=d_template.cfg,
        id_type="UTM (USS) Assigned ID",
    )
    return scenario_wifi(d)


def scenario_session(d_template):
    d = DroneSim(
        drone_id=f"sess-{uuid.uuid4().hex[:16]}",
        mac=d_template.mac, ua_name=d_template.ua_type_name,
        transport=d_template.transport, cfg=d_template.cfg,
        id_type="Specific Session ID",
    )
    return scenario_wifi(d)


def scenario_fpv(d):
    """Raw FPV Detection envelope (RX5808 / fpv_mdn_receiver.py shape).
    iOS routes by presence of `FPV Detection` key (XMLParserDelegate processFPVDetection)."""
    return {
        "FPV Detection": {
            "type": "nodeAlert",
            "frequency": 5658,
            "rssi": 1820,
            "stat": "NEW CONTACT LOCK",
            "time": int(time.time()),
            "source": f"01-{d.mac.replace(':', '').lower()[-4:]}",
        },
        "AUX_ADV_IND": build_aux_adv_ind(d),
        "aext": build_aext(d),
    }


def scenario_fpv_serial(d):
    """fpv_mdn_receiver.py raw serial passthrough — `from`/`to`/`msg` envelope.
    iOS ZMQHandler.processRawFPVMessage handles this shape directly."""
    return {
        "from": {"inst": "01", "node": d.mac.replace(":", "").lower()[-4:]},
        "to": {"inst": "00", "node": "mcn"},
        "msg": {
            "type": "nodeAlert",
            "time": d.runtime,
            "freq": int(d.frequency_mhz) if d.frequency_mhz > 0 else 5621,
            "rssi": 1278,
            "stat": "NEW CONTACT LOCK",
        },
    }


def scenario_legacy(d):
    """Legacy zmq_decoder.py output shape: short-form accuracy keys, classification
    Int (not classification_type), operator_alt_geo (not operator_altitude_geo),
    no transport, no frequency_mhz. Verifies iOS backward-compat reads."""
    obj = {
        "Basic ID": {
            "id": d.id,
            "id_type": d.id_type,
            "MAC": d.mac,
            "RSSI": d.rssi,
            "ua_type": d.ua_type_name,
            "protocol_version": d.protocol_version,
        },
        "Location/Vector Message": {
            "latitude": round(d.lat, 7),
            "longitude": round(d.lon, 7),
            "geodetic_altitude": round(d.altitude, 1),
            "speed": round(d.speed, 2),
            "vert_speed": round(random.uniform(-2, 2), 2),
            "height_agl": round(d.height_agl, 1),
            "height_type": random.choice(HEIGHT_TYPES),
            "pressure_altitude": round(d.altitude, 1),
            "ew_dir_segment": "E",
            "speed_multiplier": "0.25",
            "op_status": random.choice(OP_STATUS),
            "direction": int(d.heading),
            "horiz_acc": random.randint(0, 13),
            "vert_acc": "<3m",
            "baro_acc": random.randint(0, 7),
            "speed_acc": random.randint(0, 4),
            "timestamp": int(time.time()),
            "status": 0,
            "alt_pressure": round(d.altitude, 1),
            "operator_alt_geo": round(d.altitude - 5.0, 1),
        },
        "System Message": {
            "operator_lat": round(d.operator_lat, 7),
            "operator_lon": round(d.operator_lon, 7),
            "home_lat": round(d.home_lat, 7),
            "home_lon": round(d.home_lon, 7),
            "classification": random.randint(0, 7),
            "timestamp": int(time.time()),
        },
        "Self-ID Message": {
            "text": f"UAV {d.mac.lower()} operational",
            "description": "legacy zmq_decoder broadcast",
            "description_type": random.randint(0, 2),
        },
        "Operator ID Message": {
            "operator_id": d.operator_id_value,
        },
        "index": d.index,
        "runtime": d.runtime,
    }
    return obj


def scenario_multi(drones):
    out = []
    aux = build_aux_adv_ind(drones[0])
    aext = build_aext(drones[0])
    for d in drones:
        out.extend([
            {"Basic ID": build_basic_id(d), "AUX_ADV_IND": aux, "aext": aext},
            {"Location/Vector Message": build_location(d), "AUX_ADV_IND": aux, "aext": aext},
            {"System Message": build_system(d), "AUX_ADV_IND": aux, "aext": aext},
        ])
    return out


def scenario_health(uptime_s):
    sources = {}
    for src in ("wifi", "ble", "uart", "dji"):
        sources[src] = {
            "enabled": True,
            "state": "connected",
            "state_str": "running",
            "connected_since": (datetime.now(timezone.utc) - timedelta(seconds=uptime_s)).isoformat(),
            "last_message_time": datetime.now(timezone.utc).isoformat(),
            "connect_attempts": 1,
            "messages_total": random.randint(100, 100000),
            "messages_per_sec": round(random.uniform(0.5, 12.0), 2),
            "errors_total": random.randint(0, 50),
            "errors_recent": random.randint(0, 3),
            "last_error": "" if random.random() > 0.2 else "i/o timeout",
            "last_error_time": datetime.now(timezone.utc).isoformat(),
            "uptime": uptime_s,
            "uptime_ns": uptime_s * 1_000_000_000,
        }
    return {
        "enabled": True,
        "state": "running",
        "state_str": "running",
        "connected_since": (datetime.now(timezone.utc) - timedelta(seconds=uptime_s)).isoformat(),
        "last_message_time": datetime.now(timezone.utc).isoformat(),
        "connect_attempts": 1,
        "messages_total": sum(s["messages_total"] for s in sources.values()),
        "messages_per_sec": round(sum(s["messages_per_sec"] for s in sources.values()), 2),
        "errors_total": sum(s["errors_total"] for s in sources.values()),
        "errors_recent": sum(s["errors_recent"] for s in sources.values()),
        "uptime": uptime_s,
        "uptime_ns": uptime_s * 1_000_000_000,
        "sources": sources,
    }


# =====================================================================
# WarDragon monitor status (port 4225 JSON, parsed by iOS StatusMessageParser)
# =====================================================================

def scenario_status_json():
    return {
        "serial_number": "wardragon-test-0001",
        "gps_data": {
            "latitude": 37.7749,
            "longitude": -122.4194,
            "altitude": 30.0,
            "track": 0.0,
            "speed": 0.0,
        },
        "system_stats": {
            "cpu_usage": round(random.uniform(5, 75), 1),
            "memory": {
                "total": 16_000_000_000, "available": 12_000_000_000,
                "percent": round(random.uniform(20, 60), 1),
                "used": 4_000_000_000, "free": 8_000_000_000,
                "active": 3_500_000_000, "inactive": 500_000_000,
                "buffers": 100_000_000, "shared": 50_000_000,
                "cached": 2_000_000_000, "slab": 200_000_000,
            },
            "disk": {
                "total": 256_000_000_000, "used": 100_000_000_000,
                "free": 156_000_000_000,
                "percent": round(random.uniform(20, 60), 1),
            },
            "temperature": round(random.uniform(40, 70), 1),
            "uptime": time.time() % 1_000_000,
        },
        "ant_sdr_temps": {
            "pluto_temp": round(random.uniform(40, 75), 1),
            "zynq_temp": round(random.uniform(45, 80), 1),
        },
    }


# =====================================================================
# Spoof mutations
# =====================================================================

SPOOF_KINDS = ["rssi", "speed", "teleport", "altitude"]


def apply_spoof(obj, kind):
    if isinstance(obj, list):
        for el in obj:
            apply_spoof(el, kind)
        return obj
    loc = obj.get("Location/Vector Message")
    basic = obj.get("Basic ID")
    if kind == "rssi" and basic:
        basic["RSSI"] = -10
    elif kind == "speed" and loc:
        loc["speed"] = 999.0
    elif kind == "altitude" and loc:
        loc["geodetic_altitude"] = 99999.0
    elif kind == "teleport" and loc:
        loc["latitude"] = round(random.uniform(-89, 89), 6)
        loc["longitude"] = round(random.uniform(-179, 179), 6)
    return obj


# =====================================================================
# DragonSync CoT XML emitters (multicast 239.2.3.1:6969)
# =====================================================================

def cot_drone(d):
    """Drone CoT remarks. Combines DragonSync build_drone_cot fields (MAC, RSSI,
    ID Type, UA Type, Operator ID, Speed, Altitude, Course, Index, Runtime,
    Description, Transport, Freq) with the inline System: [...] block that
    ZMQHandler.swift emits and iOS XMLParserDelegate.parseDroneRemarks expects
    for pilot/home extraction. DragonSync alone publishes pilot/home as separate
    pilot-/home- CoT events, which iOS filters out — embedding them inline lets
    iOS surface operator and home location from a single multicast event."""
    ua_name = d.ua_type_name
    op_display = f"[{d.operator_id_type_value}: {d.operator_id_value}]"
    remarks = (
        f"MAC: {d.mac}, RSSI: {d.rssi}dBm; "
        f"ID Type: {d.id_type}; UA Type: {ua_name} ({d.ua_type}); "
        f"Operator ID: {op_display}; "
        f"Speed: {d.speed:.2f} m/s; Vert Speed: 0.0 m/s; "
        f"Altitude: {d.altitude:.1f} m; AGL: {d.height_agl:.1f} m; "
        f"Course: {d.heading:.1f}°; "
        f"Index: {d.index}; Runtime: {d.runtime}s; "
        f"Description: DragonSync iOS test broadcast; "
        f"Transport: {d.transport}"
    )
    if d.frequency_mhz > 0:
        remarks += f"; Freq: ~{d.frequency_mhz:.3f} MHz"
    if d.caa_id:
        remarks += f"; CAA ID: {d.caa_id}"
    remarks += (
        f"; System: [Operator Lat: {d.operator_lat:.7f}, "
        f"Operator Lon: {d.operator_lon:.7f}, "
        f"Home Lat: {d.home_lat:.7f}, "
        f"Home Lon: {d.home_lon:.7f}]"
    )
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>'
        f'<event version="2.0" uid="drone-{d.id}" type="a-u-A-M-H-R" '
        f'time="{now_iso()}" start="{now_iso()}" stale="{stale_iso()}" how="m-g">'
        f'<point lat="{d.lat:.7f}" lon="{d.lon:.7f}" hae="{d.altitude:.1f}" ce="35.0" le="999999"/>'
        f'<detail>'
        f'<contact callsign="drone-{d.id}"/>'
        f'<precisionlocation geopointsrc="gps" altsrc="gps"/>'
        f'<track course="{d.heading:.1f}" speed="{d.speed:.2f}"/>'
        f'<remarks>{xml_escape(remarks)}</remarks>'
        f'<color argb="-256"/>'
        f'</detail></event>'
    ).encode("utf-8")


def cot_pilot(d):
    """Mirrors DragonSync build_pilot_cot. iOS XMLParserDelegate filters on uid prefix 'pilot-'."""
    base = d.id[len("drone-"):] if d.id.startswith("drone-") else d.id
    remarks = f"Pilot location for drone drone-{d.id}"
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>'
        f'<event version="2.0" uid="pilot-{base}" type="b-m-p-s-m" '
        f'time="{now_iso()}" start="{now_iso()}" stale="{stale_iso()}" how="m-g">'
        f'<point lat="{d.operator_lat:.7f}" lon="{d.operator_lon:.7f}" hae="{d.altitude:.1f}" ce="35.0" le="999999"/>'
        f'<detail>'
        f'<contact callsign="pilot-{base}"/>'
        f'<precisionlocation geopointsrc="gps" altsrc="gps"/>'
        f'<usericon iconsetpath="com.atakmap.android.maps.public/Civilian/Person.png"/>'
        f'<remarks>{xml_escape(remarks)}</remarks>'
        f'</detail></event>'
    ).encode("utf-8")


def cot_home(d):
    """Mirrors DragonSync build_home_cot. iOS filters on uid prefix 'home-'."""
    base = d.id[len("drone-"):] if d.id.startswith("drone-") else d.id
    remarks = f"Home location for drone drone-{d.id}"
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>'
        f'<event version="2.0" uid="home-{base}" type="b-m-p-s-m" '
        f'time="{now_iso()}" start="{now_iso()}" stale="{stale_iso()}" how="m-g">'
        f'<point lat="{d.home_lat:.7f}" lon="{d.home_lon:.7f}" hae="{d.altitude:.1f}" ce="35.0" le="999999"/>'
        f'<detail>'
        f'<contact callsign="home-{base}"/>'
        f'<precisionlocation geopointsrc="gps" altsrc="gps"/>'
        f'<usericon iconsetpath="com.atakmap.android.maps.public/Civilian/House.png"/>'
        f'<remarks>{xml_escape(remarks)}</remarks>'
        f'</detail></event>'
    ).encode("utf-8")


def cot_adsb(craft):
    """Mirrors DragonSync build_adsb_cot. ADS-B aircraft uid uses ICAO hex."""
    uid = f"ADSB-{craft['hex']}"
    callsign = craft.get("flight", uid)
    remarks = (
        f"ICAO: {craft['hex']}; Flight: {callsign}; "
        f"Altitude: {craft['alt_baro']} ft; Speed: {craft['gs']} kt; Track: {craft['track']}°"
    )
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>'
        f'<event version="2.0" uid="{uid}" type="a-f-A" '
        f'time="{now_iso()}" start="{now_iso()}" stale="{stale_iso()}" how="m-g">'
        f'<point lat="{craft["lat"]:.6f}" lon="{craft["lon"]:.6f}" hae="{craft["alt_baro"] * 0.3048:.1f}" ce="35.0" le="999999"/>'
        f'<detail>'
        f'<contact callsign="{callsign}"/>'
        f'<track course="{craft["track"]}" speed="{craft["gs"]}"/>'
        f'<remarks>{xml_escape(remarks)}</remarks>'
        f'</detail></event>'
    ).encode("utf-8")


def cot_status(serial="wardragon-test-0001"):
    """WarDragon monitor system status as CoT (matches wardragon_monitor.py output)."""
    cpu = round(random.uniform(5, 75), 1)
    temp = round(random.uniform(40, 70), 1)
    pluto = round(random.uniform(40, 75), 1)
    zynq = round(random.uniform(45, 80), 1)
    mem_total_mb = 16000.0
    mem_avail_mb = round(random.uniform(8000, 13000), 1)
    mem_used_mb = round(mem_total_mb - mem_avail_mb, 1)
    mem_percent = round(mem_used_mb / mem_total_mb * 100.0, 1)
    disk_total = 256000.0
    disk_used = round(random.uniform(50000, 150000), 1)
    disk_free = round(disk_total - disk_used, 1)
    disk_percent = round(disk_used / disk_total * 100.0, 1)
    remarks = (
        f"CPU Usage: {cpu}%, "
        f"Memory Total: {mem_total_mb} MB, Memory Available: {mem_avail_mb} MB, "
        f"Memory Used: {mem_used_mb} MB, Memory Free: {mem_avail_mb} MB, "
        f"Memory Active: 3500.0 MB, Memory Inactive: 500.0 MB, "
        f"Memory Buffers: 100.0 MB, Memory Shared: 50.0 MB, "
        f"Memory Cached: 2000.0 MB, Memory Slab: 200.0 MB, "
        f"Memory Percent: {mem_percent}%, "
        f"Disk Total: {disk_total} MB, Disk Used: {disk_used} MB, "
        f"Disk Free: {disk_free} MB, Disk Percent: {disk_percent}%, "
        f"Temperature: {temp}°C, Uptime: {int(time.time() % 1_000_000)} seconds, "
        f"Pluto Temp: {pluto}°C, Zynq Temp: {zynq}°C"
    )
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>'
        f'<event version="2.0" uid="{serial}" type="b-m-p-s-m">'
        f'<point lat="37.7749" lon="-122.4194" hae="30.0" ce="9999999" le="9999999"/>'
        f'<detail>'
        f'<track course="0.0" speed="0.0"/>'
        f'<status readiness="true"/>'
        f'<remarks>{xml_escape(remarks)}</remarks>'
        f'</detail></event>'
    ).encode("utf-8")


# =====================================================================
# DragonSync to_dict() shape (MQTT / Lattice / API export wire format)
# =====================================================================

def mqtt_dict(d):
    """Mirrors DragonSync core/drone.py Drone.to_dict()."""
    return {
        "id": f"drone-{d.id}",
        "id_type": d.id_type,
        "ua_type": d.ua_type,
        "ua_type_name": d.ua_type_name,
        "operator_id_type": d.operator_id_type_value,
        "operator_id": d.operator_id_value,
        "op_status": random.choice(OP_STATUS),
        "height_type": random.choice(HEIGHT_TYPES),
        "ew_dir": random.choice(["E", "W"]),
        "direction": int(d.heading),
        "speed_multiplier": random.choice(["0.25", "0.75"]),
        "pressure_altitude": round(d.altitude + random.uniform(-3, 3), 1),
        "vertical_accuracy": random.choice(ACCURACY_STRINGS),
        "horizontal_accuracy": random.choice(ACCURACY_STRINGS),
        "baro_accuracy": random.choice(ACCURACY_STRINGS),
        "speed_accuracy": random.choice(ACCURACY_STRINGS),
        "timestamp": int(time.time()),
        "rid_timestamp": int(time.time()),
        "observed_at": time.time(),
        "timestamp_accuracy": random.choice(["0.1s", "0.2s", "0.5s", "1.0s"]),
        "seen_by": "wardragon-test-0001",
        "lat": round(d.lat, 7),
        "lon": round(d.lon, 7),
        "alt": round(d.altitude, 1),
        "height": round(d.height_agl, 1),
        "speed": round(d.speed, 2),
        "vspeed": round(random.uniform(-2, 2), 2),
        "pilot_lat": round(d.operator_lat, 7),
        "pilot_lon": round(d.operator_lon, 7),
        "home_lat": round(d.home_lat, 7),
        "home_lon": round(d.home_lon, 7),
        "description": "DragonSync iOS test broadcast",
        "mac": d.mac,
        "rssi": d.rssi,
        "index": d.index,
        "runtime": d.runtime,
        "caa_id": d.caa_id or "",
        "freq": d.frequency_mhz if d.frequency_mhz > 0 else None,
        "transport": d.transport,
        "rid": {
            "tracking": None,
            "status": None,
            "make": None,
            "model": None,
            "source": None,
            "lookup_attempted": False,
            "lookup_success": False,
        },
        "last_update_time": time.time(),
        "track_type": "drone",
    }


# =====================================================================
# ADS-B aircraft sim (for cot_adsb scenario)
# =====================================================================

class ADSBAircraft:
    def __init__(self, cfg):
        self.hex = "".join(random.choices("0123456789ABCDEF", k=6))
        self.flight = f"TEST{random.randint(100, 999)}"
        self.lat = cfg.lat_center + random.uniform(-0.1, 0.1)
        self.lon = cfg.lon_center + random.uniform(-0.1, 0.1)
        self.alt_baro = random.randint(2000, 38000)
        self.gs = random.randint(120, 480)
        self.track = random.uniform(0, 360)

    def step(self, dt):
        rad = math.radians(self.track)
        d_lat = (self.gs * 0.514444 * dt * math.cos(rad)) / 111000.0
        cos_lat = max(0.01, math.cos(math.radians(self.lat)))
        d_lon = (self.gs * 0.514444 * dt * math.sin(rad)) / (111000.0 * cos_lat)
        self.lat += d_lat
        self.lon += d_lon
        self.track = (self.track + random.uniform(-2, 2)) % 360

    def as_dict(self):
        return {
            "hex": self.hex, "flight": self.flight,
            "lat": self.lat, "lon": self.lon,
            "alt_baro": self.alt_baro, "gs": self.gs,
            "track": int(self.track),
        }


# =====================================================================
# Publisher
# =====================================================================

class Publisher:
    def __init__(self, cfg):
        self.cfg = cfg
        self.ctx = zmq.Context()
        self.zmq_sock = self.ctx.socket(zmq.PUB)
        self.zmq_sock.bind(f"tcp://{cfg.zmq_bind}")
        self.status_sock = self.ctx.socket(zmq.PUB)
        self.status_sock.bind(f"tcp://{cfg.status_bind}")
        self.mc_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        self.mc_sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        self.mqtt_client = None
        if cfg.mqtt_broker:
            if not MQTT_AVAILABLE:
                print("[mqtt] paho-mqtt not installed; mqtt_dict scenario disabled", file=sys.stderr)
            else:
                self.mqtt_client = mqtt.Client(client_id=f"dragonsync-test-{uuid.uuid4().hex[:8]}")
                try:
                    self.mqtt_client.connect(cfg.mqtt_broker, cfg.mqtt_port, 60)
                    self.mqtt_client.loop_start()
                    print(f"[mqtt] connected {cfg.mqtt_broker}:{cfg.mqtt_port}")
                except Exception as exc:
                    print(f"[mqtt] connect failed: {exc}", file=sys.stderr)
                    self.mqtt_client = None
        time.sleep(0.3)
        print(f"[zmq] telemetry on tcp://{cfg.zmq_bind}")
        print(f"[zmq] status   on tcp://{cfg.status_bind}")
        print(f"[mc]  CoT      on {cfg.multicast_group}:{cfg.multicast_port}")

    def send_telemetry(self, payload, label):
        data = json.dumps(payload).encode("utf-8")
        self.zmq_sock.send(data)
        if isinstance(payload, list):
            ids = [el["Basic ID"]["id"] for el in payload
                   if isinstance(el.get("Basic ID"), dict) and el["Basic ID"].get("id")]
            tag = ",".join(sorted(set(ids))) or "<no-bid>"
        else:
            tag = (payload.get("Basic ID") or {}).get("id", "<no-bid>")
        print(f"[tx] {label:<10} {tag} ({len(data)}B)")

    def send_status_json(self, payload):
        data = json.dumps(payload).encode("utf-8")
        self.status_sock.send(data)
        print(f"[tx] status_js ({len(data)}B)")

    def send_health(self, payload):
        data = json.dumps(payload).encode("utf-8")
        self.zmq_sock.send(data)
        print(f"[tx] health     sources={len(payload.get('sources', {}))} ({len(data)}B)")

    def send_cot(self, xml_bytes, label):
        self.mc_sock.sendto(xml_bytes, (self.cfg.multicast_group, self.cfg.multicast_port))
        print(f"[tx] {label:<10} cot multicast ({len(xml_bytes)}B)")

    def send_mqtt(self, payload, sub_topic=""):
        if not self.mqtt_client:
            return
        topic = f"{self.cfg.mqtt_topic}/{sub_topic}" if sub_topic else self.cfg.mqtt_topic
        self.mqtt_client.publish(topic, json.dumps(payload), qos=0)
        print(f"[tx] mqtt_dict topic={topic} ({len(json.dumps(payload))}B)")

    def close(self):
        self.zmq_sock.close(linger=0)
        self.status_sock.close(linger=0)
        self.ctx.term()
        self.mc_sock.close()
        if self.mqtt_client:
            self.mqtt_client.loop_stop()
            self.mqtt_client.disconnect()


# =====================================================================
# Runner
# =====================================================================

ALL_SCENARIOS = [
    "wifi", "ble", "uart", "dji", "area", "auth",
    "caa", "utm", "session", "multi", "fpv", "fpv_serial", "legacy",
    "health", "status",
    "cot", "pilot", "home", "adsb", "status_cot", "mqtt_dict",
]


def make_drone(transport, cfg, ua=None):
    serial = uuid.uuid4().hex[:20].upper()
    ua_name = ua or random.choice(["Aeroplane", "Helicopter", "Hybrid Lift", "Other"])
    return DroneSim(serial, random_mac(), ua_name, transport, cfg)


def run(cfg):
    if cfg.seed:
        random.seed(cfg.seed)

    pub = Publisher(cfg)
    drones = {
        "wifi": make_drone("wifi", cfg),
        "ble": make_drone("ble", cfg),
        "uart": make_drone("uart", cfg),
        "dji": make_drone("dji", cfg),
    }
    multi_drones = [make_drone("ble", cfg) for _ in range(3)]
    aircraft = ADSBAircraft(cfg)

    period = 1.0 / cfg.rate_hz if cfg.rate_hz > 0 else 1.0
    health_period = 1.0 / cfg.health_rate_hz if cfg.health_rate_hz > 0 else 60.0
    status_period = 1.0 / cfg.status_rate_hz if cfg.status_rate_hz > 0 else 30.0

    last_health = 0.0
    last_status = 0.0
    last_step = time.time()
    end_at = time.time() + cfg.duration_s if cfg.duration_s > 0 else None

    scenarios = cfg.scenarios
    if "all" in scenarios:
        scenarios = ALL_SCENARIOS

    print(f"[run] scenarios={scenarios} rate={cfg.rate_hz}Hz "
          f"health={cfg.health_rate_hz}Hz status={cfg.status_rate_hz}Hz")

    try:
        while True:
            now = time.time()
            dt = now - last_step
            last_step = now
            for d in drones.values():
                d.step(dt)
            for d in multi_drones:
                d.step(dt)
            aircraft.step(dt)

            for s in scenarios:
                if s == "wifi":
                    pub.send_telemetry(scenario_wifi(drones["wifi"]), "wifi")
                elif s == "ble":
                    pub.send_telemetry(scenario_ble(drones["ble"]), "ble")
                elif s == "uart":
                    pub.send_telemetry(scenario_uart(drones["uart"]), "uart")
                elif s == "dji":
                    pub.send_telemetry(scenario_dji(drones["dji"]), "dji")
                elif s == "area":
                    pub.send_telemetry(scenario_area(drones["wifi"]), "area")
                elif s == "auth":
                    for f in scenario_auth(drones["wifi"]):
                        pub.send_telemetry(f, "auth")
                elif s == "caa":
                    pub.send_telemetry(scenario_caa(drones["wifi"]), "caa")
                elif s == "utm":
                    pub.send_telemetry(scenario_utm(drones["wifi"]), "utm")
                elif s == "session":
                    pub.send_telemetry(scenario_session(drones["wifi"]), "session")
                elif s == "multi":
                    pub.send_telemetry(scenario_multi(multi_drones), "multi")
                elif s == "fpv":
                    pub.send_telemetry(scenario_fpv(drones["wifi"]), "fpv")
                elif s == "fpv_serial":
                    pub.send_telemetry(scenario_fpv_serial(drones["wifi"]), "fpv_serial")
                elif s == "legacy":
                    pub.send_telemetry(scenario_legacy(drones["wifi"]), "legacy")
                elif s.startswith("spoof:"):
                    kind = s.split(":", 1)[1]
                    if kind not in SPOOF_KINDS:
                        print(f"[warn] unknown spoof kind: {kind}", file=sys.stderr)
                        continue
                    obj = apply_spoof(scenario_wifi(drones["wifi"]), kind)
                    pub.send_telemetry(obj, f"spoof:{kind}")
                elif s == "cot":
                    pub.send_cot(cot_drone(drones["wifi"]), "cot_drone")
                elif s == "pilot":
                    pub.send_cot(cot_pilot(drones["wifi"]), "cot_pilot")
                elif s == "home":
                    pub.send_cot(cot_home(drones["wifi"]), "cot_home")
                elif s == "adsb":
                    pub.send_cot(cot_adsb(aircraft.as_dict()), "cot_adsb")
                elif s == "status_cot":
                    pub.send_cot(cot_status(), "status_cot")
                elif s == "mqtt_dict":
                    payload = mqtt_dict(drones["wifi"])
                    pub.send_mqtt(payload, sub_topic=f"drone-{drones['wifi'].id}")
                elif s in ("health", "status"):
                    pass
                else:
                    print(f"[warn] unknown scenario: {s}", file=sys.stderr)

            if "health" in scenarios and (now - last_health) >= health_period:
                pub.send_health(scenario_health(int(now - drones["wifi"].first_seen)))
                last_health = now

            if "status" in scenarios and (now - last_status) >= status_period:
                pub.send_status_json(scenario_status_json())
                last_status = now

            if end_at is not None and now >= end_at:
                break

            time.sleep(period)
    except KeyboardInterrupt:
        print("\n[run] interrupt — shutting down")
    finally:
        pub.close()


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--zmq-bind", default="0.0.0.0:4224",
                   help="droneid-go telemetry publisher bind (default 0.0.0.0:4224)")
    p.add_argument("--status-bind", default="0.0.0.0:4225",
                   help="wardragon_monitor JSON status publisher bind (default 0.0.0.0:4225)")
    p.add_argument("--multicast-group", default="239.2.3.1",
                   help="DragonSync CoT multicast group (default 239.2.3.1)")
    p.add_argument("--multicast-port", type=int, default=6969)
    p.add_argument("--mqtt-broker", default="",
                   help="MQTT broker host for mqtt_dict scenario (empty disables)")
    p.add_argument("--mqtt-port", type=int, default=1883)
    p.add_argument("--mqtt-topic", default="wardragon/drone")
    p.add_argument("--scenario", action="append", default=None,
                   help=f"repeatable. One of: {', '.join(ALL_SCENARIOS)}, all, "
                        f"or spoof:{{{ '|'.join(SPOOF_KINDS) }}}. Default: wifi")
    p.add_argument("--rate", type=float, default=1.0, help="telemetry frames/sec (default 1)")
    p.add_argument("--health-rate", type=float, default=0.1,
                   help="health snapshots/sec (default 0.1 = every 10s)")
    p.add_argument("--status-rate", type=float, default=0.033,
                   help="status frames/sec (default ~30s)")
    p.add_argument("--duration", type=float, default=0.0, help="seconds to run (0 = forever)")
    p.add_argument("--seed", type=int, default=0, help="RNG seed (0 = nondeterministic)")
    p.add_argument("--lat", type=float, default=37.25)
    p.add_argument("--lon", type=float, default=-115.75)
    return p.parse_args()


def main():
    args = parse_args()
    cfg = Config(
        zmq_bind=args.zmq_bind,
        status_bind=args.status_bind,
        multicast_group=args.multicast_group,
        multicast_port=args.multicast_port,
        mqtt_broker=args.mqtt_broker,
        mqtt_port=args.mqtt_port,
        mqtt_topic=args.mqtt_topic,
        rate_hz=args.rate,
        health_rate_hz=args.health_rate,
        status_rate_hz=args.status_rate,
        duration_s=args.duration,
        seed=args.seed,
        lat_center=args.lat,
        lon_center=args.lon,
        scenarios=args.scenario or ["wifi"],
    )
    run(cfg)


if __name__ == "__main__":
    main()
