# Gateway contract — protoDirector ⇄ LiteLLM (protoBanana)

The endpoint contract between protoDirector (the consumer) and our LiteLLM gateway,
whose media capabilities are served by [protoBanana](https://github.com/protoLabsAI/protoBanana)
(ComfyUI workflows as OpenAI model names). protoDirector is the primary programmatic
consumer; changes to this contract are negotiated here and in protoBanana issues
(video: [protoBanana#38](https://github.com/protoLabsAI/protoBanana/issues/38)).

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
   (`chat` | `image_generation` | `video_generation` | `audio_speech`).
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
- Default `seed` to a fresh random value when the user doesn't pin one —
  identical resubmission hits ComfyUI's execution cache and returns empty
  outputs ([protoBanana#34](https://github.com/protoLabsAI/protoBanana/issues/34)).
- Never auto-retry a flat-gray Ideogram result (built-in stochastic refusal);
  surface it and let the user reword.

## Video — PROPOSED (LTX-2, protoBanana#38 piece 2)

Adopt the OpenAI-compatible async video shape LiteLLM already defines
(docs.litellm.ai/docs/videos), so `protobanana/ltx2-*`, `sora-2`, and `veo-3`
aliases are indistinguishable to the client:

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

Known risk: if LiteLLM's `custom_provider_map` doesn't yet hook the `/videos`
routes for custom handlers, fall back to a LiteLLM passthrough route serving the
same three URLs — the client contract must not change either way.

## Audio — FUTURE

- **TTS / voiceover**: standard `/v1/audio/speech` → audio bytes.
- **Music**: same shape — `{model, input: <prompt or lyrics>, extra_body:
  {duration_s, instrumental, style}}` → audio bytes. Maps onto the editor's
  existing `AudioCaps` (lyrics, instrumental, durations).
- **Dubbing / voice isolation**: edits idiom — multipart input media +
  instruction fields; async job shape (as video) when runtime scales with input
  duration.

## Upscale — FUTURE

- Image: sync edits idiom (`image` part + upscale alias).
- Video: async video shape (submit/poll/content) — reuses the video runner.
