# Gateway contract — protoDirector ⇄ LiteLLM (protoBanana)

The endpoint contract between protoDirector (the consumer) and our LiteLLM gateway,
whose media capabilities are served by [protoBanana](https://github.com/protoLabsAI/protoBanana)
(ComfyUI workflows as OpenAI model names). protoDirector is the primary programmatic
consumer; changes to this contract are negotiated here and in backend issues
(video: [protoBanana#38](https://github.com/protoLabsAI/protoBanana/issues/38);
audio: [protoLab#22](https://github.com/protoLabsAI/protoLab/issues/22)).

Companion implementation plan: [GENERATION_GATEWAY_PLAN.md](GENERATION_GATEWAY_PLAN.md).

## Principles

1. **OpenAI shape where one exists** (`/images/generations`, `/images/edits`,
   `/videos`, `/audio/speech`, `/chat/completions`). LiteLLM routes them natively;
   every OpenAI client works unchanged.
2. **The edits idiom where none exists**: multipart with op-specific extra form
   fields (protoBanana's established pattern — `grounding`, `person_image`, margins).
3. **Model aliases are configuration**, not code. protoDirector ships alias
   settings with `protolabs/*` defaults; swapping models is a gateway-config edit.
4. **Discovery via `/model/info`**: `model_name` + `model_info.mode`
   (`chat` | `image_generation` | `video_generation` | `music_generation` |
   `audio_speech`).
   Capability caps (durations, sizes) are client-side per alias family until the
   gateway can publish them.

## Shared transport

- One base URL + API key for chat *and* generation (`GatewayConfig` /
  `GatewayKeychain`). Loopback gateways need no key.
- All media rides through the gateway; clients never contact backends directly.
- Request timeout ≥ 300 s (ComfyUI queues); per-op overrides allowed.
- Errors: OpenAI error JSON `{error: {message}}`; messages must be human-readable
  (they surface verbatim in the editor's agent chat).

## Images — SHIPPED (protoBanana Phases 1–7)

### `POST /v1/images/generations` (JSON, sync)
`model`, `prompt`, `size` ("WxH"), `n` (parallel), `response_format: "b64_json"`
(**only** supported value — the gateway does not host results), `seed`,
`negative_prompt`. Response: `{data: [{b64_json}]}`.

### `POST /v1/images/edits` (multipart, sync)
Parts: `image` (required), `mask` (optional). Fields: `model`, `prompt`,
`response_format`, `seed`, plus per-op extras:

| Op (alias family) | Extra fields |
|---|---|
| instruction edit (`qwen-image-edit`) | — |
| region edit (`qwen-image-region-edit`) | `grounding` (text → SAM 3 mask) |
| identity edit (`krea2-identity-edit[-realism]`) | `grounding_px` (512–1536), `person_image` (data URL; **image = scene, person_image = person**) |
| background removal (`qwen-image-bgremove`) | — (returns transparency) |
| outpaint (`qwen-image-outpaint`) | `left`/`top`/`right`/`bottom` px margins |

### `POST /v1/chat/completions` on the chat alias (sync)
The only channel accepting 2–3 reference images (multi-ref compose). Images as
`image_url` data-URL parts; response is a markdown-embedded
`data:image/png;base64,...` in `message.content`.

### Client obligations (images)
- Downscale any multipart part to **≤ 1 MB** before sending (gateway form-part cap).
- Transitional: default `seed` to a fresh random value when the user doesn't
  pin one — identical resubmission hits ComfyUI's execution cache and returns
  empty outputs ([protoBanana#34](https://github.com/protoLabsAI/protoBanana/issues/34)).
  [protoBanana#39](https://github.com/protoLabsAI/protoBanana/pull/39) moves this
  server-side (per-submission nonce); once deployed, this obligation is void
  (the random default is harmless and may remain).
- Never auto-retry a flat-gray Ideogram result (built-in stochastic refusal);
  surface it and let the user reword.

## Video — AGREED (protoBanana#38, 2026-07-13)

The OpenAI-compatible async video shape, confirmed by the lab side. Server-side
it is implemented by a standalone **video bridge** co-located with ComfyUI on
protolabs (LiteLLM 1.83.14 cannot host it: no CustomLLM video hook, and the
native /v1/videos router shadows passthrough while whitelisting only hosted
providers). The edge proxy routes `/v1/videos*` to the bridge — same base URL,
same key, so `protobanana/ltx2-*` and future hosted `sora-2`/`veo-*` aliases
stay indistinguishable to the client:

```
POST /v1/videos            {model, prompt, seconds: "8", size: "1216x704"}
                           + optional multipart `input_reference` (first frame)
                           + extra_body: {seed, negative_prompt, fps, ...}
                           → {id, status: "queued"}
GET  /v1/videos/{id}       → {id, status: queued|in_progress|completed|failed,
                              error?: {message}, progress?: 0–100}
GET  /v1/videos/{id}/content → video bytes (mp4)
```

Consumer requirements that motivate this shape (vs. base64-in-chat):

- **Stable job id** — the editor persists it and resumes polling after an app
  restart; generation placeholders survive quits.
- **Bytes download, not chat markdown** — clips go straight into the project's
  media store; a 100 MB clip as a base64 data URL in a chat message is a
  non-starter for the editor path. (A chat-alias preview for Open WebUI can
  coexist; it's a different consumer.)
- **`input_reference`** — the editor sends a start frame for image-to-video
  (LTX-2 supports first-frame conditioning).
- **`progress`** (optional but valuable) — drives the placeholder progress UI.
- **Model-agnostic params** — anything LTX-specific (fps, guidance, upscaler
  pass) rides `extra_body`, so third-party video aliases keep working.

Resolved risk (was: custom_provider_map may not hook /videos): verified it
cannot, hence the bridge. The client contract is unchanged either way.

**Video client obligation: do NOT randomize seeds.** Cache-busting is
server-side from the start on the video path (the protoBanana#39 nonce
mechanism); a client seed is only ever an explicit user pin.

## Audio — PROPOSED ([protoLab#22](https://github.com/protoLabsAI/protoLab/issues/22), 2026-07-13)

Music generation via **ACE-Step 1.5/XL** (MIT, ComfyUI-native — see
[AUDIO_DUBBING_RESEARCH.md](AUDIO_DUBBING_RESEARCH.md)) plus its edit family. TTS
reuses OpenAI's native `/v1/audio/speech`. *Where* and *how* this is served —
protoBanana ComfyUI workflow vs. a standalone ACE-Step service, and sync vs.
async — is being settled with protoLab; the client contract below is independent
of both, exactly as the video contract preceded the bridge.

**Sync vs async — OPEN.** The sync shape below is the *target*: ACE-Step runs at
~real-time on the RTX PRO 6000, so bytes-in-one-call is viable (unlike video).
But the request fields are identical either way — if protoLab serves it async
(long-form batching, a shared ComfyUI queue, or just preferring the uniform job
pattern), the same `(model, prompt, lyrics, seconds, seed, …)` moves onto the
async `/v1/videos`-style **submit → poll → content** envelope and reuses the
video runner. The client is built request-first so only the response handler
differs; picking sync or async is a protoLab call, not a re-contract.

### `POST /v1/audio/generations` (JSON, sync)
`model`, `prompt` (style / genre / mood), `lyrics` (optional; `[Verse]` /
`[Chorus]` tags), `instrumental` (bool), `seconds` (target length), `n`
(variations), `seed`, `negative_prompt`, `response_format: "b64_json"` (gateway
does not host results), `format` ("mp3" | "wav" | "flac"). Response:
`{data: [{b64_json, seed, duration_s}], format}`. Maps directly onto the editor's
existing `AudioGenerationParams` (prompt, lyrics, instrumental, durationSeconds).

Variation / retake is this endpoint with a fresh `seed` (or `n > 1`) — not a
separate op.

**Fidelity tier** — optional `dit`: `"turbo"` (default, fast) | `"sft"` (higher
fidelity, ~2× slower). Tier-aware server defaults (turbo: 8 steps / no CFG /
shift 3.0; sft: 50 steps / CFG 6.0 / shift 2.0) apply automatically; optional
`steps` / `guidance` / `shift` override them. Response echoes `dit`; `dit: "sft"`
returns 503 rather than silently downgrading if the tier isn't loaded.
`/model/info` advertises `dit_tiers` + per-tier `defaults` (protoLab#22). The
client exposes this as the agent's `quality` selector (`standard` → turbo,
`high` → sft); raw `steps`/`guidance`/`shift` are not yet surfaced.

### `POST /v1/audio/edits` (multipart, sync)
Parts: `audio` (required input clip), optional `reference_audio` (voice / style
transfer). Fields: `model`, `prompt`, `lyrics`, `seed`, plus per-op extras:

| Op (alias family) | Extra fields |
|---|---|
| extend / continue (`ace-step-extend`) | `seconds` = target total length; `direction` ("append" \| "prepend") |
| section repaint (`ace-step-repaint`) | `start_s`, `end_s` (region to regenerate), `variance` (0–1) |
| lyric / style edit (`ace-step-edit`) | new `lyrics` / `prompt`, `edit_strength` (0–1) |

Response: the same `{data: [{b64_json, ...}]}` shape.

### TTS — `POST /v1/audio/speech` (OpenAI-native, sync)
`model`, `input` (text to speak), `voice`, `response_format` → audio bytes.
Voice-clone TTS (TTS-Audio-Suite engines) rides the same endpoint with a
`reference_audio` extra field once exposed. No license gate — local experiments.

### Dubbing / lip-sync — async job (as video) when it lands
Multi-stage (ASR on-device → translate via a gateway LLM → voice-clone TTS →
optional LatentSync). Runtime scales with input duration, so this one takes the
async `/v1/videos`-style submit / poll / content shape, **not** sync. Out of the
first pass; tracked with protoLab separately.

### Discovery
`/model/info` `mode` gains `music_generation` (covers `/audio/generations` +
`/audio/edits`) alongside the existing `audio_speech`. Client caps (durations,
formats, voices) stay per-alias until the gateway publishes them.

### Client obligations (audio)
- **Cache-bust like the image/video path**: ACE-Step runs in ComfyUI, so an
  identical `(model, prompt, lyrics, seconds, seed)` hits the execution cache
  ([protoBanana#34](https://github.com/protoLabsAI/protoBanana/issues/34)).
  Server-side per-submission nonce is preferred (the protoBanana#39 pattern);
  until then the client defaults `seed` to a fresh random unless the user pins
  one — the same transitional rule as images.
- **Form-part cap — OPEN**: the image path caps multipart parts at 1 MB, but an
  input clip for `/audio/edits` routinely exceeds that (a 2-min WAV ≈ 20 MB). The
  audio-edits path needs a larger part cap or a different upload channel — to
  settle with protoLab.
- **b64 response bound**: base64-in-JSON is fine for the coherent-length target
  (≤ ~5 min); if long-form music ever needs 50 MB+ payloads, that alias moves to
  the async bytes-download shape (as video), not sync JSON.

## Upscale — FUTURE

- Image: sync edits idiom (`image` part + upscale alias).
- Video: async video shape (submit/poll/content) — reuses the video runner.
