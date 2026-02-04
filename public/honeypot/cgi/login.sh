#!/bin/bash
# Honeypot login credential harvester
# Logs attempted credentials and redirects to gzip bomb

LOG="/var/log/honeypot.log"
REAL_IP="${HTTP_CF_CONNECTING_IP:-$REMOTE_ADDR}"

# Validate and limit CONTENT_LENGTH to prevent hangs/memory issues
CONTENT_LENGTH=${CONTENT_LENGTH:-0}
[[ ! "$CONTENT_LENGTH" =~ ^[0-9]+$ ]] && CONTENT_LENGTH=0
[ "$CONTENT_LENGTH" -gt 10000 ] && CONTENT_LENGTH=10000

# Read POST data safely
POST_DATA=""
if [ "$CONTENT_LENGTH" -gt 0 ]; then
    read -n "$CONTENT_LENGTH" POST_DATA 2>/dev/null
fi

# Log the attempt
{
    echo "=== $(date -Iseconds) ==="
    echo "IP: $REAL_IP"
    echo "User-Agent: $HTTP_USER_AGENT"
    echo "Credentials: $POST_DATA"
    echo ""
} >> "$LOG" 2>/dev/null || true

# Redirect to the bomb
echo "Status: 302 Found"
echo "Location: /honeypot/cgi/serve-bomb.sh"
echo ""
