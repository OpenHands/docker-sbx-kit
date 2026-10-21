# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# (OH_SECRET_KEY below only encrypts Canvas' local settings, whose stored key is
#  itself a proxy-managed placeholder — not a real secret. Lint false positive.)
#
# OpenHands Agent Canvas recipe — the content of the workload.
#
# MIGRATION NOTE (v2 → v3): v2 pointed `sandbox.image` at the shell-docker
# template and did the real work in `setup.install` hooks at create time. v3
# bakes that work into the image at BUILD time: the agent-canvas binary, the
# headless `openhands` runner, the uvx shim and the launcher all ship in this
# recipe, so nothing is fetched or written at create. That removes the v2
# install-phase network grant — build-time network is not gated by the kit's
# network-policy — and is why openhands.yaml carries no lifecycle@1.
#
# Base kept verbatim from v2: shell-docker already ships Node.js 22 and uv.

FROM docker/sandbox-templates:shell-docker

# v2 environment.variables → ENV (static runtime env lives in the image config).
# HTTP_PROXY/HTTPS_PROXY are deliberately NOT cleared — that is how key
# injection and egress control work; only localhost bypasses the proxy.
ENV LLM_MODEL="anthropic/claude-opus-4-8" \
    PORT="8000" \
    OPENHANDS_SUPPRESS_BANNER="1" \
    OH_SECRET_KEY="sbx-openhands-dev" \
    HOME="/home/agent" \
    NO_PROXY="localhost,127.0.0.1,host.docker.internal" \
    no_proxy="localhost,127.0.0.1,host.docker.internal"

USER root

# v2 setup.install: a uvx that supports --from (shell-docker's uv has no working
# uvx). Agent Canvas runs `uvx --from openhands-agent-server==<ver> agent-server`
# at runtime; `uv tool run` handles --from.
COPY <<'EOF' /usr/local/bin/uvx
#!/bin/sh
exec uv tool run "$@"
EOF

# v2 setup.install: the Canvas launcher — starts agent-canvas on $PORT and seeds
# the model into Canvas' settings (Canvas doesn't read the LLM_* env). This is
# the workload's ENTRYPOINT, so it must serve as PID 1.
COPY <<'EOF' /usr/local/bin/openhands-canvas-launch
#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-8000}"; BASE="http://localhost:${PORT}"
agent-canvas --port "$PORT" & SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' INT TERM EXIT
for _ in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$BASE/health" 2>/dev/null)" = "200" ] && break
  sleep 2
done
KEY="$(cat "$HOME/.openhands/agent-canvas/api-key.txt" 2>/dev/null | tr -d '\r\n' || true)"
curl -s -X PATCH "$BASE/api/settings" -H "X-Session-API-Key: $KEY" \
  -H 'Content-Type: application/json' \
  -d "{\"agent_settings_diff\":{\"llm\":{\"model\":\"${LLM_MODEL}\",\"api_key\":\"sbx-proxy-managed\"}}}" \
  >/dev/null 2>&1 || echo "note: set the model in Settings > LLM if the UI is not preconfigured" >&2
echo "Agent Canvas is running at ${BASE} (forward with 'sbx run -p ${PORT} …')"
wait "$SRV"
EOF

RUN chmod +x /usr/local/bin/uvx /usr/local/bin/openhands-canvas-launch

# v2 setup.install: OpenHands Agent Canvas (bin: agent-canvas) into /usr/local.
RUN npm install -g --prefix /usr/local @openhands/agent-canvas --no-audit --no-fund

# v2 setup.install (ran as uid 1000): the headless OpenHands runner, for
# automation / verification. uv tool installs into $HOME/.local for the agent.
USER agent
RUN uv tool install openhands

WORKDIR /home/agent
# v2 sandbox.entrypoint — boots Agent Canvas on $PORT and serves it.
ENTRYPOINT ["/usr/local/bin/openhands-canvas-launch"]
