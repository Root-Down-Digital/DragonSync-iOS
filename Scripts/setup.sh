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

get_local_ip() {
  local os="$1"
  local ip=""
  
  if [[ "$os" == "macos" ]]; then
    ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
  else
    ip=$(ip route get 1 2>/dev/null | awk '{print $NF; exit}' 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
  fi
  
  [[ -n "$ip" ]] && echo "$ip" || echo "127.0.0.1"
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
  
  if [[ -d "$VENV_DIR" ]]; then
    echo "  Virtual environment already exists, checking activation script..."
    if [[ -f "$VENV_DIR/bin/activate" ]]; then
      source "$VENV_DIR/bin/activate"
      pip install --upgrade pip setuptools wheel
      echo "✔ Existing virtual environment activated."
      export USING_VENV=1
      return
    else
      echo "  Existing venv corrupted, removing and recreating..."
      rm -rf "$VENV_DIR"
    fi
  fi
  
  echo "  Creating virtual environment..."
  if python3 -m venv "$VENV_DIR" 2>&1; then
    echo "  Successfully created venv with python3 -m venv"
  elif python3 -m pip install --user virtualenv --break-system-packages 2>/dev/null && python3 -m virtualenv "$VENV_DIR" 2>&1; then
    echo "  Created venv using virtualenv module"
  elif command -v pipx &>/dev/null && pipx install virtualenv && python3 -m virtualenv "$VENV_DIR" 2>&1; then
    echo "  Created venv using pipx-installed virtualenv"
  elif command -v brew &>/dev/null && brew install pipx && pipx install virtualenv && python3 -m virtualenv "$VENV_DIR" 2>&1; then
    echo "  Created venv using brew pipx virtualenv"
  else
    echo "Error: Failed to create virtual environment. Please install virtualenv manually." >&2
    exit 1
  fi
  
  sleep 2
  
  if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
    echo "Error: Virtual environment created but activation script missing." >&2
    echo "Directory contents:"
    ls -la "$VENV_DIR"
    if [[ -d "$VENV_DIR/bin" ]]; then
      echo "Bin directory contents:"
      ls -la "$VENV_DIR/bin"
    fi
    exit 1
  fi
  
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
  
  echo "Available serial ports:" >&2
  select port in "${ports[@]}" "Manual entry"; do
    if [[ -n "$port" && "$port" != "Manual entry" ]]; then
      echo "$port"
      return
    elif [[ "$REPLY" -eq $((${#ports[@]}+1)) ]] || [[ "$port" == "Manual entry" ]]; then
      read -rp "Enter serial port: " manual
      echo "$manual"
      return
    else
      echo "Invalid selection. Please try again." >&2
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
    5) echo "Skipping firmware flash."; FLASHED_PORT=""; return 0;;
    *) echo "Invalid choice, skipping firmware flash."; FLASHED_PORT=""; return 0;;
  esac
  
  local binfile
  binfile=$(basename "$fw_url")
  echo "Downloading $binfile..."
  if ! curl -sSL -o "$binfile" "$fw_url"; then
    echo "Failed to download firmware file." >&2
    FLASHED_PORT=""
    return 1
  fi
  
  local port
  port=$(select_port "$os")
  if [[ -z "$port" ]]; then
    echo "No port selected, skipping firmware flash." >&2
    rm -f "$binfile"
    FLASHED_PORT=""
    return 1
  fi
  
  echo "Selected port: $port"
  echo "Ready to flash $binfile to $port"
  read -rp "Proceed with flashing? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Firmware flashing cancelled."
    rm -f "$binfile"
    FLASHED_PORT=""
    return 0
  fi
  
  echo "Flashing firmware..."
  if ! esptool --chip auto --port "$port" --baud 115200 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect 0x10000 "$binfile"; then
    echo "Failed to flash firmware." >&2
    rm -f "$binfile"
    FLASHED_PORT=""
    return 1
  fi
  
  echo "✔ Successfully flashed $binfile"
  rm -f "$binfile"
  FLASHED_PORT="$port"
}

create_run_scripts() {
  local venv_activate=""
  [[ "$USING_VENV" -eq 1 ]] && venv_activate="source $PWD/$VENV_DIR/bin/activate"
  
  local default_port="/dev/ttyUSB0"
  [[ -n "$FLASHED_PORT" ]] && default_port="$FLASHED_PORT"
  
  cat > run_bluetooth_receiver.sh << EOF
#!/usr/bin/env bash
set -e
$venv_activate

SERIAL_PORT="\${1:-$default_port}"
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
UART_PORT="\${3:-$default_port}"

echo "Starting WiFi receiver..."
echo "Interface: \$INTERFACE"
echo "ZMQ Setting: \$ZMQ_SETTING"
echo "UART Port: \$UART_PORT"

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

ZMQ_SETTING="\${1:-0.0.0.0:4224}"
ZMQ_CLIENTS="\${2:-127.0.0.1:4222,127.0.0.1:4223}"
UART_PORT="\${3:-$default_port}"

echo "Starting DroneID decoder..."
echo "ZMQ Setting: \$ZMQ_SETTING"
echo "ZMQ Clients: \$ZMQ_CLIENTS"
echo "UART Port: \$UART_PORT"

cd $DRONEID_DIR
python3 zmq_decoder.py --uart "\$UART_PORT" -z --zmqsetting "\$ZMQ_SETTING" --zmqclients "\$ZMQ_CLIENTS" -v
EOF
  chmod +x run_drone_decoder.sh
  
  cat > run_bluetooth_spoof.sh << EOF
#!/usr/bin/env bash
set -e
$venv_activate

SERIAL_PORT="\${1:-$default_port}"
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
  [[ -n "$FLASHED_PORT" ]] && echo "✔ Scripts configured to use flashed port: $FLASHED_PORT"
}

print_usage() {
  local os
  os=$(detect_os)
  local local_ip
  local_ip=$(get_local_ip "$os")
  
  local venv_note=""
  [[ "$USING_VENV" -eq 1 ]] && venv_note="
Virtual environment: $VENV_DIR
To activate manually: source $VENV_DIR/bin/activate"
  
  local port_note=""
  local example_port="/dev/ttyUSB0"
  if [[ -n "$FLASHED_PORT" ]]; then
    port_note="
Default port (from flash): $FLASHED_PORT"
    example_port="$FLASHED_PORT"
  fi
  
  cat << EOF

===================================================
WarDragon DroneID Setup Complete
===================================================

System Information:
- Your local IP address: $local_ip
- Detected OS: $os$venv_note$port_note

Repositories:
- $DRONEID_DIR (DroneID receiver/decoder/spoofer)
- $DRAGONSYNC_DIR (DragonSync monitor)

Advanced Usage:
1. Bluetooth Receiver (ESP32/Sonoff Dongle):
    ./run_bluetooth_receiver.sh [port] [baud] [zmq]

2. WiFi Receiver:
    ./run_wifi_receiver.sh [interface] [zmq] [uart_port]

3. PCAP Replay:
    ./run_pcap_replay.sh [pcap_file] [zmq]

4. Custom Decoder:
    ./run_drone_decoder.sh [zmq_bind] [zmq_clients] [uart_port]

5. Bluetooth Spoofer:
    ./run_bluetooth_spoof.sh [port] [baud]

6. System Monitor:
    ./run_wardragon_monitor.sh [host] [port] [interval]

Quick Start - Run the decoder (most common use case):
./run_drone_decoder.sh

This starts the decoder listening on $local_ip:4224
Access the web interface at: http://$local_ip:4224

Network Access:
- To access from other devices on your network, use: $local_ip
- To check your IP address manually: ifconfig (macOS) or ip addr (Linux)

Example Commands:

# Start with your flashed ESP32 port
./run_drone_decoder.sh 0.0.0.0:4224 127.0.0.1:4222,127.0.0.1:4223 $example_port

# Monitor system resources
./run_wardragon_monitor.sh 0.0.0.0 4225 30

Need help? Check the README files in $DRONEID_DIR and $DRAGONSYNC_DIR
EOF
}

show_main_menu() {
  echo "WarDragon DroneID Setup Script"
  echo "=============================="
  echo "1) Install software only"
  echo "2) Flash firmware only"
  echo "3) Install software and flash firmware"
  echo "4) Exit"
  echo ""
  read -rp "Select option [1-4]: " choice
  echo "$choice"
}

install_software() {
  local os
  os=$(detect_os)
  
  echo "Installing WarDragon DroneID software..."
  echo "Detected OS: $os"
  echo
  
  install_system_deps "$os"
  setup_venv
  
  clone_or_update "$DRONEID_REPO" "$DRONEID_DIR"
  clone_or_update "$DRAGONSYNC_REPO" "$DRAGONSYNC_DIR"
  
  install_python_deps "$DRONEID_DIR"
  install_python_deps "$DRAGONSYNC_DIR"
  
  create_run_scripts
  
  echo
  echo "✔ Software installation complete!"
}

flash_firmware_only() {
  local os
  os=$(detect_os)
  
  echo "Flashing ESP32 firmware only..."
  echo "Detected OS: $os"
  echo
  
  # Only install minimal dependencies needed for esptool
  if ! command -v python3 &>/dev/null; then
    echo "Python3 required for esptool. Installing..."
    if [[ "$os" == "macos" ]]; then
      if ! command -v brew &>/dev/null; then
        echo "Homebrew required to install Python3. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      brew install python3
    else
      echo "Please install python3 manually and re-run this script."
      exit 1
    fi
  fi
  
  # Check if esptool is already available
  if ! command -v esptool &>/dev/null && ! python3 -c "import esptool" 2>/dev/null; then
    echo "Installing esptool..."
    if command -v pipx &>/dev/null; then
      pipx install esptool
    else
      python3 -m pip install --user esptool --break-system-packages 2>/dev/null || python3 -m pip install --user esptool
    fi
  else
    echo "esptool already available."
  fi
  
  flash_firmware "$os"
  
  echo
  if [[ -n "$FLASHED_PORT" ]]; then
    echo "✔ Firmware flashing complete!"
    echo "Flashed to port: $FLASHED_PORT"
    echo
    echo "To use the flashed device, install the software with:"
    echo "./setup.sh (choose option 1)"
  else
    echo "Firmware flashing skipped or failed."
  fi
}


install_and_flash() {
  local os
  os=$(detect_os)
  
  echo "Installing software and flashing firmware..."
  echo "Detected OS: $os"
  echo
  
  install_system_deps "$os"
  setup_venv
  install_esptool
  
  clone_or_update "$DRONEID_REPO" "$DRONEID_DIR"
  clone_or_update "$DRAGONSYNC_REPO" "$DRAGONSYNC_DIR"
  
  install_python_deps "$DRONEID_DIR"
  install_python_deps "$DRAGONSYNC_DIR"
  
  flash_firmware "$os"
  create_run_scripts
  
  echo
  echo "✔ Complete installation finished!"
  
  print_usage
  
  echo
  echo "====================================================="
  echo "Ready to start DroneID monitoring!"
  echo "====================================================="
  echo "1) Start DroneID decoder now"
  echo "2) Start system monitor now"  
  echo "3) Create system service (auto-start on boot)"
  echo "4) Exit (run manually later)"
  echo
  read -rp "Select option [1-4]: " start_choice
  
  case "$start_choice" in
    1)
      echo "Starting DroneID decoder..."
      echo "Press Ctrl+C to stop"
      sleep 2
      ./run_drone_decoder.sh
    ;;
    2)
      echo "Starting system monitor..."
      echo "Press Ctrl+C to stop"
      sleep 2
      ./run_wardragon_monitor.sh
    ;;
    3)
      create_system_service "$os"
    ;;
    4|*)
      echo "Setup complete. You can start services manually using the run scripts."
      echo "Quick start: ./run_drone_decoder.sh"
      echo "To run both, open two terminal tabs and run:"
      echo "  Tab 1: ./run_drone_decoder.sh"
      echo "  Tab 2: ./run_wardragon_monitor.sh"
    ;;
  esac
}

