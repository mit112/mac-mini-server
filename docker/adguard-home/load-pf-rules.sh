#!/bin/bash
# Load AdGuard Home port redirect rules
# Redirects DNS port 53 -> 5335 on YOUR_LOCAL_IP

PF_CONF="/Users/mitsheth/adguard-home/pf-adguard.conf"

if [ -f "$PF_CONF" ]; then
    /sbin/pfctl -a "com.apple/adguard" -f "$PF_CONF" 2>/dev/null
    /sbin/pfctl -e 2>/dev/null
    echo "AdGuard pf rules loaded"
else
    echo "ERROR: $PF_CONF not found"
fi
