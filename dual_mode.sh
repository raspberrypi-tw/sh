#!/bin/bash
#+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#|R|a|s|p|b|e|r|r|y|P|i|.|c|o|m|.|t|w|
#+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
# Copyright (c) 2018, raspberrypi.com.tw
# All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# dual_mode.sh
# Make Pi 3 to operate in both Access Point mode and client mode simultaneously.
#
# Author : sosorry
# Date   : 10/23/2016
#
# Usage  : $ sudo ./dual_mode.sh [on|off|status]
# dual mode on means Raspberry Pi being Access Point and WiFi client simultaneously
# dual mode off means being WiFi client only
# dual mode status means to check if dual mode is on or off
#


#
# GLOBAL VARIABLES
#
CPUINFO=`cat /proc/cpuinfo | grep Revision | awk '{print $3}'`
WPA_FILE="/etc/wpa_supplicant/wpa_supplicant.conf"
BACKUP_DIR=/home/pi/.bak
PI_PSK="1234567890"


#
# Check if the hardware is Pi 3
#
check_version() {
  if  echo "$CPUINFO" | grep -xq ".*82\|.*83$"$; then
    echo "Check Pi 3 OK"
  else
    echo "Dual mode support only Raspberry Pi 3. Online shopping: https://www.raspberrypi.com.tw/10684/55/ "
    exit 0
  fi
}


#
# Find the current PSK by SSID
#
find_psk() {
  IN=`iwconfig wlan0 | grep wlan0 | awk '{print $4}'`

  if [[ $IN == "ESSID:off/any" ]]; then
      echo $'\nPlease connect to a WiFi first! \n'
      exit 0
  fi

  if [[ $IN == *":"* ]]; then
    SSID=$(echo $IN | tr ":" "\n")
    SSID=$(echo $SSID | awk '{print $2}' | tr -d '"')
  fi

  i=0
  while true
  do
    if grep -A"$i" "$SSID" "$WPA_FILE" | grep -Fxq "}"; then
      break
    else
      IN=`grep -A"$i" "$SSID" "$WPA_FILE" | grep "psk"`

      if [[ $IN == *"="* ]]; then
        PSK=$(echo $IN | tr "=" "\n")
        PSK=$(echo $PSK | awk '{print $2}' | tr -d '"')
        break
      fi
    fi
    i=$(($i+1))
  done

  if [ -z "$PSK" ]; then
    i=0
    while true
    do
      if grep -B"$i" "$SSID" "$WPA_FILE" | grep -Fxq "{"; then
        break
 6     else
        IN=`grep -B"$i" "$SSID" "$WPA_FILE" | grep "psk"`

        if [[ $IN == *"="* ]]; then
          PSK=$(echo $IN | tr "=" "\n")
          PSK=$(echo $PSK | awk '{print $2}' | tr -d '"')
          break
        fi
      fi
      i=$(($i+1))
    done
  fi
}


#
# Create SSID from input
#
ask_subnet() {
  echo -n "Input a number from [3] to [252]...> "
  read SUBNET_IP
  if [ $SUBNET_IP -eq $SUBNET_IP 2>/dev/null ] && [ $SUBNET_IP -lt 253 ] && [ $SUBNET_IP -gt 2 ]; then
    PI_SSID="RPi-$SUBNET_IP"
  else
    echo "Please try again..."
    exit 0
  fi
}


#
# Confirm SSID and PSK
#
confirm_setting() {
  echo $'\n'
  echo "====================================="
  echo "SSID: [$PI_SSID]"
  echo "PSK:  [$PI_PSK]"
  echo "====================================="
  echo "After connect to [$PI_SSID], you can SSH 'pi@192.168.[$SUBNET_IP].1' to your Pi"
  echo $'\n'
  echo -n "Confirm the setting? [yes/no] > "
  read CONFIRM
}


