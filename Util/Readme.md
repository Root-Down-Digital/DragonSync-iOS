# `Drag0net Scanner`

_**A standalone ESP32 WiFi Remote ID Scanner with ZMQ Publisher**_

- Made for [DragonSync iOS & macOS](https://github.com/Root-Down-Digital/DragonSync-iOS) as a portable alternative to the whole detection stack.

### Firmware for Currently Supported Boards
   
- `DragonScanner_espc3_xiao.bin`   
- `DragonScanner_esps3_xiao.bin`
- `DragonScanner_esps3_lily_T_dongle`

## 1. Flash

Options: Use a binary file hosted here or, you can build from source (to change the SSID name and password and more)

### Flash Precompiled Binary
- Use default credentials, flash precompiled binary with `esptool.py`

   ```
  esptool.py --chip auto --port /dev/yourportname --baud 115200 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect 0x10000 firmwareFile.bin
   ```

### Build Source

- Grab the codebase

```bash
git clone https://github.com/Root-Down-Digital/DragonSync-iOS.git
```

- Open the `DragonSync-iOS/Util/ESP32_RID_AP_FW` folder in VSCode
- Change AP creds `main.cpp`:

```
const char* ap_ssid = "Dr4g0net";
const char* ap_password = "wardragon1234";
```

- Upload using PlatformIO (can be ported to most any esp32 board)

## 2. Usage 

**Default WiFi AP Credentials**

```
SSID: Dr4g0net
PW: wardragon1234
IP:  192.168.4.1
```

#### A. DragonSync App
   - Enter the ZMQ IP `192.168.4.1`
   - Activate. Done.

#### B. WebUI
   - Connect to the AP
   - Visit `192.168.4.1` in your browser

## Notes
- This project not affiliated with WarDragon, DragonOS etc.
- Based on cemaxecuter WiFi [RID FW](https://github.com/alphafox02/T-Halow/tree/master/firmware)

> [!IMPORTANT]
> This is a work in progress, expect breaking changes and possible stability issues.
>
> Use within legal and ethical bounds. Author not responsible for anything that happens should you use any code or knowledge provided here.
