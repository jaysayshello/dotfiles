/**
 * Garmin Connect Extension for Pi
 *
 * Ports the garth-style unofficial login from jaysayshello/landing (app/src/garmin.ts):
 *   1. GET  sso/embed          → seed cookies
 *   2. GET  sso/signin         → CSRF token + cookies
 *   3. POST sso/signin         → service ticket (ST-...)
 *   4. GET  oauth/preauthorized (OAuth1, consumer only)  → oauth_token/secret
 *   5. POST oauth/exchange/2.0  (OAuth1, consumer+token) → OAuth2 bearer
 *
 * Credentials come from 1Password at login time (never stored). OAuth2 tokens
 * are persisted to ~/.pi/agent/garmin-auth.json and refreshed by re-login.
 *
 * Run /garmin-auth to log in. Garmin fingerprints TLS (JA3); running locally
 * (like this extension) reaches login fine — the wall only bit the deployed
 * Cloudflare Worker.
 */

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI, ToolDefinition } from "@wealthsimple/pi-coding-agent";
import { getAgentDir } from "@wealthsimple/pi-coding-agent";

/* -------------------------------------------------------------------------- */
/* Config                                                                      */
/* -------------------------------------------------------------------------- */

const TOOL_PREFIX = "garmin_";
const AUTH_FILENAME = "garmin-auth.json";
const SSO = "https://sso.garmin.com/sso";
const SSO_EMBED = `${SSO}/embed`;
const CONNECT_API = "https://connectapi.garmin.com";
const CONSUMER_URL = "https://thegarth.s3.amazonaws.com/oauth_consumer.json";
const UA = "com.garmin.android.apps.connectmobile";

// 1Password references for the Garmin credentials (resolved via `op read`).
const OP_ACCOUNT = "my.1password.com";
const OP_USERNAME_REF = "op://Private/sso.garmin.com/username";
const OP_PASSWORD_REF = "op://Private/sso.garmin.com/password";

function authFilePath(): string {
  return join(getAgentDir(), AUTH_FILENAME);
}

/* -------------------------------------------------------------------------- */
/* Types + persistence                                                         */
/* -------------------------------------------------------------------------- */

interface OAuth2Token {
  access_token: string;
  refresh_token: string;
  expires_at: number; // epoch seconds
}

interface Consumer {
  consumer_key: string;
  consumer_secret: string;
}

interface PersistedAuth {
  tokens?: OAuth2Token;
  consumer?: Consumer;
}

async function readPersistedAuth(): Promise<PersistedAuth> {
  try {
    return JSON.parse(await readFile(authFilePath(), "utf8")) as PersistedAuth;
  } catch {
    return {};
  }
}

async function writePersistedAuth(auth: PersistedAuth): Promise<void> {
  const path = authFilePath();
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(auth, null, 2), "utf8");
}

/* -------------------------------------------------------------------------- */
/* Credentials via 1Password                                                   */
/* -------------------------------------------------------------------------- */

async function opRead(ref: string): Promise<string> {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const run = promisify(execFile);
  const { stdout } = await run("op", ["read", ref, "--account", OP_ACCOUNT], {
    encoding: "utf8",
  });
  return stdout.trim();
}

async function garminCredentials(): Promise<{ email: string; password: string }> {
  const [email, password] = await Promise.all([
    opRead(OP_USERNAME_REF),
    opRead(OP_PASSWORD_REF),
  ]);
  if (!email || !password) {
    throw new Error("Could not read Garmin credentials from 1Password.");
  }
  return { email, password };
}

/* -------------------------------------------------------------------------- */
/* Cookie jar                                                                  */
/* -------------------------------------------------------------------------- */

