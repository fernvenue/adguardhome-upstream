#!/bin/bash
if [ "$(ps -o comm= $PPID)" == "systemd" ]; then
    IS_SYSTEMD=1
else
    IS_SYSTEMD=0
fi
log() {
	if [[ $IS_SYSTEMD == 1 ]]; then
		echo $1
	else
		echo "$(date --rfc-3339 sec): $1"
	fi
}
set -e

log "IPv4 connection testing..."

if ping -c 3 "223.6.6.6" > /dev/null 2>&1; then
	IPv4="true"
fi

log "IPv6 connection testing..."
if ping -c 3 "2400:3200:baba::1" > /dev/null 2>&1; then
	IPv6="true"
fi

if [[ $IPv4 == "true" ]]; then
	if [[ $IPv6 == "true" ]]; then
		log "IPv4 and IPv6 connections both available."
		curl -o "/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6.conf > /dev/null 2>&1
	else
		log "Only IPv4 connection available."
		curl -o "/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v4.conf > /dev/null 2>&1
	fi
else
	if [[ $IPv6 == "true" ]]; then
		log "Only IPv6 connection available."
		curl -o "/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6only.conf > /dev/null 2>&1
	else
		log "No available network connection was detected, please try again."
		exit 1
	fi
fi

log "Getting data updates..."
curl -s https://gitlab.com/fernvenue/chn-domains-list/-/raw/master/CHN.ALL.agh | sed "/#/d" > "/tmp/chinalist.upstream"

log "Processing data format..."
cat "/tmp/default.upstream" "/tmp/chinalist.upstream" > /usr/share/adguardhome.upstream

if [[ $IPv4 == "true" ]]; then
	sed -i "s|114.114.114.114|h3://223.5.5.5:443/dns-query h3://223.6.6.6:443/dns-query|g" /usr/share/adguardhome.upstream
else
	sed -i "s|114.114.114.114|2400:3200::1 2400:3200:baba::1|g" /usr/share/adguardhome.upstream
fi

log "Cleaning..."
rm /tmp/*.upstream

log "Restarting AdGuardHome service..."
systemctl restart AdGuardHome

log "All finished!"

unset IS_SYSTEMD
unset IPv4
unset IPv6