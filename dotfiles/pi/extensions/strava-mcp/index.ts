/**
 * Strava REST Extension for Pi
 *
 * Talks directly to Strava's public REST API (https://www.strava.com/api/v3)
 * using a standard OAuth authorization-code flow with a pre-registered Strava
 * API application (client_id + client_secret from strava.com/settings/api).
 *
 * On first use, run /strava-auth to authorize in the browser. Tokens are
 * persisted to ~/.pi/agent/strava-auth.json and refreshed automatically.
 *
 * Strava's hosted MCP server is not used: its OAuth dynamic client
 * registration is gated, so this connects to the normal REST API instead.
 */

import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI, ToolDefinition } from "@wealthsimple/pi-coding-agent";
import { getAgentDir } from "@wealthsimple/pi-coding-agent";

/* -------------------------------------------------------------------------- */
/* Config                                                                      */
/* -------------------------------------------------------------------------- */

const TOOL_PREFIX = "strava_";
const AUTH_FILENAME = "strava-auth.json";
const OAUTH_CALLBACK_PORT = 38746;
const OAUTH_TIMEOUT_MS = 5 * 60 * 1000;
const REDIRECT_URI = `http://localhost:${OAUTH_CALLBACK_PORT}/callback`;
const AUTHORIZE_URL = "https://www.strava.com/oauth/authorize";
const TOKEN_URL = "https://www.strava.com/oauth/token";
const API_BASE = "https://www.strava.com/api/v3";
const SCOPE = "read,activity:read_all,profile:read_all";

function authFilePath(): string {
  return join(getAgentDir(), AUTH_FILENAME);
}

/* -------------------------------------------------------------------------- */
/* Token persistence                                                           */
/* -------------------------------------------------------------------------- */

interface ClientInfo {
  client_id: string;
  client_secret: string;
}

interface Tokens {
  access_token: string;
  refresh_token: string;
  expires_at: number; // unix seconds
}

interface PersistedAuth {
  clientInfo?: ClientInfo;
  tokens?: Tokens;
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
/* OAuth callback server                                                       */
/* -------------------------------------------------------------------------- */

const SUCCESS_HTML = `<!doctype html>
<html><head><title>pi · Strava Connected</title>
<style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
text-align:center;padding:48px;color:#222;background:#f5f7f9}
.card{max-width:480px;margin:0 auto;background:#fff;border-radius:8px;
padding:32px;box-shadow:0 1px 4px rgba(0,0,0,0.08)}
h1{margin:0 0 12px;font-size:22px;color:#fc4c02}p{margin:0;line-height:1.5;color:#555}</style>
</head><body><div class="card"><h1>✓ Connected to Strava</h1>
<p>You can close this tab and return to your terminal.</p></div></body></html>`;

function waitForOAuthCallback(): Promise<string | null> {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value: string | null, server?: Server) => {
      if (settled) return;
      settled = true;
      server?.close();
      resolve(value);
    };

    const handle = (req: IncomingMessage, res: ServerResponse, server: Server): void => {
      const url = new URL(req.url ?? "/", `http://localhost:${OAUTH_CALLBACK_PORT}`);
      if (url.pathname !== "/callback") {
        res.statusCode = 404;
        res.end("Not found");
        return;
      }
      const code = url.searchParams.get("code");
      const error = url.searchParams.get("error");
      if (error) {
        res.statusCode = 400;
        res.setHeader("Content-Type", "text/html");
        res.end(`<html><body><h1>Error: ${error}</h1></body></html>`);
        finish(null, server);
        return;
      }
      res.statusCode = 200;
      res.setHeader("Content-Type", "text/html");
      res.end(SUCCESS_HTML);
      finish(code, server);
    };

    const server: Server = createServer((req, res) => {
      try {
        handle(req, res, server);
      } catch {
        try { res.statusCode = 500; res.end("Internal error"); } catch { /* noop */ }
        finish(null, server);
      }
    });

    const timer = setTimeout(() => finish(null, server), OAUTH_TIMEOUT_MS);
    server.on("close", () => clearTimeout(timer));
    server.on("error", () => finish(null));
    server.listen(OAUTH_CALLBACK_PORT, "127.0.0.1");
  });
}

