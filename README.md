# OpenHands kit for Docker Sandboxes

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **`kind: sandbox`**
kit that boots straight into [OpenHands](https://github.com/OpenHands/OpenHands)
**Agent Canvas**  the browser UI + agent-server on port 8000.

It's a self-contained agent: it owns its image, entrypoint, and credentials, so
there's no base-agent coupling and no credential collision. One spec supports
**Anthropic, OpenAI, and Gemini** via [LiteLLM](https://github.com/BerriAI/litellm).

## Architecture

![OpenHands sbx kit architecture](./assets/architecture.png)

The sandbox runs on `docker/sandbox-templates:shell-docker`. Your API key stays
**proxy-managed** — the sbx proxy injects the real key on the wire (`x-api-key`
for Anthropic, `Bearer` for OpenAI, `x-goog-api-key` for Gemini), so it never
enters the sandbox. An egress allow-list bounds outbound traffic.

## Quickstart

```bash
# 1. Sign in to Docker Hub
sbx login

# 2. Store a key once (Anthropic default; also: openai, google) — never on the CLI
echo "$ANTHROPIC_API_KEY" | sbx secret set anthropic

# 3. Launch — forward port 8000, then open http://localhost:8000
sbx run -p 8000 --kit docker.io/ajeetraina777/sbx-openhands-kits:latest openhands
```

Or from a local clone / git:

```bash
sbx run -p 8000 --kit ./ openhands
sbx run -p 8000 --kit "git+https://github.com/ajeetraina/sbx-kits-openhands.git" openhands
```

The model defaults to `anthropic/claude-opus-4-8` and is pre-seeded into Canvas.
Switch providers in **Settings > LLM**, or recreate with `LLM_MODEL` overridden
and the matching `sbx secret set <anthropic|openai|google>`.

## v2 and v3

This repo ships the kit in **both** schema versions, side by side at the repo
root:

| Version | Files | Published tag |
|---|---|---|
| v2 | `spec.yaml` | `docker.io/ajeetraina777/sbx-openhands-kits:latest` |
| v3 | `openhands.yaml`, `openhands.dockerfile`, `openhands-context.md` | `docker.io/ajeetraina777/sbx-openhands-kits:v3` |

The v3 files follow the flat per-kit layout used by
[`docker/sandbox-kit-spec`](https://github.com/docker/sandbox-kit-spec): the
`spec.yaml` grammar becomes typed capabilities in `openhands.yaml`, the image is
built from `openhands.dockerfile`, and the agent instructions live in
`openhands-context.md`.

```bash
# Validate the v3 descriptor (fails in seconds on a bad field)
docker buildx build . -f openhands.yaml --output type=cacheonly

# Build the v3 kit locally
docker buildx build . -f openhands.yaml -t sbx-openhands-kit:v3 --load

# Launch the published v3 kit — forward port 8000, then open http://localhost:8000
sbx run -p 8000 --kit docker.io/ajeetraina777/sbx-openhands-kits:v3 openhands
```

## What the kit does

1. Installs OpenHands **Agent Canvas** (`@openhands/agent-canvas`) and the
   headless `openhands` runner (base image already ships Node.js 22 + uv).
2. Boots Agent Canvas as the sandbox **entrypoint** on port 8000 and pre-seeds
   the model into its settings (Canvas doesn't read `LLM_*` env vars).
3. Declares Anthropic / OpenAI / Gemini credentials as **proxy-managed** — the
   real key is injected on the wire and never stored in the sandbox.

> **Port 8000 must be forwarded.** Launch with `sbx run -p 8000 …` so the UI is
> reachable at http://localhost:8000.

Already launched without `-p 8000`? Forward it after the fact (the ingress on
port 8000 binds to all interfaces, so no restart is needed). Use the sandbox
name from `sbx ls`:

```bash
sbx ports openhands-sbx-kits-openhands --publish 8000:8000
open http://localhost:8000
```

## Providers

| Model (`LLM_MODEL`) | Provider | Key |
|---|---|---|
| `anthropic/claude-opus-4-8` (default) | Anthropic | `sbx secret set anthropic` |
| `openai/gpt-4o` | OpenAI | `sbx secret set openai` |
| `gemini/gemini-2.5-pro` | Gemini | `sbx secret set google` |

## Automation

A headless runner is also installed for non-interactive use:

```bash
openhands --headless --override-with-envs --exit-without-confirmation -t "…"
```