#
# Backup /etc/hostapd/hostapd & /etc/dnsmasq.conf & /etc/network/interface
#
backup_setting() {
  sleep 1
  echo $'\nBackup hostapd/dnsmasq/interface settings... '
  echo "====================================="
  sudo -u pi mkdir "$BACKUP_DIR" 2>/dev/null
  has_hostapd=`dpkg -l | grep hostapd | wc | awk '{print $1}'`
  if [ $has_hostapd -lt 1 ]; then
    sudo apt-get update
    sudo apt-get install -y hostapd
  fi
  has_dnsmasq=`dpkg -l | grep dnsmasq | wc | awk '{print $1}'`
  if [ $has_dnsmasq -lt 1 ]; then
    sudo apt-get install -y dnsmasq
  fi
  if [ ! -f "$BACKUP_DIR"/dnsmasq.conf ]; then
    sudo mv /etc/dnsmasq.conf "$BACKUP_DIR" 2>/dev/null
    echo "mv /etc/dnsmasq.conf $BACKUP_DIR"
  fi
  if [ ! -f "$BACKUP_DIR"/hostapd.conf ]; then
    sudo mv /etc/hostapd/hostapd.conf "$BACKUP_DIR" 2>/dev/null
    echo "mv /etc/hostapd/hostapd.conf $BACKUP_DIR"
  fi
  if [ ! -f "$BACKUP_DIR"/interfaces ]; then
    sudo mv /etc/network/interfaces "$BACKUP_DIR" 2>/dev/null
    echo "mv /etc/network/interfaces $BACKUP_DIR"
  fi
  if [ ! -f "$BACKUP_DIR"/functions.sh ]; then
    sudo cp /etc/wpa_supplicant/functions.sh "$BACKUP_DIR" 2>/dev/null
    echo "cp /etc/wpa_supplicant/functions.sh $BACKUP_DIR"
  fi
  echo "====================================="
}


#
# Create /etc/dnsmasq.conf 
#
create_dnsmasq() {
  sudo bash -c 'cat > /etc/dnsmasq.conf << EOF
interface=lo,uap0
no-dhcp-interface=lo,wlan0
dhcp-range=192.168.'$SUBNET_IP'.100,192.168.'$SUBNET_IP'.200,12h
EOF'
}


#
# Create /etc/hostapd/hostapd.conf
#
create_hostpad() {
  CHANNEL=`iwlist wlan0 channel | grep -i current | awk '{print $5}' | rev | cut -c 2- | rev`

  sudo bash -c 'cat > /etc/hostapd/hostapd.conf << EOF
country_code=TW
interface=uap0
ssid='$PI_SSID'
hw_mode=g
channel='$CHANNEL'
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase='$PI_PSK'
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
#wmm_enabled=1 
EOF'
}


#
# Change default wpa_supplicant daemon setting
#
change_wpa_supplicant() {
  if [ -f /etc/wpa_supplicant/functions.sh ]; then
    sed -i 's/-D nl80211,wext/-Dwext/g' /etc/wpa_supplicant/functions.sh
  fi
}


#
# Create /etc/network/interface
#
create_interface() {
  sudo bash -c 'cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback
iface eth0 inet manual

auto wlan0
iface wlan0 inet dhcp
wpa-ssid '$SSID'
wpa-psk '$PSK'

auto uap0
iface uap0 inet static
address 192.168.'$SUBNET_IP'.1
netmask 255.255.255.0
EOF'
}


#
# Create dual_mode script 
#
create_dual() {
  sudo bash -c 'cat > /usr/local/bin/dual_mode << EOF
#!/bin/bash

iw dev wlan0 interface add uap0 type __ap
service dnsmasq start
sysctl net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 192.168.'$SUBNET_IP'.0/24 ! -d 192.168.'$SUBNET_IP'.0/24 -j MASQUERADE
ifconfig uap0 up
dhclient eth0
hostapd /etc/hostapd/hostapd.conf
EOF'
  sudo chmod 755 /usr/local/bin/dual_mode
}


