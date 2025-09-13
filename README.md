# DNS Upstream

[![dns-upstream](https://img.shields.io/badge/LICENSE-GPLv3%20Liscense-blue?style=flat-square)](./LICENSE)
[![dns-upstream](https://img.shields.io/badge/GitHub-DNS%20Upstream-blueviolet?style=flat-square&logo=github)](https://github.com/fernvenue/dns-upstream)

A pure shell to download, validate, and configure upstream DNS servers for [dnsproxy](https://github.com/AdguardTeam/dnsproxy), [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome).

## Features

- [x] Download and validate upstream DNS configuration files;
- [x] Support multiple DNS server formats (IPv4, IPv6, UDP, TCP, TLS, HTTPS, HTTP/3, QUIC, SDNS);
- [x] Domain-specific DNS server configuration with [/domain/]dns syntax;
- [x] Custom DNS server replacement for domain-specific entries;
- [x] Multiple upstream source support (command line, environment variables, local files);
- [x] Configurable logging levels (debug, info, warn, error);
- [x] Systemd service integration with automatic restart capability;
- [x] Built-in validation for all DNS server configurations;
- [x] Flexible output file configuration for AdGuardHome integration.
- [ ] Telegram notification support (planned).

## Usage

Download script:

```bash
curl -o /usr/local/bin/dns-upstream.sh https://raw.githubusercontent.com/fernvenue/dns-upstream/master/dns-upstream.sh
```

Give execute permissions:

```bash
chmod +x /usr/local/bin/dns-upstream.sh
```

Download systemd service and timer templates:

```bash
curl -o /etc/systemd/system/dns-upstream.service https://raw.githubusercontent.com/fernvenue/dns-upstream/master/dns-upstream.service
curl -o /etc/systemd/system/dns-upstream.timer https://raw.githubusercontent.com/fernvenue/dns-upstream/master/dns-upstream.timer
```

Customize the service and timer files if needed, then enable and start the timer:

```bash
systemctl enable dns-upstream.timer --now
systemctl status dns-upstream.timer
```

## Links

- [AdguardTeam/dnsproxy](https://github.com/AdguardTeam/dnsproxy)
- [AdguardTeam/AdGuardHome](https://github.com/AdguardTeam/AdGuardHome)
