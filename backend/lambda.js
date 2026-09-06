/**
 * CloudFront cannot hold secrets. This Lambda:
 * - proxies Token Factory for the phone preview (/v1/insight)
 * - saves waitlist emails to DynamoDB (/v1/waitlist)
 */
const https = require("https");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");

const NEBIUS_API_KEY = process.env.NEBIUS_API_KEY || "";
const NEBIUS_MODEL = process.env.NEBIUS_MODEL || "nvidia/Nemotron-3_5-Lightning";
const ORIGIN_SECRET = process.env.ORIGIN_SECRET || "";
const NEBIUS_HOST = "api.tokenfactory.nebius.com";
const WAITLIST_TABLE = process.env.WAITLIST_TABLE || "portalsos-waitlist";
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

function json(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
    },
    body: JSON.stringify(body)
  };
}

function header(event, name) {
  const headers = event.headers || {};
  const match = Object.keys(headers).find((key) => key.toLowerCase() === name.toLowerCase());
  return match ? headers[match] : "";
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
        path: "/v1/chat/completions",
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
          resolve(cleanModelText((text || "").trim()));
        });
      }
    );
    request.on("error", reject);
    request.write(payload);
    request.end();
  });
}

function cleanModelText(text) {
  const raw = (text || "").trim();
  if (!/thinking process/i.test(raw)) return raw;
  const lines = raw.split("\n").map((line) => line.trim()).filter(Boolean);
  const spoken = lines.filter((line) =>
    /^(hello|hi|hey)\b/i.test(line.replace(/^["']|["']$/g, "")) &&
    line.length < 180 &&
    !line.startsWith("-") &&
    !/^\d+\./.test(line)
  );
  if (spoken.length) return spoken[spoken.length - 1].replace(/^["']|["']$/g, "");
  const last = lines.filter((line) => !line.startsWith("-") && !/^\d+\./.test(line) && line.length < 180);
  return last[last.length - 1] || "Hello — PortalOS is ready.";
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

function parseBody(event) {
  let raw = event.body || "{}";
  if (event.isBase64Encoded) {
    raw = Buffer.from(raw, "base64").toString("utf8");
  }
  return raw ? JSON.parse(raw) : {};
}

function normalizeEmail(value) {
  const email = String(value || "").trim().toLowerCase();
  if (!email || email.length > 254) return null;
  if (!/^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$/i.test(email)) return null;
  return email;
}

async function addWaitlist(email) {
  const existing = await ddb.send(new GetCommand({ TableName: WAITLIST_TABLE, Key: { email } }));
  if (existing.Item) return { already: true };
  try {
    await ddb.send(new PutCommand({
      TableName: WAITLIST_TABLE,
      Item: {
        email,
        createdAt: new Date().toISOString(),
        source: "waitlist"
      },
      ConditionExpression: "attribute_not_exists(email)"
    }));
  } catch (error) {
    if (error.name === "ConditionalCheckFailedException") return { already: true };
    throw error;
  }
  return { already: false };
}

exports.handler = async (event) => {
  const method = (event.requestContext && event.requestContext.http && event.requestContext.http.method)
    || event.httpMethod
    || "GET";
  const path = event.rawPath || (event.requestContext && event.requestContext.http && event.requestContext.http.path) || "/";

  if (method === "OPTIONS") {
    return json(204, {});
  }

  if (ORIGIN_SECRET && header(event, "x-portalsos-proxy") !== ORIGIN_SECRET) {
    return json(403, { error: { message: "Forbidden" } });
  }

  if (method === "GET" && path === "/health") {
    return json(200, { ok: true, engine: "nebius", configured: Boolean(NEBIUS_API_KEY) });
  }

  if (method === "POST" && path === "/v1/waitlist") {
    try {
      const body = parseBody(event);
      const email = normalizeEmail(body.email);
      if (!email) {
        return json(400, { error: { message: "Enter a valid email." } });
      }
      const result = await addWaitlist(email);
      return json(200, { ok: true, already: result.already });
    } catch (error) {
      return json(502, { error: { message: "Could not save that email." } });
    }
  }

  if (method === "POST" && (path === "/v1/insight" || path === "/v1/autopilot")) {
    if (!NEBIUS_API_KEY) {
      return json(503, { error: { message: "NEBIUS_API_KEY is not set." } });
    }
    try {
      const body = parseBody(event);
      const text = await nebiusChat(insightPrompt(body), 360);
      return json(200, { text });
    } catch (error) {
      return json(502, { error: { message: error.message || "Nebius request failed." } });
    }
  }

  return json(404, { error: { message: "Not found" } });
};
