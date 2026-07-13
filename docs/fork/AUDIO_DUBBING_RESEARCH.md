# Self-hosted music & dubbing — research + recommended gateway aliases

Actionable basis for new protoBanana/gateway model aliases (Phase 4 of
[GENERATION_GATEWAY_PLAN.md](GENERATION_GATEWAY_PLAN.md)). Researched mid-2026;
findings adversarially verified. Serving maps onto the same async-job bridge
pattern as the video path ([GATEWAY_CONTRACT.md](GATEWAY_CONTRACT.md)).

Fleet assumed: RTX PRO 6000 Blackwell (sm120/cu130) + A6000 Ampere (48 GB).
We already have: on-device Whisper-class ASR in the editor; gateway chat LLMs
(`protolabs/fast` etc.); `fish-s2-pro` TTS.

## TL;DR recommendations

| | Primary | Fallback | Serve as |
|---|---|---|---|
| **Music** | **ACE-Step 1.5** (MIT, commercial-OK) | Stable Audio 3.0 open weights (Community License) | sync where possible on Blackwell; else async job |
| **Dubbing** | ComfyUI graph: **TTS-Audio-Suite** (voice-clone TTS + subtitle timing + ASR) **+ LatentSync 1.6** (lip-sync, Apache-2.0) | swap the TTS engine per license needs | async job (multi-stage, slow) |

**The dubbing translation step needs no new model** — reuse the gateway's own
LLMs; ASR is already on-device. The only genuinely new pieces are voice-clone
TTS and optional lip-sync.

**The one hard problem is voice-cloning licensing** — the best-quality cloners
are non-commercial (see below). For personal/internal use anything goes; for a
commercial product the field narrows sharply.

## Music

### ACE-Step (recommended primary)
- **License: commercial-OK.** ACE-Step v1 (3.5B) is Apache-2.0; ACE-Step 1.5 /
  XL (4B) is MIT, trained on licensed/royalty-free/synthetic data. This is the
  differentiator vs. the non-commercial pack below.
- **Fast enough to serve sync on our hardware.** ~1 s for a 4-min song on an
  RTX 5090 (Blackwell class), <2 s on A100, <10 s on RTX 3090; distilled variant
  ~1 s for 240 s of audio on A100. Real-time factor ~34× on a 4090. → On the
  RTX PRO 6000 this is effectively real-time; a synchronous bytes response is
  viable, unlike video.
- **Duration:** nominal up to 10 min; clean single-pass ~90–120 s, longer via
  batching (coherence degrades past ~5 min).
- **VRAM:** tiny — runs in <4–8 GB (v1 3.5B); XL 4B wants ≥20 GB, ≥24 GB for
  no-offload. Fits both GPUs with headroom.
- **Quality:** 1.5 XL rated between Suno v4.5 and v5; leads open models on
  AudioBox CU/PQ; still trails commercial Suno on style/lyric alignment. A
  "metallic shimmer" artifact is noted.
- **ComfyUI:** native/first-party — Template Library audio workflow, core nodes
  (`EmptyAceStepLatentAudio`, Text2music params). Note the *separate*
  `ACE-Step-ComfyUI` node pack is early (~12 commits) and its `Text2music Server`
  node talks to a local inference server on :8002 — which maps cleanly onto a
  service-bridge, same as our video bridge.
- **Languages:** 50+ (v1: 17), lyrics-driven, 1000+ styles, LoRA fine-tune.

### Stable Audio 3.0 (fallback / sound-design)
- **License: commercial-OK under the Stability Community License** — you own
  outputs and may commercialize; paid Enterprise only above $1M revenue.
  Trained on fully-licensed data (legal-risk differentiator).
- Open weights: Small SFX, Small, Medium (Large is API-only). Long-form: Small
  ≤2 min, Medium/Large >6 min.
- **ComfyUI support is announced but unconfirmed as shipped** (this claim was
  refuted in verification — treat as planned, verify before relying on it).
  Better suited to SFX/textural beds than full songs.

### Avoid for commercial use
- **MusicGen** — CC-BY-NC 4.0 (non-commercial).
- **LeVo 2** — highest quality in one survey but Tencent non-commercial license.
- **YuE** — Apache-2.0 (commercial-OK) and good for lyric-driven full songs, but
  ~12× slower than real-time on a 4090 (→ async only), and full songs need
  80 GB+ VRAM (truncated 2-session mode fits 24 GB; tight even on the PRO 6000).
  ComfyUI support via community forks only — not first-party. Keep as a distant
  option behind ACE-Step.

## Dubbing (a pipeline, not one model)

Stages and where each runs:

| Stage | Recommendation | Runs in ComfyUI? |
|---|---|---|
| ASR | already on-device (Whisper); or Qwen3-ASR / Granite in TTS-Audio-Suite | yes (suite) |
| Translation | **reuse gateway LLMs** (`protolabs/fast`); or M2M-100 / NLLB-200 | no — gateway call |
| Voice-clone TTS | **TTS-Audio-Suite** (17 engines: F5-TTS, IndexTTS-2, CosyVoice3, Higgs, VibeVoice, Fish S2 Pro, RVC) | yes |
| Subtitle/temporal align | TTS-Audio-Suite SRT-aware nodes (smart timing, overlap-safe, emits real audio timings) | yes |
| Lip-sync (optional) | **LatentSync 1.6** (`ComfyUI-LatentSyncWrapper`) | yes |

