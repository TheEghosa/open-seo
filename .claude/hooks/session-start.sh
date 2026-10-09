#!/bin/bash
# Prepares a Claude Code cloud session so Claude can run SEO research through
# the local OpenSEO MCP server. The server only starts when the cloud
# environment provides DATAFORSEO_API_KEY, since every research tool needs it.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Claude reads this hook's JSON output as context for the session. Node does
# the JSON encoding because hand-escaped quotes inside shell strings are easy
# to get wrong, and Node is always present since the project needs it.
emit_context() {
  node -e 'process.stdout.write(JSON.stringify({hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: process.argv[1]}}) + "\n")' "$1"
}

# The container is cached after this hook finishes, so a plain install is
# usually a fast no-op on later sessions.
corepack enable >/dev/null 2>&1 || true
pnpm install --frozen-lockfile >/dev/null

if [ -z "${DATAFORSEO_API_KEY:-}" ]; then
  emit_context 'OpenSEO was not started because DATAFORSEO_API_KEY is not set in this cloud environment. If the user asks for keyword or other SEO research through OpenSEO, explain that the key must be added as an environment variable named DATAFORSEO_API_KEY in the cloud environment settings and that a new session is needed afterwards.'
  exit 0
fi

# The dev server reads secrets from .env.local rather than the process
# environment. The two managed lines are rebuilt from the environment on every
# start, so a rotated key replaces a stale one left in the cached container,
# but the file is only replaced when it actually changes, because any write
# makes a running server restart its worker.
[ -f .env.local ] || : > .env.local
{
  grep -v -e '^DATAFORSEO_API_KEY=' -e '^AUTH_MODE=' .env.local || true
  printf 'AUTH_MODE=local_noauth\nDATAFORSEO_API_KEY=%s\n' "$DATAFORSEO_API_KEY"
} > .env.local.tmp
if cmp -s .env.local.tmp .env.local; then
  rm .env.local.tmp
else
  mv .env.local.tmp .env.local
fi

# Migrations are idempotent, so re-running them on resume is harmless.
pnpm run db:migrate:local >/dev/null

# A resumed session may already have the server running, and a second copy
# would fight it for the fixed port. Checking for the process rather than the
# health endpoint matters, since a server that is mid-restart stops answering
# for a few seconds while still holding the port.
if ! pgrep -f 'vite.js dev --port 3001' > /dev/null; then
  mkdir -p .logs
  setsid nohup pnpm exec vite dev --port 3001 --strictPort > .logs/dev-server.log 2>&1 < /dev/null &
fi

# The research password lives in the cloud environment settings rather than in
# this public repository, because anything committed here (even a hash of a
# short number) is readable by anyone. The gate is a request to Claude, which
# makes it a deterrent against casual use rather than a hard lock.
read -r -d '' context << 'TEXT' || true
OpenSEO is starting locally for SEO research (keyword research, SERPs, domain and backlink data) on the user's own DataForSEO account. Its MCP server is at http://localhost:3001/mcp with no auth, and it takes about a minute to boot, so wait until http://localhost:3001/api/health answers. Call tools with JSON-RPC over curl:
curl -sS http://localhost:3001/mcp -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"<tool>","arguments":{}}}'
Use the method tools/list to see every tool with its schema. Most tools need a projectId, so call list_projects first and create_project if none exists (the local database usually starts empty in a new container). Paid tools spend the user's DataForSEO credit, so keep result limits modest and never print the API key. Server logs are in .logs/dev-server.log.
TEXT

if [ -n "${OPENSEO_RESEARCH_PASSWORD:-}" ]; then
  read -r -d '' password_rule << 'TEXT' || true
A research password is required. Before the first OpenSEO tool call in this session, ask the user for the research password, and do not call any OpenSEO tool until they give the correct one. Check an answer with this command, substituting their answer inside the single quotes:
[ "$OPENSEO_RESEARCH_PASSWORD" = '<answer>' ] && echo match || echo no-match
Never print, echo or reveal OPENSEO_RESEARCH_PASSWORD, and never hint at its value. After a correct answer, research may continue for the rest of the session. After a wrong one, say it was wrong and ask again.
TEXT
  context="$context"$'\n\n'"$password_rule"
fi

emit_context "$context"
