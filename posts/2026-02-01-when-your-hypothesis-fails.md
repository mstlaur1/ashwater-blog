---
title: When Your Hypothesis Fails: A Journey to 2x Faster Edge LLM Inference 
date: 2026-02-01
description: I wanted to run a 7B parameter language model on a Raspberry Pi Zero.
The numbers don’t add up at first glance: - LLaMA-7B: ~3.5GB (INT4 quantized) - Pi Zero RAM: 512MB - Gap: 7x too large
But what if we didn’t need to fit the whole model in memory?
---

## The Dream: Running a 7B Model on a $15 Computer

I wanted to run a 7B parameter language model on a Raspberry Pi Zero.

The numbers don't add up at first glance:
- **LLaMA-7B:** ~3.5GB (INT4 quantized)
- **Pi Zero RAM:** 512MB
- **Gap:** 7x too large

But what if we didn't need to fit the whole model in memory? What if we could predict which parts of the model we'd need and preload them from storage while computing with what we have?

That was the hypothesis. Here's what actually happened.

---

## Chapter 1: The Beautiful Theory That Didn't Work

### The Original Idea

Transformer language models process text through dozens of layers, each transforming the input representation. I noticed something interesting when I measured how similar these representations are across different inputs:

**Activations cluster tightly.** When you run 400 different prompts through GPT-2, the hidden states at each layer show 78-95% cosine similarity. The pattern forms a distinctive U-curve:

```
Similarity
   ^
0.95|         ****
    |        *    *
0.90|       *
    |      *
0.85|     *
    |    *
0.80| ***
    |________________> Layer
      0  2  4  6  8  10  11
```

Early layers: generic encoding (high similarity)
Middle layers: task-specific reasoning (lower similarity)
Late layers: converging toward output vocabulary (highest similarity)

The clustering suggested a shortcut: **What if we could cache cluster centroids and splice them into the forward pass, skipping the actual computation?**

### The Crash

I implemented it. The results were catastrophic.

| Layer | KL Divergence | Top-1 Token Match |
|-------|---------------|-------------------|
| 3     | 5.65          | 26%               |
| 5     | 5.92          | 24%               |
| 7     | 5.23          | 20%               |
| 9     | 5.94          | 34%               |

A KL divergence of 5+ is disaster territory. You need <0.1 for safe substitution. The model's outputs were completely wrong.

**Similarity doesn't mean substitutability.**

Why? Transformers amplify small differences exponentially:
1. Layer normalization rescales activations, amplifying relative differences
2. Attention converts tiny key/query differences into large weight changes
3. Residual connections accumulate errors across layers
4. Softmax exponentially amplifies the output distribution

Even a 5% difference in activation values can snowball into complete gibberish by the output layer.