#
# Create a systemd script
#
create_service() {
  sudo bash -c 'cat > /lib/systemd/system/dual_mode.service << EOF
[Unit]
Description=Both Access Point mode and client mode simultaneously

[Service]
ExecStart=/usr/local/bin/dual_mode

[Install]
WantedBy=multi-user.target
EOF'
  sudo systemctl start dual_mode.service
  sudo systemctl enable dual_mode.service
}


#
# Restore settings from $BACKUP_DIR
#
restore_setting() {
  sleep 2
  echo $'\nRestore hostapd/dnsmasq/interface settings... '
  echo "====================================="
  if [ -f "$BACKUP_DIR"/dnsmasq.conf ]; then
    sudo mv "$BACKUP_DIR"/dnsmasq.conf /etc/dnsmasq.conf 2>/dev/null
    echo "mv $BACKUP_DIR/dnsmasq.conf /etc/dnsmasq.conf"
  fi
  if [ -f "$BACKUP_DIR"/hostapd.conf ]; then
    sudo mv "$BACKUP_DIR"/hostapd.conf /etc/hostapd/hostapd.conf 2>/dev/null
    echo "mv $BACKUP_DIR/hostapd.conf /etc/hostapd/hostapd.conf"
  fi
  if [ -f "$BACKUP_DIR"/interfaces ]; then
    sudo mv "$BACKUP_DIR"/interfaces /etc/network/interfaces 2>/dev/null
    echo "mv $BACKUP_DIR/interfaces /etc/network/interfaces"
  fi
  if [ -f "$BACKUP_DIR"/functions.sh ]; then
    sudo mv "$BACKUP_DIR"/functions.sh /etc/wpa_supplicant/functions.sh 2>/dev/null
    echo "mv $BACKUP_DIR/functions.sh /etc/wpa_supplicant/functions.sh"
  fi
  sudo systemctl stop dual_mode.service
  sudo systemctl disable dual_mode.service
  echo "====================================="
  echo $'\n'
}


#
# Notify to reboot
#
ready_reboot() {
  echo $'\n'
  echo "Ready to reboot after [6] seconds... "
  echo $'\n'

  secs=6
  while [ $secs -gt -1 ]; do
    echo -ne "$secs\033[0K\r"
    sleep 1
    : $((secs--))
  done
  echo $'Lost connection... \n'
  echo $'\n'

  sudo sync; sudo init 6
}


#
# Get SSID from hostapd.conf
#
find_pi_ssid() {
  IN=`cat /etc/hostapd/hostapd.conf | grep -i ^ssid`

  if [[ $IN == "ssid="* ]]; then
    PI_SSID=$(echo $IN | tr "=" "\n")
    PI_SSID=$(echo $PI_SSID | awk '{print $2}' | tr -d '"')
  fi
}


#
# main function
#
main() {
  if [ "$1" == "on" ]; then
    check_version
    find_psk
    echo $'Dual mode on... \n'
    ask_subnet
    confirm_setting
    if [ "$CONFIRM" == "yes" ]; then
      backup_setting
      create_dnsmasq
      create_hostpad
      change_wpa_supplicant
      create_interface
      create_dual
      create_service
      ready_reboot
    else
      echo "Please try again..."
      exit 0
    fi
  elif [ "$1" == "off" ]; then
    echo $'Dual mode off... \n'
    restore_setting
    ready_reboot
  elif [ "$1" == "status" ]; then
    if [ "$(ls -A $BACKUP_DIR)" ]; then
      echo $'\n'
      find_pi_ssid
      echo "Dual mode is on... "
      echo "====================================="
      echo "SSID: [$PI_SSID]"
      echo "PSK:  [$PI_PSK]"
      echo "====================================="
      echo $'\n'
    else
      echo $'\n'
      echo "Dual mode is off... "
      echo $'\n'
    fi
  else
    echo $'Usage: sudo ./dual_mode.sh [on|off|status] \n'
  fi
}


#
# bootstrap
#
main $1
