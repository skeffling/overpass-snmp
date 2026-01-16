# Overpass SNMP Monitor

Export Overpass API server statistics via SNMP.

## Overview

This tool provides SNMP monitoring for Overpass API servers with two methods:

**Method 1: SNMP Extend (Simple)**
- Uses NET-SNMP-EXTEND-MIB
- Values returned as strings
- Quick to set up

**Method 2: Custom MIB with pass_persist (Recommended)**
- Uses custom OVERPASS-MIB
- Proper typed values (Gauge32, STRING)
- Better integration with monitoring tools

**Files:**
- **`overpass-stats.sh`** - Cron script that fetches stats and caches them
- **`overpass-snmp.sh`** - SNMP extend script (Method 1)
- **`overpass-snmp-persist.sh`** - SNMP pass_persist script (Method 2)
- **`OVERPASS-MIB.txt`** - Custom MIB definition

## Available Statistics

### Numeric (for graphing in LibreNMS, etc.)

| Stat Name | Type | Description |
|-----------|------|-------------|
| `slots_available` | gauge | Available query slots |
| `slots_total` | gauge | Total query slots |
| `active` | gauge | Currently running queries |
| `latency` | gauge | Status fetch latency (ms) |
| `age` | gauge | Data age in minutes |

### Informational (string values)

| Stat Name | Type | Description |
|-----------|------|-------------|
| `version` | string | Overpass API version |
| `timestamp` | string | Data timestamp (ISO format) |
| `last_update` | string | When stats were last fetched |

## Requirements

- `curl`
- `jq`
- SNMP daemon with extend support (net-snmp)

## Installation

### 1. Install dependencies

```bash
sudo apt install curl jq
```

### 2. Download and install scripts

```bash
# Core scripts
sudo curl -o /usr/local/bin/overpass-stats.sh https://raw.githubusercontent.com/skeffling/overpass-snmp/main/overpass-stats.sh
sudo curl -o /usr/local/bin/overpass-snmp.sh https://raw.githubusercontent.com/skeffling/overpass-snmp/main/overpass-snmp.sh
sudo curl -o /usr/local/bin/overpass-snmp-persist.sh https://raw.githubusercontent.com/skeffling/overpass-snmp/main/overpass-snmp-persist.sh
sudo chmod +x /usr/local/bin/overpass-stats.sh
sudo chmod +x /usr/local/bin/overpass-snmp.sh
sudo chmod +x /usr/local/bin/overpass-snmp-persist.sh

# MIB file
sudo curl -o /usr/share/snmp/mibs/OVERPASS-MIB.txt https://raw.githubusercontent.com/skeffling/overpass-snmp/main/OVERPASS-MIB.txt
```

### 3. Create cache directory

```bash
sudo mkdir -p /var/cache/overpass-snmp
sudo chown $USER /var/cache/overpass-snmp
```

### 4. Configure the server URL

Edit `/usr/local/bin/overpass-stats.sh` and change the `OVERPASS_URL` variable:

```bash
OVERPASS_URL="${OVERPASS_URL:-http://localhost}"  # Change to your server
```

Or set it via environment variable in cron.

### 5. Add cron job

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

### 6. Configure SNMP

Choose one of the following methods:

#### Method 1: SNMP Extend (Simple)

Add to `/etc/snmp/snmpd.conf`:

```
extend overpass-slots-avail   /usr/local/bin/overpass-snmp.sh slots_available
extend overpass-slots-total   /usr/local/bin/overpass-snmp.sh slots_total
extend overpass-active        /usr/local/bin/overpass-snmp.sh active
extend overpass-latency       /usr/local/bin/overpass-snmp.sh latency
extend overpass-age           /usr/local/bin/overpass-snmp.sh age
extend overpass-version       /usr/local/bin/overpass-snmp.sh version
```

#### Method 2: Custom MIB with pass_persist (Recommended)

Add to `/etc/snmp/snmpd.conf`:

```
pass_persist .1.3.6.1.4.1.99999.1 /usr/local/bin/overpass-snmp-persist.sh
```

Then restart SNMP daemon:

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

