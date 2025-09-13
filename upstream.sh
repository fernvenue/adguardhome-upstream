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

log "Downloading upstream configuration..."
curl -o "/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6.conf > /dev/null 2>&1

log "Getting data updates..."
curl -s https://gitlab.com/fernvenue/chn-domains-list/-/raw/master/CHN.ALL.agh | sed "/#/d" > "/tmp/chinalist.upstream"

log "Processing data format..."
cat "/tmp/default.upstream" "/tmp/chinalist.upstream" > /usr/share/adguardhome.upstream

sed -i "s|114.114.114.114|h3://223.5.5.5:443/dns-query h3://223.6.6.6:443/dns-query|g" /usr/share/adguardhome.upstream

log "Cleaning..."
rm /tmp/*.upstream

log "Restarting AdGuardHome service..."
systemctl restart AdGuardHome

log "All finished!"

unset IS_SYSTEMD