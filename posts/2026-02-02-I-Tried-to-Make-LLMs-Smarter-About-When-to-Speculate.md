---
title: I Tried to Make LLMs Smarter About When to Speculate. It Didn't Matter.
date: 2026-02-02
description: A shower thought, a week of experiments, and a satisfying dead end.
---

## The Setup

I've been researching ways to run large language models on limited hardware — think laptops, edge devices, or that old desktop gathering dust in your closet. One technique that helps is **speculative decoding**: instead of generating one token at a time, you *guess* multiple tokens ahead, then verify them in one batch.

There's a clever variant called **model-free speculation** that doesn't need a separate "draft" model. Instead, it looks at what the model has already generated and finds patterns. If the model just wrote "The capital of France is", and earlier in the conversation it wrote "The capital of Germany is Berlin", it might guess the next tokens will follow a similar pattern.

This actually works. On repetitive text (code, dialogue, structured documents), you can get 10-20% speedups for free.

But here's the thing: speculation doesn't always pay off. Sometimes the model is uncertain — it could go multiple directions — and your guess will be wrong. When that happens, you've wasted effort.

## The Hypothesis

I had what felt like a clever idea:

> What if we only speculate when the model is confident?

Language models output a probability distribution over possible next tokens. When the model is confident, one token dominates. When it's uncertain, the probabilities spread out. This "spread" is called **entropy** — low entropy means confident, high entropy means uncertain.

My hypothesis: **gate speculation on entropy**. Only bother guessing ahead when the model was confident on the previous token. When it's uncertain, just generate normally.

The logic seemed sound:
- Low entropy → predictable continuation → speculation likely to succeed
- High entropy → uncertain continuation → speculation likely to fail

If this worked, we could skip wasted speculation attempts and improve throughput.

## Testing It

I set up a systematic experiment pipeline. Before building anything fancy, I needed to answer some basic questions:

### Question 1: Do long acceptance chains even exist?

If speculation only ever accepts 1 token before failing, there's nothing to optimize. I measured acceptance lengths across different types of text.

**Result**: Yes, chains exist. 60% of speculation attempts accepted 5+ tokens. On dialogue, the average was 12 tokens. Good news.

### Question 2: Does entropy actually predict success?

I bucketed tokens by the previous token's entropy and measured acceptance rates.

**Result**: Yes, the correlation exists.

| Entropy Level | P(accept 5+ tokens) |
|---------------|---------------------|
| Very Low | 63.7% |
| Low | 57.1% |
| Medium | 60.0% |
| High | 30.0% |

Low entropy tokens had 2x the success rate of high entropy tokens. The signal is real.

### Question 3: Does gating improve actual throughput?

This is the only question that matters. I built three systems:
- **Baseline**: Standard generation, one token at a time
- **Always-on**: Speculate whenever possible
- **Entropy-gated**: Only speculate when entropy is low

Results on GPT-2 (CPU):

| Mode | Tokens/sec | vs Baseline |
|------|------------|-------------|
| Baseline | 10.46 | — |
| Always-on | 11.19 | +7% |
| Entropy-gated | 11.34 | +8% |

Gating added... 1.3%. Statistically negligible.

I tried TinyLlama (a bigger model where each forward pass costs more). Same story: gating was neutral.

### Question 4: What if we use a better signal?

Maybe entropy was too indirect. I tried gating on **L_pred** — the actual number of tokens we could propose. This is the direct signal: only speculate if we have a long match to propose.

| Mode | Tokens/sec | vs Always-on |
|------|------------|--------------|
| Always-on | 11.88 | — |
| L_pred ≥ 2 | 11.91 | 1.00x |
| L_pred ≥ 4 | 11.87 | 1.00x |
| L_pred ≥ 8 | 11.72 | 0.99x |

Dead flat. The direct signal didn't help either.

## Why It Failed

The hypothesis wasn't wrong — the signal exists. Low entropy really does predict better speculation outcomes. But the **economics** don't work out.

Here's what actually happens on CPU:

- **Lookup cost**: ~20 microseconds
- **Forward pass cost**: ~100-700 milliseconds (depending on model size)

The lookup is essentially free. And when speculation fails? You've done one forward pass and accepted one token — exactly what baseline would have done anyway.

**There's nothing to save by skipping speculation.**

The waste in always-on speculation isn't from "mis-triggering." It's from the fundamental limit of how many tokens get accepted. Gating solves a problem that doesn't exist.

## What I Learned

**1. Always-on speculation is already near-optimal**

For model-free speculation on CPU, just do it every time. The overhead of failed attempts is negligible. You get 8-20% speedup on repetitive workloads with zero cleverness required.

**2. Signals can be real but useless**

Entropy genuinely predicts speculation success. But predicting success isn't valuable when failure is cheap. When speculation fails, the system ends up doing almost exactly the same work it would have done anyway. This is a good reminder that statistical significance isn't the same as practical significance.

**3. Dead ends are data**

This took a week of experiments. The hypothesis was reasonable, the methodology was sound, and the answer was "no." That's not failure — it's one less thing the next researcher needs to try.

## The Takeaway

If you're running LLMs on CPU and want free speedup:
- Let the model reuse patterns it’s already written
- Always speculate when you have a match
- Don’t add fancy logic to decide when to try — it’s usually not worth it

The simple approach wins because the problem it solves (wasted speculation) isn't actually a problem.

Sometimes the clever optimization is no optimization at all.