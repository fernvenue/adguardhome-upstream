#!/bin/bash
if [ "$(ps -o comm= $PPID 2>/dev/null)" == "systemd" ]; then
    IS_SYSTEMD=1
else
    IS_SYSTEMD=0
fi

if [ -n /etc/os-release ] && [ -n "$(grep OpenWrt /etc/os-release)" ]; then
	OPENWRT=1
else
	OPENWRT=0
fi

if [[ $IS_SYSTEMD == 1 ]]; then
	log() { echo $1; }
elif [[ $OPENWRT == 1 ]]; then
	log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)]: $1"; }
else
	log() { echo "$(date --rfc-3339 sec): $1"; }
fi

if command -v wget >/dev/null 2>&1; then
	download() { wget -qO "$1" "$2" ; }
	download_stdout() { wget -qO- "$@" ; }
elif command -v curl >/dev/null 2>&1; then
	download() { curl -fsLo "$1" "$2" ; }
	download_stdout() { curl -fsLo - "$@" ; }
else
	echo "This script needs curl or wget" >&2
	exit 2
fi

if [ -n "$1" ]; then
	log "Output destination set to: $1"
	OUT_DEST="$1"
else
	OUT_DEST=/usr/share/adguardhome.upstream
fi

if [ -n "$2" ]; then
	log "Default upstream file set to $2"
	UPSTREAM_FILE="$2"
else
	UPSTREAM_FILE=/tmp/default.upstream
fi


set -e

download_upstream() {
	if [[ $IPv4 == "true" ]]; then
		if [[ $IPv6 == "true" ]]; then
			log "IPv4 and IPv6 connections both available."
			download "$UPSTREAM_FILE" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6.conf
		else
			log "Only IPv4 connection available."
			download "$UPSTREAM_FILE" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v4.conf
		fi
	else
		if [[ $IPv6 == "true" ]]; then
			log "Only IPv6 connection available."
			download "$UPSTREAM_FILE" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6only.conf
		else
			log "No available network connection was detected, please try again."
			exit 1
		fi
	fi
}


log "IPv4 connection testing..."

if ping -c 3 "223.6.6.6" > /dev/null 2>&1; then
	IPv4="true"
fi

log "IPv6 connection testing..."
if ping -c 3 "2400:3200:baba::1" > /dev/null 2>&1; then
	IPv6="true"
fi


log "Getting data updates..."
download_stdout https://gitlab.com/fernvenue/chn-domains-list/-/raw/master/CHN.ALL.agh | sed "/#/d" > "/tmp/chinalist.upstream"

log "Processing data format..."
cat "$UPSTREAM_FILE" "/tmp/chinalist.upstream" > $OUT_DEST

if [[ $IPv4 == "true" ]]; then
	sed -i "s|114.114.114.114|h3://223.5.5.5:443/dns-query h3://223.6.6.6:443/dns-query|g" $OUT_DEST
else
	sed -i "s|114.114.114.114|2400:3200::1 2400:3200:baba::1|g" $OUT_DEST
fi

if [ -f "$UPSTREAM_FILE" ]; then
	cp "$UPSTREAM_FILE" /tmp/default.upstream
else
	download_upstream
fi

log "Cleaning..."
rm /tmp/*.upstream

if [[ $OPENWRT != 1 ]]; then
	log "Restarting AdGuardHome service..."
	systemctl restart AdGuardHome
fi

log "All finished!"

unset IS_SYSTEMD
unset IPv4
unset IPv6
unset OUT_DEST
unset OPENWRT
unset UPSTREAM_FILE