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
  echo "Installing system dependencies for $os…"
  
  case "$os" in
    "linux")
      if command -v apt-get &>/dev/null; then
        sudo apt-get update
        sudo apt-get install -y python3 python3-pip python3-venv git curl build-essential libssl-dev libffi-dev lm-sensors gpsd gpsd-clients
      elif command -v yum &>/dev/null; then
        sudo yum install -y python3 python3-pip python3-virtualenv git curl gcc openssl-devel libffi-devel lm-sensors gpsd
      elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm python python-pip python-virtualenv git curl gcc openssl libffi lm-sensors gpsd
      else
        echo "Unsupported Linux distro; install python3, pip, venv/virtualenv, git, curl, lm-sensors & gpsd manually." >&2
        exit 1
      fi
    ;;
    "macos")
      if ! command -v brew &>/dev/null; then
        echo "Homebrew missing → installing…"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      brew update
      brew install python3 git curl
      echo "Note: GPS & sensors on macOS need extra setup."
    ;;
    *)
      echo "Unsupported OS: $os" >&2
      exit 1
    ;;
  esac
  
  echo "✔ System dependencies installed."
}

install_esptool() {
  echo "→ Installing esptool..."
  if [[ "$USING_VENV" -eq 1 ]]; then
    pip install esptool
  else
    if command -v pipx &>/dev/null; then
      pipx install esptool
    else
      python3 -m pip install --user esptool --break-system-packages
    fi
  fi
  echo "✔ esptool installed."
}

setup_venv() {
  echo "→ Setting up Python virtual environment…"
  
  # Create venv (try stdlib, else fallback to virtualenv)
  if [[ ! -d "$VENV_DIR" ]]; then
    echo "  Creating virtual environment..."
    if ! python3 -m venv "$VENV_DIR" 2>/dev/null; then
      echo "  stdlib venv failed; trying to install virtualenv in user space"
      if ! python3 -m pip install --user virtualenv --break-system-packages 2>/dev/null; then
        echo "  Installing virtualenv with pipx..."
        if ! command -v pipx &>/dev/null; then
          if command -v brew &>/dev/null; then
            brew install pipx
          else
            echo "Error: Cannot install virtualenv. Please install pipx manually." >&2
            exit 1
          fi
        fi
        pipx install virtualenv
        python3 -m virtualenv "$VENV_DIR"
      else
        python3 -m virtualenv "$VENV_DIR"
      fi
    fi
  fi
  
  # Avoid racing on slow filesystems
  until [[ -f "$VENV_DIR/bin/activate" ]]; do
    echo "  waiting for venv to finish…"
    sleep 1
  done
  
  # Activate and prep
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip setuptools wheel
  
  echo "✔ Virtual environment ready & activated."
  export USING_VENV=1
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
    echo "${ports[0]}"
    return
  fi
  
  echo "Available serial ports:"
  select port in "${ports[@]}" "Manual entry"; do
    if [[ "$REPLY" -le "${#ports[@]}" ]]; then
      echo "$port"
      return
    elif [[ "$REPLY" -eq $((${#ports[@]}+1)) ]]; then
      read -rp "Enter serial port: " manual
      echo "$manual"
      return
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
  curl -sSL -o "$binfile" "$fw_url"
  
  local port
  port=$(select_port "$os")
  if [[ -z "$port" ]]; then
    echo "No port selected, skipping firmware flash." >&2
    rm -f "$binfile"
    return 1
  fi
  
  echo "Ready to flash $binfile to $port"
  read -rp "Proceed with flashing? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Firmware flashing cancelled."; rm -f "$binfile"; return 0; }
  
  pip install esptool
  esptool --chip auto --port "$port" --baud 115200 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect 0x10000 "$binfile"
  echo "✔ Successfully flashed $binfile"
  rm -f "$binfile"
}

create_run_scripts() {
  local venv_activate=""
  [[ "$USING_VENV" -eq 1 ]] && venv_activate="source $PWD/$VENV_DIR/bin/activate"
  
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
  chmod +x run_bluetooth_receiver.sh

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
  chmod +x run_wifi_receiver.sh

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
  chmod +x run_pcap_replay.sh

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
  chmod +x run_drone_decoder.sh

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
  chmod +x run_bluetooth_spoof.sh

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
  chmod +x run_wardragon_monitor.sh

  echo "✔ Created run scripts for all DroneID modes"
}

print_usage() {
  local venv_note=""
  [[ "$USING_VENV" -eq 1 ]] && venv_note="
Virtual environment: $VENV_DIR
To activate manually: source $VENV_DIR/bin/activate"

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
   run_bluetooth_receiver.sh [port] [baud] [zmq]
2. WiFi Receiver:
   run_wifi_receiver.sh [iface] [zmq]
3. PCAP Replay:
   run_pcap_replay.sh [pcap] [zmq]
4. Decoder:
   run_drone_decoder.sh [zmq] [clients]
5. Spoofer:
   run_bluetooth_spoof.sh [port] [baud]
6. Monitor:
   run_wardragon_monitor.sh [host] [port] [interval]
EOF
}

main() {
  local os
  os=$(detect_os)
  
  echo "WarDragon DroneID Setup Script"
  echo "Detected OS: $os"
  echo "============================"
  
  install_system_deps "$os"
  setup_venv
  install_esptool
  
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
