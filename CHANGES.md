# Changes from upstream (GPLv3 §5(a) notice)

protoDirector is a fork of [Palmier Pro](https://github.com/palmier-io/palmier-pro).
This file records the modifications, most recent first. Upstream is merged
regularly; upstream's own history is preserved in git.

## 2026-07-12 — Rebrand (light-touch)

- App identity: display name `protoDirector`, bundle ID `studio.protolabs.director`,
  project UTI `studio.protolabs.project`, executable `protoDirector`. Internal SPM
  module/target names and the `Sources/PalmierPro` path are intentionally unchanged
  to keep upstream merges clean.
- The `palmier` URL scheme and `.palmier` project file extension are kept for
  compatibility with existing project files.
- User-visible strings, menu items, on-disk cache/log/storage paths, FCPXML export
  event name, and the MCP surface (server name `proto-director`,
  `proto-director://models/*` resources, `proto-director.mcpb`) rebranded.
- Sparkle auto-update feed removed (no SUFeedURL/SUPublicEDKey); the updater no-ops.
- App icon replaced: Lucide "clapperboard" glyph (ISC, see NOTICE), silver on black,
  rendered to AppIcon.icns/AppIcon.png/AppIcon.icon and the mcpb icon.
- Build scripts produce `protoDirector.app`; Palmier signing/notarization defaults
  removed (supply SIGNING_IDENTITY / NOTARY_PROFILE via env for signed builds).
- Hosted-backend (Clerk/Convex), Sentry, and PostHog remain unconfigured in this
  fork's builds; the app degrades gracefully (Mode A per docs/fork/REBRAND_AND_CORDS.md).

## 2026-07-11 — OpenAI-compatible gateway (fork feature)

- Added an OpenAI-compatible chat client for the in-app agent (gateway / local
  models) and gateway-routed image generation, replacing the hosted-backend
  requirement. See docs/fork/AI_ARCHITECTURE.md.
