#!/usr/bin/env bash
set -e
IFS=$'\n\t'

DRONEID_REPO="https://github.com/alphafox02/DroneID.git"
DRAGONSYNC_REPO="https://github.com/alphafox02/DragonSync.git"
DRONEID_DIR="DroneID"
DRAGONSYNC_DIR="DragonSync"
VENV_DIR="drone_env"

detect_os() {
 if [[ "$OSTYPE" == "darwin"* ]]; then
   echo "macos"
 elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
   echo "linux"
 else
   echo "unknown"
 fi
}

install_system_deps() {
 local os="$1"
 echo "Installing system dependencies for $os..."
 
 case "$os" in
   "linux")
     if command -v apt-get &>/dev/null; then
       sudo apt-get update
       sudo apt-get install -y python3 python3-pip python3-venv git curl build-essential libssl-dev libffi-dev lm-sensors gpsd gpsd-clients
     elif command -v yum &>/dev/null; then
       sudo yum install -y python3 python3-pip python3-venv git curl gcc openssl-devel libffi-devel lm-sensors gpsd
     elif command -v pacman &>/dev/null; then
       sudo pacman -Sy python python-pip python-virtualenv git curl gcc openssl libffi lm-sensors gpsd
     else
       echo "Unsupported Linux distribution. Please install python3, python3-pip, python3-venv, git, curl, lm-sensors, and gpsd manually" >&2
       exit 1
     fi
     ;;
   "macos")
     if ! command -v brew &>/dev/null; then
       echo "Installing Homebrew..."
       /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
     fi
     brew update
     brew install python3 git curl
     echo "Note: GPS and sensor monitoring may require additional setup on macOS"
     ;;
   *)
     echo "Unsupported OS: $os" >&2
     exit 1
     ;;
 esac
 
 python3 -m pip install --user esptool
 echo "✔ System dependencies installed."
}

setup_venv() {
 local os="$1"
 
 if [[ "$os" == "macos" ]] || [[ -n "$FORCE_VENV" ]]; then
   echo "Setting up Python virtual environment..."
   
   if [[ ! -d "$VENV_DIR" ]]; then
     python3 -m venv "$VENV_DIR"
   fi
   
   source "$VENV_DIR/bin/activate"
   pip install --upgrade pip setuptools wheel
   
   echo "✔ Virtual environment activated."
   export USING_VENV=1
 else
   echo "Using system Python on Linux."
   export USING_VENV=0
 fi
}

clone_or_update() {
 local url="$1"
 local dir="$2"
 
 if [[ -d "$dir/.git" ]]; then
   echo "Updating $dir..."
   git -C "$dir" pull --ff-only
 else
   echo "Cloning $dir..."
   git clone --recursive "$url" "$dir"
 fi
 
 if [[ -f "$dir/.gitmodules" ]]; then
   echo "Updating submodules for $dir..."
   git -C "$dir" submodule init
   git -C "$dir" submodule update --init --recursive
 fi
}

install_python_deps() {
 local dir="$1"
 
 if [[ -f "$dir/requirements.txt" ]]; then
   echo "Installing Python dependencies for $dir..."
   pip install -r "$dir/requirements.txt"
 fi
 
 if [[ "$dir" == "$DRONEID_DIR" ]]; then
   echo "Ensuring DroneID dependencies are installed..."
   pip install pyzmq pyserial numpy scapy
 elif [[ "$dir" == "$DRAGONSYNC_DIR" ]]; then
   echo "Ensuring DragonSync dependencies are installed..."
   pip install pyzmq psutil gpsd-py3
 fi
}

get_available_ports() {
 local os="$1"
 local patterns=()
 
 if [[ "$os" == "macos" ]]; then
   patterns=(/dev/cu.*)
 else
   patterns=(/dev/ttyUSB* /dev/ttyACM*)
 fi
 
 local ports=()
 for p in "${patterns[@]}"; do 
   [[ -e "$p" ]] && ports+=("$p")
 done
 
 printf '%s\n' "${ports[@]}"
}

