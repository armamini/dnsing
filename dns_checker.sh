#!/bin/bash

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

for cmd in jq curl python3 tput; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: '$cmd' is not installed. Please install it.${NC}"
        exit 1
    fi
done

HOST="$1"
MAX_NODES="${2:-50}"

if [ -z "$HOST" ]; then
    echo -e "${YELLOW}Usage:${NC} $0 <domain_or_ip> [max_nodes]"
    exit 1
fi

API_URL="https://check-host.net"
CHECK_TYPE="dns"

TERM_WIDTH=$(tput cols)
if [ -z "$TERM_WIDTH" ] || [ "$TERM_WIDTH" -lt 60 ]; then
    TERM_WIDTH=80
fi

LOC_WIDTH=35
STATUS_WIDTH=10
RESULT_WIDTH=$((TERM_WIDTH - LOC_WIDTH - STATUS_WIDTH - 6))

if [ $RESULT_WIDTH -lt 20 ]; then
    RESULT_WIDTH=20
    TERM_WIDTH=$((LOC_WIDTH + STATUS_WIDTH + 6 + RESULT_WIDTH))
fi

echo -e "${BLUE}:: Initiating DNS check for:${NC} ${BOLD}$HOST${NC}"

RESPONSE=$(curl -s -H "Accept: application/json" "${API_URL}/check-${CHECK_TYPE}?host=${HOST}&max_nodes=${MAX_NODES}")

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to connect to check-host.net API.${NC}"
    exit 1
fi

OK=$(echo "$RESPONSE" | jq -r '.ok')
if [ "$OK" != "1" ]; then
    echo -e "${RED}Error: API request failed.${NC}"
    echo "$RESPONSE"
    exit 1
fi

REQUEST_ID=$(echo "$RESPONSE" | jq -r '.request_id')
PERMANENT_LINK=$(echo "$RESPONSE" | jq -r '.permanent_link')

echo -e "Request ID: ${CYAN}$REQUEST_ID${NC}"
echo -e "Report Link: ${BLUE}$PERMANENT_LINK${NC}"

declare -A NODES_INFO
NODES_OUTPUT=$(echo "$RESPONSE" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    nodes = data.get("nodes", {})
    for key, val in nodes.items():
        # val is [cc, country, city, ip, as]
        cc = val[0].upper()
        country = val[1]
        city = val[2]
        # Generate flag
        flag = chr(ord(cc[0]) + 127397) + chr(ord(cc[1]) + 127397)
        # Escape pipes just in case (unlikely but safe)
        print(f"{key}|{flag}|{country}|{city}")
except Exception:
    pass
')

while IFS="|" read -r KEY FLAG COUNTRY CITY; do
    LOC_STR="$FLAG  $COUNTRY, $CITY"
    NODES_INFO["$KEY"]="$LOC_STR"
done <<< "$NODES_OUTPUT"

echo -e "${YELLOW}Waiting for results...${NC}"

print_separator() {
    printf -v LINE '%*s' "$TERM_WIDTH"
    echo -e "${BOLD}${LINE// /-}${NC}"
}

print_separator
printf "${BOLD}%-${LOC_WIDTH}s | %-${STATUS_WIDTH}s | %s${NC}\n" "Location" "Status" "Result (IP / TTL)"
print_separator

MAX_RETRIES=20
SLEEP_TIME=3

declare -A COMPLETED_NODES

for ((i=1; i<=MAX_RETRIES; i++)); do
    RESULT_RESPONSE=$(curl -s -H "Accept: application/json" "${API_URL}/check-result/${REQUEST_ID}")
    
    ALL_DONE=true
    
    for NODE_ID in "${!NODES_INFO[@]}"; do
        if [ "${COMPLETED_NODES[$NODE_ID]}" == "1" ]; then
            continue
        fi

        NODE_DATA=$(echo "$RESULT_RESPONSE" | jq -r --arg NODE "$NODE_ID" '.[$NODE]')

        if [ "$NODE_DATA" == "null" ]; then
            ALL_DONE=false
        else
            COMPLETED_NODES["$NODE_ID"]="1"
            
            RAW_LOC="${NODES_INFO[$NODE_ID]}"
            
            ERROR_MSG=$(echo "$NODE_DATA" | jq -r '
                if .[0].error then .[0].error
                elif .[0] == null and .[1].message then .[1].message
                else empty end
            ')
            
            if [ -n "$ERROR_MSG" ]; then
                 printf "${CYAN}%-${LOC_WIDTH}s${NC} | ${RED}%-${STATUS_WIDTH}s${NC} | ${RED}%s${NC}\n" "${RAW_LOC:0:$LOC_WIDTH}" "Error" "$ERROR_MSG"
            else
                 IPS=$(echo "$NODE_DATA" | jq -r '(.[0].A[]? // empty), (.[0].AAAA[]? // empty)' | tr '\n' ' ' | sed 's/ $//')
                 TTL=$(echo "$NODE_DATA" | jq -r '.[0].TTL // empty')
                 
                 if [ -z "$IPS" ]; then IPS="No records"; fi
                 
                 FULL_RES="$IPS (TTL: $TTL)"
                 TTL_SUFFIX=" (TTL: $TTL)"
                 SUFFIX_LEN=${#TTL_SUFFIX}
                 
                 MAX_IP_LEN=$((RESULT_WIDTH - SUFFIX_LEN - 3))
                 
                 if [ ${#IPS} -gt $MAX_IP_LEN ] && [ $MAX_IP_LEN -gt 0 ]; then
                     IPS="${IPS:0:$MAX_IP_LEN}..."
                 fi
                 
                 FINAL_RES="$IPS$TTL_SUFFIX"
                 
                 printf "${CYAN}%-${LOC_WIDTH}s${NC} | ${GREEN}%-${STATUS_WIDTH}s${NC} | %s\n" "${RAW_LOC:0:$LOC_WIDTH}" "OK" "$FINAL_RES"
            fi
        fi
    done

    if [ "$ALL_DONE" = true ]; then
        break
    fi

    if [ $i -lt $MAX_RETRIES ]; then
        sleep $SLEEP_TIME
    fi
done

print_separator
echo -e "${GREEN}Check complete.${NC}"