**TTS-Audio-Suite (v5.4.5)** is the key find: one ComfyUI node pack collapses
ASR → punctuation → Text-to-SRT, 17 TTS/voice-conversion engines, and
subtitle-timed TTS into a single graph — so most of the dub pipeline is
ComfyUI-native, not a bespoke service. Only translation sits outside (and we
already have LLMs for it).

**LatentSync 1.6** (ByteDance) is Apache-2.0, a mature ComfyUI node, ~20 GB VRAM
(fits both GPUs), trained at 512×512 / 25 fps — best ComfyUI-native lip-sync.
Alternatives: Wav2Lip, MuseTalk (real-time, >30 fps).

### Voice-cloning licensing — the real constraint
Best-quality cloners are **non-commercial**:
- **XTTS v2** — Coqui CPML non-commercial; Coqui shut down Jan 2024, so no
  commercial license is even purchasable. Treat as non-commercial only.
- **F5-TTS** — CC-BY-NC 4.0 (the *ComfyUI node* is MIT, but the weights are NC).
- **`fish-s2-pro`, which we already expose** — Fish Audio Research License
  (per this research, non-commercial). **Vet before any commercial ship.**
- TTS-Audio-Suite's own code is MIT, but each bundled engine keeps its license
  (Echo-TTS is CC-BY-NC-SA, etc.) — must be vetted per engine.

Commercial-safe options that *don't* clone: StyleTTS 2 (MIT, ~4.3 MOS, 2–4 GB),
Piper (MIT), Kokoro (Apache-2.0). Commercial-safe that *do* clone: Tortoise
(Apache-2.0, but very slow); CosyVoice3 / Qwen3-TTS / IndexTTS-2 clone from
3–30 s of reference and have ComfyUI nodes — **licenses to be verified per
engine**, and these are the ones to check first for a commercial path.

**Consent caveat:** none of these nodes ship consent/rights safeguards; the
integrating layer (us) must add them. Voice cloning from a speaker's audio
should be gated on explicit consent in-product.

## Serving contract mapping

Verified LiteLLM facts that shape this:
- **No native audio-generation endpoint** in LiteLLM's `custom_provider_map`
  (only chat/completions/embeddings/images). So audio/music/dubbing **cannot**
  be a clean custom-provider model — it rides a **pass-through route**, exactly
  like the video bridge.
- **`pass_through_endpoints`** forward arbitrary methods to a backend (GET+POST
  through one route with `include_subpath: true` for `/jobs/{id}/status` +
  `/content`), inject gateway auth, default 600 s timeout (configurable). This
  is the same mechanism the video edge route uses.

Therefore, both new capabilities reuse the **video bridge shape**:

```
POST /v1/audio            {model, prompt|lyrics, seconds, extra_body:{...}} -> {id, status}
GET  /v1/audio/{id}       -> {id, status, progress, error?}
GET  /v1/audio/{id}/content -> audio bytes (audio/mpeg | audio/wav)

POST /v1/dubs             multipart: source video + {target_language, voice_ref?, lipsync?} -> {id, status}
GET  /v1/dubs/{id}        -> {id, status, progress, error?}
GET  /v1/dubs/{id}/content -> mp4/audio bytes
```

- **Music**: ACE-Step on Blackwell is fast enough that a **sync** bytes response
  is defensible — but adopting the async job shape keeps one client pattern
  across image/video/audio. Recommend async for uniformity, sync as an
  optimization later.
- **Dubbing**: inherently multi-stage and slow (lip-sync is the heavy stage,
  ~20–30 GB) → **async job, no question.**

protoDirector already has the async-job client (video runner) — a `/v1/audio`
and `/v1/dubs` alias would reuse `GatewayGenerationRunner`'s poll loop nearly
verbatim, differing only in the create payload and the output content-type.

## Concrete asks for the protoBanana / infra team

1. **`protolabs/ace-step` music alias** — ACE-Step 1.5 workflow JSON (MIT),
   served via the bridge pattern. Injection map: `prompt`/`lyrics`, `seconds`,
   `seed`, `language`. Fastest win, cleanest license.
2. **`protolabs/dub` pipeline alias** — TTS-Audio-Suite graph (ASR→translate→
   clone-TTS→SRT-align) + optional LatentSync, behind an async `/v1/dubs` route.
   Translation node calls back into the gateway LLMs.
3. **License decision on the TTS engine** — pick the voice-clone engine by
   commercial intent: CosyVoice3 / IndexTTS-2 / Qwen3-TTS to be vetted for a
   commercial path; XTTS/F5-TTS/fish-s2-pro are personal/internal only. This is
   a go/no-go the team should make explicitly, not inherit by default.
4. **Confirm `fish-s2-pro`'s license** before it's used in any shipped feature.

## Sources
ACE-Step: github.com/ace-step/ACE-Step-1.5, huggingface.co/ACE-Step/ACE-Step-v1-3.5B,
blog.comfy.org/p/ace-step-15-*, docs.comfy.org/tutorials/audio/ace-step,
github.com/ace-step/ACE-Step-ComfyUI. Stable Audio:
stability.ai/news-updates/meet-stable-audio-3. Dubbing: github.com/diodiogod/TTS-Audio-Suite,
github.com/ShmuelRonen/ComfyUI-LatentSyncWrapper, github.com/niknah/ComfyUI-F5-TTS,
union.ai open-source-video-dubbing blog, videodubbing.com/blog best-open-source-2026.
Serving: docs.litellm.ai/docs/providers/custom_llm_server,
docs.litellm.ai/docs/proxy/pass_through, github.com/SaladTechnologies/comfyui-api.