async function openBrowser(url: string): Promise<void> {
  try {
    const { exec } = await import("node:child_process");
    exec(`open "${url}"`, () => {});
  } catch {
    // best-effort
  }
}

/* -------------------------------------------------------------------------- */
/* Token exchange + refresh                                                    */
/* -------------------------------------------------------------------------- */

interface StravaTokenResponse {
  access_token: string;
  refresh_token: string;
  expires_at: number;
}

async function exchangeCode(client: ClientInfo, code: string): Promise<Tokens> {
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: client.client_id,
      client_secret: client.client_secret,
      code,
      grant_type: "authorization_code",
    }),
  });
  if (!res.ok) {
    throw new Error(`token exchange failed: HTTP ${res.status} ${await res.text()}`);
  }
  const data = (await res.json()) as StravaTokenResponse;
  return { access_token: data.access_token, refresh_token: data.refresh_token, expires_at: data.expires_at };
}

async function refreshTokens(client: ClientInfo, tokens: Tokens): Promise<Tokens> {
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: client.client_id,
      client_secret: client.client_secret,
      refresh_token: tokens.refresh_token,
      grant_type: "refresh_token",
    }),
  });
  if (!res.ok) {
    throw new Error(`token refresh failed: HTTP ${res.status} ${await res.text()}`);
  }
  const data = (await res.json()) as StravaTokenResponse;
  return { access_token: data.access_token, refresh_token: data.refresh_token, expires_at: data.expires_at };
}

/* -------------------------------------------------------------------------- */
/* Authenticated API access                                                    */
/* -------------------------------------------------------------------------- */

async function getValidAccessToken(): Promise<string> {
  const persisted = await readPersistedAuth();
  if (!persisted.clientInfo) {
    throw new Error("No Strava client credentials found. Add them to strava-auth.json.");
  }
  if (!persisted.tokens) {
    throw new Error("Not authenticated with Strava. Run /strava-auth first.");
  }
  const nowPlusBuffer = Math.floor(Date.now() / 1000) + 60;
  if (persisted.tokens.expires_at > nowPlusBuffer) {
    return persisted.tokens.access_token;
  }
  const refreshed = await refreshTokens(persisted.clientInfo, persisted.tokens);
  await writePersistedAuth({ ...persisted, tokens: refreshed });
  return refreshed.access_token;
}

async function stravaGet(
  path: string,
  query: Record<string, unknown> | undefined,
  signal: AbortSignal | undefined,
): Promise<unknown> {
  const token = await getValidAccessToken();
  const url = new URL(`${API_BASE}${path}`);
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined && v !== null && v !== "") url.searchParams.set(k, String(v));
    }
  }
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
    signal,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Strava API ${path} failed: HTTP ${res.status} ${text}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
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
    name: "get_athlete",
    description: "Get the authenticated athlete's profile (name, id, location, gear, clubs).",
    parameters: Type.Object({}),
    run: (_p, signal) => stravaGet("/athlete", undefined, signal),
  },
  {
    name: "get_athlete_stats",
    description: "Get activity totals and stats for an athlete. Requires the athlete id (from get_athlete).",
    parameters: Type.Object({
      athlete_id: Type.Number({ description: "Numeric Strava athlete id." }),
    }),
    run: (p, signal) => stravaGet(`/athletes/${p.athlete_id}/stats`, undefined, signal),
  },
  {
    name: "list_activities",
    description:
      "List the authenticated athlete's activities, newest first. Supports paging and time filters.",
    parameters: Type.Object({
      page: Type.Optional(Type.Number({ description: "Page number (default 1)." })),
      per_page: Type.Optional(Type.Number({ description: "Results per page (default 30, max 200)." })),
      before: Type.Optional(Type.Number({ description: "Unix timestamp; only activities before this time." })),
      after: Type.Optional(Type.Number({ description: "Unix timestamp; only activities after this time." })),
    }),
    run: (p, signal) => stravaGet("/athlete/activities", p, signal),
  },
  {
    name: "get_activity",
    description: "Get a single activity by id, with full detail.",
    parameters: Type.Object({
      activity_id: Type.Number({ description: "Numeric Strava activity id." }),
      include_all_efforts: Type.Optional(
        Type.Boolean({ description: "Include all segment efforts (default false)." }),
      ),
    }),
    run: (p, signal) =>
      stravaGet(`/activities/${p.activity_id}`, { include_all_efforts: p.include_all_efforts }, signal),
  },
  {
    name: "get_activity_zones",
    description: "Get the heart-rate and power zones for an activity by id.",
    parameters: Type.Object({
      activity_id: Type.Number({ description: "Numeric Strava activity id." }),
    }),
    run: (p, signal) => stravaGet(`/activities/${p.activity_id}/zones`, undefined, signal),
  },
  {
    name: "list_activity_laps",
    description: "Get the laps for an activity by id.",
    parameters: Type.Object({
      activity_id: Type.Number({ description: "Numeric Strava activity id." }),
    }),
    run: (p, signal) => stravaGet(`/activities/${p.activity_id}/laps`, undefined, signal),
  },
  {
    name: "get_segment",
    description: "Get details for a segment by id.",
    parameters: Type.Object({
      segment_id: Type.Number({ description: "Numeric Strava segment id." }),
    }),
    run: (p, signal) => stravaGet(`/segments/${p.segment_id}`, undefined, signal),
  },
  {
    name: "list_starred_segments",
    description: "List the authenticated athlete's starred segments.",
    parameters: Type.Object({
      page: Type.Optional(Type.Number({ description: "Page number (default 1)." })),
      per_page: Type.Optional(Type.Number({ description: "Results per page (default 30)." })),
    }),
    run: (p, signal) => stravaGet("/segments/starred", p, signal),
  },
];