**Method 1 (extend):**
```bash
snmpwalk -v2c -c public localhost NET-SNMP-EXTEND-MIB::nsExtendOutput1Line
snmpget -v2c -c public localhost 'NET-SNMP-EXTEND-MIB::nsExtendOutput1Line."overpass-slots-avail"'
```

**Method 2 (pass_persist with MIB):**
```bash
snmpwalk -v2c -c public localhost .1.3.6.1.4.1.99999.1
snmpget -v2c -c public localhost .1.3.6.1.4.1.99999.1.1
# Or with MIB names:
snmpwalk -v2c -c public localhost OVERPASS-MIB::overpassObjects
snmpget -v2c -c public localhost OVERPASS-MIB::overpassSlotsAvailable.0
```

## SNMP OIDs

### Method 2: Custom MIB OIDs (Recommended)

**Base OID:** `.1.3.6.1.4.1.99999.1` (overpassObjects)

| OID | Name | Type | Unit | Description |
|-----|------|------|------|-------------|
| `.1.3.6.1.4.1.99999.1.1` | overpassSlotsAvailable | Gauge32 | slots | Available query slots |
| `.1.3.6.1.4.1.99999.1.2` | overpassSlotsTotal | Gauge32 | slots | Total query slots |
| `.1.3.6.1.4.1.99999.1.3` | overpassActive | Gauge32 | queries | Running queries |
| `.1.3.6.1.4.1.99999.1.4` | overpassLatency | Gauge32 | ms | Status fetch latency |
| `.1.3.6.1.4.1.99999.1.5` | overpassAge | Gauge32 | minutes | Data age |
| `.1.3.6.1.4.1.99999.1.6` | overpassVersion | STRING | - | Version string |

### Method 1: Extend OIDs

**Base OID:** `.1.3.6.1.4.1.8072.1.3.2.3.1.1` (nsExtendOutput1Line)

| Extend Name | Type | Unit | Full OID |
|-------------|------|------|----------|
| overpass-slots-avail | GAUGE | slots | `.1.3.6.1.4.1.8072.1.3.2.3.1.1.20.111.118.101.114.112.97.115.115.45.115.108.111.116.115.45.97.118.97.105.108` |
| overpass-slots-total | GAUGE | slots | `.1.3.6.1.4.1.8072.1.3.2.3.1.1.20.111.118.101.114.112.97.115.115.45.115.108.111.116.115.45.116.111.116.97.108` |
| overpass-active | GAUGE | queries | `.1.3.6.1.4.1.8072.1.3.2.3.1.1.15.111.118.101.114.112.97.115.115.45.97.99.116.105.118.101` |
| overpass-latency | GAUGE | ms | `.1.3.6.1.4.1.8072.1.3.2.3.1.1.16.111.118.101.114.112.97.115.115.45.108.97.116.101.110.99.121` |
| overpass-age | GAUGE | minutes | `.1.3.6.1.4.1.8072.1.3.2.3.1.1.12.111.118.101.114.112.97.115.115.45.97.103.101` |
| overpass-version | STRING | - | `.1.3.6.1.4.1.8072.1.3.2.3.1.1.16.111.118.101.114.112.97.115.115.45.118.101.114.115.105.111.110` |

**Data Types:**
- **Gauge32/GAUGE** - Point-in-time value that can increase or decrease (use for graphing)
- **STRING** - Text value (informational only, not for graphing)

**How OIDs are constructed:**

The OID suffix is the extend name encoded as: `<length>.<ascii values of each character>`

For example, `overpass-age` (12 characters) becomes:
```
12.111.118.101.114.112.97.115.115.45.97.103.101
   o   v   e   r   p   a  s   s   -  a  g   e
```

**Discover OIDs dynamically:**

```bash
snmpwalk -v2c -c public localhost .1.3.6.1.4.1.8072.1.3.2.3.1.1
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

- Ensure jq is installed: `jq --version` (if not, run `sudo apt install jq`)
- Check if the cron job is running: `cat /var/cache/overpass-snmp/last_update`
- Check if curl can reach the server: `curl -s http://localhost/api/status`
- Check for errors: `cat /var/cache/overpass-snmp/error`

### Date parsing issues on macOS

The script attempts both GNU and BSD date formats. If age shows "U", check if the timestamp is being parsed correctly.

## License

MIT
