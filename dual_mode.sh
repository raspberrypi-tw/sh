#!/bin/bash
#+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#|R|a|s|p|b|e|r|r|y|P|i|.|c|o|m|.|t|w|
#+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
# Copyright (c) 2016, raspberrypi.com.tw
# All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# dual_mode.sh
# Make Pi 3 to be in both Access Point mode and client mode simultaneously.
#
# Author : sosorry
# Date   : 10/23/2016

CPUINFO=`cat /proc/cpuinfo | grep -i hardware | awk '{print $3}'`
if [ "$CPUINFO" != "BCM2709" ]
then
    echo "Dual mode support only Raspberry Pi 3. Online shopping: https://www.raspberrypi.com.tw/10684/55/ "
    exit 0
fi


if [ $# -eq 1 ] 
then

    #
    # dual mode on
    # 
    if [ "$1" == "on" ]
    then

        #
        # backup setting files
        # 
        sudo -u pi mkdir /home/pi/bak 2>/dev/null
        has_hostapd=`dpkg -l | grep hostapd | wc | awk '{print $1}'`
        if [ $has_hostapd -lt 1 ]; then
            sudo apt-get update
            sudo apt-get install -y hostapd
        fi
        has_dnsmasq=`dpkg -l | grep dnsmasq | wc | awk '{print $1}'`
        if [ $has_dnsmasq -lt 1 ]; then
            sudo apt-get install -y dnsmasq
        fi

        if [ ! -f /home/pi/bak/dnsmasq.conf ]; then
            mv /etc/dnsmasq.conf /home/pi/bak 2>/dev/null
            echo "mv /etc/dnsmasq.conf /home/pi/bak"
        fi

        if [ ! -f /home/pi/bak/hostapd.conf ]; then
            mv /etc/hostapd/hostapd.conf /home/pi/bak 2>/dev/null
            echo "mv /etc/hostapd/hostapd.conf /home/pi/bak"
        fi

        if [ ! -f /home/pi/bak/interfaces ]; then
            mv /etc/network/interfaces /home/pi/bak 2>/dev/null
            echo "mv /etc/network/interfaces /home/pi/bak"
        fi

        echo -n "Create subnet IP? [2-253] "
        read SUBNET_IP
        sudo bash -c 'cat > /etc/dnsmasq.conf << EOF
interface=lo,uap0
no-dhcp-interface=lo,wlan0
dhcp-range=192.168.'$SUBNET_IP'.100,192.168.'$SUBNET_IP'.200,12h
EOF'

        CHANNEL=`iwlist wlan0 channel | grep -i current | awk '{print $5}' | rev | cut -c 2- | rev`
        echo -n "Pi-AP's name? "
        read PI_AP
        echo -n "Pi-AP's psk? "
        read PI_PSK
        sudo bash -c 'cat > /etc/hostapd/hostapd.conf << EOF
interface=uap0
ssid='$PI_AP'
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
EOF'

        echo -n "Current AP's name? "
        read CURRENT_AP
        echo -n "Current AP's psk? "
        read CURRENT_PSK
        sudo bash -c 'cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback
iface eth0 inet manual

auto wlan0
iface wlan0 inet dhcp
wpa-ssid '$CURRENT_AP'
wpa-psk '$CURRENT_PSK'

auto uap0
iface uap0 inet static
address 192.168.'$SUBNET_IP'.1
netmask 255.255.255.0
EOF'

        sudo bash -c 'cat > /usr/local/bin/dual_mode << EOF
#!/bin/bash

iw dev wlan0 interface add uap0 type __ap
service dnsmasq restart
sysctl net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 192.168.'$SUBNET_IP'.0/24 ! -d 192.168.'$SUBNET_IP'.0/24 -j MASQUERADE
ifup uap0
hostapd /etc/hostapd/hostapd.conf
EOF'

        sudo chmod 755 /usr/local/bin/dual_mode

        sudo bash -c 'cat > /lib/systemd/system/dual_mode.service << EOF
[Unit]
Description=Both Access Point mode and client mode simultaneously
     
[Service]
ExecStart=/usr/local/bin/dual_mode
     
[Install]
WantedBy=multi-user.target
EOF'

        systemctl start dual_mode.service
        systemctl enable dual_mode.service

        echo "Ready to reboot... "
        sleep 3
        sudo sync; sudo init 6

    #
    # dual mode off
    # 
    elif [ "$1" == "off" ]
    then
        echo "Dual mode off..."

        if [ -f /home/pi/bak/dnsmasq.conf ]; then
            mv /home/pi/bak/dnsmasq.conf /etc/dnsmasq.conf 2>/dev/null
            echo "mv /home/pi/bak/dnsmasq.conf /etc/dnsmasq.conf"
        fi

        if [ -f /home/pi/bak/hostapd.conf ]; then
            mv /home/pi/bak/hostapd.conf /etc/hostapd/hostapd.conf 2>/dev/null
            echo "mv /home/pi/bak/hostapd.conf /etc/hostapd/hostapd.conf"
        fi

        if [ -f /home/pi/bak/interfaces ]; then
            mv /home/pi/bak/interfaces /etc/network/interfaces 2>/dev/null
            echo "mv /home/pi/bak/interfaces /etc/network/interfaces"
        fi

        systemctl stop dual_mode.service
        systemctl disable dual_mode.service

        echo "Ready to reboot... "
        sleep 3
        sudo sync; sudo init 6
    else
        echo "Usage: sudo ./dual_mode.sh [on|off]"
    fi
else
    echo "Invalid argument please pass only one argument "
fi

