#!/bin/bash
#
# overpass-snmp.sh - SNMP extend script for Overpass API stats
#
# Usage: overpass-snmp.sh <stat_name>
#
# Available stats (numeric - for graphing):
#   slots_available - Available slots (integer)
#   slots_total     - Total slots (integer)
#   active          - Running query count (integer)
#   latency         - Last fetch latency in ms (integer)
#   age             - Data age in minutes (integer)
#
# Informational (string):
#   version         - Overpass API version string
#   timestamp       - Data timestamp (ISO format)
#   last_update     - When stats were last fetched
#
# Returns "U" (unknown) if the stat is not available.

CACHE_DIR="${CACHE_DIR:-/var/cache/overpass-snmp}"

if [[ -z "$1" ]]; then
    echo "Usage: $0 <stat_name>"
    exit 1
fi

cat "$CACHE_DIR/$1" 2>/dev/null || echo "U"
