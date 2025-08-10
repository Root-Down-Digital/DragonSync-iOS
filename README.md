# DragonSync iOS

[![TestFlight Beta](https://img.shields.io/badge/TestFlight-Closed_Beta-blue.svg?style=f&logo=apple)](https://testflight.apple.com/join/QKDKMSfA)
[![MobSF](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml/badge.svg)](https://github.com/Root-Down-Digital/DragonSync-iOS/actions/workflows/mobsf.yml)
[![Latest Release](https://img.shields.io/github/v/release/Root-Down-Digital/DragonSync-iOS?label=Version)](https://github.com/Root-Down-Digital/DragonSync-iOS/releases/latest)

<div align="center">
  <img src="https://github.com/user-attachments/assets/d21ab909-7dba-4b42-8996-a741248e9223" width="80%" alt="DragonSync Logo">
</div>
<br>

<div align="center">
  Real-time drone detection and monitoring for iOS/macOS, powered by locally-hosted decoding. Enjoy professional-grade detection with advanced signal analysis and tracking. 
</div>
<br>


### App
- [Features](#features)
- [Detection & Tracking](#detection--tracking)
- [History & Analysis](#history--analysis)
 - [Build Instructions](#build-instructions)

### Supplying Backend Data
- [Hardware Requirements](#hardware-requirements)
 - [Software Setup](#software-requirements)
 - [Connection Choices](#connection-choices)
 - [Command Reference](#backend-data-guide)

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

## 1. Pick a Stack 

#### Hardware Requirements

**Option 1: [WarDragon/Pro](https://cemaxecuter.com/?post_type=product)**
- Works out of the box, put its IP into the connection settings and go.

**Option 2: DIY**
- Uses your own stack to provide the app data

  **Configuration A: WiFi & BT Adapters**
   - WiFi adapter 
   - Sniffle-compatible BT dongle (Catsniffer, Sonoff) flashed with Sniffle FW

  **Configuration B:**
  - ESP32S3/C3

- (Optional) ANTSDR E200 - for decoding Ocusync and others
- (Optional) GPS USB module to use host instead of on-device GPS
    
> [!NOTE]
> **New standalone WiFi RID [option](https://github.com/Root-Down-Digital/DragonSync-iOS/tree/main/Util) can be flashed with the auto installer below:**
> - _Note this is for WiFi RID only (the most prevalant)_
> - No additional software/hw installation required

## 2. Install Software & Flash Firmware
  
  - ### Auto Installation
    
    _**The below unix command will verify the expected sha256sum and install the [software](https://github.com/Root-Down-Digital/DragonSync-iOS/blob/main/Scripts/setup.sh) and then flash an esp32.**_

    > _For Windows see [manual setup](#python-tools-setup-instructions)_

```bash
curl -fsSL https://raw.githubusercontent.com/Root-Down-Digital/DragonSync-iOS/refs/heads/main/Scripts/setup.sh -o setup.sh && [[ $(shasum -a 256 setup.sh 2>/dev/null || sha256sum setup.sh) =~ ^be41d0ca3cfb0727d1780d37c033a354d9a32f2f53d8e6433fc096ea9d5dfe04 ]] && chmod +x setup.sh && ./setup.sh
```


```
=====================================================
WarDragon DroneID Setup Script
=====================================================

OPTIONS:
---------
1) Install software only
2) Flash standard firmware only (requires software)
3) Install software AND flash standard firmware

STANDALONE OPTIONS (ESP32S3/C3):
------------------------------------------
4) Flash STANDALONE DragonSync AP firmware
   ➜ Creates WiFi AP for DragonSync iOS/macOS
   ➜ No additional software/hw installation required

5) Exit

Select option [1-5]: 
```

  > [!IMPORTANT]
  > Placeholder commands are created for the different hardware options. **You need to add the flags**, use the examples below.
> 
> - An autostart option is given after using option 3
> 
> - Choose 4 to use your esp32 as a **standalone** alternative to the the hardware and software stacks
> - **Choose skip flashing when prompted if using your own wireless adapters instead of esp32**
    
  ---
  
  - ### Manual Installation
  
    **First, visit [software requirements](#software-requirements) and complete all steps**
    
    **1. Choose Firmware:**
    
    - [Official WarDragon WiFi RID ESP32 FW for T-Halow Dongle](https://github.com/alphafox02/T-Halow/raw/refs/heads/master/firmware/firmware_T-Halow_DragonOS_RID_Scanner_20241107.bin) - Recommended
    - [Dualcore BT/WiFI for xiao esp32s3](https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_s3dualcoreRIDfirmware.bin)*
    - [WiFI Only for xiao esp32s3](https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_s3_WiFi_RID_firmware.bin)
    - [WiFI Only for xiao esp32c3](https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_c3_WiFi_RID_firmware.bin)
    
    **2. Flash**
    
    ```python
    esptool.py --chip auto --port /dev/yourportname --baud 115200 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect 0x10000 firmwareFile.bin
    ```    
    - (Change port name and firmware name/filepath)

## 3. Start Detection

*Swap in this zmq decoder to handle both types over UART RID [here](https://github.com/lukeswitz/DroneID/blob/dual-esp32-rid/zmq_decoder.py) **if using the dual RID fw.**

**Optional: Persist detection using [service files](https://github.com/alphafox02/DragonSync/tree/main/services)** made by @alphafox02.
- Mod the commands to suite and copy to an OS service dir (`/etc/systemd/system` for example).

**Start Detecting WiFi RID using esp32** _(the setup.sh creates use commands for all hardware cases, this is an example workflow)_

```python
# Run the decoder
cd DroneID
python3 zmq_decoder.py -z --uart /dev/youresp32port --zmqsetting 0.0.0.0:4224 --zmqclients 127.0.0.1:4222

# In a new tab, run the system monitor (not a requirement)
cd Dragonsync
python3 wardragon_monitor.py --zmq_host 0.0.0.0 --zmq_port 4225 --interval 30

```

## 4. Start App 
  - Set app ZMQ IP to your host and enable in settings.
  - The app will continue monitoring in the backround.

---

## Software Requirements

This section covers manually setting up the backend Python environment on Linux, macOS, and Windows.

**Required**

`WiFi`
- [DroneID](https://github.com/alphafox02/DroneID) for decoding RID packets

`Bluetooth`
- [Sniffle](https://github.com/nccgroup/Sniffle) flashed on BT RID hardware (Sonoff, Catsniffer)

`Status`
- [DragonSync Python](https://github.com/alphafox02/DragonSync) for system stats, TAK integration and more


`Optional`
- [DJI Firmware - E200](https://github.com/alphafox02/antsdr_dji_droneid) for SDR

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

### ZMQ Server – Recommended

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