select_port() {
 local os="$1"
 local ports=()
 
 while IFS= read -r line; do
   [[ -n "$line" ]] && ports+=("$line")
 done < <(get_available_ports "$os")
 
 if [[ ${#ports[@]} -eq 0 ]]; then
   read -rp "No serial ports detected. Enter port manually: " manual_port
   echo "$manual_port"
   return
 fi
 
 if [[ ${#ports[@]} -eq 1 ]]; then
   echo "Auto-selecting: ${ports[0]}" >&2
   echo "${ports[0]}"
   return
 fi
 
 echo "Available serial ports:" >&2
 for i in "${!ports[@]}"; do
   echo "$((i+1))) ${ports[i]}" >&2
 done
 echo "$((${#ports[@]}+1))) Manual entry" >&2
 
 while true; do
   read -rp "Choose serial port [1-$((${#ports[@]}+1))]: " choice
   if [[ "$choice" -ge 1 && "$choice" -le "${#ports[@]}" ]]; then
     echo "${ports[$((choice-1))]}"
     return
   elif [[ "$choice" -eq $((${#ports[@]}+1)) ]]; then
     read -rp "Enter serial port: " manual_port
     echo "$manual_port"
     return
   else
     echo "Invalid selection. Try again." >&2
   fi
 done
}

flash_firmware() {
 local os="$1"
 
 echo "ESP32 Firmware Options:"
 echo "1) Official WarDragon ESP32 FW (T-Halow) - Recommended"
 echo "2) Dual-core BT/WiFi for Xiao ESP32-S3"
 echo "3) WiFi-only for Xiao ESP32-S3"
 echo "4) WiFi-only for Xiao ESP32-C3"
 echo "5) Skip flashing"
 
 read -rp "Select firmware [1-5]: " fw_choice
 
 local fw_url
 case "$fw_choice" in
   1) fw_url="https://github.com/alphafox02/T-Halow/raw/refs/heads/master/firmware/firmware_T-Halow_DragonOS_RID_Scanner_20241107.bin";;
   2) fw_url="https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_s3dualcoreRIDfirmware.bin";;
   3) fw_url="https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_s3_WiFi_RID_firmware.bin";;
   4) fw_url="https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_c3_WiFi_RID_firmware.bin";;
   5) echo "Skipping firmware flash."; return 0;;
   *) echo "Invalid choice, skipping firmware flash."; return 0;;
 esac

 local binfile
 binfile=$(basename "$fw_url")
 echo "Downloading $binfile..."
 
 if ! curl -sSL -o "$binfile" "$fw_url"; then
   echo "Failed to download firmware" >&2
   return 1
 fi

 local port
 port=$(select_port "$os")
 
 if [[ -z "$port" ]]; then
   echo "No port selected, skipping firmware flash." >&2
   rm -f "$binfile"
   return 1
 fi
 
 echo "Ready to flash $binfile to $port"
 read -rp "Proceed with flashing? [y/N]: " confirm
 case "$confirm" in 
   [Yy]*) ;;
   *) echo "Firmware flashing cancelled."; rm -f "$binfile"; return 0;;
 esac

 echo "Flashing firmware..."
 if esptool --chip auto --port "$port" --baud 115200 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect 0x10000 "$binfile"; then
   echo "✔ Successfully flashed $binfile"
   export FLASHED_PORT="$port"
 else
   echo "Firmware flashing failed" >&2
   return 1
 fi
 
 rm -f "$binfile"
}

create_run_scripts() {
 local venv_activate=""
 
 if [[ "$USING_VENV" -eq 1 ]]; then
   venv_activate="source $PWD/$VENV_DIR/bin/activate"
 fi
 
 cat > run_bluetooth_receiver.sh << EOF
#!/usr/bin/env bash
set -e
$venv_activate

SERIAL_PORT="\${1:-/dev/ttyUSB0}"
BAUDRATE="\${2:-2000000}"
ZMQ_SETTING="\${3:-127.0.0.1:4222}"

echo "Starting Bluetooth receiver..."
echo "Serial Port: \$SERIAL_PORT"
echo "Baudrate: \$BAUDRATE"
echo "ZMQ Setting: \$ZMQ_SETTING"

cd $DRONEID_DIR
python3 bluetooth_receiver.py -b "\$BAUDRATE" -s "\$SERIAL_PORT" --zmqsetting "\$ZMQ_SETTING" -v
EOF
 
 cat > run_wifi_receiver.sh << EOF
#!/usr/bin/env bash
set -e
$venv_activate

INTERFACE="\${1:-wlan0}"
ZMQ_SETTING="\${2:-127.0.0.1:4223}"

echo "Starting WiFi receiver..."
echo "Interface: \$INTERFACE"
echo "ZMQ Setting: \$ZMQ_SETTING"

cd $DRONEID_DIR
python3 wifi_receiver.py --interface "\$INTERFACE" -z --zmqsetting "\$ZMQ_SETTING"
EOF
 
 cat > run_pcap_replay.sh << EOF
#!/usr/bin/env bash
set -e
$venv_activate

PCAP_FILE="\${1:-examples/odid_wifi_sample.pcap}"
ZMQ_SETTING="\${2:-127.0.0.1:4223}"

echo "Starting PCAP replay..."
echo "PCAP File: \$PCAP_FILE"
echo "ZMQ Setting: \$ZMQ_SETTING"

cd $DRONEID_DIR
python3 wifi_receiver.py --pcap "\$PCAP_FILE" -z --zmqsetting "\$ZMQ_SETTING"
EOF
 
 cat > run_drone_decoder.sh << EOF
#!/usr/bin/env bash
set -e
$venv_activate

ZMQ_SETTING="\${1:-127.0.0.1:4224}"
ZMQ_CLIENTS="\${2:-127.0.0.1:4222,127.0.0.1:4223}"

echo "Starting DroneID decoder..."
echo "ZMQ Setting: \$ZMQ_SETTING"
echo "ZMQ Clients: \$ZMQ_CLIENTS"

cd $DRONEID_DIR
python3 zmq_decoder.py -z --zmqsetting "\$ZMQ_SETTING" --zmqclients "\$ZMQ_CLIENTS" -v
EOF
 
 cat > run_bluetooth_spoof.sh << EOF
#!/usr/bin/env bash
set -e
$venv_activate

SERIAL_PORT="\${1:-/dev/ttyUSB0}"
BAUDRATE="\${2:-2000000}"

echo "Starting Bluetooth spoofer..."
echo "Serial Port: \$SERIAL_PORT"
echo "Baudrate: \$BAUDRATE"
echo "Edit drone.json for data to spoof"

cd $DRONEID_DIR
python3 bluetooth_spoof.py -s "\$SERIAL_PORT" -b "\$BAUDRATE"
EOF
 
 cat > run_wardragon_monitor.sh << EOF
#!/usr/bin/env bash
set -e
$venv_activate

ZMQ_HOST="\${1:-0.0.0.0}"
ZMQ_PORT="\${2:-4225}"
INTERVAL="\${3:-30}"

echo "Starting WarDragon system monitor..."
echo "ZMQ Host: \$ZMQ_HOST"
echo "ZMQ Port: \$ZMQ_PORT"
echo "Interval: \$INTERVAL seconds"

cd $DRAGONSYNC_DIR
python3 wardragon_monitor.py --zmq_host "\$ZMQ_HOST" --zmq_port "\$ZMQ_PORT" --interval "\$INTERVAL"
EOF
 
 chmod +x run_*.sh
 echo "✔ Created run scripts for all DroneID modes"
}

print_usage() {
 local venv_note=""
 
 if [[ "$USING_VENV" -eq 1 ]]; then
   venv_note="
Virtual environment: $VENV_DIR
To activate manually: source $VENV_DIR/bin/activate"
 fi
 
 cat << EOF

===================================================
WarDragon DroneID Setup Complete
===================================================

Repositories:
- $DRONEID_DIR (DroneID receiver/decoder/spoofer)
- $DRAGONSYNC_DIR (DragonSync monitor)

$venv_note

DroneID Modes:
1. Bluetooth Receiver (Sonoff Dongle):
   ./run_bluetooth_receiver.sh [serial_port] [baudrate] [zmq_setting]
   Default: ./run_bluetooth_receiver.sh /dev/ttyUSB0 2000000 127.0.0.1:4222

2. WiFi Receiver (Monitor Mode):
   ./run_wifi_receiver.sh [interface] [zmq_setting]
   Default: ./run_wifi_receiver.sh wlan0 127.0.0.1:4223

3. PCAP Replay:
   ./run_pcap_replay.sh [pcap_file] [zmq_setting]
   Default: ./run_pcap_replay.sh examples/odid_wifi_sample.pcap 127.0.0.1:4223

4. DroneID Decoder (ZMQ Server):
   ./run_drone_decoder.sh [zmq_setting] [zmq_clients]
   Default: ./run_drone_decoder.sh 127.0.0.1:4224 127.0.0.1:4222,127.0.0.1:4223

5. Bluetooth Spoofer:
   ./run_bluetooth_spoof.sh [serial_port] [baudrate]
   Default: ./run_bluetooth_spoof.sh /dev/ttyUSB0 2000000
   Note: Edit drone.json for data to spoof

6. WarDragon Monitor:
   ./run_wardragon_monitor.sh [zmq_host] [zmq_port] [interval]
   Default: ./run_wardragon_monitor.sh 0.0.0.0 4225 30

Complete Setup Example:
1. Start decoder: ./run_drone_decoder.sh 127.0.0.1:4224 127.0.0.1:4222,127.0.0.1:4223
2. Start bluetooth receiver: ./run_bluetooth_receiver.sh /dev/ttyUSB0 2000000 127.0.0.1:4222
3. Start wifi receiver: ./run_wifi_receiver.sh wlan0 127.0.0.1:4223
4. Start monitor: ./run_wardragon_monitor.sh 0.0.0.0 4225 30

===================================================
EOF
}

main() {
 local os
 os=$(detect_os)
 
 echo "WarDragon DroneID Setup Script"
 echo "Detected OS: $os"
 echo "============================"
 
 install_system_deps "$os"
 setup_venv "$os"
 
 clone_or_update "$DRONEID_REPO" "$DRONEID_DIR"
 clone_or_update "$DRAGONSYNC_REPO" "$DRAGONSYNC_DIR"
 
 install_python_deps "$DRONEID_DIR"
 install_python_deps "$DRAGONSYNC_DIR"
 
 flash_firmware "$os"
 create_run_scripts
 print_usage
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
