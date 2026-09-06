# PortalOS

**Nebius × NVIDIA Global AI Hackathon submission**

PortalOS is an AI-first phone OS prototype. The home screen is the agent surface: drop live app context into **Insight**, run **Autopilot** over mail, and open **Agent Channel** — the Token Factory–powered agent that plans your week, month, or year from Mail, Calendar, Notes, and Weather.

Built on **Nebius Token Factory** with **NVIDIA Nemotron** open models.

| | |
|---|---|
| **Track** | **Best Apps and Agents** |
| **Working demo** | https://d21exrzscgvse2.cloudfront.net/ |
| **Repository** | https://github.com/stalkiq/portalsos |
| **License** | [MIT](./LICENSE) (visible at repo root) |
| **Primary model** | `nvidia/Nemotron-3_5-Lightning` via Token Factory |
| **Vision fallback** | `nvidia/Nemotron-3-Nano-Omni` (+ VL fallbacks) |

---

## The challenge (how we meet it)

| Requirement | PortalOS |
|---|---|
| Runs on Nebius Token Factory or Nebius AI Cloud | Yes — all inference goes to `api.tokenfactory.nebius.com` |
| Uses at least one NVIDIA open source model | Yes — NVIDIA Nemotron text + vision models |
| Working project | iOS Simulator app + hosted web demo |
| Category / track | Best Apps and Agents |
| Project description | This README |
| Working demo URL | https://d21exrzscgvse2.cloudfront.net/ |
| Public repo + open source license | This repo, MIT |
| README with setup + Token Factory / Nemotron callouts | Below |
| Feedback on Nebius / NVIDIA tools | [Feedback](#feedback-on-nebius-token-factory--nvidia-tools) |

> **Demo video:** add your public YouTube URL here before final hackathon submit (≤ 3 minutes, with audio covering Token Factory + Nemotron).

---

## What we built

PortalOS treats the phone as an **agent runtime**, not a chat box bolted onto apps.

1. **Insight** — drag Browser, Camera, Notes, Mail, Calendar, Weather, or Agent onto the home-screen chat. Nemotron reads that live context and answers.
2. **Agent Channel** — the dedicated home for the Token Factory agent. It aggregates Mail + Calendar + Notes + Weather and generates actionable **Week / Month / Year** plans.
3. **Mail Autopilot** — watches Gmail (when signed in), drafts replies with Nemotron, and can save important mail to Notes. Drafts are never auto-sent.
4. **App suite** — Browser, Camera (vision), Notes, Mail (Gmail OAuth), Calendar (Google Calendar), Weather (Open-Meteo + Nemotron briefing).

### Why this track

**Best Apps and Agents:** someone would actually use this — a productivity OS with a planning agent, mail drafting, calendar briefing, and camera insight, all routed through Token Factory so inference stays on open Nebius infrastructure.

---

## How NVIDIA Nemotron + Nebius Token Factory are used

| Surface | Model role | Token Factory path |
|---|---|---|
| Agent Channel week/month/year plans | Fast reasoning over multi-app context | `POST /v1/chat/completions` |
| Insight (Mail triage, Calendar brief, Weather) | Everyday Nemotron calls for responsive UX | same |
| Camera Insight | Vision Nemotron / Omni (+ VL fallback) | same |
| Mail “Write with Token Factory” | Draft generation | same |
| Autopilot | Background-style draft / note suggestions | same |
| Web demo `/v1/insight` | Lambda proxy → Token Factory (key never in browser) | same |

**Default text models (iOS, with fallback order):**

- `nvidia/Nemotron-3_5-Lightning`
- `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B`

**Vision models:**

- `nvidia/Nemotron-3-Nano-Omni`

Endpoint used throughout:

```text
https://api.tokenfactory.nebius.com/v1/chat/completions
```

**Where Token Factory accelerated the workflow**

- One OpenAI-compatible chat API for every app surface — no separate model hosting.
- Swap Lightning ↔ Nano without changing app architecture (`NEBIUS_MODEL`).
- Web demo stays serverless: CloudFront + Lambda call Token Factory; API key stays server-side.

**Other Nebius / stack notes**

- Primary: **Nebius Token Factory** (required path for this project).
- Hosted demo: AWS CloudFront + S3 + Lambda proxy (not Nebius Serverless Endpoints — Token Factory is the AI substrate; CDN is only for the public waitlist/demo URL).
- Optional local Node proxy: `backend/server.js` for device/simulator testing without Lambda.

---

## Architecture

```text
┌─────────────────────────────┐
│  PortalOS (SwiftUI iOS)     │
│  Insight · Autopilot · Apps │
│  Agent Channel              │
└──────────────┬──────────────┘
               │ HTTPS chat/completions
               ▼
┌─────────────────────────────┐
│  Nebius Token Factory       │
│  NVIDIA Nemotron models     │
└─────────────────────────────┘

Web demo:
Browser → CloudFront → S3 (static) / Lambda → Token Factory
```

**Context sources the agent can use**

- Gmail (OAuth + PKCE, tokens in Keychain)
- Google Calendar
- Local Notes store
- Open-Meteo weather
- Camera frames (vision)

---

## Quick start

### 1. Nebius Token Factory key

1. Create an API key in [Nebius Token Factory](https://tokenfactory.nebius.com/).
2. Copy `Config/Secrets.xcconfig.example` → `Config/Secrets.xcconfig`:

```xcconfig
NEBIUS_API_KEY = your_key_here
```

`Secrets.xcconfig` and `Sources/Generated/` are gitignored — never commit keys.

Optional overrides:

```text
NEBIUS_MODEL=nvidia/Nemotron-3_5-Lightning
NEBIUS_VISION_MODEL=nvidia/Nemotron-3-Nano-Omni
```

### 2. Run the iOS app (full experience)

Requirements: macOS, Xcode 15+, iOS 17 simulator or device.

```bash
git clone https://github.com/stalkiq/portalsos.git
cd portalsos
open PortalsOS.xcodeproj
```

1. Ensure `Config/Secrets.xcconfig` has `NEBIUS_API_KEY`.
2. Select the **PortalsOS** scheme → iPhone simulator → Run.
3. Pull the app drawer → open **Agent** → choose Week / Month / Year → **Plan**.
4. Sign into Mail/Calendar for live inbox + events; open Weather for forecast context.

Google sign-in needs your own OAuth client IDs configured in the Google Cloud console for Gmail/Calendar scopes (see `GmailEngine.swift` / project Info.plist URL schemes).

### 3. Run the web demo locally

```bash
cd backend
cp .env.example .env   # set NEBIUS_API_KEY
npm start              # or: node server.js
```

Open http://localhost:8080 — phone preview calls Token Factory through the local proxy.

### 4. Hosted demo

https://d21exrzscgvse2.cloudfront.net/

This is an **interactive phone demo** (not a waitlist landing): open Agent to plan a week, triage demo Mail, drag apps into Insight, or flip Autopilot. Every chat call hits Nebius Token Factory via Lambda. The full Google-connected Agent Channel is in the **iOS build**.

---

## Repository layout

```text
Sources/                 SwiftUI OS shell, apps, NebiusService, Agent Channel
Config/                  xcconfig + secret embed helpers (no real keys in git)
backend/                 Local Node proxy + Lambda Token Factory proxy
web/                     Hosted phone demo / waitlist
deploy/                  Endpoint helper scripts
PortalsOS.xcodeproj/     Xcode project
```

---

## Feedback on Nebius Token Factory & NVIDIA tools

**What worked well**

- OpenAI-compatible Token Factory API made it trivial to wire one `NebiusService` for Insight, Agent Channel, Mail drafts, Calendar briefs, and Autopilot.
- Nemotron Lightning / Nano pairing matches the product: fast everyday Insight calls, heavier multi-app planning when needed.
- Model IDs like `nvidia/Nemotron-3_5-Lightning` made the “NVIDIA open model on Nebius” story unambiguous for judges and demos.

**Friction / wishlist**

- Clearer public docs for which Nemotron SKUs support vision vs text-only (we keep an ordered fallback list).
- First-token latency on cold paths can feel long on mobile — streaming helped Insight feel alive.
- A first-class Token Factory “project” + usage dashboard link in the console would help hackathon teams budget credits across Lightning vs Nano.

---

## Prior work note

PortalOS began as a Nebius Token Factory phone-OS prototype before / during the submission period. During the hackathon window we significantly expanded it into a multi-app agent OS: **Agent Channel** (week/month/year planning over Mail · Calendar · Notes · Weather), Google Calendar Insight, Weather, richer Mail Autopilot, and a public CloudFront demo backed by a Token Factory Lambda proxy.

---

## Security notes

- Nebius API keys never ship in the browser; web demo uses a Lambda/Node proxy.
- Gmail/Calendar use OAuth + PKCE; tokens stay in Keychain.
- Autopilot drafts replies — it does not send mail without the user.

---

## License

MIT — see [LICENSE](./LICENSE).
