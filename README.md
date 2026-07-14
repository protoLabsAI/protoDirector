<div align="center">

# protoDirector

**The video editor built for AI.**

<sub><i>Requires macOS 26 (Tahoe) on Apple Silicon</i></sub>

</div>

---

> [!IMPORTANT]
> **protoDirector is a pattern, not a product.** It's a reference fork that demonstrates how to wire an AI-native video editor to an OpenAI-compatible gateway — self-hosted models, your own endpoints, no hosted backend. It is not a supported, out-of-the-box release.
>
> **Want an editor that just works?** Use the original: **[Palmier Pro](https://github.com/palmier-io/palmier-pro)**.

protoDirector is a fork of [Palmier Pro](https://github.com/palmier-io/palmier-pro), an open source AI-native video editor for Mac. You and your agent can generate and edit videos together inside the timeline.

What this fork changes:

- **OpenAI-compatible gateway support** — point the in-app agent and image generation at any OpenAI-compatible endpoint (LiteLLM, local models) instead of the hosted backend. See [docs/fork/AI_ARCHITECTURE.md](docs/fork/AI_ARCHITECTURE.md).
- **No hosted-backend requirement** — builds run without Clerk/Convex/Sentry configuration; hosted-only features degrade gracefully.
- **Rebranded** — see [CHANGES.md](CHANGES.md) for the full change notice.

Upstream tracking: we merge `palmier-io/palmier-pro` main regularly.

## Build

```bash
swift build
swift run
```

Dev loop with logs: `scripts/dev.sh`. App bundle: `scripts/bundle.sh [release|debug]`.

## MCP server

When the app is open, it exposes an MCP server at `http://127.0.0.1:19789/mcp` via HTTP. To connect:

**Claude Code**
```bash
claude mcp add --transport http proto-director http://127.0.0.1:19789/mcp
```

**Codex**
```bash
codex mcp add proto-director --url http://127.0.0.1:19789/mcp
```

**Cursor**

Inside the app: `Help` -> `MCP Instructions` -> `Install in Cursor`, or add to `~/.cursor/mcp.json`:

```
{
  "mcpServers": {
    "proto-director": {
      "type": "http",
      "url": "http://127.0.0.1:19789/mcp"
    }
  }
}
```

**Claude Desktop**

A bundled [mcpb](https://github.com/modelcontextprotocol/mcpb) allows one-click Desktop Extension install: `Help` -> `MCP Instructions` -> `Install in Claude Desktop`.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

Copyright (C) 2026 Palmier, Inc.
Modifications Copyright (C) 2026 protoLabs Studio.

protoDirector is a fork of Palmier Pro and remains open source under [GPLv3](LICENSE). See [NOTICE](NOTICE) and [CHANGES.md](CHANGES.md) for the change notice required by GPLv3 §5(a).
