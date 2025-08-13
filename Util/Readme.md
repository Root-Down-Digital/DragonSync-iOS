# `Drag0net Scanner`

_**A standalone ESP32 WiFi Remote ID Scanner with ZMQ Publisher**_

- Made for [DragonSync iOS & macOS](https://github.com/Root-Down-Digital/DragonSync-iOS) as a portable alternative to the whole detection stack.

### Firmware for Currently Supported Boards
   
- `DragonScanner_espc3_xiao.bin`   
- `DragonScanner_esps3_xiao.bin`
- `DragonScanner_esps3_lily_T_dongle`

## 1. Flash

**Options**: Use a binary file hosted here or, you can build from source (to change the SSID name and password and more)

### Flash Precompiled Binary

- An [auto-flasher](https://github.com/Root-Down-Digital/DragonSync-iOS/tree/main#2-install-software--flash-firmware) script is here also to make it even simpler, or continue below:

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
   
      <img src="https://github.com/user-attachments/assets/9903ebef-0dd7-4a6e-a976-c855221eff52" width="60%" />
   
   - Activate, status will appear within 60s

     <img src="https://github.com/user-attachments/assets/6fe4d993-61e9-43bc-83eb-311b7df89342" width="60%" />

#### B. WebUI
   - Connect to the AP
   - Visit `192.168.4.1` in your browser

      <img src="https://github.com/user-attachments/assets/93a034eb-4c81-456c-8457-f604307392f5" width="60%" />


## Notes
- This project not affiliated with WarDragon, DragonOS etc.
- Based on cemaxecuter WiFi [RID FW](https://github.com/alphafox02/T-Halow/tree/master/firmware

> [!IMPORTANT]
> This is a work in progress, expect breaking changes and possible stability issues.
>
> Use within legal and ethical bounds. Author not responsible for anything that happens should you use any code or knowledge provided here.
