#\!/bin/bash
# Bomb serving wrapper - checks toggle, counts serves

FLAG="/var/www/blog/.bomb-enabled"
COUNTER="/var/www/blog/public/honeypot/.bomb-count"
BOMB="/var/www/blog/public/honeypot/secrets.gz"
LOG="/var/log/honeypot.log"

# Get real IP (CF-Connecting-IP header, fallback to REMOTE_ADDR)
REAL_IP="${HTTP_CF_CONNECTING_IP:-$REMOTE_ADDR}"

# Log the attempt regardless
{
    echo "=== $(date -Iseconds) [BOMB REQUEST] ==="
    echo "IP: $REAL_IP"
    echo "User-Agent: $HTTP_USER_AGENT"
    echo "Path: $REQUEST_URI"
    echo ""
} >> "$LOG" 2>/dev/null

# Check if bombs are enabled
if [ -f "$FLAG" ]; then
    # Increment counter
    COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
    echo $((COUNT + 1)) > "$COUNTER" 2>/dev/null
    
    # Serve the bomb with gzip encoding
    echo "Content-Type: application/octet-stream"
    echo "Content-Encoding: gzip"
    echo "Content-Length: $(stat -c%s "$BOMB")"
    echo ""
    cat "$BOMB"
else
    # Bombs disabled - serve a tiny response
    echo "Content-Type: text/plain"
    echo ""
    echo "404 Not Found"
fi
