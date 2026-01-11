> [!IMPORTANT]
> **TestFlight beta has expired**. With rapid DragonSync/DroneID development by @alphafox02, I lack resources to continue this project. Open an issue if you'd like to see development resume.


<div align="center">
  
  # DragonSync iOS
  
  [![TestFlight Beta](https://img.shields.io/badge/TestFlight-Beta-blue.svg?style=f&logo=apple)](https://testflight.apple.com/join/1PGR3fyX)
  [![MobSF](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml/badge.svg)](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml)
  [![Latest Release](https://img.shields.io/github/v/release/Root-Down-Digital/DragonSync-iOS?label=Version)](https://github.com/Root-Down-Digital/DragonSync-iOS/releases/latest)

  <img src="https://github.com/user-attachments/assets/d21ab909-7dba-4b42-8996-a741248e9223" width="70%" alt="DragonSync Logo">

**Professional drone and aircraft detection for iOS/macOS**

Real-time Remote ID • ADS-B tracking • FPV detection • Encrypted drone monitoring • Advanced spoof detection

[Get Started](#installation) • [What It Detects](#what-it-detects) • [Screenshots](#in-action) • [Integrations](#integrations)

</div>

---

## What It Detects

<table>
<tr>
<td width="50%" valign="top">

**Remote ID Broadcasts**
- WiFi 2.4GHz and 5GHz transmissions
- Bluetooth Low Energy advertisements
- SDR-based RF decoding (ANTSDR)
- Live position, altitude, speed, heading
- Pilot and home point locations
- Operator information and serial numbers

**ADS-B Aircraft**
- 1090MHz Mode S transponders
- Real-time aircraft tracking
- Flight number, altitude, speed
- Position history and flight paths
- Commercial and general aviation

**Encrypted Drones (DJI Ocusync)**
- RSSI-based distance estimation
- MAC address tracking
- Signal strength analysis
- No position data (encrypted protocol)

**FPV Video Transmitters**
- 5.8GHz analog video detection
- RX5808 receiver integration
- Channel and frequency identification
- Signal strength monitoring

**Threats and Anomalies**
- Spoof detection via signal analysis
- Position consistency validation
- Flight physics anomaly detection
- MAC randomization attack detection
- Transmission pattern recognition

</td>
<td width="50%" valign="top">

![3DAE54D1-BD51-40C1-9009-0564F5A41E23_1_201_a](https://github.com/user-attachments/assets/edfbb366-2140-4e1e-88ba-6fe79ee51d40)

<img src="https://github.com/user-attachments/assets/4bca9359-3351-4579-94fe-ce67ed1ae635" width="100%" />


<img src="https://github.com/user-attachments/assets/5c4a860a-ae6b-432a-b01d-88f824960e42" width="100%" />

</td>
</tr>
</table>

---

## In Action

**Features**
- **Live Map View** - All detections on unified map with color-coded markers
- **Detection Details** - Full telemetry: position, altitude, speed, heading, manufacturer
- **FAA Registry Lookup** - Real-time drone registration data with operator info
- **History & Analysis** - Search, filter, export encounters (KML, CSV)
- **System Monitoring** - CPU, memory, temperature, GPS, ANTSDR sensors
- **Proximity Alerts** - Configurable distance thresholds with notifications

<table>
<tr>
<td width="50%">
<img src="https://github.com/user-attachments/assets/b702c9d5-a034-4cbb-86a4-2c76c4b641b4" width="100%">
</td>
<td width="50%">
  <img src="https://github.com/user-attachments/assets/f1395931-c5f0-4812-9ce2-fa997ebc3a05" width="100%">

</td>
</tr>
<tr>
<td width="40%">
<img src="https://github.com/user-attachments/assets/816debe7-6c05-4c7a-9e88-14a6a4f0989a" width="100%">
</td>
<td width="50%">
<img src="https://github.com/user-attachments/assets/3c5165f1-4177-4934-8a79-4196f3824ba3" width="100%">
</td>
</table>

---

## Integrations

**Push Detection Data To:**
- **REST API** - 7 JSON endpoints on port 8088 (`/drones` `/aircraft` `/status` `/signals` `/config` `/health` `/update/check`)
- **MQTT** - Home Assistant auto-discovery, TLS support, QoS 0-2
- **TAK/ATAK** - CoT XML via multicast/TCP/TLS with iOS Keychain .p12
- **Kismet** - Automatic device tagging via REST API
- **Lattice DAS** - Structured detection reports to Lattice platform
- **Webhooks** - Discord, Slack, custom HTTP POST with event filtering

**Receive Data From:**
- **ZMQ** - Ports 4224 (detections) and 4225 (system status) from DroneID backend
- **Multicast CoT** - 239.2.3.1:6969 from DragonSync.py wrapper
- **ADS-B HTTP** - readsb, tar1090, dump1090 JSON feeds
- **Background Mode** - Continuous monitoring with local notifications

### Reference 

- A database migration guide can be [found here](https://github.com/Root-Down-Digital/DragonSync-iOS/blob/main/MIGRATION_GUIDE.md)
- Data flow and system information is [here](https://github.com/Root-Down-Digital/DragonSync-iOS/blob/main/DATA_FLOW_DIAGRAM.md)
---


# Installation

## Hardware Options

| Setup | Time | WiFi RID | BT RID | SDR | FPV | Best For |
|-------|------|----------|--------|-----|-----|----------|
| **WarDragon Pro** | 5 min | ✓ | ✓ | ✓ | ✓ | Full-spectrum deployment |
| **Drag0net ESP32** | 15 min | ✓ 2.4GHz | ✗ | ✗ | ✗ | Portable WiFi RID only |
| **Custom Build** | 60 min | ✓ | ✓ | ✓ | ✓ | DIY / maximum control |

---

## Option 1: WarDragon Pro (Turnkey)

Pre-configured system with ANTSDR E200, RX5808, GPS hardware.

**Quick Start:**
1. Power on device
2. Connect iOS device to same network
3. App → Settings → ZMQ → Enter WarDragon IP
4. Start monitoring

**Troubleshooting:**
```bash
# Config file: /home/dragon/WarDragon/DragonSync/config.ini
zmq_host = 0.0.0.0                 # Use if localhost fails
tak_multicast_addr = 224.0.0.1     # Alternative multicast address
```
- System status requires GPS lock (use `--static_gps` flag or wait for fix)
- SDR temps require DJI firmware on ANTSDR (UHD firmware won't report temps)

---

## Option 2: Drag0net ESP32 (Portable)

Flash ESP32-C3/S3 or LilyGO T-Dongle for standalone WiFi RID detection.

**Automated Flash:**
```bash
curl -fsSL https://raw.githubusercontent.com/Root-Down-Digital/DragonSync-iOS/refs/heads/main/Util/setup.sh -o setup.sh
chmod +x setup.sh && ./setup.sh
# Select option 4 (ESP32-C3) or 5 (ESP32-S3)
```

**Connect to Device:**
- SSID: `Dr4g0net`
- Password: `wardragon1234`
- IP Address: `192.168.4.1`
- App Settings → ZMQ IP: `192.168.4.1`
- Web UI: Navigate to `192.168.4.1` in browser

**Manual Flash:** [Download firmware](https://github.com/Root-Down-Digital/DragonSync-iOS/tree/main/Util)
```bash
esptool.py --chip auto --port /dev/YOUR_PORT --baud 115200 \
  --before default_reset --after hard_reset write_flash -z \
  --flash_mode dio --flash_freq 80m --flash_size detect \
  0x10000 firmware.bin
```

---

## Option 3: Custom Build (Full Features)

Complete detection stack with all protocols.

**Hardware Requirements:**
- Dual-band WiFi adapter (2.4/5GHz)
- Sniffle Bluetooth sniffer dongle
- Optional: ANTSDR E200 (SDR), GPS module, RX5808 (FPV)

**Automated Install:**
```bash
curl -fsSL https://raw.githubusercontent.com/Root-Down-Digital/DragonSync-iOS/refs/heads/main/Util/setup.sh -o setup.sh
chmod +x setup.sh && ./setup.sh
# Follow prompts for your platform
```

<details>
<summary>Manual Installation Steps</summary>

**Linux:**
```bash
sudo apt update
sudo apt install -y python3 python3-pip git gpsd gpsd-clients lm-sensors
git clone https://github.com/alphafox02/DroneID.git
git clone https://github.com/alphafox02/DragonSync.git
cd DroneID && git submodule update --init && ./setup.sh
```

**macOS:**
```bash
brew install python3 git gpsd
git clone https://github.com/alphafox02/DroneID.git
git clone https://github.com/alphafox02/DragonSync.git
cd DroneID && git submodule update --init && ./setup.sh
```

**Windows:** Use WSL2 or manually install Python 3.9+ and Git
</details>

**Run Detection Stack:**
```bash
# Terminal 1 - WiFi RID Receiver
cd DroneID
python3 wifi_receiver.py --interface wlan0 -z --zmqsetting 127.0.0.1:4223

# Terminal 2 - Bluetooth RID Receiver
cd DroneID/Sniffle
python3 python_cli/sniff_receiver.py -l -e -a -z -b 2000000

# Terminal 3 - Decoder (aggregates all sources)
cd DroneID
python3 zmq_decoder.py -z --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222,127.0.0.1:4223 -v

# Terminal 4 - System Health Monitor
cd DragonSync
python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30
```

**iOS App Configuration:**
- Settings → ZMQ → Host IP address, Port 4224
- Advanced → Status Port 4225
- Enable ADS-B, MQTT, TAK, webhooks as needed



<img width="736" height="848" alt="63D3EB3E-ACFC-481D-8E17-954FA5F22D40" src="https://github.com/user-attachments/assets/70b2b109-21bd-4de2-a702-7427acb9fc02" />


**Persistence:** Use [systemd service files](https://github.com/alphafox02/DragonSync/tree/main/services) for auto-start

---

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│               Detection Sources                     │
│                                                     │
│  WiFi RID (2.4/5GHz) ─── wifi_receiver.py          │
│  Bluetooth RID ────────── sniff_receiver.py         │
│  SDR Decode ──────────── ANTSDR E200               │
│  FPV Video ───────────── RX5808 + fpv_mdn_receiver │
│  ESP32 Standalone ────── Drag0net WiFi 2.4GHz      │
└────────────────────┬────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
 ┌──────▼────────┐       ┌────────▼────────┐
 │ zmq_decoder   │       │ DragonSync.py   │
 │ Port 4224     │       │ (wrapper)       │
 │ (JSON)        │       │ Multicast CoT   │
 └──────┬────────┘       └────────┬────────┘
        │                         │
        └──────────┬──────────────┘
                   │
        ┌──────────▼──────────┐      ┌────────────────┐
        │  DragonSync iOS     │◄─────┤ ADS-B Source   │
        │                     │      │ HTTP JSON      │
        │  ZMQ: 4224, 4225    │      │ readsb/tar1090 │
        │  CoT: 239.2.3.1     │      └────────────────┘
        │  API: 8088          │
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────┐
        │   Output Channels   │
        │                     │
        │  REST API (JSON)    │
        │  MQTT               │
        │  TAK/ATAK (CoT)     │
        │  Webhooks           │
        │  Kismet Tags        │
        │  Lattice DAS        │
        └─────────────────────┘
```

**Data Flow:**
- **Ingestion**: ZMQ JSON (4224 detections, 4225 status), Multicast CoT (239.2.3.1:6969), ADS-B HTTP
- **Processing**: SwiftData persistence, spoof detection, signature analysis, rate limiting
- **Output**: REST API (8088), MQTT, TAK/ATAK, webhooks, Kismet, Lattice

---

## Command Reference

| Task | Command |
|------|---------|
| **System Monitor** | `python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30` |
| **Static GPS** | `python3 wardragon_monitor.py --static_gps 37.7749,-122.4194,10` |
| **SDR Decode** | `python3 zmq_decoder.py --dji -z --zmqsetting 0.0.0.0:4224` |
| **WiFi Sniffer** | `python3 wifi_receiver.py --interface wlan0 -z --zmqsetting 127.0.0.1:4223` |
| **BT Sniffer** | `python3 Sniffle/python_cli/sniff_receiver.py -l -e -a -z -b 2000000` |
| **Decoder** | `python3 zmq_decoder.py -z --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222,127.0.0.1:4223 -v` |
| **FPV Detection** | `python3 fpv_mdn_receiver.py -z --zmqsetting 127.0.0.1:4222` |

---

## Connection Protocols

**ZMQ (Recommended)** - Full JSON telemetry with complete detection data
- Port 4224: Drone and aircraft detections
- Port 4225: System health and status

**Multicast CoT** - TAK/ATAK integration with reduced detail
- Address: 239.2.3.1:6969
- Protocol: CoT XML

**ADS-B HTTP** - Aircraft tracking from standard feeds
- Endpoints: readsb, tar1090, dump1090
- Format: JSON

**REST API** - Expose detections via HTTP
- Port: 8088
- Format: JSON

**MQTT** - Publish to Home Assistant or broker
- Formats: JSON, Home Assistant discovery
- TLS and authentication support

---

## Build from Source

```bash
git clone https://github.com/Root-Down-Digital/DragonSync-iOS.git
cd DragonSync-iOS
pod install
```

Open `WarDragon.xcworkspace` in Xcode 15+.

**Requirements:**
- Xcode 15.0 or later
- iOS 17.0+ / macOS 14.0+ deployment target
- CocoaPods for dependencies

---

## Credits & License

**Built on:** [DroneID](https://github.com/alphafox02/DroneID) • [DragonSync](https://github.com/alphafox02/DragonSync) • [Sniffle](https://github.com/nccgroup/Sniffle)

**License:** [MIT License](https://github.com/Root-Down-Digital/DragonSync-iOS/blob/main/LICENSE.md)

---

## Legal Disclaimer

**READ BEFORE USE**

While receiving RF signals is generally legal in most jurisdictions, users are solely responsible for:

- Complying with all applicable local, state, federal, and international laws
- Ensuring proper authorization before monitoring any communications
- Understanding that monitoring transmissions you are not authorized to receive may be illegal
- Obtaining necessary licenses or permissions from local regulatory authorities
- Using appropriate frequencies and power levels per local regulations

**The authors, contributors, and maintainers of this software:**
- Make NO WARRANTIES, express or implied
- Accept NO RESPONSIBILITY for any use, misuse, or consequences
- Accept NO LIABILITY for any legal violations, damages, or harm
- Provide this software "AS IS" without guarantee of fitness for any purpose

**By using this software, you acknowledge:**
- You are solely responsible for your actions and consequences
- You will use this software only in compliance with applicable laws
- The authors bear no responsibility for your use

**USE AT YOUR OWN RISK**

---


> [!NOTE]
> Keep WarDragon and DragonOS updated for optimal compatibility.

> [!CAUTION]
> Use only in compliance with local regulations and laws.
