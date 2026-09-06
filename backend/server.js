const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");

function loadEnvFile(file) {
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq < 1) continue;
    const key = trimmed.slice(0, eq);
    const value = trimmed.slice(eq + 1);
    if (!process.env[key]) process.env[key] = value;
  }
}
loadEnvFile(path.join(__dirname, ".env"));

const PORT = process.env.PORT || 8080;
const NEBIUS_API_KEY = process.env.NEBIUS_API_KEY || "";
const NEBIUS_MODEL = process.env.NEBIUS_MODEL || "nvidia/Nemotron-3_5-Lightning";
const NEBIUS_AI_PROJECT_ID = (process.env.NEBIUS_AI_PROJECT_ID || "").trim();
const NEBIUS_HOST = "api.tokenfactory.nebius.com";
const WEB_ROOT = fs.existsSync(path.join(__dirname, "web"))
  ? path.join(__dirname, "web")
  : path.join(__dirname, "..", "web");

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon"
};

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
  });
  res.end(payload);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function nebiusChat(messages, maxTokens) {
  const payload = JSON.stringify({
    model: NEBIUS_MODEL,
    temperature: 0.4,
    max_tokens: maxTokens,
    messages
  });

  return new Promise((resolve, reject) => {
    const request = https.request(
      {
        hostname: NEBIUS_HOST,
        path: NEBIUS_AI_PROJECT_ID
          ? `/v1/chat/completions?ai_project_id=${encodeURIComponent(NEBIUS_AI_PROJECT_ID)}`
          : "/v1/chat/completions",
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${NEBIUS_API_KEY}`,
          "Content-Length": Buffer.byteLength(payload)
        }
      },
      (response) => {
        const chunks = [];
        response.on("data", (chunk) => chunks.push(chunk));
        response.on("end", () => {
          const raw = Buffer.concat(chunks).toString("utf8");
          let parsed = {};
          try {
            parsed = JSON.parse(raw);
          } catch (error) {
            reject(new Error(raw || "Invalid Nebius response"));
            return;
          }
          if (response.statusCode < 200 || response.statusCode >= 300) {
            const message = parsed.error && parsed.error.message ? parsed.error.message : raw;
            reject(new Error(message));
            return;
          }
          const text = parsed.choices && parsed.choices[0] && parsed.choices[0].message
            ? parsed.choices[0].message.content
            : "";
          resolve((text || "").trim());
        });
      }
    );
    request.on("error", reject);
    request.write(payload);
    request.end();
  });
}

function insightPrompt(body) {
  return [
    {
      role: "system",
      content: "You are PortalOS, an AI-first phone OS assistant running on Nebius Token Factory with NVIDIA Nemotron. Chat like a helpful phone. Be concise. If inbox, note, photo, or page context is provided, use only that context. Never invent Gmail that is not listed. Never write a thinking process."
    },
    {
      role: "user",
      content: [
        body.appName ? `Open app: ${body.appName}.` : "No app pinned. Answer as a general PortalOS assistant.",
        body.contextHint ? `Context:\n${body.contextHint}` : "",
        body.history ? `Recent chat:\n${body.history}` : "",
        `User: ${body.userPrompt || "Say hello and ask how you can help."}`
      ].filter(Boolean).join("\n\n")
    }
  ];
}

function autopilotPrompt() {
  return [
    {
      role: "system",
      content: "You are PortalOS Autopilot. Invent one plausible autonomous action the OS just completed in Browser, Camera, Notes, or Mail. Reply with ONLY compact JSON: {\"title\":\"...\",\"detail\":\"...\",\"symbol\":\"safari.fill\"}. symbol must be safari.fill, camera.fill, note.text, or envelope.fill."
    },
    {
      role: "user",
      content: "Generate the next live Autopilot action now."
    }
  ];
}

function parseAutopilot(text) {
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) {
    return { title: "Autopilot update", detail: text, symbol: "bolt.fill" };
  }
  try {
    const parsed = JSON.parse(match[0]);
    return {
      title: parsed.title || "Autopilot update",
      detail: parsed.detail || text,
      symbol: parsed.symbol || "bolt.fill"
    };
  } catch (error) {
    return { title: "Autopilot update", detail: text, symbol: "bolt.fill" };
  }
}

function serveStatic(res, pathname) {
  const requested = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  const abs = path.resolve(WEB_ROOT, requested);
  if (!abs.startsWith(path.resolve(WEB_ROOT))) {
    send(res, 403, { error: { message: "Forbidden" } });
    return;
  }
  fs.readFile(abs, (err, data) => {
    if (err) {
      send(res, 404, { error: { message: "Not found" } });
      return;
    }
    res.writeHead(200, { "Content-Type": MIME[path.extname(abs)] || "application/octet-stream" });
    res.end(data);
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    send(res, 204, {});
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === "GET" && url.pathname === "/health") {
    send(res, 200, {
      ok: true,
      engine: "nebius",
      project: NEBIUS_AI_PROJECT_ID,
      configured: Boolean(NEBIUS_API_KEY)
    });
    return;
  }

  if (req.method === "POST" && (url.pathname === "/v1/insight" || url.pathname === "/v1/autopilot")) {
    if (!NEBIUS_API_KEY) {
      send(res, 503, { error: { message: "NEBIUS_API_KEY is not set on the PortalOS backend." } });
      return;
    }

    try {
      const body = await readBody(req);
      const isAutopilot = url.pathname === "/v1/autopilot" || body.mode === "autopilot";
      const text = await nebiusChat(isAutopilot ? autopilotPrompt() : insightPrompt(body), isAutopilot ? 120 : 360);
      if (isAutopilot) {
        send(res, 200, parseAutopilot(text));
        return;
      }
      send(res, 200, { text });
    } catch (error) {
      send(res, 502, { error: { message: error.message || "Nebius request failed." } });
    }
    return;
  }

  if (req.method === "GET") {
    serveStatic(res, url.pathname);
    return;
  }

  send(res, 404, { error: { message: "Not found" } });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`PortalOS Nebius backend listening on ${PORT}`);
});
