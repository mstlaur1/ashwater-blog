#\!/bin/bash
echo "Content-Type: text/plain"
echo ""
env | grep -i "HTTP_\|REMOTE" | sort
