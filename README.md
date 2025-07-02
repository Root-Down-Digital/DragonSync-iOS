# DragonSync iOS

[![MobSF](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml/badge.svg)](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml)

<div align="center">
  <img src="https://github.com/user-attachments/assets/d21ab909-7dba-4b42-8996-a741248e9223" width="80%" alt="DragonSync Logo">
</div>
<br>
<div align="center">
  Real-time drone detection and monitoring for iOS/macOS, powered by locally-hosted decoding. Enjoy professional-grade detection with advanced signal analysis and tracking. 
</div>
<br>
<div align="center">
  
 [![TestFlight Beta](https://img.shields.io/badge/TestFlight-Join_Beta-blue.svg?style=for-the-badge&logo=apple)](https://testflight.apple.com/join/QKDKMSfA)
 
</div>

**App**
- [Features](#features)
- [Detection & Tracking](#detection--tracking)
- [History & Analysis](#history--analysis)
- [App Settings Config](#app-settings)
 - [Build Instructions](#build-instructions)

**Backend Data**
- [Hardware Requirements](#hardware-requirements)
 - [Software Setup](#software-requirements)
 - [Connection Choices](#connection-choices)
 - [Command Reference](#backend-data-guide)

**About**
- [Credits, Disclaimer & License](#credits-disclaimer--license)
- [Contributing & Contact](#contributing--contact)
- [Notes](#notes)

---

## Features

### Real-Time Monitoring
- Live tracking of Remote/Drone ID–compliant drones
- Decodes Ocusync and others
- Instant flight path visualization and telemetry
- Multi-protocol (ZMQ & multicast)
- Source identification 

### Spoof Detection
- Advanced analysis: signal strength, position consistency, transmission patterns, and flight physics

### Visualize Encrypted Drones
- No GPS, no problem. Using the RSSI lets us estimate distance to target.

<div align="center">
 <img src="https://github.com/user-attachments/assets/528c818a-9913-4d05-b9fa-eb38c937f356" width="60%" alt="Drone Encounter Screenshot">
</div>

### MAC Randomization Detection
- Real-time alerts for MAC changes with historical tracking and origin ID association

<div align="center">
  <img src="https://github.com/user-attachments/assets/a6c0698f-944d-4a41-b38c-fca75778a5e8" width="60%" alt="MAC Randomization Detection Screenshot">
</div>

### Multi-Source Signal Analysis
- Identifies WiFi, BT, and SDR signals with source MAC tracking and signal strength monitoring

<div align="center">
  <img src="https://github.com/user-attachments/assets/4477787a-8877-4421-88b8-ffd7ec38e26b" width="70%" alt="Signal Analysis Interface">
</div>

### System Monitoring
- Real-time performance metrics: memory, CPU load, temperature, GPS & ANTSDR status

## Detection & Tracking

- Swipe-to-delete & untrack
- Label encounters with aliases and trust status

> [!TIP]
>  Tap the "Live" map button for all drones with full-screen tracking. Select an active drone for details.


### Dashboard Display
- Overview of live signal counts, system health, and active drones with proximity alerts

## History & Analysis

### Encounter History
- Logs each drone encounter automatically with options to search, sort, review, export, or delete records.

<div align="center">
  <img src="https://github.com/user-attachments/assets/816debe7-6c05-4c7a-9e88-14a6a4f0989a" width="60%" alt="Encounter History View">
</div>

### FAA Database Analysis

![image](https://github.com/user-attachments/assets/3c5165f1-4177-4934-8a79-4196f3824ba3)


## App Settings

### Settings & Warning Dials
- Customize warning thresholds, proximity alerts, and display preferences.
- Set limits for CPU usage, temperature (including PLUTO and ZYNQ), memory, and RSSI.


---

## Hardware Requirements

### Option 1: [WarDragon/Pro](https://cemaxecuter.com/?post_type=product)

### Option 2: DIY Setup

Configuration A. WiFi & BT Adapters
   - ESP32 with WiFi RID Firmware, or a a WiFi adapter using DroneID `wifi_sniffer` below
   - Sniffle-compatible BT dongle (Catsniffer, Sonoff) flashed with Sniffle FW.

Configuration B. Single Xiao ESP32S3
   - Flash it with this [firmware](https://github.com/lukeswitz/T-Halow/blob/master/firmware/xiao_s3dualcoreRIDfirmware.bin)
   - Change port name and firmware filepath: 
     ```esptool.py --chip esp32s3 --port /dev/yourportname --baud 115200 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size 16MB 0x10000 firmwareFile.bin```

   - Swap in updated zmq decoder that handles both types over UART [here](https://github.com/lukeswitz/DroneID/blob/dual-esp32-rid/zmq_decoder.py)
  
- (Optional) ANTSDR E200 & DJI FW

---

## Software Requirements

This section covers setting up the backend Python environment on Linux, macOS, and Windows.

**Required**
- [Sniffle](https://github.com/nccgroup/Sniffle)
- [DroneID](https://github.com/alphafox02/DroneID)

**Optional**
- [DJI Firmware - E200](https://github.com/alphafox02/antsdr_dji_droneid), [WiFi Remote ID Firmware](https://github.com/alphafox02/T-Halow/tree/wifi_rid/examples/DragonOS_RID_Scanner), [DragonSync Python](https://github.com/alphafox02/DragonSync)


### Python Tools Setup Instructions

#### Linux
1. **Install Dependencies:**

       sudo apt update && sudo apt install -y python3 python3-pip git gpsd gpsd-clients lm-sensors

2. **Clone & Setup:**

       git clone https://github.com/alphafox02/DroneID.git
       git clone https://github.com/alphafox02/DragonSync.git
       cd DroneID
       git submodule update --init
       ./setup.sh

#### macOS
1. **Install Homebrew & Dependencies:**

       /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
       brew install python3 git gpsd

2. **Clone & Setup:**

       git clone https://github.com/alphafox02/DroneID.git
       git clone https://github.com/alphafox02/DragonSync.git
       cd DroneID
       git submodule update --init
       ./setup.sh

#### Windows (Using WSL or Native)
- **WSL (Recommended):**  
  Install WSL (`wsl --install`) and follow the Linux instructions.
- **Native Setup:**  
  Install Python and Git from [python.org](https://www.python.org/downloads/) and [git-scm.com](https://git-scm.com/download/win), then clone and set up using Git commands above.
- **Install Backend Dependencies**

       # DroneID Setup
       git clone https://github.com/alphafox02/DroneID.git
       cd DroneID
       git submodule update --init
       ./setup.sh

       # Install additional dependencies:
       sudo apt update && sudo apt install lm-sensors gpsd gpsd-clients
       cd ..
       git clone https://github.com/alphafox02/DragonSync/


## Connection Choices

### ZMQ Server (JSON) – Recommended

The ZMQ Server option provides direct JSON-based communication with full data access. Ideal for detailed monitoring and SDR decoding.

### Multicast (CoT) – Experimental

The Multicast option uses Cursor on Target (CoT) to transmit data for integration with TAK/ATAK systems. It supports multiple instances but may offer less detailed data compared to ZMQ.

---

## Backend Data Guide

### ZMQ Commands

> **Monitoring & Decoding Options**

| **Task**                     | **Command**                                                                               | **Notes**                         |
|------------------------------|-------------------------------------------------------------------------------------------|-----------------------------------|
| **System Monitor**           | `python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30`             | Works on most Linux systems       |
| **SDR Decoding (DroneID)**   | `python3 zmq_decoder.py --dji -z --zmqsetting 0.0.0.0:4224`                                 | Required for DroneID SDR decoding |

> **Starting Sniffers & Decoders**

| **Sniffer Type**                      | **Command**                                                                                                    | **Notes**                           |
|---------------------------------------|----------------------------------------------------------------------------------------------------------------|-------------------------------------|
| **BT Sniffer for Sonoff (no `-b`)**     | `python3 Sniffle/python_cli/sniff_receiver.py -l -e -a -z -b 2000000`                                             | Requires Sniffle                    |
| **WiFi Sniffer (Wireless Adapter)**   | `python3 wifi_receiver.py --interface wlan0 -z --zmqsetting 127.0.0.1:4223`                                       | Requires compatible WiFi adapter    |
| **WiFi Adapter/BT Decoder**           | `python3 zmq_decoder.py -z --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222,127.0.0.1:4223 -v`                | Run after starting WiFi sniffer     |
| **ESP32/BT Decoder**                  | `python3 zmq_decoder.py -z --uart /dev/esp0 --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222 -v`             | Replace `/dev/esp0` with actual port |


---

## Build Instructions

1. **Clone Repository:**

       git clone https://github.com/Root-Down-Digital/DragonSync-iOS.git

2. **Build the iOS App:**

       cd DragonSync-iOS
       pod install

3. **Open in Xcode:**  
   Open `WarDragon.xcworkspace`

4. **Deploy:**  
   Run the backend scripts as described; then build and deploy to your iOS device or use TestFlight.

---

## Credits, Disclaimer & License

- **Credits:**  
  - [DragonSync](https://github.com/alphafox02/DragonSync)  
  - [DroneID](https://github.com/alphafox02/DroneID)  
  - [Sniffle](https://github.com/nccgroup/Sniffle)  
  - Special thanks to [@alphafox02](https://github.com/alphafox02) and [@bkerler](https://github.com/bkerler)

- **Disclaimer:**  
  This software is provided as-is without warranty. Use at your own risk and in compliance with local regulations.

- **License:**  
  MIT License. See `LICENSE.md` for details.

---

## Contributing & Contact

- **Contributing:** Contributions are welcome via pull requests or by opening an issue.
- **Contact:** For support, please open an issue in this repository.

---

## Notes

**DragonSync is under active development; features may change or have bugs. Feedback welcome**

> [!IMPORTANT]
> Keep your WarDragon DragonOS image updated for optimal compatibility.  

> [!TIP]
> Ensure your iOS device and backend system are on the same local network for best performance.  

> [!CAUTION]
> Use in compliance with local regulations to avoid legal issues.
