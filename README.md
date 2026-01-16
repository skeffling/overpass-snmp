# Overpass SNMP Monitor

Export Overpass API server statistics via SNMP extend.

## Overview

This tool consists of two bash scripts:

1. **`overpass-stats.sh`** - Cron script that fetches stats from your Overpass API server and caches them
2. **`overpass-snmp.sh`** - SNMP extend script that reads and returns cached stats

## Available Statistics

| Stat Name | Type | Description |
|-----------|------|-------------|
| `slots` | string | Slots available (e.g., "2/4") |
| `slots_available` | integer | Available query slots |
| `slots_total` | integer | Total query slots |
| `active` | integer | Currently running queries |
| `latency` | integer | Status fetch latency (ms) |
| `age` | integer | Data age in minutes |
| `version` | string | Overpass API version |
| `timestamp` | string | Data timestamp (ISO format) |
| `last_update` | string | When stats were last fetched |

## Requirements

- `curl`
- `jq`
- SNMP daemon with extend support (net-snmp)

## Installation

### 1. Install scripts

```bash
sudo cp overpass-stats.sh /usr/local/bin/
sudo cp overpass-snmp.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/overpass-stats.sh
sudo chmod +x /usr/local/bin/overpass-snmp.sh
```

### 2. Create cache directory

```bash
sudo mkdir -p /var/cache/overpass-snmp
sudo chown $USER /var/cache/overpass-snmp
```

### 3. Configure the server URL

Edit `/usr/local/bin/overpass-stats.sh` and change the `OVERPASS_URL` variable:

```bash
OVERPASS_URL="${OVERPASS_URL:-http://localhost}"  # Change to your server
```

Or set it via environment variable in cron.

### 4. Add cron job

```bash
crontab -e
```

Add:

```
* * * * * /usr/local/bin/overpass-stats.sh
```

Or with a custom URL:

```
* * * * * OVERPASS_URL=http://your-server /usr/local/bin/overpass-stats.sh
```

### 5. Configure SNMP

Add to `/etc/snmp/snmpd.conf`:

```
extend overpass-slots         /usr/local/bin/overpass-snmp.sh slots
extend overpass-slots-avail   /usr/local/bin/overpass-snmp.sh slots_available
extend overpass-slots-total   /usr/local/bin/overpass-snmp.sh slots_total
extend overpass-active        /usr/local/bin/overpass-snmp.sh active
extend overpass-latency       /usr/local/bin/overpass-snmp.sh latency
extend overpass-age           /usr/local/bin/overpass-snmp.sh age
extend overpass-version       /usr/local/bin/overpass-snmp.sh version
```

Restart SNMP daemon:

```bash
sudo systemctl restart snmpd
```

## Testing

### Test the cron script manually

```bash
/usr/local/bin/overpass-stats.sh
ls -la /var/cache/overpass-snmp/
cat /var/cache/overpass-snmp/slots
```

### Test the SNMP extend script

```bash
/usr/local/bin/overpass-snmp.sh slots
/usr/local/bin/overpass-snmp.sh version
/usr/local/bin/overpass-snmp.sh age
```

### Test via SNMP

```bash
# List all extended stats
snmpwalk -v2c -c public localhost NET-SNMP-EXTEND-MIB::nsExtendOutput1Line

# Get a specific stat
snmpget -v2c -c public localhost 'NET-SNMP-EXTEND-MIB::nsExtendOutput1Line."overpass-slots"'
```

## Configuration Options

Environment variables for `overpass-stats.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `OVERPASS_URL` | `http://localhost` | Overpass API server URL |
| `CACHE_DIR` | `/var/cache/overpass-snmp` | Cache directory |
| `TIMEOUT` | `10` | Request timeout in seconds |

## Troubleshooting

### Stats show "U" (unknown)

- Check if the cron job is running: `cat /var/cache/overpass-snmp/last_update`
- Check if curl can reach the server: `curl -s http://localhost/api/status`
- Check for errors: `cat /var/cache/overpass-snmp/error`

### Date parsing issues on macOS

The script attempts both GNU and BSD date formats. If age shows "U", check if the timestamp is being parsed correctly.

## License

MIT
