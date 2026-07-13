# Plan: generation via the LiteLLM gateway (protoBanana)

Supersedes the "Change 2 / Change 4" sketches in [AI_ARCHITECTURE.md](AI_ARCHITECTURE.md).
Wire protocol lives in [GATEWAY_CONTRACT.md](GATEWAY_CONTRACT.md). Status 2026-07-12.

With protoBanana as the gateway's media provider (images shipped; LTX-2 video next
— protoBanana#38; music/dubbing on the roadmap), the gateway is the **primary**
generation backend for this fork. The hosted Convex path stays functional but is
legacy: no new gateway checks get scattered through it.

## Architecture: one runner, few seams

No `GenerationTransport` protocol extraction — upstream actively rewrites
`GenerationService`/`ToolExecutor` and a threaded seam would bleed at every merge.
Instead, everything gateway-side concentrates in one new file:

**`Generation/GatewayGenerationRunner.swift`** — owns all gateway calls
(sync image jobs, edits-suite jobs, async video jobs incl. poll/resume) and feeds
results to the existing `finalizeSuccess` (which already handles local file URLs).

Seams into upstream code (kept minimal, all already exist or are one-line):

1. `GenerationService.runJob` — single early intercept: gateway claims the params
   or the Convex path proceeds (exists for image; extend to video/audio).
2. `GenerationService.prepareReferences` — gateway route keeps preprocessed
   *local* file URLs (no Convex upload).
3. `ToolExecutor.canGenerate` (static, post-0.6.5) — already gateway-aware.
4. `EditSubmitter` — future: upscale/audio-transform route through the same
   runner when protoBanana grows those ops. Until then they stay hosted-gated.

## Phase 1a — image transport completion (now)

`OpenAICompatGenerationClient` grows the two missing call shapes (port of
protobanana-plugin `client.py`):

- `editImage(model:prompt:image:mask:fields:)` — multipart `/images/edits`,
  op-specific extra fields as strings.
- `chatCompose(model:prompt:images:)` — chat alias, extract markdown data URL.
- Shared: multipart encoder, ≤ 1 MB reference downscale (CoreGraphics),
  300 s request timeout, random default `seed` (ComfyUI cache — protoBanana#34),
  `negative_prompt` passthrough.

Routing in `generateImageViaGateway`: 0 refs → generations; 1 ref (± mask) →
edits; 2–3 refs → compose; > 3 refs → clear tool error. This **fixes the current
silent reference drop**.

Tests: multipart encoding golden, data-URL extraction, downscale boundary,
routing table; extend existing `OpenAICompatGenerationTests`.

## Phase 1b — the editing suite as agent tools (now)

New tools in `ToolDefinitions`/`ToolExecutor+Generate`, mirroring the
protobanana-plugin surface, results landing as image assets through the existing
placeholder pipeline:

| Tool | Route | Editor value |
|---|---|---|
| `edit_image` | edits | instruction edits on stills/frames |
| `region_edit` | edits + `grounding` | "change the sign text", keep the rest |
| `remove_background` | edits (bgremove) | transparent overlays for the timeline |
| `outpaint_image` | edits + margins | reframe 16:9 stills for 9:16 cuts |
| `identity_edit` | edits + `person_image` | face-preserving edits |
| `compose_images` | chat compose | 2–3-ref combination |
| typography | generations (ideogram alias) | title cards that can spell |

Aliases become settings (gen / turbo / edit / region / bgremove / outpaint /
identity / realism-identity / typography / chat) with `protolabs/*` defaults —
stored beside `GatewayConfig`, surfaced in the Settings gateway pane.
Tool descriptions lift the plugin's operational notes verbatim where they're
load-bearing (identity ref ordering, `grounding_px` tradeoff, Ideogram refusal).

## Phase 2 — catalog + in-app UI

`ModelCatalog` gains a gateway population path so the in-app generation UI
(model pickers, AIEditMenu) works without Convex — today only agent tools do:

- protoBanana aliases: bundled `CatalogEntry` caps keyed by the alias settings
  (semantics are known; `/model/info` just confirms presence).
- Third-party aliases: synthesize conservative entries from `/model/info`
  `mode` (+ a small caps table for sora/veo families).

## Phase 3 — video runner (contract AGREED per protoBanana#38; gated on the video bridge going live)

Do not implement client-side seed randomization here — the video path is
cache-nonce'd server-side from day one (protoBanana#39).

- `generateVideo` on the client: POST `/videos` (JSON or multipart with
  `input_reference`), poll `GET /videos/{id}` (10 s cadence, backoff, per-model
  timeout), `GET /videos/{id}/content` → temp file → `finalizeSuccess`.
- Resume: persist the video id in the existing `backendJobId` metadata slot;
  teach `monitorBackendJob`'s restart path to poll gateway jobs (status GET is
  stateless — cheap).
- Tool routing: `generate_video` → gateway when configured; unmappable params
  (end frame, multi-reference, source-video edit) throw errors naming what the
  gateway path can't do.
- Contract-first: build against the shape in GATEWAY_CONTRACT.md; a stub server
  in tests until the alias is live.

## Phase 4 — audio (ACE-Step) + remaining ops

Kicked off with protoLab ([#22](https://github.com/protoLabsAI/protoLab/issues/22));
contract in [GATEWAY_CONTRACT.md](GATEWAY_CONTRACT.md#audio). ACE-Step 1.5/XL
music **generation** first — `POST /v1/audio/generations` (JSON, sync-target) →
a new `generateViaGateway(audioJob:)` + `gatewayGenerateAudio` tool, mirroring
the image/video runner. Then the edit family (extend / variation / section
repaint / lyric edit) via `POST /v1/audio/edits` (multipart edits idiom), and
TTS via `/audio/speech`. Dubbing/lip-sync is the async multi-stage job, later.

Serving home (protoBanana workflow vs. standalone service) and sync-vs-async are
protoLab's call (#22); the client is built request-first so only the response
handler (sync bytes vs. submit→poll→content) differs — the async branch reuses
the video runner. No license gate (local experiments). `EditSubmitter` gets its
runner seam (seam 4) when the edit ops land.

## Risks

| Risk | Mitigation |
|---|---|
| ~~LiteLLM custom providers may not hook `/videos` routes~~ | Resolved (protoBanana#38): verified they can't — served by a standalone video bridge behind the edge proxy; client unchanged |
| Upstream merge conflicts in `runJob`/tool layer | All gateway logic in one new file; seams are single lines (see rebrand memory: keep-the-seams-thin is the fork's standing strategy) |
| ComfyUI queue latency vs. URLSession defaults | 300 s timeout + async video shape for anything longer |
| RMBG-2.0 workflow is CC BY-NC | Fine for personal use; use BiRefNet alias if builds are ever distributed commercially |
| Ideogram stochastic refusal | Never auto-retry; surface to user (encoded in tool description) |

## Acceptance (per phase)

- 1a: live gateway smoke — generate / edit / compose from the agent panel, refs > 1 MB downscaled, seeds vary across retries.
- 1b: each tool round-trips against the live gateway; bgremove lands with alpha intact on the timeline.
- 2: fresh install, no Convex, no Anthropic key — model pickers populated, in-app generate works.
- 3: LTX clip generated from a prompt + start frame; app quit mid-job resumes and finalizes.
