> [!IMPORTANT]
> **TestFlight beta has expired**. With the rapid dev of DragonSync and DroneID by @alphafox02, I no longer have the resources to dedicate to this project.
> 
> Thanks to the supporters, this stayed in active development. When time and resources allow, I will overhaul the app to work with his backend repos. The standalone ESP32 FW will also eventually be updated (works with codebase as is for those building from source).
> 
> Open an issue if you'd like to see this back in development. Thanks again to those who contributed and made this possible. 

<div align="center">
  
  # DragonSync iOS
  
  [![TestFlight Beta](https://img.shields.io/badge/TestFlight-Beta-blue.svg?style=f&logo=apple)](https://testflight.apple.com/join/1PGR3fyX)
  [![MobSF](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml/badge.svg)](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml)
  [![Latest Release](https://img.shields.io/github/v/release/Root-Down-Digital/DragonSync-iOS?label=Version)](https://github.com/Root-Down-Digital/DragonSync-iOS/releases/latest)

  <img src="https://github.com/user-attachments/assets/d21ab909-7dba-4b42-8996-a741248e9223" width="80%" alt="DragonSync Logo">

<br>

Real-time drone, aircraft & FPV detection and monitoring for iOS/macOS. Professional-grade detection with advanced signal analysis and intelligence. 

Enrich data from ADS-B, DragonSync and DroneID feeds: In-app ADS-B, MQTT and TAK support allows for easy integration, granting users functionality without complex backend configurations.
</div>
<br>

### App
- [Features](#features)
- [Detection & Tracking](#detection--tracking)
- [History & Analysis](#history--analysis)
- [Build Instructions](#build-instructions)

### Detection Feed
- [Installation](#installation)
- [Connection Choices](#connection-choices)
- [Command Reference](#command-reference)

### About
- [Credits, Disclaimer & License](#credits-disclaimer--license)
- [Contributing & Contact](#contributing--contact)
- [Notes](#notes)

---

## Features

### Real-Time Monitoring
<div align="center">
  <img src="https://github.com/user-attachments/assets/4bca9359-3351-4579-94fe-ce67ed1ae635" width="55%" />
</div>

- Live tracking of Remote/Drone ID–compliant drones
- Decodes Ocusync and others
- Instant flight path visualization and telemetry
- Multi-protocol (ZMQ & multicast)
- Source identification

### Spoof Detection
- Advanced analysis: signal strength, position consistency, transmission patterns, and flight physics

### Visualize Encrypted Drones
- No GPS, no problem. Using the RSSI lets us estimate distance to target.

### Spot FPV Cameras
- Problematic drones may not have any ID broadcast, but it sure has a camera. Using a RX5808 SIM module and the [FPVWD](https://github.com/alphafox02/FPV_WD/blob/main/fpv_mdn_receiver.py) tool, tracking is trivial:

![image](https://github.com/user-attachments/assets/3e60ec99-e165-45fc-a6d0-bc43d53c07eb)

### MAC Randomization Detection
- Real-time alerts for MAC changes with historical tracking and origin ID association

### Multi-Source Signal Analysis
- Identifies WiFi, BT, and SDR signals with source MAC tracking and signal strength monitoring

### System Monitoring
- Real-time performance metrics: memory, CPU load, temperature, GPS & ANTSDR status

<div align="center">
  <img src="https://github.com/user-attachments/assets/f1395931-c5f0-4812-9ce2-fa997ebc3a05" width="50%" />
</div>

## Detection & Tracking

- Swipe-to-delete & untrack
- Label encounters with aliases and trust status

<div align="center">
  <img src="https://github.com/user-attachments/assets/5c4a860a-ae6b-432a-b01d-88f824960e42" width="50%" />
</div>

>  Find the live map view and other tools in the upper right menu icon of any drone message

### Dashboard Display
- Overview of live signal counts, system health, and active drones with proximity alerts

## History & Analysis

### Encounter History
- Logs each drone encounter automatically with options to search, sort, review, export, or delete records.

<div align="center">
  <img src="https://github.com/user-attachments/assets/816debe7-6c05-4c7a-9e88-14a6a4f0989a" width="50%" alt="Encounter History View">
</div>

### FAA Database Analysis
<div align="center">
<img src="https://github.com/user-attachments/assets/3c5165f1-4177-4934-8a79-4196f3824ba3" width="50%" alt="Encounter History View">
</div>

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

**Pre-configured turnkey solution**

1. Power on WarDragon Pro device
2. Connect to same network as iOS device
3. Open DragonSync app → Settings → Enable ZMQ
4. Enter WarDragon Pro IP address
5. Start monitoring

**If no connection/data:**
- System status from wardragon monitor service needs GPS. Assign it with the static flag or wait for lock
- The `config.ini` file in the `/home/dragon/WarDragon/DragonSync/` directory may need to be changed:
    - `zmq_host = 127.0.0.1` -> `zmq_host = 0.0.0.0` - to use all interfaces if localhost does not see the dragon
    - `tak_multicast_addr = 239.2.3.1` -> `tak_multicast_addr = 224.0.0.1` - for multicast on some networks (using macOS firewall, etc.)
---

## Option 2: Drag0net Scanner (ESP32 Standalone)

**Portable WiFi RID detection without a computer**

### Hardware Needed
- ESP32-C3 XIAO, ESP32-S3 XIAO, or ESP32-S3 LilyGO T-Dongle
- USB cable (data-capable, not charge-only)

### Flash Firmware

**Automatic (Linux/macOS):**
```bash
curl -fsSL https://raw.githubusercontent.com/Root-Down-Digital/DragonSync-iOS/refs/heads/main/Util/setup.sh -o setup.sh && \
[[ $(shasum -a 256 setup.sh 2>/dev/null || sha256sum setup.sh) =~ ^f268d6f6b00400c8ce8d4491da08b94b7844b7aa0414e0dbdd92982a1ed024d6 ]] && \
chmod +x setup.sh && ./setup.sh
```

Select:
- **Option 4**: Standalone DragonSync AP firmware
- **Option 5**: Standalone + Meshtastic mesh (requires Meshtastic board)

**Manual (All Platforms):**

Download firmware: **[Drag0net Scanner](https://github.com/Root-Down-Digital/DragonSync-iOS/tree/main/Util)**
```bash
esptool.py --chip auto --port /dev/YOUR_PORT --baud 115200 \
  --before default_reset --after hard_reset write_flash -z \
  --flash_mode dio --flash_freq 80m --flash_size detect \
  0x10000 firmwareFile.bin
```

Or use [Espressif Flash Download Tool](https://www.espressif.com/en/support/download/other-tools) (Windows): flash at offset `0x10000` with 115200 baud

### Connect & Use

**Default WiFi Credentials:**
```
SSID:     Dr4g0net
Password: wardragon1234
IP:       192.168.4.1
```

**Using DragonSync App:**
1. Power on ESP32
2. Connect phone to `Dr4g0net` WiFi network
3. Open DragonSync app → Settings
4. Enter ZMQ IP: `192.168.4.1`
5. Enable ZMQ connection
6. Detection starts automatically (uses iOS device GPS)

**Using Web Interface:**
1. Connect to `Dr4g0net` WiFi network
2. Visit `192.168.4.1` in browser
3. Monitor detections via web dashboard

> **Note:** WiFi RID 2.4GHz only. For 5GHz, Bluetooth, or SDR detection, use Custom Build.

---

## Option 3: Custom Build

**Full feature set with flexible hardware**

### Hardware Needed

**WiFi & Bluetooth:**
- Dual-band WiFi adapter (2.4/5GHz)
- [Sniffle](https://github.com/nccgroup/Sniffle)-compatible BT dongle (Catsniffer, Sonoff) with Sniffle firmware

**Optional:**
- [ANTSDR E200](https://github.com/alphafox02/antsdr_dji_droneid) for Ocusync/SDR decoding
- GPS USB module (falls back to iOS device GPS if not present)
- RX5808 module for FPV camera detection

### Installation

**Automatic (Recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/Root-Down-Digital/DragonSync-iOS/refs/heads/main/Util/setup.sh -o setup.sh && \
[[ $(shasum -a 256 setup.sh 2>/dev/null || sha256sum setup.sh) =~ ^f268d6f6b00400c8ce8d4491da08b94b7844b7aa0414e0dbdd92982a1ed024d6 ]] && \
chmod +x setup.sh && ./setup.sh
```

**Select option 1**: Install software only

The installer handles:
- Python dependencies
- [DroneID](https://github.com/alphafox02/DroneID) and [DragonSync](https://github.com/alphafox02/DragonSync) repositories
- System dependencies (gpsd, lm-sensors)

**Manual Installation:**

<details>
<summary><strong>Linux</strong></summary>
  
```bash
sudo apt update && sudo apt install -y python3 python3-pip git gpsd gpsd-clients lm-sensors
git clone https://github.com/alphafox02/DroneID.git
git clone https://github.com/alphafox02/DragonSync.git
cd DroneID
git submodule update --init
./setup.sh
```

</details>

<details>
<summary><strong>macOS</strong></summary>
  
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install python3 git gpsd
git clone https://github.com/alphafox02/DroneID.git
git clone https://github.com/alphafox02/DragonSync.git
cd DroneID
git submodule update --init
./setup.sh
```

</details>

<details>
<summary><strong>Windows</strong></summary>

**WSL (Recommended):**

Install WSL: `wsl --install`, then follow Linux instructions above.

**Native Windows:**

Install [Python](https://www.python.org/downloads/) and [Git](https://git-scm.com/download/win), then:

```bash
git clone https://github.com/alphafox02/DroneID.git
cd DroneID
git submodule update --init
./setup.sh
cd ..
git clone https://github.com/alphafox02/DragonSync/
```

</details>

### Start Detection

**WiFi + Bluetooth:**
```bash
# Terminal 1 - WiFi Sniffer
cd DroneID
python3 wifi_receiver.py --interface wlan0 -z --zmqsetting 127.0.0.1:4223

# Terminal 2 - BT Sniffer
cd DroneID/Sniffle
python3 python_cli/sniff_receiver.py -l -e -a -z -b 2000000

# Terminal 3 - Decoder
cd DroneID
python3 zmq_decoder.py -z --zmqsetting 0.0.0.0:4224 \
  --zmqclients 127.0.0.1:4222,127.0.0.1:4223 -v

# Terminal 4 - System Monitor (Optional)
cd DragonSync
python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30
```

> **Note:** setup.sh creates custom startup commands for your hardware configuration.

### Configure App

1. Open DragonSync app → Settings
2. Enable ZMQ
3. Enter host IP (your computer's local IP)
4. Port: 4224 (default)
5. Start monitoring

App continues monitoring in background.

### Persist on Boot (Optional)

Use [service files](https://github.com/alphafox02/DragonSync/tree/main/services) by @alphafox02:
```bash
# Modify commands for your hardware
sudo cp your-service.service /etc/systemd/system/
sudo systemctl enable your-service
sudo systemctl start your-service
```

---

## Connection Choices

### ZMQ Server (Recommended)

Direct JSON-based communication with full data access. Ideal for detailed monitoring and SDR decoding.

### Multicast CoT (Experimental)

Cursor on Target (CoT) format for TAK/ATAK system integration. Supports multiple instances but less detailed than ZMQ.

---

## Command Reference

### Monitoring & Decoding

| Task | Command | Notes |
|------|---------|-------|
| System Monitor | `python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30` | Works on most Linux systems |
| SDR Decoding | `python3 zmq_decoder.py --dji -z --zmqsetting 0.0.0.0:4224` | Requires ANTSDR E200 |

### Sniffers & Decoders

| Type | Command | Notes |
|------|---------|-------|
| BT Sniffer | `python3 Sniffle/python_cli/sniff_receiver.py -l -e -a -z -b 2000000` | Requires Sniffle firmware |
| WiFi Sniffer | `python3 wifi_receiver.py --interface wlan0 -z --zmqsetting 127.0.0.1:4223` | Dual-band adapter for 5GHz |
| Decoder (WiFi/BT) | `python3 zmq_decoder.py -z --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222,127.0.0.1:4223 -v` | After starting sniffers |

---

## Build Instructions
```bash
git clone https://github.com/Root-Down-Digital/DragonSync-iOS.git
cd DragonSync-iOS
pod install
```

Open `WarDragon.xcworkspace` in Xcode, then build and deploy to your device or use [TestFlight](https://testflight.apple.com/join/1PGR3fyX).

---

## Credits, Disclaimer & License

**Credits:**
- [DroneID](https://github.com/alphafox02/DroneID)
- [Sniffle](https://github.com/nccgroup/Sniffle)

**Disclaimer:** This software is provided as-is without warranty. Use at your own risk and in compliance with local regulations.

**License:** MIT License. See `LICENSE.md` for details.

---

## Contributing & Contact

**Contributing:** Contributions welcome via pull requests or by opening an issue.

**Contact:** For support, please open an issue in this repository.

---

## Notes

**DragonSync is under active development; features may change or have bugs. Feedback welcome.**

> [!IMPORTANT]
> Keep your WarDragon DragonOS image updated for optimal compatibility.

> [!TIP]
> Ensure your iOS device and backend system are on the same local network for best performance.

> [!CAUTION]
> Use in compliance with local regulations to avoid legal issues.