This finding aligned with [Lawson & Aitchison's June 2025 paper](https://arxiv.org/abs/2506.21103) which tried learning to skip middle layers dynamically. Their conclusion: "our approach does not achieve improvements in the trade-off between validation cross-entropy and estimated FLOPs."

**First lesson learned: You can see where the computation is going without being able to shortcut getting there.**

---

## Chapter 2: What If We Just... Predict?

The substitution approach failed, but I noticed something else in the data: **early layers are highly predictive of late-layer patterns.**

I trained a simple MLP to predict which cluster an activation would belong to at layer 6, using only the activation from layer 2:

| Predictor → Target | Accuracy |
|--------------------|----------|
| L2 → L6            | 94.6%    |
| L3 → L6            | 93.8%    |
| L2 → L8            | 87.5%    |
| L2 → L10           | 90.0%    |

This works across domains:

| Domain    | L2 → L6 Accuracy |
|-----------|------------------|
| Code      | 100%*            |
| Knowledge | 98.7%            |
| General   | 90.2%            |
| Medical   | 87.5%            |

*The 100% code accuracy is suspicious—likely an artifact of all code prompts starting with "Write Python code to:". The general domain numbers are more trustworthy.

### The I/O Hiding Idea

If we can predict what patterns will occur at later layers, we can speculatively preload the weights we'll need from the SD card while computing with current weights.

For a Pi Zero running a 7B model:
- **Layer size:** ~110MB
- **SD card speed:** 60 MB/s
- **I/O time per layer:** 1.8 seconds
- **Compute time per layer:** ~2.5 seconds

If we predict at layer 2 what we'll need at layer 6, we get 4 layers × 2.5 seconds = 10 seconds of compute time to preload future weights.

### The Disappointment

I ran the simulation. The speedup was... underwhelming.

| Scenario    | Speedup |
|-------------|---------|
| Pessimistic | 1.04x   |
| Realistic   | 1.06x   |
| Optimistic  | 1.07x   |

Why so small? The prediction window is too short. Predicting from L2 to L6 gives you 4 layers of compute time—enough to preload maybe 5-6 layers. But a 7B model has 32 layers. You still need to load the other 26 layers sequentially.

**Second lesson learned: A single prediction point isn't enough.**

---

## Chapter 3: The Breakthrough—Cascaded Prediction

Then it clicked.

What if we don't just predict once, but predict at multiple checkpoints?

```
Single-shot:              Cascaded:
L0 ────────→ L6           L0 → L6 → L12 → L18 → L24 → L30
   (1 window)                (5 windows, additive preload)
```

Each prediction uses the *actual* activation at that checkpoint, not a predicted one. This is crucial—prediction errors don't compound multiplicatively.

I validated this on Mistral-7B with 4,000 samples:

| Stage     | Overall Accuracy |
|-----------|------------------|
| L0 → L6   | 84.6%            |
| L6 → L12  | 92.1%            |
| L12 → L18 | 92.5%            |
| L18 → L24 | 93.4%            |
| L24 → L30 | 90.0%            |

The I/O overlap ratio changes dramatically:

| Scenario    | Single-Shot | Cascaded | Speedup |
|-------------|-------------|----------|---------|
| Pessimistic | 6.8%        | 57.9%    | **1.52x** |
| Realistic   | 13.6%       | 115.7%   | **1.96x** |
| Optimistic  | 16.3%       | 138.9%   | **2.11x** |

An overlap ratio >100% means we're preloading faster than we're consuming. **The system becomes compute-bound instead of I/O-bound.**

### Why This Works

The key insight is that multiple prediction windows are additive, not multiplicative:

```
L0 → L6:   Preload 6 layers during compute
L6 → L12:  Preload 6 more layers during compute
L12 → L18: Preload 6 more layers during compute
L18 → L24: Preload 6 more layers during compute
L24 → L30: Preload 6 more layers during compute

Total preload opportunities: 5 × 6 = 30 layers
32-layer model: Can hide nearly ALL I/O
```

What about mispredictions? I ran a Monte Carlo simulation with 10,000 samples:
- **63% of inputs:** Zero mispredictions (all stages correct)
- **27% of inputs:** One misprediction (one I/O stall)
- **10% of inputs:** Two or more mispredictions
- **Average cost:** 0.44 stage-stalls per input

A misprediction costs one stage of I/O stall, not a full model reload. The math still works out.

---

## Chapter 4: Does It Actually Work? (Hardware Validation)

Simulations are nice. Reality is better.

### Real Tensor Operations

I implemented a streaming inference benchmark with actual FP16 matrix multiplications—not simulated delays:

| I/O Speed | Naive tok/s | Cascaded tok/s | Speedup |
|-----------|-------------|----------------|---------|
| 25 MB/s   | 0.05        | 0.09           | **1.94x** |
| 60 MB/s   | 0.11        | 0.21           | **1.85x** |
| 90 MB/s   | 0.16        | 0.29           | **1.82x** |

**Consistent 1.8-2x speedup across all I/O speeds with real matrix operations.**

Slower storage = more overlap opportunity = higher speedup. The 50% cache hit rate matched predictions.

### The Negative Result You Should Know About

I also tested whether cascaded prefetching helps when the model fits in RAM but is limited by memory bandwidth (DDR4 RAM → CPU cache).

**It doesn't. It makes things worse.**

| Strategy          | Time (ms) | Speedup |
|-------------------|-----------|---------|
| Baseline          | 6879      | 1.00x   |
| Inline prefetch   | 7878      | **0.87x** |
| Threaded prefetch | 7672      | 0.90x   |
| Cascaded prefetch | 7771      | 0.89x   |

All prefetching strategies degraded performance by 10-13%.

Why? Modern CPUs have sophisticated hardware prefetchers that automatically detect sequential memory access. Software prefetch instructions compete with rather than complement this. Plus, the L3 cache (~8-32MB) can't hold a full layer (~110MB), so prefetched data gets evicted before use.

**Third lesson learned: Know your bottleneck.** Cascaded prediction helps I/O-bound systems (storage → RAM). It hurts memory-bandwidth-bound systems (RAM → cache).

---

## What We Actually Learned

### The Prediction-Substitutability Gap

| Operation | Accuracy | Viable? |
|-----------|----------|---------|
| Predict cluster from early layers | 87-95% | Yes |
| Substitute centroid for activation | <35% | No |
| Single-shot I/O hiding | 1.04-1.07x | Marginal |
| **Cascaded I/O hiding** | **1.52-2.11x** | **Yes** |

### The Boundary Conditions

| System Type | Bottleneck | Cascaded Prediction Works? |
|-------------|------------|----------------------------|
| SD card → RAM | I/O bandwidth | **Yes** (1.25-2x speedup) |
| RAM → CPU cache | Memory bandwidth | **No** (10-13% slower) |
| GPU VRAM → SM | Memory bandwidth | Likely no |

### The Transformer U-Curve

This one is interesting for interpretability folks: activations form a U-curve across layer depth. Early layers are similar (generic encoding), middle layers diverge (task-specific reasoning), late layers converge again (projecting to shared vocabulary).

This is the opposite of CNNs, where early layers are generic and late layers are task-specific. The difference? LLMs project to a shared 50K+ token vocabulary (convergent), while CNNs project to task-specific classes (divergent).

---

## Can We Actually Run 7B on a Pi Zero?

With ~1.5-2x speedup, inference shifts from I/O-bound toward compute-bound. Estimated performance:

- **Without cascaded prediction:** ~0.02 tok/s
- **With cascaded prediction:** ~0.04-0.06 tok/s

That's... slow. But potentially usable for offline batch processing. One token every 15-25 seconds means generating a 100-token response takes 25-40 minutes. Not great for chat, but maybe viable for:
- Overnight document summarization
- Batch classification tasks
- Offline email drafting

The engineering challenge remaining: actually implementing the memory-mapped streaming layer inference on the Pi. The prediction infrastructure adds minimal overhead (0.53ms per checkpoint vs ~164ms per layer compute).

---

## The Takeaways

1. **High similarity ≠ substitutability.** Transformers amplify small differences exponentially. Don't skip layers just because they look similar.

2. **Single predictions have short horizons.** Predicting 4 layers ahead isn't enough to hide I/O for a 32-layer model.

3. **Cascade your predictions.** Multiple checkpoints create additive (not multiplicative) preload windows.

4. **Know your bottleneck.** This technique helps I/O-bound systems, hurts memory-bandwidth-bound systems.

5. **Negative results are results.** The DDR4 prefetching failure saved others from going down that path.

---

## What's Next

If someone wants to push this further:

1. **Full Pi Zero implementation** with memory-mapped weights and quantized inference runtime
2. **Prefix-stripped validation** to verify domain accuracy without format artifacts
3. **MoE integration**—cascaded prediction could predict expert routing
4. **Adaptive scheduling** based on prediction confidence

The code is at [github.com/mstlaur1/activation-memoization](https://github.com/mstlaur1/activation-memoization).

---

*This started as a failed hypothesis about activation substitution and ended with a practical technique for edge inference. Sometimes the detours are where you find the good stuff.*