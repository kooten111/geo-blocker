#!/bin/bash

# ==============================================================================
# UFW Geo-Blocking Update Script: Manage Allow Rules for Swedish & Local IPs
# ==============================================================================
# Description:
# This script manages UFW rules to allow incoming connections from Swedish IP
# addresses AND specified local network ranges.
#
# MODES:
# 1. Update Mode (default): REMOVES previously added rules tagged for the
#    country before adding the latest ones. Ensures local/loopback rules exist.
# 2. Init Mode (`--init` flag): Skips deletion, ensures local/loopback/SSH
#    rules exist, adds country rules. Use this for the very first run.
#
# INTENDED USE:
# - For systems where UFW is configured with a default deny policy.
# - Run with `--init` once for initial setup.
# - Run without flags periodically (e.g., via cron) for updates.
#
# PREREQUISITES:
# - UFW must be installed.
# - Required commands: ufw, wget, grep, awk, sort, sed.
# - For `--init` mode: Manually ensure UFW default policy is DENY incoming
#   and UFW is enabled *after* running the script, or ensure SSH is allowed
#   by other means if you enable UFW before running.
#
# WARNING:
# - If your default policy is not DENY, this script will NOT secure your server.
# - IP geolocation lists are not always 100% accurate or up-to-date.
# - Ensure the RULE_COMMENT variables are unique if you modify the script.
# ==============================================================================

# --- Configuration ---
COUNTRY_CODE="" # se = Sweden
IP_LIST_URL="http://www.ipdeny.com/ipblocks/data/countries/${COUNTRY_CODE}.zone"
LOCAL_NETWORKS="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12" # Adjust as needed

# --- Rule Comments for Tagging ---
COUNTRY_RULE_COMMENT="AUTO-GEOBLOCK-${COUNTRY_CODE^^}"
LOCAL_RULE_COMMENT="AUTO-LOCAL-ALLOW"
LOOPBACK_RULE_COMMENT="AUTO-LOOPBACK"
SSH_RULE_COMMENT="AUTO-SSH-ALLOW" # Comment for the essential SSH rule

# --- Script Variables ---
TMP_IP_LIST=$(mktemp)
INIT_MODE=false

# --- Process Command Line Arguments ---
if [[ "$1" == "--init" ]]; then
  INIT_MODE=true
  echo "--- Running in INIT mode ---"
fi

# --- Functions ---
cleanup() {
  rm -f "$TMP_IP_LIST"
}
trap cleanup EXIT SIGINT SIGTERM

check_command() {
  command -v "$1" >/dev/null 2>&1 || { echo >&2 "ERROR: Command '$1' not found. Please install it. Aborting."; exit 1; }
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (or using sudo)."
    exit 1
  fi
}

check_country() {
  if [[ -z $COUNTRY_CODE ]]; then
    echo "ERROR: No country code was defined."
    echo "REMINDER: Valid country codes can be found here: https://www.ipdeny.com/ipblocks/"
    exit 1
  fi
}

load_environment() {
  if [[ -f $PWD/.env ]]; then
    . .env
  else
    echo "NOTICE: There is no .env file in the current working directory"
  fi
}

# --- Pre-run Checks ---
check_root
load_environment
check_country
check_command ufw
check_command wget
check_command grep
check_command awk
check_command sort
check_command sed

# --- User Confirmation (Show only in non-init mode, less verbose for cron) ---
if ! $INIT_MODE; then
    echo "------------------------------------------------------------------"
    echo " UFW Geo-Blocking Update Script: Updating ${COUNTRY_CODE^^} & Local IPs"
    echo "------------------------------------------------------------------"
    echo "This script will:"
    echo " 1. DELETE existing UFW rules with the comment: '${COUNTRY_RULE_COMMENT}'"
    echo " 2. Ensure rules exist for Local Networks, Loopback (and SSH if missing)."
    echo " 3. Download the latest IP list for ${COUNTRY_CODE^^}."
    echo " 4. Add new UFW rules for ${COUNTRY_CODE^^} IPs, tagged with '${COUNTRY_RULE_COMMENT}'."
    echo "ASSUMPTION: Your default incoming policy is DENY."
    echo "------------------------------------------------------------------"
    # Optional: Add a read prompt here if you want confirmation for manual updates
    # read -p "Do you want to continue? (y/N): " confirm
    # if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    #   echo "Aborting script."
    #   exit 0
    # fi
    # echo "Proceeding..."
