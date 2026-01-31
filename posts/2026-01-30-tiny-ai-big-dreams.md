---
title: Running a Language Model on a $15 Computer
date: 2026-01-30
description: How a 15-million parameter AI generates daily stories on a Raspberry Pi Zero 2 W, and what it means for the future of local inference.
---

Every night at 3am, a tiny computer on my shelf wakes up, loads a language model into its 512MB of RAM, generates a short story, and goes back to sleep. The whole process takes about 30 seconds. The computer cost $15.

## The Setup

The hardware is a Raspberry Pi Zero 2 W — a quad-core ARM board roughly the size of a stick of gum. It draws about 0.5 watts idle, maybe 1.5 watts when the CPU is working hard. That's less than an LED bulb.

The model is TinyStories-15M, a 15-million parameter language model specifically trained to generate coherent children's stories. At 14MB quantized, it fits comfortably in memory with room to spare. The model is trained on TinyStories, a dataset created by Microsoft Research to explore how small a model can be while still producing grammatically correct, narratively coherent text.

For inference, I'm using llama.cpp — the same engine that powers local LLM inference on everything from phones to servers. On the Pi Zero 2's four Cortex-A53 cores, it manages roughly 100 tokens per second. Not fast by modern standards, but more than enough to generate a 200-word story in a few seconds.

## Why This Matters

A few years ago, running any kind of neural language model required a GPU and gigabytes of VRAM. Today, a model that can write coherent paragraphs runs on a board you could power with a phone charger.

The stories aren't going to win any literary awards. The model sometimes gets confused about which character is doing what, or wraps up the plot in ways that don't quite make sense. But they're *stories* — with characters, settings, problems, and resolutions. Generated entirely on-device, with no cloud API, no internet connection required, no per-token fees.

This is the leading edge of a larger trend: capable AI models are shrinking. Quantization, distillation, and architectural improvements are making it possible to run useful inference on increasingly constrained hardware. What requires a data center today might run on your phone tomorrow, and on your thermostat the day after.

## The Technical Details

The generation script is straightforward:

1. Start llama.cpp's built-in HTTP server
2. Send a completion request with a random story prompt
3. Process the output (paragraph formatting, title extraction)
4. Save as markdown, rebuild the blog
5. Kill the server to free RAM

The model stays loaded only during generation. On a device with 512MB of RAM serving a web server and handling SSH connections, memory management matters. The entire generation-and-cleanup cycle takes about 30 seconds, most of which is model loading.

## Looking Forward

We're still in the early days of local inference. The 15M model I'm running is impressive for its size, but it's a specialized tool — good at one thing (children's stories) and not much else.

The interesting question is where this goes. We're seeing capable 1-7B parameter models that can handle general tasks, running on phones and laptops. We're seeing specialized small models that excel at specific domains. We're seeing hardware vendors building dedicated inference accelerators into consumer devices.

The trajectory points toward a future where AI inference is a basic capability of computing devices, not a cloud service. Where your devices can understand and generate language locally, privately, without round-trips to a data center. Where a $15 computer can tell bedtime stories.

The Pi on my shelf is a proof of concept. The stories it generates at 3am are simple things — a frog who makes friends with a fish, a cat who plays in a garden. But they're being written by silicon, in real-time, on hardware that costs less than lunch.

That's kind of magical.

---

*Check out the [Pi Stories](/pi-stories/) section to read the daily output, or visit the [colophon](/colophon.html) to see live stats from the Pi itself.*
