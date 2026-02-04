#!/bin/bash
# Honeypot credential logger

LOG="/var/log/honeypot.log"

# Get real IP (CF-Connecting-IP header, fallback to REMOTE_ADDR)
REAL_IP="${HTTP_CF_CONNECTING_IP:-$REMOTE_ADDR}"

# Get POST data
read -n $CONTENT_LENGTH POST_DATA 2>/dev/null

# Log the attempt
{
    echo "=== $(date -Iseconds) ==="
    echo "IP: $REAL_IP"
    echo "User-Agent: $HTTP_USER_AGENT"
    echo "Credentials: $POST_DATA"
    echo ""
} >> "$LOG" 2>/dev/null

# Redirect to bomb wrapper
echo "Status: 302 Found"
echo "Location: /honeypot/cgi/serve-bomb.sh"
echo ""