else
    echo "------------------------------------------------------------------"
    echo " UFW Geo-Blocking Initial Setup: Adding ${COUNTRY_CODE^^} & Local IPs"
    echo "------------------------------------------------------------------"
    echo "This script will:"
    echo " 1. Ensure rules exist for Local Networks, Loopback, and SSH."
    echo " 2. Download the IP list for ${COUNTRY_CODE^^}."
    echo " 3. Add UFW rules for ${COUNTRY_CODE^^} IPs, tagged with '${COUNTRY_RULE_COMMENT}'."
    echo ""
    echo "IMPORTANT: After this script finishes:"
    echo " - Ensure UFW's default incoming policy is DENY: 'sudo ufw default deny incoming'"
    echo " - Enable UFW if it's not already active: 'sudo ufw enable'"
    echo "------------------------------------------------------------------"
    # No confirmation needed for init mode usually, but you could add one.
fi


# --- Delete Old Country Rules (Only in Update Mode) ---
DELETED_COUNT=0
if ! $INIT_MODE; then
    echo "[1/6] Deleting old ${COUNTRY_CODE^^} rules tagged with '${COUNTRY_RULE_COMMENT}'..."
    RULE_NUMBERS=$(ufw status numbered | grep -F "# ${COUNTRY_RULE_COMMENT}" | awk -F'[][]' '{print $2}' | sort -nr)
    if [[ -n "$RULE_NUMBERS" ]]; then
      for num in $RULE_NUMBERS; do
        if ufw status numbered | grep -q "\[ ${num}\]"; then
            echo "      Deleting rule number: $num"
            ufw --force delete "$num" > /dev/null
            if [[ $? -eq 0 ]]; then
                ((DELETED_COUNT++))
            else
                echo "      WARNING: Failed to delete rule number $num."
            fi
        fi
      done
    fi
    if [[ $DELETED_COUNT -gt 0 ]]; then
        echo "      Deleted ${DELETED_COUNT} old ${COUNTRY_CODE^^} rules."
    else
        echo "      No old ${COUNTRY_CODE^^} rules found with the tag '${COUNTRY_RULE_COMMENT}'."
    fi
else
    echo "[1/6] Skipping rule deletion in INIT mode."
fi


# --- Ensure Static Rules (Loopback, Local, SSH) ---
STEP_NUM=2 # Start step numbering after potential deletion step

echo "[$((STEP_NUM++))/6] Ensuring loopback rules exist..."
# Check and add loopback rules (IPv4 and IPv6)
if ! ufw status | grep -qw '127.0.0.1'; then
    echo "      Adding loopback rule for 127.0.0.1"
    ufw allow from 127.0.0.1 to any comment "${LOOPBACK_RULE_COMMENT}"
else
    echo "      Loopback rule for 127.0.0.1 already exists."
fi
if ! ufw status | grep -qw '::1'; then
    echo "      Adding loopback rule for ::1"
    ufw allow from ::1 to any comment "${LOOPBACK_RULE_COMMENT}"
else
    echo "      Loopback rule for ::1 already exists."
fi

echo "[$((STEP_NUM++))/6] Ensuring local network rules exist..."
if [[ -n "$LOCAL_NETWORKS" ]]; then
  for net in $LOCAL_NETWORKS; do
    if [[ "$net" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2}$ ]]; then
        # Check if rule exists allowing *from* this network
        if ! ufw status verbose | grep -qP "ALLOW +IN +FROM +${net}( +|$)"; then
           echo "      Adding allow rule for local network: ${net}"
           ufw allow from "$net" to any comment "${LOCAL_RULE_COMMENT}"
        else
           echo "      Rule for local network ${net} already exists."
        fi
    else
        echo "      Skipping invalid local network format: ${net}"
    fi
  done
else
  echo "      No local networks defined in LOCAL_NETWORKS variable."
fi

echo "[$((STEP_NUM++))/6] Ensuring SSH rule exists..."
# Check if an allow rule for SSH (port 22/tcp) exists
# This grep is basic, might match unrelated rules if '22/tcp' appears elsewhere.
# A more robust check could parse 'ufw status numbered' output more carefully.
if ! ufw status | grep -qE '(ALLOW +IN +22/tcp|ALLOW +IN +ssh)'; then
    echo "      Adding allow rule for SSH (port 22/tcp)"
    ufw allow ssh comment "${SSH_RULE_COMMENT}"
