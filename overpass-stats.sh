#!/bin/bash
#
# overpass-stats.sh - Fetch Overpass API stats and cache for SNMP
#
# This script fetches statistics from an Overpass API server and writes
# them to cache files for use by SNMP extend scripts.
#
# Usage: Run via cron every minute:
#   * * * * * /usr/local/bin/overpass-stats.sh
#
# Configuration via environment variables or edit defaults below:
#   OVERPASS_URL  - Server URL (default: http://localhost)
#   CACHE_DIR     - Cache directory (default: /var/cache/overpass-snmp)
#   TIMEOUT       - Request timeout in seconds (default: 10)

set -e

# Configuration
OVERPASS_URL="${OVERPASS_URL:-http://localhost}"
CACHE_DIR="${CACHE_DIR:-/var/cache/overpass-snmp}"
TIMEOUT="${TIMEOUT:-10}"

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Helper function to write a stat to cache
write_stat() {
    local name="$1"
    local value="$2"
    echo "$value" > "$CACHE_DIR/$name"
}

# Fetch /api/status and measure latency
fetch_status() {
    local start_time end_time latency
    start_time=$(date +%s%3N)

    local status_response
    if ! status_response=$(curl -s --max-time "$TIMEOUT" "$OVERPASS_URL/api/status" 2>/dev/null); then
        write_stat "error" "Failed to fetch status"
        return 1
    fi

    end_time=$(date +%s%3N)
    latency=$((end_time - start_time))

    # Parse slots available (e.g., "2 slots available now.")
    local slots_available
    slots_available=$(echo "$status_response" | grep -o '[0-9]* slots available' | grep -o '[0-9]*' || echo "U")

    # Parse rate limit / total slots (e.g., "Rate limit: 4")
    local slots_total
    slots_total=$(echo "$status_response" | grep -o 'Rate limit: [0-9]*' | grep -o '[0-9]*' || echo "U")

    # Count running queries (lines after "Currently running queries:" that have content)
    local active_queries=0
    local in_queries=false
    while IFS= read -r line; do
        if [[ "$line" == "Currently running queries"* ]]; then
            in_queries=true
        elif $in_queries && [[ -n "$line" && "$line" =~ ^[0-9] ]]; then
            ((active_queries++))
        fi
    done <<< "$status_response"

    # Write stats
    write_stat "slots_available" "$slots_available"
    write_stat "slots_total" "$slots_total"
    write_stat "slots" "${slots_available}/${slots_total}"
    write_stat "active" "$active_queries"
    write_stat "latency" "$latency"

    return 0
}

# Fetch metadata (version and data age) via /api/interpreter
fetch_metadata() {
    local query='[out:json][timeout:5];node(1);out meta;'

    local meta_response
    if ! meta_response=$(curl -s --max-time "$TIMEOUT" -X POST "$OVERPASS_URL/api/interpreter" \
        -d "data=$query" 2>/dev/null); then
        write_stat "version" "U"
        write_stat "age" "U"
        return 1
    fi

    # Parse version from generator field using jq
    local version
    version=$(echo "$meta_response" | jq -r '.generator // "U"' 2>/dev/null || echo "U")

    # Parse data age from osm3s.timestamp_osm_base
    local timestamp
    timestamp=$(echo "$meta_response" | jq -r '.osm3s.timestamp_osm_base // ""' 2>/dev/null || echo "")

    # Calculate age in minutes
    local age="U"
    if [[ -n "$timestamp" && "$timestamp" != "null" ]]; then
        local ts_epoch now_epoch
        ts_epoch=$(date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || echo "")
        if [[ -n "$ts_epoch" ]]; then
            now_epoch=$(date +%s)
            age=$(( (now_epoch - ts_epoch) / 60 ))
        fi
    fi

    write_stat "version" "$version"
    write_stat "age" "$age"
    write_stat "timestamp" "$timestamp"

    return 0
}

# Main
main() {
    # Record fetch time
    write_stat "last_update" "$(date -Iseconds)"

    # Fetch status (slots, active, latency)
    fetch_status || true

    # Fetch metadata (version, age)
    fetch_metadata || true
}

main "$@"