class Jar {
  private jar = new Map<string, string>();
  header(): string {
    return [...this.jar.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
  }
  absorb(res: Response): void {
    for (const c of res.headers.getSetCookie()) {
      const [pair] = c.split(";");
      const eq = pair.indexOf("=");
      if (eq > 0) this.jar.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
    }
  }
}

/* -------------------------------------------------------------------------- */
/* OAuth1 signing (HMAC-SHA1)                                                  */
/* -------------------------------------------------------------------------- */

function enc(s: string): string {
  return encodeURIComponent(s).replace(
    /[!'()*]/g,
    (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase(),
  );
}

async function hmacSha1(key: string, base: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(base));
  return Buffer.from(new Uint8Array(sig)).toString("base64");
}

async function oauth1Header(
  method: string,
  url: string,
  consumer: Consumer,
  token?: { key: string; secret: string },
  extra: Record<string, string> = {},
): Promise<string> {
  const u = new URL(url);
  const params: Record<string, string> = {
    oauth_consumer_key: consumer.consumer_key,
    oauth_nonce: crypto.randomUUID().replace(/-/g, ""),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: String(Math.floor(Date.now() / 1000)),
    oauth_version: "1.0",
    ...extra,
  };
  if (token) params.oauth_token = token.key;

  const all: Record<string, string> = { ...params };
  u.searchParams.forEach((v, k) => (all[k] = v));

  const baseParams = Object.keys(all)
    .sort()
    .map((k) => `${enc(k)}=${enc(all[k])}`)
    .join("&");
  const base = [method.toUpperCase(), enc(`${u.origin}${u.pathname}`), enc(baseParams)].join("&");
  const signingKey = `${enc(consumer.consumer_secret)}&${enc(token?.secret ?? "")}`;
  params.oauth_signature = await hmacSha1(signingKey, base);

  const header = Object.keys(params)
    .sort()
    .map((k) => `${enc(k)}="${enc(params[k])}"`)
    .join(", ");
  return `OAuth ${header}`;
}

async function getConsumer(persisted: PersistedAuth): Promise<Consumer> {
  if (persisted.consumer) return persisted.consumer;
  const res = await fetch(CONSUMER_URL);
  if (!res.ok) throw new Error(`Garmin consumer fetch failed: ${res.status}`);
  const c = (await res.json()) as Consumer;
  persisted.consumer = c;
  await writePersistedAuth(persisted);
  return c;
}

/* -------------------------------------------------------------------------- */
/* Login                                                                       */
/* -------------------------------------------------------------------------- */

async function login(
  persisted: PersistedAuth,
  mfaCode?: string,
): Promise<OAuth2Token> {
  const { email, password } = await garminCredentials();
  const jar = new Jar();
  const embedParams = new URLSearchParams({
    id: "gauth-widget",
    embedWidget: "true",
    gauthHost: SSO,
  });
  const signinParams = new URLSearchParams({
    id: "gauth-widget",
    embedWidget: "true",
    gauthHost: SSO_EMBED,
    service: SSO_EMBED,
    source: SSO_EMBED,
    redirectAfterAccountLoginUrl: SSO_EMBED,
    redirectAfterAccountCreationUrl: SSO_EMBED,
  });

  jar.absorb(await fetch(`${SSO_EMBED}?${embedParams}`, { headers: { "user-agent": UA } }));

  const signinUrl = `${SSO}/signin?${signinParams}`;
  const csrfRes = await fetch(signinUrl, { headers: { "user-agent": UA, cookie: jar.header() } });
  jar.absorb(csrfRes);
  const csrfHtml = await csrfRes.text();
  const csrf = csrfHtml.match(/name="_csrf"\s+value="([^"]+)"/)?.[1];
  if (!csrf) {
    throw new Error(
      "Garmin: could not read CSRF token (Garmin likely rejected the TLS handshake).",
    );
  }

  const form = new URLSearchParams({
    username: email,
    password,
    embed: "true",
    _csrf: csrf,
  });
  const postRes = await fetch(signinUrl, {
    method: "POST",
    headers: {
      "user-agent": UA,
      cookie: jar.header(),
      referer: signinUrl,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: form.toString(),
  });
  jar.absorb(postRes);
  let postHtml = await postRes.text();

  // MFA: submit the one-time code against the same session, then continue.
  if (/mfa/i.test(postRes.url) || /verification code|mfa-code/i.test(postHtml)) {
    if (!mfaCode) {
      throw new Error("MFA_REQUIRED");
    }
    const mfaForm = new URLSearchParams({
      "mfa-code": mfaCode,
      embed: "true",
      _csrf: csrfHtml.match(/name="_csrf"\s+value="([^"]+)"/)?.[1] ?? csrf,
      fromPage: "setupEnterMfaCode",
    });
    const mfaRes = await fetch(`${SSO}/verifyMFA/loginEnterMfaCode?${signinParams}`, {
      method: "POST",
      headers: {
        "user-agent": UA,
        cookie: jar.header(),
        referer: postRes.url,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: mfaForm.toString(),
    });
    jar.absorb(mfaRes);
    postHtml = await mfaRes.text();
  }

  const ticket = postHtml.match(/embed\?ticket=([^"]+)"/)?.[1];
  if (!ticket) throw new Error("Garmin: login failed (no ticket — check credentials/MFA).");

  const c = await getConsumer(persisted);
  const preUrl =
    `${CONNECT_API}/oauth-service/oauth/preauthorized` +
    `?ticket=${enc(ticket)}&login-url=${enc(SSO_EMBED)}&accepts-mfa-tokens=true`;
  const preRes = await fetch(preUrl, {
    headers: { "user-agent": UA, authorization: await oauth1Header("GET", preUrl, c) },
  });
  if (!preRes.ok) throw new Error(`Garmin OAuth1 preauth failed: ${preRes.status}`);
  const oauth1 = new URLSearchParams(await preRes.text());
  const token = {
    key: oauth1.get("oauth_token") ?? "",
    secret: oauth1.get("oauth_token_secret") ?? "",
  };
  if (!token.key) throw new Error("Garmin: OAuth1 exchange returned no token.");

  const exUrl = `${CONNECT_API}/oauth-service/oauth/exchange/user/2.0`;
  const exRes = await fetch(exUrl, {
    method: "POST",
    headers: {
      "user-agent": UA,
      "content-type": "application/x-www-form-urlencoded",
      authorization: await oauth1Header("POST", exUrl, c, token),
    },
    body: "",
  });
  if (!exRes.ok) throw new Error(`Garmin OAuth2 exchange failed: ${exRes.status}`);
  const o2 = (await exRes.json()) as { access_token: string; refresh_token: string; expires_in: number };
  return {
    access_token: o2.access_token,
    refresh_token: o2.refresh_token,
    expires_at: Math.floor(Date.now() / 1000) + o2.expires_in,
  };
}

/* -------------------------------------------------------------------------- */
/* Authenticated API access                                                    */
/* -------------------------------------------------------------------------- */

async function bearer(): Promise<string> {
  const persisted = await readPersistedAuth();
  if (persisted.tokens && persisted.tokens.expires_at - 120 > Math.floor(Date.now() / 1000)) {
    return persisted.tokens.access_token;
  }
  if (!persisted.tokens) {
    throw new Error("Not authenticated with Garmin. Run /garmin-auth first.");
  }
  // Token expired — re-login (MFA accounts will need /garmin-auth interactively).
  const fresh = await login(persisted);
  await writePersistedAuth({ ...persisted, tokens: fresh });
  return fresh.access_token;
}

async function garminGet(path: string, signal: AbortSignal | undefined): Promise<unknown> {
  const doFetch = async (token: string) =>
    fetch(`${CONNECT_API}${path}`, {
      headers: { "user-agent": UA, authorization: `Bearer ${token}`, "nk": "NT" },
      signal,
    });

  let res = await doFetch(await bearer());
  if (res.status === 401) {
    const persisted = await readPersistedAuth();
    delete persisted.tokens;
    await writePersistedAuth(persisted);
    res = await doFetch(await bearer());
  }
  const text = await res.text();
  if (!res.ok) throw new Error(`Garmin API ${path} failed: HTTP ${res.status} ${text}`);
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

const DISPLAY_TZ = "America/New_York";

function fmtTz(epochMs: unknown): string | undefined {
  if (typeof epochMs !== "number") return undefined;
  return new Date(epochMs).toLocaleString("en-US", {
    timeZone: DISPLAY_TZ,
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short",
  });
}

// Garmin timestamps are epoch millis in GMT; surface EST/EDT-formatted copies
// so downstream readers don't misread them in the host time zone.
function enrichSleep(result: unknown): unknown {
  if (result === null || typeof result !== "object") return result;
  const r = result as Record<string, unknown>;
  const dto = r.dailySleepDTO as Record<string, unknown> | undefined;
  if (!dto) return result;
  return {
    ...r,
    dailySleepDTO: {
      ...dto,
      sleepStartLocalDisplay: fmtTz(dto.sleepStartTimestampGMT),
      sleepEndLocalDisplay: fmtTz(dto.sleepEndTimestampGMT),
      displayTimeZone: DISPLAY_TZ,
    },
  };
}

/* -------------------------------------------------------------------------- */
/* Tool definitions                                                            */
/* -------------------------------------------------------------------------- */

interface RestTool {
  name: string;
  description: string;
  parameters: ReturnType<typeof Type.Object>;
  run: (params: Record<string, unknown>, signal?: AbortSignal) => Promise<unknown>;
}

const REST_TOOLS: RestTool[] = [
  {
    name: "get_profile",
    description: "Get the authenticated Garmin user's profile and settings.",
    parameters: Type.Object({}),
    run: (_p, signal) => garminGet("/userprofile-service/userprofile/user-settings", signal),
  },
  {
    name: "list_activities",
    description: "List the athlete's activities, newest first.",
    parameters: Type.Object({
      start: Type.Optional(Type.Number({ description: "Offset into the list (default 0)." })),
      limit: Type.Optional(Type.Number({ description: "How many to return (default 10)." })),
    }),
    run: (p, signal) =>
      garminGet(
        `/activitylist-service/activities/search/activities?start=${p.start ?? 0}&limit=${p.limit ?? 10}`,
        signal,
      ),
  },
  {
    name: "get_activity",
    description: "Get full detail for one activity by id.",
    parameters: Type.Object({
      activity_id: Type.Number({ description: "Numeric Garmin activity id." }),
    }),
    run: (p, signal) => garminGet(`/activity-service/activity/${p.activity_id}`, signal),
  },
  {
    name: "get_steps",
    description: "Get daily step data for a date (YYYY-MM-DD, defaults to today).",
    parameters: Type.Object({
      date: Type.Optional(Type.String({ description: "Date as YYYY-MM-DD." })),
    }),
    run: (p, signal) =>
      garminGet(`/usersummary-service/usersummary/daily?calendarDate=${p.date ?? today()}`, signal),
  },
  {
    name: "get_sleep",
    description: "Get sleep data for a date (YYYY-MM-DD, defaults to today).",
    parameters: Type.Object({
      date: Type.Optional(Type.String({ description: "Date as YYYY-MM-DD." })),
    }),
    run: async (p, signal) =>
      enrichSleep(
        await garminGet(
          `/wellness-service/wellness/dailySleepData?date=${p.date ?? today()}&nonSleepBufferMinutes=60`,
          signal,
        ),
      ),
  },
  {
    name: "get_heart_rate",
    description: "Get daily heart-rate data for a date (YYYY-MM-DD, defaults to today).",
    parameters: Type.Object({
      date: Type.Optional(Type.String({ description: "Date as YYYY-MM-DD." })),
    }),
    run: (p, signal) =>
      garminGet(`/wellness-service/wellness/dailyHeartRate?date=${p.date ?? today()}`, signal),
  },
  {
    name: "get_body_battery",
    description: "Get Body Battery data over a date range (YYYY-MM-DD).",
    parameters: Type.Object({
      start_date: Type.Optional(Type.String({ description: "Start date YYYY-MM-DD (default today)." })),
      end_date: Type.Optional(Type.String({ description: "End date YYYY-MM-DD (default today)." })),
    }),
    run: (p, signal) =>
      garminGet(
        `/wellness-service/wellness/bodyBattery/reports/daily?startDate=${p.start_date ?? today()}&endDate=${p.end_date ?? today()}`,
        signal,
      ),
  },
  {
    name: "get_stats",
    description: "Get the daily user summary stats for a date (YYYY-MM-DD, defaults to today).",
    parameters: Type.Object({
      date: Type.Optional(Type.String({ description: "Date as YYYY-MM-DD." })),
    }),
    run: (p, signal) =>
      garminGet(`/usersummary-service/usersummary/daily?calendarDate=${p.date ?? today()}`, signal),
  },
];

function makeTool(tool: RestTool): ToolDefinition {
  const piName = `${TOOL_PREFIX}${tool.name}`;
  return {
    name: piName,
    label: piName,
    description: `[garmin] ${tool.description}`,
    parameters: tool.parameters,
    async execute(_toolCallId, params, signal) {
      try {
        const result = await tool.run((params ?? {}) as Record<string, unknown>, signal);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }] as never,
          details: {},
        };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `Error: ${message}` }] as never,
          details: { exception: message },
        };
      }
    },
  } as ToolDefinition;
}

