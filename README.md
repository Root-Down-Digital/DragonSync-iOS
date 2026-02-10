> [!IMPORTANT]
> **Public TestFlight has expired**. 

<div align="center">
  
  # DragonSync iOS
  
  [![TestFlight Beta](https://img.shields.io/badge/TestFlight-Beta-blue.svg?style=f&logo=apple)](https://testflight.apple.com/join/1PGR3fyX)
  [![MobSF](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml/badge.svg)](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml)
  [![Latest Release](https://img.shields.io/github/v/release/Root-Down-Digital/DragonSync-iOS?label=Version)](https://github.com/Root-Down-Digital/DragonSync-iOS/releases/latest)

  <img src="https://github.com/user-attachments/assets/d21ab909-7dba-4b42-8996-a741248e9223" width="70%" alt="DragonSync Logo">

**Professional drone and aircraft detection for iOS/macOS** _Use WiFi, BT, ADS-B & SDR for total airspace awareness_

**Remote/Drone ID • ADS-B tracking • FPV detection • Encrypted drone capable • Spoofing & Randomization detection**

[Get Started](#installation) • [What It Detects](#what-it-detects) • [Screenshots](#in-action) • [Integrations](#integrations)

</div>

---
## What It Detects

<table>
<tr>
<td width="60%" valign="top">

**Remote ID Broadcasts**
- WiFi 2.4GHz and 5GHz transmissions
- Bluetooth Low Energy advertisements
- SDR-based RF decoding (ANTSDR)
- Live position, altitude, speed, heading
- Pilot and home point locations, FAA lookup

**ADS-B Aircraft**
- 1090MHz Mode S transponders
- Real-time aircraft tracking
- Flight number, altitude, speed
- Supply your own or use OpenSky

**Encrypted Drones (DJI Ocusync)**
- RSSI-based distance estimation
- Reads unencrypted elements of RID

**FPV Video Transmitters**
- 5.8GHz analog video detection
- RX5808 receiver integration
- Channel and frequency identification
- Signal strength ring map markers

**Threats and Anomalies**
- Spoof detection via signal analysis
- Position consistency validation
- Flight physics anomaly detection
- MAC randomization detection

</td>
<td width="40%" valign="top">

![Detection interface](https://github.com/user-attachments/assets/53bea64a-08ef-492a-8468-6b0ccb93105b)
![Signal analysis](https://github.com/user-attachments/assets/4bca9359-3351-4579-94fe-ce67ed1ae635)
<img width="965" height="912" alt="914C869C-2EAA-47D2-AA86-0DB41CF0EE74" src="https://github.com/user-attachments/assets/27674677-25f3-4ca8-be47-509ee5dba69e" />



</td>
</tr>
</table>

---

## In Action

**Features**
- **Live Map View** - All detections on unified map with color-coded markers
- **Detection Details** - Full telemetry: position, altitude, speed, heading, manufacturer & more
- **FAA Registry Lookup** - Real-time drone registration data with operator info
- **History & Analysis** - Search, filter, export encounters (KML, CSV). Data is stored securely in iOS Keychain (TAK) and the app uses SwiftData. 
- **System Monitoring** - CPU, memory, temperature, GPS, ANTSDR sensors
- **Proximity & System Alerts** - Configurable distance thresholds with notifications. Memory and temperature alert triggers. 

<table>
<tr>
<td width="50%">
  <img src="https://github.com/user-attachments/assets/f1395931-c5f0-4812-9ce2-fa997ebc3a05" width="100%">

</td>
<td width="50%">
   <img width="1011" height="790" alt="C5A87C81-B6C2-417D-B0CC-5068A7824E6D" src="https://github.com/user-attachments/assets/50ee00df-db1d-4afe-90ae-fdcdbd0201d7" />
</td>
</tr>
<tr>
<td width="50%">
  <img src="https://github.com/user-attachments/assets/816debe7-6c05-4c7a-9e88-14a6a4f0989a" width="100%">
</td>
<td width="50%">
  
  ![EF03E9CF-B175-4B55-BCDE-B6B65A9032A4_4_5005_c](https://github.com/user-attachments/assets/5ee6bb15-584e-4724-bf26-4e6f45e77980)

  <img src="https://github.com/user-attachments/assets/3c5165f1-4177-4934-8a79-4196f3824ba3" width="100%">
</td>
</tr>
</table>

---

## Integrations

**Push Detection Data To:**
- **MQTT** - Home Assistant auto-discovery, TLS support, QoS 0-2
- **TAK/ATAK** - CoT XML via multicast/TCP/TLS with iOS Keychain .p12
- **Lattice DAS** - Structured detection reports to Lattice platform
- **Webhooks** - Discord, Slack, custom HTTP POST with event filtering

**Receive Data From:**
- **ZMQ** - Ports 4224 (detections) and 4225 (system status) from DroneID backend
- **Multicast CoT** - 239.2.3.1:6969 from DragonSync.py wrapper
- **ADS-B** - readsb, tar1090, dump1090 JSON feeds and [OpenSky Network](https://opensky-network.org)
- **Background Mode** - Continuous monitoring with local notifications

### Reference 

- Although performed automatically, a database migration guide can be [found here](https://github.com/Root-Down-Digital/DragonSync-iOS/blob/main/MIGRATION_GUIDE.md) for users coming from earlier versions. 
---


# Installation

## Hardware Options

| Setup | Time | WiFi RID | BT RID | SDR | FPV | Best For |
|-------|------|----------|--------|-----|-----|----------|
| **WarDragon Pro** | 5 min | ✓ | ✓ | ✓ | ✓ | Full-spectrum deployment |
| **Drag0net ESP32** | 15 min | ✓ 2.4GHz | ✗ | ✗ | ✗ | Portable WiFi RID only |
| **Custom Build** | 60 min | ✓ | ✓ | ✓ | ✓ | DIY / maximum control |

---

> [!NOTE]
> Keeping up with all the changes to the backend data wrappers is difficult. This uses my own [zmq_decoder fork](https://github.com/lukeswitz/DroneID) for FPV and other changes. The stock DroneID parser is fine when not using FPV. Either use the fork, or multicast and additional python [DragonSync](https://github.com/alphafox02/DragonSync) wrapper for FPV. 

- Be sure to `git pull` in both DroneID and DragonSync directories. 
- Use the troubleshooting guide to fix common issues. 

## Option 1: WarDragon Pro

Pre-configured system with ANTSDR E200, WiFi/BT, GPS hardware


**Quick Start:**
1. Power on device
2. Connect iOS device to same network
3. App → Settings → ZMQ → Enter WarDragon IP
4. Start monitoring

**Troubleshooting:**

No Network Connection/Data: 

A. Toggling the in-app connection off and on is sometimes needed first run for Apple to request connections. 

B. Backend ***connection settings*** that may need modification:

   - Edit the Config file: `/home/dragon/WarDragon/DragonSync/config.ini`
     - Change if localhost fails to ***listen for zmq**
     `zmq_host = 0.0.0.0`
     - Alternative ***multicast*** address 
     `tak_multicast_addr = 224.0.0.1`  

System Status: 

A. To send data, `wardragon_monitor.py` ***requires GPS lock*** (use `--static_gps` flag or wait for lock)

B. ***SDR temps*** require DJI firmware on ANTSDR (UHD firmware won't report temps)

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
python3 zmq_decoder.py -z --dji 127.0.0.1:4221 --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222,127.0.0.1:4223,127.0.0.1:4226 -v

# Terminal 4 - System Health Monitor
cd DragonSync
python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30

# Terminal 5 - (Optional) FPV Detections
cd DroneID
fpv_mdn_receiver.py --serial /dev/ttyFPV --baud 115200 --zmq-port 4226 --stationary --debug
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
│  WiFi RID (2.4/5GHz) ─── wifi_receiver.py           │
│  Bluetooth RID ────────── sniff_receiver.py         │
│  SDR Decode ──────────── ANTSDR E200                │
│  FPV Video ───────────── RX5808 + fpv_mdn_receiver  │
│  ESP32 Standalone ────── Drag0net WiFi 2.4GHz       │
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
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────┐
        │   Output Channels   │
        │                     │
        │  MQTT               │
        │  TAK/ATAK (CoT)     │
        │  Webhooks           │
        │  Lattice DAS        │
        └─────────────────────┘
```

**Data Flow:**
- **Ingestion**: ZMQ JSON (4224 detections, 4225 status), Multicast CoT (239.2.3.1:6969), ADS-B HTTP
- **Processing**: SwiftData persistence, spoof detection, signature analysis, rate limiting
- **Output**: MQTT, TAK/ATAK, Webhooks & Lattice

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
- Port 4224: Drone detections
- Port 4225: System health and status
  
**Multicast CoT** - TAK/ATAK integration with reduced detail
- Address: 239.2.3.1:6969
- Protocol: CoT XML

**ADS-B HTTP** - Aircraft tracking from standard feeds or OpenSky
- Endpoints: readsb, tar1090, dump1090
- OpenSky Network: Use with or without an account

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

This app is not affiliated with DragonOS or cemaxecutor in any official context. I wanted a simple way to interact with the drone capabilities, and easily integrate my ANTSDR. cemaxecuter was instrumental to the development of this project- All credit really should go to him.

**Built on:** [DroneID](https://github.com/alphafox02/DroneID) • [DragonSync](https://github.com/alphafox02/DragonSync) • [Sniffle](https://github.com/nccgroup/Sniffle)

**Third-party frameworks used:** 
```
SwiftyZeroMQ5
CocoaMQTT
CocoaAsyncSocket
Starscream
```

**API Data Sources:**
- faa.gov
- opensky-network.org

**[Privacy Policy](https://github.com/Root-Down-Digital/DragonSync-iOS/blob/main/PRIVACY.md)**

**[MIT License](https://github.com/Root-Down-Digital/DragonSync-iOS/blob/main/LICENSE.md)**

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
