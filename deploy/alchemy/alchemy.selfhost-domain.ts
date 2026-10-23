// A self-host's own hostname (SELFHOST_DOMAIN), for deployments that should
// answer somewhere other than workers.dev. Access covers the hostname from the
// first deploy, but the Worker only declares it once it is attached (by hand
// in the dashboard when the deploy token has no access to the zone), because
// alchemy detaches every live domain the config leaves out, and attaching one
// the token cannot reach would fail the deploy.

import * as Cloudflare from "alchemy/Cloudflare";
import * as CfWorkers from "@distilled.cloud/cloudflare/workers";
import * as Config from "effect/Config";
import * as Console from "effect/Console";
import * as Effect from "effect/Effect";
import { workerName } from "./alchemy.access.ts";

const HOSTNAME = /^[a-z0-9-]+(\.[a-z0-9-]+)+$/;

export const resolveSelfHostDomain = (stage: string) =>
  Effect.gen(function* () {
    const hostname = (yield* Config.string("SELFHOST_DOMAIN").pipe(
      Config.withDefault(""),
    )).trim();
    if (!hostname) {
      return { hostname: "", attached: false };
    }
    if (!HOSTNAME.test(hostname)) {
      return yield* Effect.die(
        new Error(
          `SELFHOST_DOMAIN must be a bare hostname such as seo.example.com, not "${hostname}".`,
        ),
      );
    }

    const { accountId } = yield* yield* Cloudflare.CloudflareEnvironment;
    const live = yield* CfWorkers.listDomains({ accountId, hostname }).pipe(
      Effect.catch((error) =>
        Effect.die(
          new Error(
            `Could not check whether ${hostname} is attached: ${String(error)}`,
          ),
        ),
      ),
    );
    const owner = live.result.find(
      (entry) => entry.hostname === hostname,
    )?.service;
    const worker = workerName(stage);
    if (owner && owner !== worker) {
      return yield* Effect.die(
        new Error(
          `${hostname} is attached to the Worker "${owner}", not ${worker}. Detach it there or choose another SELFHOST_DOMAIN.`,
        ),
      );
    }
    if (!owner) {
      yield* Console.log(
        `${hostname} is protected by Access but not attached yet. Attach it to ${worker} under Settings, Domains & Routes in the Cloudflare dashboard, then redeploy so the Worker keeps it.`,
      );
    }
    return { hostname, attached: owner === worker };
  });