create_system_service() {
  local os="$1"
  local current_dir="$PWD"
  local user="$USER"
  
  echo "Creating system service for auto-start on boot..."
  
  case "$os" in
    "linux")
      cat > wardragon-droneid.service << EOF
[Unit]
Description=WarDragon DroneID Decoder
After=network.target

[Service]
Type=simple
User=$user
WorkingDirectory=$current_dir
ExecStart=$current_dir/run_drone_decoder.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
      
      echo "Installing systemd service..."
      sudo cp wardragon-droneid.service /etc/systemd/system/
      sudo systemctl daemon-reload
      sudo systemctl enable wardragon-droneid.service
      
      echo "✔ Service installed. Commands:"
      echo "  Start:   sudo systemctl start wardragon-droneid"
      echo "  Stop:    sudo systemctl stop wardragon-droneid"
      echo "  Status:  sudo systemctl status wardragon-droneid"
      echo "  Logs:    sudo journalctl -u wardragon-droneid -f"
      
      read -rp "Start the service now? [y/N]: " start_now
      if [[ "$start_now" =~ ^[Yy]$ ]]; then
        sudo systemctl start wardragon-droneid
        echo "Service started!"
      fi
      
      rm wardragon-droneid.service
    ;;
    
    "macos")
      local plist_file="com.wardragon.droneid.plist"
      
      cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wardragon.droneid</string>
    <key>ProgramArguments</key>
    <array>
        <string>$current_dir/run_drone_decoder.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$current_dir</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/wardragon-droneid.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/wardragon-droneid.out</string>
