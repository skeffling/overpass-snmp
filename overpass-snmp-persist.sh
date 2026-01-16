#!/bin/bash
#
# overpass-snmp-persist.sh - SNMP pass_persist script for Overpass API stats
#
# This script implements the pass_persist protocol for net-snmp.
# It returns properly typed values (Gauge32, STRING) instead of strings.
#
# Base OID: .1.3.6.1.4.1.99999.1 (overpassObjects)
#
# Configure in snmpd.conf:
#   pass_persist .1.3.6.1.4.1.99999.1 /usr/local/bin/overpass-snmp-persist.sh

CACHE_DIR="${CACHE_DIR:-/var/cache/overpass-snmp}"

# Base OID for overpassObjects
BASE_OID=".1.3.6.1.4.1.99999.1"

# OID mapping: sub-oid -> (cache_file, type)
# Types: gauge, string, integer
declare -A OID_MAP=(
    ["1"]="slots_available:gauge"
    ["2"]="slots_total:gauge"
    ["3"]="active:gauge"
    ["4"]="latency:gauge"
    ["5"]="age:gauge"
    ["6"]="version:string"
)

# Sorted OID list for GETNEXT
OID_LIST=(1 2 3 4 5 6)

# Read a cached value
read_value() {
    local file="$1"
    local value
    value=$(cat "$CACHE_DIR/$file" 2>/dev/null)
    if [[ -z "$value" || "$value" == "U" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

# Output an OID response
output_response() {
    local oid="$1"
    local type="$2"
    local value="$3"

    echo "$oid"
    case "$type" in
        gauge)
            echo "gauge"
            echo "${value:-0}"
            ;;
        integer)
            echo "integer"
            echo "${value:-0}"
            ;;
        string)
            echo "string"
            echo "${value:-}"
            ;;
    esac
}

# Handle GET request
handle_get() {
    local oid="$1"

    # Check if OID starts with our base
    if [[ "$oid" != "$BASE_OID"* ]]; then
        echo "NONE"
        return
    fi

    # Extract sub-OID
    local sub_oid="${oid#$BASE_OID.}"

    # Look up in map
    if [[ -n "${OID_MAP[$sub_oid]}" ]]; then
        local mapping="${OID_MAP[$sub_oid]}"
        local cache_file="${mapping%%:*}"
        local type="${mapping##*:}"
        local value
        value=$(read_value "$cache_file")

        if [[ -n "$value" ]]; then
            output_response "$oid" "$type" "$value"
        else
            echo "NONE"
        fi
    else
        echo "NONE"
    fi
}

# Handle GETNEXT request
handle_getnext() {
    local oid="$1"

    # If OID is before or at base, return first element
    if [[ "$oid" < "$BASE_OID" || "$oid" == "$BASE_OID" ]]; then
        local first_sub="${OID_LIST[0]}"
        local mapping="${OID_MAP[$first_sub]}"
        local cache_file="${mapping%%:*}"
        local type="${mapping##*:}"
        local value
        value=$(read_value "$cache_file")
        output_response "$BASE_OID.$first_sub" "$type" "$value"
        return
    fi

    # Check if OID is in our tree
    if [[ "$oid" != "$BASE_OID"* ]]; then
        echo "NONE"
        return
    fi

    # Extract sub-OID
    local sub_oid="${oid#$BASE_OID.}"

    # Find next OID
    local found_next=false
    for next_sub in "${OID_LIST[@]}"; do
        if [[ "$next_sub" -gt "$sub_oid" ]]; then
            local mapping="${OID_MAP[$next_sub]}"
            local cache_file="${mapping%%:*}"
            local type="${mapping##*:}"
            local value
            value=$(read_value "$cache_file")
            output_response "$BASE_OID.$next_sub" "$type" "$value"
            found_next=true
            break
        fi
    done

    if [[ "$found_next" == false ]]; then
        echo "NONE"
    fi
}

# Main loop - read commands from stdin
while read -r cmd; do
    case "$cmd" in
        PING)
            echo "PONG"
            ;;
        get)
            read -r oid
            handle_get "$oid"
            ;;
        getnext)
            read -r oid
            handle_getnext "$oid"
            ;;
        set)
            # Read and discard set request (we're read-only)
            read -r oid
            read -r value
            echo "not-writable"
            ;;
        *)
            # Unknown command
            ;;
    esac
done