function makeTool(tool: RestTool): ToolDefinition {
  const piName = `${TOOL_PREFIX}${tool.name}`;
  return {
    name: piName,
    label: piName,
    description: `[strava] ${tool.description}`,
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
        process.stderr.write(`strava: skipped tool ${tool.name}: ${message}\n`);
      }
    }
  }

  // /strava-auth: interactive OAuth authorization-code flow
  pi.registerCommand("strava-auth", {
    description: "Authenticate with Strava (opens browser for OAuth)",
    handler: async (_args, ctx) => {
      try {
        const persisted = await readPersistedAuth();
        if (!persisted.clientInfo?.client_id || !persisted.clientInfo?.client_secret) {
          ctx.ui.notify(
            "Missing Strava client_id/client_secret in strava-auth.json. Add them from strava.com/settings/api.",
            "error",
          );
          return;
        }

        ctx.ui.notify("Starting Strava OAuth flow...", "info");

        const authorizeUrl = new URL(AUTHORIZE_URL);
        authorizeUrl.search = new URLSearchParams({
          client_id: persisted.clientInfo.client_id,
          redirect_uri: REDIRECT_URI,
          response_type: "code",
          approval_prompt: "auto",
          scope: SCOPE,
        }).toString();

        const codePromise = waitForOAuthCallback();
        await openBrowser(authorizeUrl.toString());
        ctx.ui.notify(
          `If the browser didn't open, visit:\n${authorizeUrl.toString()}`,
          "info",
        );

        const code = await codePromise;
        if (!code) {
          ctx.ui.notify("Strava auth failed or timed out: no authorization code received.", "error");
          return;
        }

        ctx.ui.notify("Received authorization code, exchanging for tokens...", "info");
        const tokens = await exchangeCode(persisted.clientInfo, code);
        await writePersistedAuth({ ...persisted, tokens });

        registerTools();
        ctx.ui.notify(`✓ Strava connected! ${REST_TOOLS.length} tools registered.`, "info");
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        ctx.ui.notify(`Strava auth failed: ${message}`, "error");
      }
    },
  });

  // /strava-disconnect: clear tokens (keep client credentials)
  pi.registerCommand("strava-disconnect", {
    description: "Disconnect from Strava (clear saved tokens)",
    handler: async (_args, ctx) => {
      const persisted = await readPersistedAuth();
      await writePersistedAuth(persisted.clientInfo ? { clientInfo: persisted.clientInfo } : {});
      ctx.ui.notify("Strava disconnected. Run /strava-auth to reconnect.", "info");
    },
  });

  // Register tools eagerly if we already have tokens; calls refresh on demand.
  const persisted = await readPersistedAuth();
  if (persisted.tokens) {
    registerTools();
  }
}
