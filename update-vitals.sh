#!/bin/bash
# Update Pi vitals every 30 minutes

BLOG_DIR="/var/www/blog"
PUBLIC_DIR="$BLOG_DIR/public"

# Get stats
UPTIME_SECONDS=$(cat /proc/uptime | cut -d. -f1)
UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
UPTIME_HOURS=$(( (UPTIME_SECONDS % 86400) / 3600 ))
UPTIME_MINS=$(( (UPTIME_SECONDS % 3600) / 60 ))

if [ $UPTIME_DAYS -gt 0 ]; then
    UPTIME_STR="${UPTIME_DAYS}d ${UPTIME_HOURS}h"
else
    UPTIME_STR="${UPTIME_HOURS}h ${UPTIME_MINS}m"
fi

CPU_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk "{printf \"%.1f\", \$1/1000}")
MEM_USED=$(free -m | awk "/Mem:/ {print \$3}")
MEM_TOTAL=$(free -m | awk "/Mem:/ {print \$7}")
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
LOAD=$(cat /proc/loadavg | cut -d" " -f1)
DISK_USED=$(df -h / | awk "NR==2 {print \$3}")
DISK_AVAIL=$(df -h / | awk "NR==2 {print \$4}")
UPDATED=$(date "+%Y-%m-%d %H:%M")

# Save uptime for footer
echo "$UPTIME_STR" > "$PUBLIC_DIR/uptime.txt"

# Generate colophon with live stats
cat > "$PUBLIC_DIR/colophon.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Colophon | Ashwater</title>
  <meta name="description" content="The hardware and software stack powering Ashwater">
  <link rel="stylesheet" href="/style.css?v=3">
  <link rel="icon" href="/favicon.ico">
  <style>.vitals td:first-child { font-weight: bold; } .vitals { margin: 1rem 0; }</style>
</head>
<body>
<nav>
  <a href="/">~/home</a>
  <a href="/posts/">~/posts</a>
  <a href="/pi-stories/">~/pi-stories</a>
  <a href="/about.html">~/about</a>
</nav>
<main>
<h1>Colophon</h1>

<p>This blog is served from a tiny computer sitting on a shelf, running 24/7 on less power than an LED bulb.</p>

<h2>Live Vitals</h2>
<table class="vitals">
<tr><td>Uptime</td><td>${UPTIME_STR}</td></tr>
<tr><td>CPU Temp</td><td>${CPU_TEMP}°C</td></tr>
<tr><td>Memory</td><td>${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)</td></tr>
<tr><td>Load</td><td>${LOAD}</td></tr>
<tr><td>Disk</td><td>${DISK_USED} used / ${DISK_AVAIL} free</td></tr>
<tr><td>Updated</td><td>${UPDATED}</td></tr>
</table>

<h2>Hardware</h2>
<table>
<tr><td><strong>Board</strong></td><td>Raspberry Pi Zero 2 W</td></tr>
<tr><td><strong>CPU</strong></td><td>Quad-core ARM Cortex-A53 @ 1GHz</td></tr>
<tr><td><strong>RAM</strong></td><td>512MB LPDDR2</td></tr>
<tr><td><strong>Storage</strong></td><td>64GB microSD</td></tr>
<tr><td><strong>Network</strong></td><td>802.11 b/g/n WiFi</td></tr>
<tr><td><strong>Power</strong></td><td>~0.5W idle, ~1.5W under load</td></tr>
<tr><td><strong>Cost</strong></td><td>~\$15 USD</td></tr>
</table>

<h2>Software Stack</h2>
<table>
<tr><td><strong>OS</strong></td><td>Raspberry Pi OS Lite (Debian Bookworm)</td></tr>
<tr><td><strong>Web Server</strong></td><td>lighttpd</td></tr>
<tr><td><strong>Tunnel</strong></td><td>Cloudflare Tunnel (cloudflared)</td></tr>
<tr><td><strong>Build System</strong></td><td>~250 lines of bash + lowdown</td></tr>
<tr><td><strong>AI Model</strong></td><td>TinyLlama-15M-Stories (14MB GGUF)</td></tr>
<tr><td><strong>Inference</strong></td><td>llama.cpp (~100 tokens/sec)</td></tr>
</table>

<h2>Architecture</h2>
<pre>
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────▶│  Cloudflare │────▶│  Pi Zero 2  │
│             │◀────│   (Tunnel)  │◀────│  (lighttpd) │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                    HTTPS termination
                    DDoS protection
                    (No caching - pure tunnel)
</pre>

<h2>Fun Facts</h2>
<ul>
<li>The Pi draws about <strong>4 kWh per year</strong> — roughly \$0.50 in electricity</li>
<li>Every page you see was served directly from this tiny board, not a CDN</li>
<li>Daily stories are generated at 3am by a 15-million parameter AI model</li>
<li>The entire blog (HTML, CSS, posts) fits in about 100KB</li>
<li>Build time for the whole site: ~0.1 seconds</li>
<li>The WiFi chip is the bottleneck — theoretically maxing out at ~50 Mbps</li>
</ul>

<h2>Why?</h2>
<p>Because its fun. Because a \$15 computer can serve a blog to thousands of people. Because the web doesnt need to be complicated.</p>

</main>
<footer>
  <p><a href="/feed.xml">rss</a></p>
  <p><a href="/colophon.html">Served from a Pi Zero 2 W</a></p>
  <p class="uptime">uptime: ${UPTIME_STR}</p>
</footer>
</body>
</html>
EOF

# Update about.html footer with uptime
sed -i "s/uptime: [^<]*/uptime: ${UPTIME_STR}/" "$PUBLIC_DIR/about.html"

echo "Vitals updated: uptime=$UPTIME_STR temp=${CPU_TEMP}°C mem=${MEM_PCT}%"
