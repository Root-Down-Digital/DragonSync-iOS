# Drag0net Scanner

**Standalone ESP32 WiFi Remote ID Scanner with ZMQ Publisher**

A portable alternative to the full detection stack for [DragonSync iOS & macOS](https://github.com/Root-Down-Digital/DragonSync-iOS). No computer required—just flash, power on, and connect.

---

## Supported Hardware

- **ESP32-C3 XIAO** (AP/Mesh)
- **ESP32-S3 XIAO** (AP/Mesh)
- **ESP32-S3 LilyGO T-Dongle** (AP only)

Additional firmware options available in the `FW` folder.

---

## Installation

### Quick Flash (Recommended)

Use the [auto-flasher script](https://github.com/Root-Down-Digital/DragonSync-iOS/tree/main#2-install-software--flash-firmware) for automated installation, or flash manually:
```bash
esptool.py --chip auto --port /dev/YOUR_PORT --baud 115200 \
  --before default_reset --after hard_reset write_flash -z \
  --flash_mode dio --flash_freq 80m --flash_size detect \
  0x10000 firmwareFile.bin
```

Replace `/dev/YOUR_PORT` with your ESP32's serial port and `firmwareFile.bin` with the downloaded firmware.

### Build from Source

Customize WiFi credentials and settings:

1. Clone repository:
```bash
   git clone https://github.com/Root-Down-Digital/DragonSync-iOS.git
```

2. Open `DragonSync-iOS/Util/ESP32_RID_AP_FW` in VSCode

3. Edit `main.cpp` to change credentials:
```cpp
   const char* ap_ssid = "Dr4g0net";
   const char* ap_password = "wardragon1234";
```

4. Upload using PlatformIO (portable to most ESP32 boards)

---

## Usage

### Default Credentials
```
SSID:     Dr4g0net
Password: wardragon1234
IP:       192.168.4.1
```

### Option A: DragonSync App

1. Connect phone to `Dr4g0net` WiFi network
2. Open DragonSync app → Settings
3. Enter ZMQ IP: `192.168.4.1`
4. Enable ZMQ connection
5. Status appears within 60 seconds

<img src="https://github.com/user-attachments/assets/9903ebef-0dd7-4a6e-a976-c855221eff52" width="60%" />

<img src="https://github.com/user-attachments/assets/6fe4d993-61e9-43bc-83eb-311b7df89342" width="60%" />

### Option B: Web Interface

1. Connect to `Dr4g0net` WiFi network
2. Open browser and navigate to `192.168.4.1`
3. Monitor detections via web dashboard

<img src="https://github.com/user-attachments/assets/93a034eb-4c81-456c-8457-f604307392f5" width="60%" />

### Option C: Meshtastic Integration

**1. Connect to Meshtastic:**
- Install Meshtastic app on phone or use web interface
- Connect to your Meshtastic device via Bluetooth or serial

**2. Configure Serial Module:**

Navigate to: Module Settings → Serial Config

Set parameters:
- **Enabled:** ON
- **Mode:** TEXTMSG
- **RX GPIO:** 19
- **TX GPIO:** 20
- **Baud Rate:** 115200
- **Timeout:** 5000ms

---

## Notes

- This project is not affiliated with WarDragon, DragonOS, or related projects
- Based on [cemaxecuter WiFi RID firmware](https://github.com/alphafox02/T-Halow/tree/master/firmware)

> [!IMPORTANT]
> **Work in Progress:** Expect breaking changes and possible stability issues.
>
> **Legal Use Only:** Use within legal and ethical bounds. Author is not responsible for misuse of this code or knowledge.
