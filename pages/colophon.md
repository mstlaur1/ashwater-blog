---
title: Colophon
description: The hardware and software stack powering Ashwater
---

This blog is served from a tiny computer sitting on a shelf, running 24/7 on less power than an LED bulb.

## Hardware

| Component | Spec |
|-----------|------|
| Board | Raspberry Pi Zero 2 W |
| CPU | Quad-core ARM Cortex-A53 @ 1GHz |
| RAM | 512MB LPDDR2 |
| Storage | 64GB microSD |
| Network | 802.11 b/g/n WiFi |
| Power | ~0.5W idle, ~1.5W under load |
| Cost | ~$15 USD |

## Software Stack

| Component | Tech |
|-----------|------|
| OS | Raspberry Pi OS Lite (Debian Bookworm) |
| Web Server | lighttpd |
| Tunnel | Cloudflare Tunnel (cloudflared) |
| Build System | ~250 lines of bash + lowdown |
| AI Model | TinyLlama-15M-Stories (14MB GGUF) |
| Inference | llama.cpp (~100 tokens/sec) |

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────▶│  Cloudflare │────▶│  Pi Zero 2  │
│             │◀────│   (Tunnel)  │◀────│  (lighttpd) │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                    HTTPS termination
                    DDoS protection
                    (No caching - pure tunnel)
```

## Fun Facts

- The Pi draws about **4 kWh per year** — roughly $0.50 in electricity
- Every page you see was served directly from this tiny board, not a CDN
- Daily stories are generated at 3am by a 15-million parameter AI model
- The entire blog (HTML, CSS, posts) fits in about 100KB
- Build time for the whole site: ~0.1 seconds
- The WiFi chip is the bottleneck — theoretically maxing out at ~50 Mbps

## Why?

Because it's fun. Because a $15 computer can serve a blog to thousands of people. Because the web doesn't need to be complicated.
