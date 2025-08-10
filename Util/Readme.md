# `Drag0net Scanner`

_**A standalone ESP32 WiFi Remote ID Scanner with ZMQ Publisher**_


- Made for [DragonSync iOS & macOS](https://github.com/Root-Down-Digital/DragonSync-iOS) as a portable alternative to the whole detection stack.

### Firmware for Currently Supported Boards
   
- `DragonScanner_espc3_xiao.bin`   
- `DragonScanner_esps3_xiao.bin`
- `DragonScanner_esps3_lily_T_dongle`

## 1. Flash

### Flash Precompiled Binary
- Use default credentials, flash precompiled binary with `esptool.py`

   ```
  esptool.py --chip auto --port /dev/yourportname --baud 115200 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect 0x10000 firmwareFile.bin
   ```

## 2. Usage 

**Default WiFi AP Credentials**

SSID: `Dr4g0net`

PW: `wardragon1234`

IP:  `192.168.4.1`

#### A. DragonSync App
   - Enter the ZMQ IP
   - Activate. Done.
   
   <img src="https://github.com/user-attachments/assets/059c5efa-5a8a-4af8-8401-c8fa00273610" width="60%" >

#### B. WebUI
   - Connect to the AP
   - Visit 192.168.4.1 in your browser
   
   <img src="https://github.com/user-attachments/assets/5823cf88-0d82-4b68-9610-1b4c0fb24432" width="80%" >

## Notes
**This project not affiliated with WarDragon, DragonOS etc. Thanks to cemaxecuter for the original WiFi RID FW this is based on**

> [!IMPORTANT]
> This is a work in progress, expect breaking changes and possible stability issues.
>
> Use within legal and ethical bounds. Author not responsible for anything that happens should you use any code or knowledge provided here.