</dict>
</plist>
EOF
      
      echo "Installing LaunchAgent..."
      cp "$plist_file" ~/Library/LaunchAgents/
      launchctl load ~/Library/LaunchAgents/"$plist_file"
      
      echo "✔ LaunchAgent installed. Commands:"
      echo "  Start:   launchctl start com.wardragon.droneid"
      echo "  Stop:    launchctl stop com.wardragon.droneid"
      echo "  Unload:  launchctl unload ~/Library/LaunchAgents/$plist_file"
      echo "  Logs:    tail -f /tmp/wardragon-droneid.out"
      
      read -rp "Start the service now? [y/N]: " start_now
      if [[ "$start_now" =~ ^[Yy]$ ]]; then
        launchctl start com.wardragon.droneid
        echo "Service started!"
      fi
      
      rm "$plist_file"
    ;;
    
    *)
      echo "System service creation not supported on $os"
      echo "You'll need to set up auto-start manually."
    ;;
  esac
}


main() {
  echo "WarDragon DroneID Setup Script"
  echo "=============================="
  echo "1) Install software only"
  echo "2) Flash firmware only" 
  echo "3) Install software and flash firmware"
  echo "4) Exit"
  echo ""
  read -rp "Select option [1-4]: " choice
  
  case "$choice" in
    1)
      install_software
      print_usage
    ;;
    2)
      flash_firmware_only
    ;;
    3)
      install_and_flash
      print_usage
    ;;
    4)
      echo "Exiting..."
      exit 0
    ;;
    *)
      echo "Invalid choice. Exiting..."
      exit 1
    ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi