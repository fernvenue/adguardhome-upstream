#!/bin/bash
set -e
DATE=$(date -Iseconds)
echo "$DATE: IPv4 connection testing..."
DATE=$(date -Iseconds)
echo "$DATE: IPv4 connection testing..."
if ping -c 3 "223.6.6.6" > /dev/null 2>&1; then
        IPv4="true"
fi
echo "$DATE: IPv6 connection testing..."
if ping -c 3 "2400:3200:baba::1" > /dev/null 2>&1; then
        IPv6="true"
fi
if [[ $IPv4 == "true" ]]; then
        if [[ $IPv6 == "true" ]]; then
                echo "$DATE: IPv4 and IPv6 connections both available."
                curl -o "/var/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6.conf > /dev/null 2>&1
        else
                echo "$DATE: IPv4 connection available."
                curl -o "/var/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v4.conf > /dev/null 2>&1
        fi
else
        if [[ $IPv6 == "true" ]]; then
                echo "$DATE: IPv6 connection available."
                curl -o "/var/tmp/default.upstream" https://gitlab.com/fernvenue/adguardhome-upstream/-/raw/master/v6only.conf > /dev/null 2>&1
        else
                echo "ERROR: No available network connection was detected, please try again."
                exit 1
        fi
fi
echo "$DATE: Getting data updates..."
curl -s https://gitlab.com/fernvenue/chn-domains-list/-/raw/master/CHN.ALL.agh | sed "/#/d" > "/var/tmp/chinalist.upstream"
echo "$DATE: Processing data format..."
cat "/var/tmp/default.upstream" "/var/tmp/chinalist.upstream" > /usr/share/adguardhome.upstream
if [[ $IPv4 == "true" ]]; then
        sed -i "s|114.114.114.114|h3://223.5.5.5:443/dns-query h3://223.6.6.6:443/dns-query|g" /usr/share/adguardhome.upstream
else
        sed -i "s|114.114.114.114|2400:3200::1 2400:3200:baba::1|g" /usr/share/adguardhome.upstream
fi
echo "$DATE: Cleaning..."
rm /var/tmp/*.upstream
/etc/init.d/AdGuardHome restart
echo "$DATE: All finished!"
if crontab -l | grep -q '/usr/local/bin/upstream.sh'; then
    echo "$DATE: 定时任务已存在。"
else
    echo "$DATE: 开始添加到crontab"
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/upstream.sh") | crontab -
    echo "$DATE: 已将 /usr/local/bin/upstream.sh 添加到crontab中"
fi