else
    echo "      SSH allow rule (port 22/tcp or service name) already exists."
fi


# --- Download New Country IPs ---
echo "[$((STEP_NUM++))/6] Downloading IP list for ${COUNTRY_CODE^^}..."
wget --quiet --output-document="$TMP_IP_LIST" "$IP_LIST_URL"

COUNTRY_RULE_ADD_FAILED=false
if [[ $? -ne 0 || ! -s "$TMP_IP_LIST" ]]; then
  echo "ERROR: Failed to download IP list from ${IP_LIST_URL} or the list is empty."
  echo "No new country-specific rules will be added. Check connection or URL."
  COUNTRY_RULE_ADD_FAILED=true
else
  echo "      IP list downloaded successfully."
fi


# --- Add New Country Rules ---
ADDED_COUNT=0
echo "[$((STEP_NUM++))/6] Adding new allow rules for ${COUNTRY_CODE^^} IPs..."
if ! $COUNTRY_RULE_ADD_FAILED; then
    while IFS= read -r ip_range || [[ -n "$ip_range" ]]; do
        ip_range=$(echo "$ip_range" | sed 's/^[ \t]*//;s/[ \t]*$//')
        [[ -z "$ip_range" || "$ip_range" =~ ^# ]] && continue

        if [[ "$ip_range" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$ ]]; then
            is_local=false
            if [[ -n "$LOCAL_NETWORKS" ]]; then
                for net in $LOCAL_NETWORKS; do
                    if [[ "$ip_range" == "$net" ]]; then
                        is_local=true
                        break
                    fi
                done
            fi

            if ! $is_local; then
                echo "      Allowing from ${ip_range}"
                ufw allow from "$ip_range" to any comment "${COUNTRY_RULE_COMMENT}"
                ((ADDED_COUNT++))
            else
                echo "      Skipping ${ip_range} (already covered by local network rule: ${net})"
            fi
        else
            echo "      Skipping invalid line in country list: ${ip_range}"
        fi
    done < "$TMP_IP_LIST"
    echo "      Added ${ADDED_COUNT} new rules for ${COUNTRY_CODE^^}."
else
    echo "      Skipped adding country rules due to download failure."
fi


# --- Completion ---
echo "------------------------------------------------------------------"
echo " UFW Rule Management Complete!"
echo "------------------------------------------------------------------"
echo " Summary:"
if ! $INIT_MODE; then
    echo "  - Mode: Update"
    echo "  - Deleted ${DELETED_COUNT} old rules tagged '${COUNTRY_RULE_COMMENT}'."
else
    echo "  - Mode: Initial Setup (--init)"
    echo "  - Skipped deleting old country rules."
fi
echo "  - Ensured rules exist for Loopback, Local Networks (${LOCAL_NETWORKS:-None}), and SSH."
if ! $COUNTRY_RULE_ADD_FAILED; then
  echo "  - Added ${ADDED_COUNT} new rules for ${COUNTRY_CODE^^} tagged '${COUNTRY_RULE_COMMENT}'."
else
  echo "  - FAILED to add new rules for ${COUNTRY_CODE^^} due to download error."
fi
echo ""
if $INIT_MODE; then
    echo " REMINDER: Ensure UFW is enabled ('sudo ufw enable') and default policy"
    echo "           is deny incoming ('sudo ufw default deny incoming')."
fi
echo " IMPORTANT: This script relies on your default incoming policy being DENY."
echo " Verify with: sudo ufw status verbose"
echo "------------------------------------------------------------------"
echo " Current UFW status (brief):"
ufw status
echo "------------------------------------------------------------------"
if ! $INIT_MODE; then
    echo " Consider running this script periodically (e.g., daily or weekly) via cron"
    echo " to keep the ${COUNTRY_CODE^^} IP list updated."
    echo " Example crontab entry (run daily at 3:05 AM):"
    echo " 5 3 * * * /path/to/your/script.sh > /var/log/ufw-geoblock-update.log 2>&1"
fi
echo "------------------------------------------------------------------"

exit 0
