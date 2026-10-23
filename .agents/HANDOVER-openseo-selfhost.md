# Handover: self-hosting OpenSEO for Fredrick's team and Claude

This file carries the context from the planning thread (6 to 9 October 2026) into a fresh session, because a new session starts with no memory of that conversation. Read all of it before acting, since the first thing the user expects is answers to the open questions below rather than a deploy.

Fredrick has standing preferences that apply to every reply and every file: ask clarifying questions before starting a task, never guess (say what you don't know and ask), never use em dashes or en dashes, and write in natural prose using the `anthropic-skills:house-prose-style` skill. Load that skill before writing anything.

## Where things stand

Nothing has been deployed and no code has changed. The repository is `TheEghosa/open-seo`, a fork of `every-app/open-seo` at release v0.1.11 (MIT licence), and the working branch from the planning thread is `claude/inspiring-babbage-ag9h40`, which holds only this file on top of the release commit. Fredrick has opened a DataForSEO account and has an API key, but it has not been shared in chat and must never be, so it will arrive as an environment variable.

## What Fredrick asked for

In his words, the plan is to set up Cloudflare, add the DataForSEO key there, and then use the fork "to build our own keyword tools inside Claude", using all of the MCP tools and skills. Work should start with the features that run without DataForSEO and then move to the ones that need it, so usage is maximised, and "every necessary chat in this Claude account" should be able to use the build.

Restated as intent: a self-hosted OpenSEO on Fredrick's Cloudflare account that he and his team can reach from any Claude chat through one connector and a shared set of skills, deployed first and then extended with custom keyword tooling.

## Ask these four questions first

They were put to Fredrick at the end of the planning thread and are still unanswered, and each one changes the work, so ask them before starting.

1. What should "our own keyword tools" do that the shipped `keyword-research` skill does not? His account already has a `keyword-opportunity-finder` skill, so find out whether he wants that rebuilt on OpenSEO data or something new.
2. Is his Claude account an individual plan (Pro or Max) or a Team or Enterprise plan, and do teammates have their own Claude accounts? A connector added to one account only appears in that account's chats. On Team and Enterprise an owner may be able to add it organisation-wide, but that is unconfirmed, so check before relying on it.
3. Does he have a Google Cloud project, and access to his clients' Search Console and GA4 properties? Phase 1 depends on both.
4. Is the default `workers.dev` address acceptable, or should OpenSEO sit on his own domain?

## What Fredrick needs to provide

Secrets go into the cloud environment's settings (the environment menu in the session title bar, then Edit), never into chat. A session only reads environment variables when it starts, so if any are added mid-session, a new session is needed to see them.

| Item                                                             | Where it goes               | Required for                                                                             |
| ---------------------------------------------------------------- | --------------------------- | ---------------------------------------------------------------------------------------- |
| `CLOUDFLARE_API_TOKEN`                                           | Cloud environment variable  | The deploy, because the browser-based `pnpm alchemy login` cannot run in a cloud session |
| `CLOUDFLARE_ACCOUNT_ID`                                          | Cloud environment variable  | The deploy                                                                               |
| `DATAFORSEO_API_KEY`                                             | Cloud environment variable  | The deploy refuses to run without it, even for the free features                         |
| Team email addresses                                             | Told to you in chat         | `ACCESS_ALLOWED_EMAILS`, which decides who can log in                                    |
| R2 switched on in the Cloudflare dashboard                       | Fredrick does this once     | Cloudflare requires a card on file before R2 works, even on the free tier                |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `BETTER_AUTH_SECRET` | Cloud environment variables | Search Console and GA4 (optional, but Phase 1 leans on them)                             |
| `OPENROUTER_API_KEY`                                             | Cloud environment variable  | Automatic project research and Sam, the in-app chat (optional)                           |

The API token permissions are only partly documented. `docs/maintainers/preview-deployments.md` lists write access to Workers Scripts, KV, D1, R2 and Workflows, plus Secrets Store read and Account Settings read. The self-host deploy also creates a Cloudflare Access application, a browser binding, Durable Objects and a rate limiter, so Access: Apps and Policies (edit) and Browser Rendering (edit) are probably needed too, and the first-time `alchemy cloudflare bootstrap` writes a token into the Secrets Store, which suggests Secrets Store edit rather than read. Those additions are inferred from `deploy/alchemy/alchemy.run.ts`, not documented, so expect to adjust the token if a step fails on permissions.

## Deploy steps

Node v22.22.0 and pnpm 10.30.1 are installed in the cloud image, which meets the docs' Node 22.6 minimum, and on 6 October both `api.cloudflare.com` and `api.dataforseo.com` were reachable from the sandbox. The steps below follow `docs/SELF_HOSTING_CLOUDFLARE.md` with the token route substituted for the interactive login.

1. Confirm the variables exist without printing their values, for example `for v in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID DATAFORSEO_API_KEY; do [ -n "${!v}" ] && echo "$v set" || echo "$v MISSING"; done`.
2. Run `corepack enable && pnpm install`, since `node_modules` is not present in a fresh clone.
3. Create `.env.selfhost` from `deploy/.env.selfhost.example` using the environment values and the team emails. The file is gitignored, and it must never be committed or printed to the terminal, because it holds every secret.
4. Run `pnpm alchemy cloudflare bootstrap` once to create alchemy's state-store Worker. Whether this works with an API token alone has not been tested. `preview-deployments.md` says the `CI` environment variable is what makes alchemy read `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, so if alchemy asks for a browser login, retry with `CI=true`.
5. Run `pnpm deploy:selfhost --yes`. The preflight script (`scripts/selfhost-deploy-preflight.mjs`) skips the login-profile check when `CLOUDFLARE_API_TOKEN` is set, and it fails early if `DATAFORSEO_API_KEY` or `ACCESS_ALLOWED_EMAILS` is missing.
6. Validate by opening `https://<worker-hostname>/api/health`, which reports configuration checks and database status. The account also has a Cloudflare Developer Platform connector (`workers_list`, `d1_databases_list` and similar tools), which can confirm what was created.
7. Turn on Managed OAuth for the OpenSEO Access application (Zero Trust, Access controls, Applications, Edit, Additional settings, OAuth), as `docs/SELF_HOSTING_CLOUDFLARE_OPERATIONS.md` describes. Allow `localhost` redirect URIs for Claude Code and the HTTPS callback for claude.ai web connectors. The exact claude.ai callback URL has not been confirmed, so look it up instead of guessing. Skipping this step lets Claude log in but leaves it with no tools.
8. Fredrick adds `https://<worker-hostname>/mcp` as a custom connector at claude.ai/customize/connectors. Connectors are read when a chat or session starts, so only new chats see it.

## Getting the skills into every chat

There are two routes, and the team may need both. For claude.ai chats, Fredrick's own account skills already sync into his sessions (this is how `house-prose-style` arrives), so uploading the twelve skills from `plugins/openseo/skills/` to his account should make them available everywhere. The exact upload screen has not been confirmed, so check it before giving him steps.

For Claude Code, the fork's plugin is the cleaner route, but it currently points at the hosted service: `plugins/openseo/.mcp.json` sets the server URL to `https://app.openseo.so/mcp`. Before teammates install it, that URL must change to the self-hosted worker. They would then install with `/plugin marketplace add TheEghosa/open-seo` and `/plugin install openseo@openseo`. That only works if they can read the fork on GitHub, and it is not yet known whether the fork is public. Per `AGENTS.md`, editing plugin configuration also means bumping the version in all three plugin manifests.

## The two phases

This split was worked out by checking which MCP tools each shipped skill calls, against which services call the DataForSEO client.

| Phase                  | Tools                                                                                                                                                                                           | Skills                                                                                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1, no DataForSEO spend | Site audit with Lighthouse off (the MCP tool defaults it off), Search Console performance and URL inspection, the nine GA4 tools including `get_search_opportunities`, project context, reports | `seo-coach`, `seo-report` and `seo-project-setup` work almost entirely. `seo-audit` and `keyword-clustering` work partly, since they mix free and paid tools |
| 2, DataForSEO          | Keywords, SERPs, domains, backlinks, rank tracking, local SEO, AI visibility, Brand Lookup                                                                                                      | `keyword-research`, `competitor-analysis`, `competitive-landscape`, `link-prospecting`, `local-seo`, `ai-prompt-research`, `ai-visibility-audit`             |

One gap emerged that suits a first custom build, and it was proposed to Fredrick but not yet approved. None of the twelve shipped skills calls the GA4 tools or `get_search_opportunities`, even though that tool scores a site's pages in positions 4 to 20 using its own Search Console and GA4 data, uses no OpenSEO credits and makes no DataForSEO calls. A keyword-opportunity skill built on it would be free to run and useful from the first day, which fits his "free features first" order. Confirm it against his answer to question 1 before building.

## Costs, for reference

These figures come from the cost model in `web/src/routes/_marketing/pricing.tsx`, whose comments say DataForSEO prices were checked in July and September 2026. Treat them as the repo's figures rather than live quotes. Self-hosting pays DataForSEO's raw price with no OpenSEO markup.

| Action                                      | Raw cost     |
| ------------------------------------------- | ------------ |
| Keyword research, default 150 results       | $0.042       |
| Backlink profile with a year of history     | about $0.061 |
| Rank check, one keyword, top 40 results     | about $0.002 |
| AI prompt check, one prompt on one platform | $0.0012      |

New DataForSEO accounts get $1 of free credit and the minimum top-up is $50 (`docs/DATAFORSEO_API_KEY.md`). JavaScript rendering in site audits needs a paid Workers plan, because the free plan's browser limit is too slow for a crawl.

## Rules for changing the fork

`AGENTS.md` governs any code change, and the points most likely to matter here are these. New backend features follow a TanStack server function, then service, then repository structure. Schema and queries must work on both SQLite and Postgres. Any MCP tool, shipped skill or plugin configuration change needs a patch bump across `plugins/openseo/.codex-plugin/plugin.json`, `plugins/openseo/.claude-plugin/plugin.json` and `plugins/openseo/.cursor-plugin/plugin.json`, and changed skills must be followed by `pnpm sync-plugin-skills`. Skills belong in `.agents/skills/`, and the repo's `create-repo-skill` skill covers that. The repo's `verify-local-mcp` and `evaluate-skill` skills are the intended way to test MCP and skill changes. Upstream ships often, so a heavily customised fork will need regular merges from `every-app/open-seo`.

## What is verified and what is not

Verified in the code or by running commands: the feature split between free and paid, the preflight's requirements, the token bypass, the plugin's hosted MCP URL, the installed Node and pnpm versions, network reachability on 6 October, and that `.env.selfhost` is gitignored.

Not yet verified, so confirm each one before relying on it: the full API token permission list, whether `alchemy cloudflare bootstrap` runs non-interactively with a token, the claude.ai OAuth callback URL, the claude.ai screen for uploading account skills, organisation-wide connectors on Team or Enterprise plans, and whether the fork is public.
