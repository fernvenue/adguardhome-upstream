#!/bin/bash
set -e
if [ "$(ps -o comm= $PPID)" == "systemd" ]; then
    SYSTEMD=1
fi
if [[ $SYSTEMD == 1 ]]; then
    echo "IPv4 connection testing..."
else
	DATE=`date --rfc-3339 sec`
    echo "$DATE: IPv4 connection testing..."
fi
if ping -c 3 "223.6.6.6" > /dev/null 2>&1; then
	IPv4="true"
fi
if [[ $SYSTEMD == 1 ]]; then
    echo "IPv6 connection testing..."
else
	DATE=`date --rfc-3339 sec`
    echo "$DATE: IPv6 connection testing..."
fi
if ping -c 3 "2400:3200:baba::1" > /dev/null 2>&1; then
	IPv6="true"
fi
if [[ $IPv4 == "true" ]]; then
	if [[ $IPv6 == "true" ]]; then
		if [[ $SYSTEMD == 1 ]]; then
			echo "IPv4 and IPv6 connections both available."
		else
			DATE=`date --rfc-3339 sec`
			echo "$DATE: IPv4 and IPv6 connections both available."
		fi
		curl -o "/var/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6.conf > /dev/null 2>&1
	else
		if [[ $SYSTEMD == 1 ]]; then
			echo "Only IPv4 connection available."
		else
			DATE=`date --rfc-3339 sec`
			echo "$DATE: Only IPv4 connection available."
		fi
		curl -o "/var/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v4.conf > /dev/null 2>&1
	fi
else
	if [[ $IPv6 == "true" ]]; then
		if [[ $SYSTEMD == 1 ]]; then
			echo "Only IPv6 connection available."
		else
			DATE=`date --rfc-3339 sec`
			echo "$DATE: Only IPv6 connection available."
		fi
		curl -o "/var/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6only.conf > /dev/null 2>&1
	else
		if [[ $SYSTEMD == 1 ]]; then
			echo "No available network connection was detected, please try again."
		else
			DATE=`date --rfc-3339 sec`
			echo "$DATE: No available network connection was detected, please try again."
		fi
		exit 1
	fi
fi
if [[ $SYSTEMD == 1 ]]; then
    echo "Getting data updates..."
else
	DATE=`date --rfc-3339 sec`
    echo "$DATE: Getting data updates..."
fi
curl -s https://gitlab.com/fernvenue/chn-domains-list/-/raw/master/CHN.ALL.agh | sed "/#/d" > "/var/tmp/chinalist.upstream"
if [[ $SYSTEMD == 1 ]]; then
    echo "Processing data format..."
else
	DATE=`date --rfc-3339 sec`
    echo "$DATE: Processing data format..."
fi
cat "/var/tmp/default.upstream" "/var/tmp/chinalist.upstream" > /usr/share/adguardhome.upstream
if [[ $IPv4 == "true" ]]; then
	sed -i "s|114.114.114.114|h3://223.5.5.5:443/dns-query h3://223.6.6.6:443/dns-query|g" /usr/share/adguardhome.upstream
else
	sed -i "s|114.114.114.114|2400:3200::1 2400:3200:baba::1|g" /usr/share/adguardhome.upstream
fi
if [[ $SYSTEMD == 1 ]]; then
    echo "Cleaning..."
else
	DATE=`date --rfc-3339 sec`
    echo "$DATE: Cleaning..."
fi
rm /var/tmp/*.upstream
if [[ $SYSTEMD == 1 ]]; then
    echo "Restarting AdGuardHome service..."
else
	DATE=`date --rfc-3339 sec`
    echo "$DATE: Restarting AdGuardHome service..."
fi
systemctl restart AdGuardHome
if [[ $SYSTEMD == 1 ]]; then
    echo "All finished!"
else
	DATE=`date --rfc-3339 sec`
    echo "$DATE: All finished!"
fi