/* -------------------------------------------------------------------------- */
/* Extension entry point                                                       */
/* -------------------------------------------------------------------------- */

export default async function (pi: ExtensionAPI): Promise<void> {
  function registerTools(): void {
    for (const tool of REST_TOOLS) {
      try {
        pi.registerTool(makeTool(tool));
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        process.stderr.write(`garmin: skipped tool ${tool.name}: ${message}\n`);
      }
    }
  }

  pi.registerCommand("garmin-auth", {
    description: "Authenticate with Garmin Connect (uses 1Password creds; pass an MFA code as an argument if prompted)",
    handler: async (args, ctx) => {
      try {
        ctx.ui.notify("Logging in to Garmin Connect...", "info");
        const persisted = await readPersistedAuth();
        const mfaCode = (args ?? "").trim() || undefined;

        let tokens: OAuth2Token;
        try {
          tokens = await login(persisted, mfaCode);
        } catch (err) {
          if (err instanceof Error && err.message === "MFA_REQUIRED") {
            ctx.ui.notify(
              "Garmin sent an MFA code. Re-run: /garmin-auth <code>",
              "error",
            );
            return;
          }
          throw err;
        }

        await writePersistedAuth({ ...persisted, tokens });
        registerTools();
        ctx.ui.notify(`✓ Garmin connected! ${REST_TOOLS.length} tools registered.`, "info");
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        ctx.ui.notify(`Garmin auth failed: ${message}`, "error");
      }
    },
  });

  pi.registerCommand("garmin-disconnect", {
    description: "Disconnect from Garmin (clear saved tokens)",
    handler: async (_args, ctx) => {
      const persisted = await readPersistedAuth();
      delete persisted.tokens;
      await writePersistedAuth(persisted);
      ctx.ui.notify("Garmin disconnected. Run /garmin-auth to reconnect.", "info");
    },
  });

  const persisted = await readPersistedAuth();
  if (persisted.tokens) registerTools();
}
