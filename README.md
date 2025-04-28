# UFW Geo-Blocking Manager

A Bash script to dynamically manage UFW (Uncomplicated Firewall) rules for geo-based network access control. This script maintains allow rules for specific countries and local networks while enforcing deny-by-default security.

## 🔥 Features

- **Country-Based Allow Rules**: Dynamically manage allow rules for specific countries (default: Sweden)
- **Local Network Protection**: Automatically preserves access from defined local network ranges
- **Self-Maintaining**: Automatically removes outdated rules before adding new ones
- **Initialization Mode**: Special mode for first-time setup to ensure SSH access is preserved
- **Robust Error Handling**: Checks for dependencies and provides clear error messages
- **Detailed Logging**: Comprehensive output of actions taken

## 📋 Prerequisites

- UFW (Uncomplicated Firewall) must be installed
- Required commands: `ufw`, `wget`, `grep`, `awk`, `sort`, `sed`
- Root privileges (script must be run with sudo)

## 🚀 Quick Start

1. **Clone this repository**:
   ```bash
   git clone https://github.com/yourusername/ufw-geoblocking.git
   cd ufw-geoblocking
   ```

2. **Make the script executable**:
   ```bash
   chmod +x ufw-geoblock.sh
   ```

3. **Initial setup** (first time only):
   ```bash
   sudo ./ufw-geoblock.sh --init
   ```

4. **After initialization, ensure UFW is properly configured**:
   ```bash
   sudo ufw default deny incoming  # If not already set
   sudo ufw enable                 # If not already enabled
   ```

5. **For regular updates** (can be scheduled via cron):
   ```bash
   sudo ./ufw-geoblock.sh
   ```

## ⚙️ Configuration

Edit the following variables at the top of the script to customize its behavior:

```bash
# Country to allow (ISO code)
COUNTRY_CODE="se"  # se = Sweden

# IP list source
IP_LIST_URL="http://www.ipdeny.com/ipblocks/data/countries/${COUNTRY_CODE}.zone"

# Local networks to always allow
LOCAL_NETWORKS="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"

# Rule comment identifiers
COUNTRY_RULE_COMMENT="AUTO-GEOBLOCK-${COUNTRY_CODE^^}"
LOCAL_RULE_COMMENT="AUTO-LOCAL-ALLOW"
LOOPBACK_RULE_COMMENT="AUTO-LOOPBACK"
SSH_RULE_COMMENT="AUTO-SSH-ALLOW"
```

## 🔄 Automation with Cron

For automatic updates, add a cron job:

```bash
# Edit crontab
sudo crontab -e

# Add a line to run the script daily at 3:05 AM
5 3 * * * /path/to/ufw-geoblock.sh > /var/log/ufw-geoblock-update.log 2>&1
```

## 🔍 Understanding the Output

The script provides detailed information about its actions:

```
------------------------------------------------------------------
 UFW Geo-Blocking Update Script: Updating SE & Local IPs
------------------------------------------------------------------
[1/6] Deleting old SE rules tagged with 'AUTO-GEOBLOCK-SE'...
[2/6] Ensuring loopback rules exist...
[3/6] Ensuring local network rules exist...
[4/6] Ensuring SSH rule exists...
[5/6] Downloading IP list for SE...
[6/6] Adding new allow rules for SE IPs...
------------------------------------------------------------------
 UFW Rule Management Complete!
------------------------------------------------------------------
```

## ⚠️ Important Warnings

- This script assumes your UFW default policy is set to DENY incoming connections
- IP geolocation lists are not 100% accurate or always up-to-date
- Always ensure SSH access is properly configured before enabling UFW
- This script is designed to be one part of a comprehensive security strategy, not a complete solution

## 🔒 Security Considerations

- The script adds SSH access by default to prevent lockouts
- All rules are tagged with specific comments for easy identification and management
- Loopback and local network access is preserved to ensure system functionality
- Only the specified country's IP ranges are allowed for incoming connections

## ⚠️ AI-Generated Code Disclaimer
IMPORTANT: This script was generated with the assistance of artificial intelligence. Before deploying this script in a production environment, it is strongly recommended to Thoroughly review all code and understand each command's purpose

The author of this repository cannot guarantee the script's perfect functionality across all environments and use cases.
