#!/usr/bin/env bash
set -e
IFS=$'\n\t'

export PATH="$HOME/.local/bin:$PATH"

DRONEID_REPO="https://github.com/alphafox02/DroneID.git"
DRAGONSYNC_REPO="https://github.com/alphafox02/DragonSync.git"
DRONEID_DIR="DroneID"
DRAGONSYNC_DIR="DragonSync"

clone_or_update() {
  url="$1"; dir="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only
  else
    git clone --recursive "$url" "$dir"
  fi
  git -C "$dir" submodule update --init --recursive
}

select_port() {
  if [ "$(uname)" = "Darwin" ]; then
    patterns=(/dev/cu.*)
  else
    patterns=(/dev/ttyUSB* /dev/ttyACM*)
  fi
  ports=()
  for p in "${patterns[@]}"; do [ -e "$p" ] && ports+=("$p"); done
  if [ ${#ports[@]} -eq 0 ]; then
    read -rp "Enter serial port: " manual
    echo "$manual"; return
  fi
  PS3="Choose serial port: "
  select port in "${ports[@]}" "Manual entry"; do
    if [ "$REPLY" -le "${#ports[@]}" ] 2>/dev/null; then
      echo "$port"; return
    elif [ "$REPLY" -eq $((${#ports[@]}+1)) ]; then
      read -rp "Enter serial port: " manual
      echo "$manual"; return
    fi
  done
}

install_deps() {
  if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip git esptool curl
  elif command -v brew &>/dev/null; then
    brew update
    brew install python3 git esptool curl
  else
    echo "Please install python3, pip3, git, esptool, and curl manually" >&2
    exit 1
  fi
  python3 -m pip install --user esptool
  echo "✔ Core dependencies installed."
}

flash_firmware() {
  echo "1) Official WarDragon ESP32 FW (T-Halow)"
  echo "2) Dual-core BT/WiFi for Xiao ESP32-S3"
  echo "3) WiFi-only for Xiao ESP32-S3"
  echo "4) WiFi-only for Xiao ESP32-C3"
  read -rp "Select [1-4]: " fw
  case "$fw" in
    1) url="https://github.com/alphafox02/T-Halow/raw/refs/heads/master/firmware/firmware_T-Halow_DragonOS_RID_Scanner_20241107.bin";;
    2) url="https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_s3dualcoreRIDfirmware.bin";;
    3) url="https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_s3_WiFi_RID_firmware.bin";;
    4) url="https://github.com/lukeswitz/T-Halow/raw/refs/heads/master/firmware/xiao_c3_WiFi_RID_firmware.bin";;
    *) echo "Invalid choice" >&2; exit 1;;
  esac

  binfile=$(basename "$url")
  echo "Downloading $binfile..."
  curl -sSL -o "$binfile" "$url"

  port=$(select_port)
  baud=115200

  read -rp "Proceed to flash $binfile on auto-chip @ $port @$baud? [y/N]: " yn
  case "$yn" in [Yy]*) ;; *) echo "Aborted."; exit 1;; esac

  esptool --chip auto --port "$port" --baud "$baud" write-flash \
    --flash-mode dio --flash-freq 80m --flash-size detect \
    0x10000 "$binfile"

  echo "✔ Flashed $binfile."
}

# --- MAIN ---

install_deps

clone_or_update "$DRONEID_REPO" "$DRONEID_DIR"
clone_or_update "$DRAGONSYNC_REPO" "$DRAGONSYNC_DIR"

flash_firmware

cat <<EOF

===================================================
Setup Complete.
Manual next steps:

1. Install Python requirements:
   pip3 install -r $DRONEID_DIR/requirements.txt
   pip3 install -r $DRAGONSYNC_DIR/requirements.txt

2. To run ZMQ decoder:
   python3 $DRONEID_DIR/zmq_decoder.py -z --uart <serial> --zmqsetting <bind> --zmqclients <clients>

3. To run monitor:
   python3 $DRAGONSYNC_DIR/wardragon_monitor.py --zmq_host <host> --zmq_port <port> --interval <seconds>

===================================================
EOF
