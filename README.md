> [!IMPORTANT]
> **TestFlight beta has expired**. With rapid DragonSync/DroneID development by @alphafox02, I lack resources to continue this project. Open an issue if you'd like to see development resume.

<div align="center">
  
  # DragonSync iOS
  
  [![TestFlight Beta](https://img.shields.io/badge/TestFlight-Beta-blue.svg?style=f&logo=apple)](https://testflight.apple.com/join/1PGR3fyX)
  [![MobSF](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml/badge.svg)](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml)
  [![Latest Release](https://img.shields.io/github/v/release/Root-Down-Digital/DragonSync-iOS?label=Version)](https://github.com/Root-Down-Digital/DragonSync-iOS/releases/latest)

  <img src="https://github.com/user-attachments/assets/d21ab909-7dba-4b42-8996-a741248e9223" width="70%" alt="DragonSync Logo">
<br>
<br>

**Real-time drone, aircraft & FPV detection and monitoring for iOS/macOS. Professional-grade detection with advanced signal analysis and intelligence.** 

</div>
<br>

### What is it?
- DragonSync is a user friendly iOS/macOS **alternative/companion app to the Python backend [utility](https://github.com/lukeswitz/DragonSync)**
- **Relies on ZMQ data** from [DroneID](https://github.com/lukeswitz/DroneID), and can be used with or without additional wrapper scripts
- **Standalone** WiFi RID [ESP32 firmware](https://github.com/Root-Down-Digital/DragonSync-iOS/tree/main/Util) is also an option. Learn more in [installation](#installation) options

### App
- [Features](#features)
- [Detection & Tracking](#detection--tracking)
- [History & Analysis](#history--analysis)
- [Integrations](#integrations)
- [Build Instructions](#build-instructions)

### Backend
- [Installation](#installation)
- [Connection Choices](#connection-choices)
- [Command Reference](#command-reference)

### Legal
- [Credits, Disclaimer & License](#credits-disclaimer--license)

---

## Features
<div align="center">
  <img src="https://github.com/user-attachments/assets/4bca9359-3351-4579-94fe-ce67ed1ae635" width="50%" />
</div>

### ADS-B Aircraft Tracking
- 1090MHz Mode S/ADS-B reception

### TAK/ATAK, Kismet and Lattice Integrations
- Multicast forwarding of ZMQ to CoT
- Output to Kismet, Lattice and API endpoints
- iOS Keychain support for TAK TLS

### Onboard DB Manager
- Migrage from v1, export and restore backups
- Uses SwiftData for speed and secure storage

### Real-Time Monitoring
- Remote/Drone ID tracking (WiFi, Bluetooth, SDR)
- Ocusync decoding
- Flight path visualization
- Multi-protocol support (ZMQ, multicast CoT)

### Detection Capabilities
- **Spoof Detection**: Signal strength, position consistency, transmission patterns, flight physics analysis
- **Encrypted Drones**: RSSI-based distance estimation
- **FPV Cameras**: RX5808 + [FPVWD](https://github.com/alphafox02/FPV_WD/blob/main/fpv_mdn_receiver.py) detection
- **MAC Randomization Sniffer**: Real-time alerts with origin tracking
- **ADS-B**: Uses any feed with valid data (readsb,dump1090,tar1090,etc.)

### System Monitoring
<div align="center">
  <img src="https://github.com/user-attachments/assets/f1395931-c5f0-4812-9ce2-fa997ebc3a05" width="50%" />
</div>

- CPU, memory, temperature, GPS status
- ANTSDR Pluto & Zynq temperatures
- Configurable health & range alerts



## Detection & Tracking

<div align="center">
<img src="https://github.com/user-attachments/assets/3c5165f1-4177-4934-8a79-4196f3824ba3" width="25%" alt="FAA Lookup"> 
  <img src="https://github.com/user-attachments/assets/816debe7-6c05-4c7a-9e88-14a6a4f0989a" width="25%" alt="Encounter History"> <img src="https://github.com/user-attachments/assets/5c4a860a-ae6b-432a-b01d-88f824960e42" width="25%" />
</div>

<div align="center">
  
</div>

- Swipe-to-delete & untrack
- Aliases and trust labels
- Live map view shows unified detections by type
- Dashboard with signal counts, health, proximity alerts

## History & Analysis



### Detailed History & Mapping
- Aircraft and drones are stored for analysis
- FAA RID lookup provides up-to-date drone data
- Displays operator, takeoff and drone locations
- Search, sort, review, export (KML, CSV)


## Integrations

### Data Output
- **REST API** (port 8088): 7 JSON endpoints (`/drones`, `/aircraft`, `/status`, `/signals`, `/config`, `/health`, `/update/check`)
- **MQTT**: Home Assistant auto-discovery, TLS, QoS 0-2, configurable topics
- **TAK/ATAK**: CoT XML over multicast/TCP/TLS with iOS Keychain .p12 support
- **Webhooks**: Discord, Slack, custom HTTP POST with event filtering
- **Kismet**: Device tagging via REST API
- **Lattice DAS**: Structured detection reports

### Data Ingestion
- **ZMQ**: Direct JSON from `zmq_decoder.py` (ports 4224/4225)
- **Multicast CoT**: Receive from `DragonSync.py` (239.2.3.1:6969)
- **ADS-B**: HTTP polling from readsb/tar1090/dump1090 endpoints
- **Background**: Continuous monitoring with local notifications

---

# Installation

## Choose Your Setup

| Feature | WarDragon Pro | Drag0net Scanner | Custom Build |
|---------|---------------|------------------|--------------|
| **Best For** | Immediate deployment | Portable WiFi RID detection | Full feature set |
| **Setup Time** | ~5 min | ~15 min | 30-60 min |
| **WiFi RID (2.4GHz)** | ✓ | ✓ | ✓ |
| **WiFi RID (5GHz)** | ✓ | ✗ | ✓ (dual-band adapter) |
| **Bluetooth RID** | ✓ | ✗ | ✓ (Sniffle hardware) |
| **SDR Decoding** | ✓ (ANTSDR E200) | ✗ | ✓ (ANTSDR E200) |
| **FPV Detection** | ✓ (RX5808) | ✗ | ✓ (RX5808) |
| **GPS** | External USB | iOS device | External USB |
| **System Monitoring** | ✓ | ✗ | ✓ |
| **TAK Integration** | ✓ | ✗ | ✓ |
| **Requires Computer** | No | No | Yes |

---

## Option 1: WarDragon Pro

Pre-configured turnkey solution.

1. Power on device
2. Connect iOS device to same network
3. App → Settings → Enable ZMQ → Enter IP
4. Start monitoring

**Troubleshooting:**
- System status requires GPS (use `--static_gps` flag or wait for lock)
- Connection issues? Mod Config: `/home/dragon/WarDragon/DragonSync/config.ini`
  - `zmq_host = 0.0.0.0` (if localhost fails)
  - `tak_multicast_addr = 224.0.0.1` (for some networks)
- No SDR Temps in status: Use the DJI FW on ANTSDR, UHD will not work with this
---

## Option 2: Drag0net Scanner (ESP32)

Portable WiFi RID without a computer.

**Hardware:** ESP32-C3/S3 XIAO or LilyGO T-Dongle

**Flash (Linux/macOS):**
```bash
curl -fsSL https://raw.githubusercontent.com/Root-Down-Digital/DragonSync-iOS/refs/heads/main/Util/setup.sh -o setup.sh && \
[[ $(shasum -a 256 setup.sh 2>/dev/null || sha256sum setup.sh) =~ ^f268d6f6b00400c8ce8d4491da08b94b7844b7aa0414e0dbdd92982a1ed024d6 ]] && \
chmod +x setup.sh && ./setup.sh
```
Select option 4 or 5.

**Manual:** [Download firmware](https://github.com/Root-Down-Digital/DragonSync-iOS/tree/main/Util)
```bash
esptool.py --chip auto --port /dev/YOUR_PORT --baud 115200 \
  --before default_reset --after hard_reset write_flash -z \
  --flash_mode dio --flash_freq 80m --flash_size detect \
  0x10000 firmwareFile.bin
```

**Connect:**
- SSID: `Dr4g0net` | Password: `wardragon1234` | IP: `192.168.4.1`
- App: Settings → ZMQ IP: `192.168.4.1`
- Web: `192.168.4.1` in browser

---

## Option 3: Custom Build

Full feature set.

**Hardware:**
- Dual-band WiFi adapter
- [Sniffle](https://github.com/nccgroup/Sniffle) BT dongle
- Optional: ANTSDR E200, GPS, RX5808

**Install:**
```bash
curl -fsSL https://raw.githubusercontent.com/Root-Down-Digital/DragonSync-iOS/refs/heads/main/Util/setup.sh -o setup.sh && \
[[ $(shasum -a 256 setup.sh 2>/dev/null || sha256sum setup.sh) =~ ^f268d6f6b00400c8ce8d4491da08b94b7844b7aa0414e0dbdd92982a1ed024d6 ]] && \
chmod +x setup.sh && ./setup.sh
```

<details>
<summary>Manual Install</summary>

**Linux:**
```bash
sudo apt update && sudo apt install -y python3 python3-pip git gpsd gpsd-clients lm-sensors
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

**Windows:** Use WSL or install Python/Git manually.
</details>

**Run:**
```bash
# Terminal 1 - WiFi
cd DroneID
python3 wifi_receiver.py --interface wlan0 -z --zmqsetting 127.0.0.1:4223

# Terminal 2 - Bluetooth
cd DroneID/Sniffle
python3 python_cli/sniff_receiver.py -l -e -a -z -b 2000000

# Terminal 3 - Decoder
cd DroneID
python3 zmq_decoder.py -z --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222,127.0.0.1:4223 -v

# Terminal 4 - System Monitor
cd DragonSync
python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30
```

**App Config:**
- Settings → ZMQ → Host IP → Port 4224
- Advanced → Port 4225 for system health
- Enable ADS-B, MQTT, webhooks as needed

**Persist:** Use [service files](https://github.com/alphafox02/DragonSync/tree/main/services)


## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Detection Sources                                  │
│  • WiFi RID (2.4/5GHz) - wifi_receiver.py           │
│  • Bluetooth RID - sniff_receiver.py (Sniffle)      │
│  • SDR/FPV - ANTSDR/RX5808 via fpv_mdn_receiver.py  │
│  • ESP32 Standalone - Drag0net (WiFi 2.4GHz)        │
└────────────────────┬────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
 ┌──────▼────────┐       ┌────────▼────────┐
 │ zmq_decoder   │       │ DragonSync.py   │
 │ Port: 4224    │       │ Multicast CoT   │
 │ (JSON)        │       │ 239.2.3.1:6969  │
 └──────┬────────┘       └────────┬────────┘
        │                         │
        └──────────┬──────────────┘
                   │
        ┌──────────▼──────────┐      ┌────────────────┐
        │  DragonSync iOS     │◄─────┤ ADS-B (HTTP)   │
        │  • ZMQ: 4224, 4225  │      │ readsb/tar1090 │
        │  • Multicast: 6969  │      └────────────────┘
        │  • API: 8088        │
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────┐
        │   Output Channels   │
        │  • REST API (JSON)  │
        │  • MQTT             │
        │  • TAK/ATAK (CoT)   │
        │  • Webhooks         │
        │  • Kismet           │
        │  • Lattice DAS      │
        └─────────────────────┘
```

**Ingestion**: ZMQ JSON (4224, 4225), Multicast CoT (239.2.3.1:6969), ADS-B HTTP  
**Processing**: SwiftData persistence, spoof detection, signature analysis, rate limiting  
**Output**: REST (8088), MQTT, TAK, webhooks, Kismet, Lattice
---

## Connection Choices

**ZMQ (Recommended):** JSON-based, full data access
- Port 4224: Drone detections
- Port 4225: System health

**Multicast CoT:** TAK/ATAK integration, less detailed

**ADS-B:** Enable in Settings, ingest from a given endpoint

**MQTT:** Home Assistant auto-discovery

**REST API:** JSON endpoints for custom integrations

---

## Command Reference

| Task | Command |
|------|---------|
| System Monitor | `python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30` |
| Static GPS | `python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --static_gps 37.7749,-122.4194,10` |
| SDR Decode | `python3 zmq_decoder.py --dji -z --zmqsetting 0.0.0.0:4224` |
| WiFi Sniffer | `python3 wifi_receiver.py --interface wlan0 -z --zmqsetting 127.0.0.1:4223` |
| BT Sniffer | `python3 Sniffle/python_cli/sniff_receiver.py -l -e -a -z -b 2000000` |
| Decoder | `python3 zmq_decoder.py -z --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222,127.0.0.1:4223 -v` |


---

## Build Instructions
```bash
git clone https://github.com/Root-Down-Digital/DragonSync-iOS.git
cd DragonSync-iOS && pod install
```
Open `WarDragon.xcworkspace` in Xcode.

---

## Credits, Disclaimer & License

**Credits:** [DroneID](https://github.com/alphafox02/DroneID) [DragonSync](https://github.com/alphafox02/DragonSync)• [Sniffle](https://github.com/nccgroup/Sniffle)

**License:** [MIT](https://github.com/Root-Down-Digital/DragonSync-iOS/blob/main/LICENSE.md)


## Legal Disclaimer

**IMPORTANT: READ BEFORE USE**
```
While receiving RF signals is generally legal in most jurisdictions, users are solely responsible for:

- Complying with all applicable local, state, federal, and international laws and regulations
- Ensuring proper authorization before monitoring any communications
- Understanding that monitoring transmissions you are not authorized to receive may be illegal in your jurisdiction
- Obtaining necessary licenses or permissions required by your local regulatory authority
- Using appropriate frequencies and power levels in accordance with local regulations

**The authors, contributors, and maintainers of this software:**
- Make NO WARRANTIES, express or implied, regarding this software
- Accept NO RESPONSIBILITY for any use, misuse, or consequences of using this software
- Accept NO LIABILITY for any legal violations, damages, or harm resulting from use of this software
- Provide this software "AS IS" without any guarantee of fitness for any particular purpose

**By using this software, you acknowledge that:**
- You are solely responsible for your actions and any consequences
- You will use this software only in compliance with all applicable laws
- The authors bear no responsibility for your use of this software

**USE AT YOUR OWN RISK.**
```


> [!IMPORTANT]
> Keep WarDragon DragonOS updated for compatibility.

> [!CAUTION]
> Use in compliance with local regulations.

