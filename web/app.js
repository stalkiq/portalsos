const dockApps = [
  { id: "Browser", hint: "Browser is open on a PortalOS search page." },
  { id: "Camera", hint: "Camera is ready. Capture a photo for vision insight." },
  { id: "Notes", hint: "Notes holds local ideas you can drop into Insight." },
  { id: "Mail", hint: "Demo inbox is pinned for triage and drafts." }
];

const drawerApps = [
  { id: "Agent", hint: "Agent Channel plans week/month/year from Mail, Calendar, Notes, Weather, Maps." },
  { id: "Calendar", hint: "Demo calendar: Pro meeting, check-in, Charlotte→Fort Myers flights." },
  { id: "Weather", hint: "Demo forecast: mild week, rain midweek." },
  { id: "Maps", hint: "Demo Google Maps place + route for Token Factory trip briefs." }
];

const allApps = [...dockApps, ...drawerApps];

const icons = {
  Browser: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><path d="M12 3c2.2 3 3.3 6 3.3 9s-1.1 6-3.3 9c-2.2-3-3.3-6-3.3-9s1.1-6 3.3-9z"/><path d="M3.5 9.5h17M3.5 14.5h17"/></svg>',
  Camera: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 8.5h3l1.4-2h7.2l1.4 2H20a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 20 19.5H4A1.5 1.5 0 0 1 2.5 18v-8A1.5 1.5 0 0 1 4 8.5z"/><circle cx="12" cy="13.5" r="3.2"/></svg>',
  Notes: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M7 3.5h7.5L19.5 8v12.5a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4.5a1 1 0 0 1 1-1z"/><path d="M14.5 3.5V8H19.5M8.5 12h7M8.5 15.5h7M8.5 19h4.5"/></svg>',
  Mail: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3.5" y="6" width="17" height="12.5" rx="2"/><path d="M4 7.5l8 6 8-6"/></svg>',
  Agent: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 3l1.2 4.2L17.5 8.5l-4.3 1.3L12 14l-1.2-4.2L6.5 8.5l4.3-1.3L12 3z"/><path d="M18.5 14l.7 2.3 2.3.7-2.3.7-.7 2.3-.7-2.3-2.3-.7 2.3-.7.7-2.3z"/></svg>',
  Calendar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3.5" y="5.5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3.5v4M16 3.5v4M8 14h3M13 14h3M8 17.5h3"/></svg>',
  Weather: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="9" cy="10" r="3.2"/><path d="M9 4.5v1.2M9 14.3v1.2M4.5 10H3.3M14.7 10h-1.2M5.7 6.7l-.9-.9M13.2 14.2l-.9-.9M13.2 5.8l-.9.9M5.7 13.3l-.9.9"/><path d="M12.5 16.5h5.2a3.3 3.3 0 1 0-.4-6.55A4.4 4.4 0 0 0 9.2 8.2"/></svg>',
  Maps: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M9 4.5l-5.5 2.2v12.6L9 17.1l6 2.4 5.5-2.2V4.7L15 6.9 9 4.5z"/><path d="M9 4.5v12.6M15 6.9v12.6"/></svg>'
};

const demoMaps = {
  name: "The Metropolitan Museum of Art",
  address: "1000 5th Ave, New York, NY",
  route: "Drive 18 min · 4.2 km from Midtown",
  detail: "Leave by 10:35 AM for an 11:00 visit. Street parking is tight near Fifth Ave — consider a garage on 83rd."
};

const demoMail = [
  {
    id: "m1",
    from: "Jordan Hale",
    subject: "Monday standup notes",
    unread: true,
    snippet: "Three bullets from this morning’s sync. Nothing needs a reply today.",
    date: "9:14 AM",
    body: "Three bullets from this morning’s sync.\n\n1. Home screen Autopilot layout is locked.\n2. Waitlist copy is final.\n3. Nothing needs a reply today."
  },
  {
    id: "m2",
    from: "Northwind Studio",
    subject: "Design review moved to 4pm",
    unread: true,
    snippet: "Same link as last week. Bring the latest home-screen mock.",
    date: "8:02 AM",
    body: "Same link as last week. Bring the latest home-screen mock.\n\nIf 4pm does not work, send a note before noon."
  },
  {
    id: "m3",
    from: "PortalOS Digest",
    subject: "What Autopilot drafted overnight",
    unread: false,
    snippet: "Two suggested replies are waiting. Nothing was sent.",
    date: "Yesterday",
    body: "Two suggested replies are waiting. Nothing was sent.\n\nOpen Autopilot to review drafts before they expire."
  }
];

const demoCalendar = {
  subtitle: "7 upcoming events",
  hero: "Charlotte then Fort Myers, 2h50 layover",
  detail: "Pro meeting at 11:00 AM, then check-in at 12:00 PM. Flight to Charlotte at 2:39 PM, layover 2h50m, then flight to Fort Myers at 7:55 PM.",
  next: "Pro between Slashy and Al Moreau at 11:00 AM",
  risk: "No conflicts",
  free: "Open after 9:30 PM"
};

const state = {
  systemOn: false,
  drawerOpen: true,
  context: null,
  messages: [],
  notes: JSON.parse(localStorage.getItem("portalsos.notes") || "[]"),
  selectedNote: 0,
  browserUrl: "https://www.google.com/search?igu=1&q=PortalOS",
  photo: null,
  busy: false,
  autoFeed: [],
  autoTimers: [],
  openAppId: null,
  mailView: "inbox",
  mailIndex: 0,
  mailItems: demoMail.map((item) => ({ ...item })),
  compose: null,
  drafting: false,
  calendarBrief: null
};

const $ = (id) => document.getElementById(id);

function saveNotes() {
  localStorage.setItem("portalsos.notes", JSON.stringify(state.notes));
}

function appById(id) {
  return allApps.find((item) => item.id === id);
}

function scrubModelText(text) {
  let out = (text || "").trim();
  if (/thinking process|chain of thought|<think>/i.test(out)) {
    out = out
      .replace(/<think>[\s\S]*?<\/think>/gi, "")
      .replace(/^here's a thinking process:[\s\S]*?(?:\n\n|$)/i, "")
      .replace(/^thinking process:[\s\S]*?(?:\n\n|$)/i, "")
      .trim();
    if (!out) {
      const parts = (text || "").split(/\n\n+/);
      out = (parts[parts.length - 1] || "").trim();
    }
  }
  return out || "No reply.";
}

function tileButton(app) {
  return `<button class="app-tile" draggable="true" data-id="${app.id}" title="${app.id}">
    <span class="app-glyph">${icons[app.id] || ""}</span>
    <small>${app.id}</small>
  </button>`;
}

function bindTiles(root) {
  root.querySelectorAll(".app-tile").forEach((el) => {
    el.addEventListener("click", () => openApp(el.dataset.id));
    if (state.systemOn) {
      el.draggable = false;
      return;
    }
    el.addEventListener("dragstart", (event) => {
      el.classList.add("dragging");
      event.dataTransfer.setData("text/plain", el.dataset.id);
    });
    el.addEventListener("dragend", () => el.classList.remove("dragging"));
  });
}

function renderDock() {
  $("dock").innerHTML = dockApps.map(tileButton).join("") +
    `<button type="button" class="power ${state.systemOn ? "on" : ""}" id="power" aria-pressed="${state.systemOn}" aria-label="Autopilot ${state.systemOn ? "on" : "off"}"></button>`;
  bindTiles($("dock"));
  $("power").onclick = togglePower;
}

function renderDrawer() {
  const drawer = $("drawer");
  drawer.classList.toggle("open", state.drawerOpen && !state.systemOn);
  drawer.innerHTML = drawerApps.map(tileButton).join("");
  bindTiles(drawer);
  $("drawerToggle")?.classList.toggle("open", state.drawerOpen && !state.systemOn);
}

function renderClock() {
  const now = new Date();
  $("statusTime").textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  $("homeDate").textContent = now.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
}

function contextMeta(id) {
  if (id === "Mail") return `${state.mailItems.length} messages · ${state.mailItems.filter((m) => m.unread).length} unread`;
  if (id === "Calendar") return demoCalendar.subtitle;
  if (id === "Weather") return "New York · demo forecast";
  if (id === "Maps") return demoMaps.name;
  if (id === "Notes") {
    const note = state.notes[state.selectedNote];
    return note ? (note.title || "Untitled note") : "No note selected";
  }
  if (id === "Browser") return "PortalOS search";
  if (id === "Agent") return "Mail · Calendar · Notes · Weather";
  if (id === "Camera") return state.photo ? "Photo captured" : "No photo yet";
  return "";
}

function placeholderFor(id) {
  switch (id) {
    case "Mail": return "Send a reply, or save an email to Notes…";
    case "Camera": return "Ask about this photo…";
    case "Notes": return "Ask about this note…";
    case "Browser": return "Ask about this page…";
    case "Calendar": return "Add an event, or ask about this week…";
    case "Weather": return "Ask about this forecast…";
    case "Maps": return "Ask about this place or route…";
    case "Agent": return "Plan my week, month, or year…";
    default: return "Ask PortalOS…";
  }
}

function emptyCopy() {
  return `<div class="empty">
    <strong>AI system ready</strong>
    Drop an app into Insight for live context, or ask PortalOS anything. Autopilot is the red power toggle.
  </div>`;
}

function calendarBriefHtml() {
  const b = demoCalendar;
  return `<div class="cal-brief">
    <h2>${escapeHtml(b.hero)}</h2>
    <p class="cal-detail">${escapeHtml(b.detail)}</p>
    <div class="cal-chip next"><span>NEXT</span><b>${escapeHtml(b.next)}</b></div>
    <div class="cal-chip risk"><span>RISK</span><b>${escapeHtml(b.risk)}</b></div>
    <div class="cal-chip free"><span>FREE</span><b>${escapeHtml(b.free)}</b></div>
  </div>`;
}

function renderTryRow() {
  const row = $("tryRow");
  if (!row) return;
  const show = !state.systemOn && !state.context && state.messages.length === 0 && !state.busy;
  row.hidden = !show;
  if (!show) {
    row.innerHTML = "";
    return;
  }
  row.innerHTML = [
    ["Plan week", "agent"],
    ["Triage Mail", "mail"],
    ["Brief Maps", "maps"]
  ].map(([label, id]) => `<button type="button" class="try-chip" data-try="${id}">${label}</button>`).join("");
  row.querySelectorAll("[data-try]").forEach((btn) => {
    btn.onclick = () => {
      const kind = btn.dataset.try;
      if (kind === "agent") return pinApp("Agent");
      if (kind === "mail") return pinApp("Mail");
      if (kind === "maps") return pinApp("Maps");
    };
  });
}

function renderChat() {
  const head = $("insightHead");
  const title = $("analyzingTitle");
  const sub = $("analyzingSub");
  const prompt = $("prompt");
  if (state.context) {
    head.hidden = false;
    title.textContent = `Analyzing ${state.context}`;
    sub.textContent = contextMeta(state.context);
    prompt.placeholder = placeholderFor(state.context);
  } else {
    head.hidden = state.messages.length === 0;
    title.textContent = "Insight";
    sub.textContent = "";
    prompt.placeholder = "Ask PortalOS…";
  }

  const box = $("transcript");
  if (state.context === "Calendar" && state.calendarBrief && state.messages.length <= 1) {
    box.innerHTML = calendarBriefHtml();
  } else if (!state.messages.length) {
    box.innerHTML = emptyCopy();
  } else {
    box.innerHTML = state.messages
      .filter((m) => m.role !== "system")
      .map((m) => {
        if (m.role === "assistant" && state.context === "Calendar" && state.calendarBrief && m.brief) {
          return calendarBriefHtml();
        }
        return `<div class="bubble ${m.role}">${escapeHtml(m.text)}</div>`;
      })
      .join("");
    box.scrollTop = box.scrollHeight;
  }
  if (state.busy) {
    box.innerHTML += `<div class="typing">Nemotron is writing…</div>`;
  }
  renderTryRow();
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function contextHint() {
  if (state.context === "Agent") {
    const note = state.notes[state.selectedNote];
    return [
      "PortalOS Agent Channel context.",
      "MAIL:\n" + demoMail.map((m) => `${m.unread ? "UNREAD" : "read"} ${m.from} | ${m.subject} | ${m.snippet}`).join("\n"),
      note ? `NOTES:\n${note.title}\n${note.body}` : "NOTES: none",
      `CALENDAR:\n${demoCalendar.hero}\n${demoCalendar.detail}`,
      "WEATHER: mild week, rain chance midweek.",
      `MAPS:\n${demoMaps.name} · ${demoMaps.route}\n${demoMaps.detail}`
    ].join("\n\n");
  }
  if (state.context === "Mail") {
    return "Sample inbox:\n" + demoMail.map((m) => `${m.unread ? "UNREAD" : "read"} ${m.from} | ${m.subject} | ${m.snippet}`).join("\n");
  }
  if (state.context === "Calendar") {
    return `Google Calendar demo:\n${demoCalendar.hero}\n${demoCalendar.detail}\nNEXT: ${demoCalendar.next}\nRISK: ${demoCalendar.risk}\nFREE: ${demoCalendar.free}`;
  }
  if (state.context === "Weather") {
    return "Open-Meteo demo: New York, high 74°F, low 61°F, rain chance Wednesday, otherwise mild.";
  }
  if (state.context === "Maps") {
    return `Google Maps demo place:\nName: ${demoMaps.name}\nAddress: ${demoMaps.address}\nRoute: ${demoMaps.route}\nNotes: ${demoMaps.detail}`;
  }
  if (state.context === "Notes") {
    const note = state.notes[state.selectedNote];
    return note ? `Open note: ${note.title}\n${note.body}` : "Notes app open, no note selected.";
  }
  if (state.context === "Browser") return `Browser open at ${state.browserUrl}`;
  if (state.context === "Camera") {
    return state.photo ? "A photo is captured on Camera." : "Camera open, no photo yet.";
  }
  return "";
}

async function ask(text) {
  if (!text || state.busy) return;
  state.messages.push({ role: "user", text });
  renderChat();
  state.busy = true;
  $("prompt").value = "";
  renderChat();
  try {
    const response = await fetch("/v1/insight", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        appName: state.context || "PortalOS",
        contextHint: contextHint() + "\n\nReply with the final answer only. No thinking process.",
        userPrompt: text + "\n/no_think",
        history: state.messages.slice(-8).map((m) => `${m.role}: ${m.text}`).join("\n")
      })
    });
    const data = await response.json();
    const reply = scrubModelText(data.text || (data.error && data.error.message) || "No reply");
    state.messages.push({ role: "assistant", text: reply });
  } catch (error) {
    state.messages.push({ role: "assistant", text: "Could not reach Token Factory. " + error.message });
  }
  state.busy = false;
  renderChat();
}

function newChat() {
  state.context = null;
  state.messages = [];
  state.calendarBrief = null;
  renderChat();
}

function pinApp(id) {
  state.context = id;
  state.messages = [];
  state.calendarBrief = null;
  renderChat();
  if (id === "Mail") {
    ask("Triage this inbox. What is important, what is noise, and what is safe to ignore. Short bullets only.");
    return;
  }
  if (id === "Agent") {
    ask("Plan my week. Prioritize the next 7 days using mail, notes, calendar, and weather. Short actionable bullets only.");
    return;
  }
  if (id === "Calendar") {
    state.calendarBrief = demoCalendar;
    state.messages = [{ role: "assistant", text: demoCalendar.hero, brief: true }];
    renderChat();
    return;
  }
  if (id === "Weather") {
    ask("Brief this forecast. What to wear, umbrella or not, and the day that changes plans. Short bullets only.");
    return;
  }
  if (id === "Maps") {
    ask("Brief this Google Maps place and route. Leave-by time, how to go, and what to watch for. Short bullets only.");
    return;
  }
  const app = appById(id);
  ask(`Brief ${id}. ${app ? app.hint : ""} Keep it under 6 short sentences. Final answer only.`);
}

function clearAutoTimers() {
  state.autoTimers.forEach((id) => clearTimeout(id));
  state.autoTimers = [];
}

function pushAuto(event) {
  state.autoFeed.unshift(event);
  state.autoFeed = state.autoFeed.slice(0, 4);
  renderAutoFeed();
}

function renderAutoFeed() {
  const feed = $("autoFeed");
  if (!feed) return;
  feed.innerHTML = state.autoFeed.map((event, index) => `
    <div class="auto-item">
      <div class="auto-item-row">
        <span class="auto-sym">${event.icon || "•"}</span>
        <div>
          <strong>${escapeHtml(event.title)}</strong>
          <p>${escapeHtml(event.detail)}</p>
        </div>
      </div>
      ${event.draft && !event.didSend
        ? `<button type="button" class="send-draft" data-i="${index}">Send to ${escapeHtml(event.draft.to)}</button>`
        : ""}
      ${event.didSend ? `<p class="sent">Sent</p>` : ""}
    </div>
  `).join("");
  feed.querySelectorAll(".send-draft").forEach((btn) => {
    btn.onclick = () => {
      const item = state.autoFeed[Number(btn.dataset.i)];
      if (!item || !item.draft || item.didSend) return;
      item.didSend = true;
      item.detail = `Sent to ${item.draft.to}.`;
      renderAutoFeed();
    };
  });
}

function applySystemLayout() {
  $("autopilot").hidden = !state.systemOn;
  $("insightBody").hidden = state.systemOn;
  $("composer").hidden = state.systemOn;
  $("drawerToggle").style.visibility = state.systemOn ? "hidden" : "visible";
  $("homeDate").style.opacity = state.systemOn ? "0" : "1";
  renderDock();
  renderDrawer();
  if (state.systemOn) renderAutoFeed();
}

function togglePower() {
  state.systemOn = !state.systemOn;
  applySystemLayout();
  if (state.systemOn) startAutopilot();
  else stopAutopilot();
}

function startAutopilot() {
  clearAutoTimers();
  state.autoFeed = [{
    icon: "⚡",
    title: "Watching inbox",
    detail: "Autopilot will triage new mail, draft replies, and save important threads to Notes. Drafts are not sent until you tap Send."
  }];
  renderAutoFeed();
  state.autoTimers.push(setTimeout(() => {
    if (!state.systemOn) return;
    pushAuto({
      icon: "✎",
      title: "Draft ready",
      detail: "Northwind moved the review. Confirm you can make 4pm.",
      draft: { to: "studio@northwind.example" }
    });
  }, 1800));
  state.autoTimers.push(setTimeout(() => {
    if (!state.systemOn) return;
    const note = { title: "PortalOS Digest", body: "Two suggested replies are waiting. Nothing was sent." };
    if (!state.notes.some((item) => item.title === note.title)) {
      state.notes.unshift(note);
      saveNotes();
    }
    pushAuto({
      icon: "📝",
      title: "Saved to Notes",
      detail: `“${note.title}” — kept the overnight digest so you can review drafts later.`
    });
  }, 4200));
}

function stopAutopilot() {
  clearAutoTimers();
  state.autoFeed = [{
    icon: "⏻",
    title: "Autopilot standby",
    detail: "Turn ON to watch Mail, draft replies, and save important mail to Notes."
  }];
}

function senderInitial(from) {
  return (from || "?").trim().charAt(0).toUpperCase();
}

function nebiusMark() {
  return `<p class="nebius-mark"><i></i>Powered by Nebius</p>`;
}

function setSheetChrome(id, title, actionsHtml, closeLabel) {
  $("appSheet").className = "sheet " + id.toLowerCase();
  $("sheetTitle").textContent = title;
  $("sheetTitle").classList.toggle("ghost", !title);
  $("sheetActions").innerHTML = actionsHtml || "";
  $("closeSheet").textContent = closeLabel || "Close";
}

function ensureNotes() {
  if (!state.notes.length) {
    state.notes = [{
      title: "Welcome",
      body: "Write ideas here. Close this app and drag Notes into Insight to summarize, extract tasks, or suggest a next step."
    }];
    state.selectedNote = 0;
    saveNotes();
  }
  if (state.selectedNote >= state.notes.length) state.selectedNote = 0;
}

function renderNotes() {
  ensureNotes();
  const note = state.notes[state.selectedNote] || state.notes[0];
  setSheetChrome("Notes", "Notes", `<button type="button" id="addNote">New</button><button type="button" class="danger" id="deleteNote">Delete</button>`);
  $("sheetBody").innerHTML = `
    <div class="notes-split">
      <div class="notes-list">
        ${state.notes.map((item, index) => `
          <button type="button" class="note-card ${index === state.selectedNote ? "selected" : ""}" data-i="${index}">
            <strong>${escapeHtml(item.title || "Untitled")}</strong>
            <span>${escapeHtml(item.body || "Empty note")}</span>
          </button>`).join("")}
      </div>
      <div class="notes-editor">
        <input class="note-title" id="noteTitle" value="${escapeHtml(note.title)}" placeholder="Title" />
        <textarea class="note-body" id="noteBody" placeholder="Note">${escapeHtml(note.body)}</textarea>
      </div>
    </div>`;
  $("addNote").onclick = () => {
    persistNote();
    state.notes.unshift({ title: "New note", body: "" });
    state.selectedNote = 0;
    saveNotes();
    renderNotes();
  };
  $("deleteNote").onclick = () => {
    state.notes.splice(state.selectedNote, 1);
    state.selectedNote = 0;
    saveNotes();
    renderNotes();
  };
  $("sheetBody").querySelectorAll("[data-i]").forEach((btn) => {
    btn.onclick = () => {
      persistNote();
      state.selectedNote = Number(btn.dataset.i);
      renderNotes();
    };
  });
  $("noteTitle").oninput = persistNote;
  $("noteBody").oninput = persistNote;
}

function persistNote() {
  if (!state.notes[state.selectedNote]) return;
  state.notes[state.selectedNote] = { title: $("noteTitle").value, body: $("noteBody").value };
  saveNotes();
}

function renderMailInbox() {
  const items = state.mailItems;
  const latest = items[0];
  const earlier = items.slice(1);
  setSheetChrome("Mail", "", `<button type="button" class="sheet-icon" id="composeMail" aria-label="New message">✎</button>`);
  $("sheetBody").innerHTML = `
    <div class="mail-screen"><div class="mail-inbox">
      <div class="mail-incoming"><h2>Incoming</h2><span class="mail-live"><i></i>LIVE</span></div>
      <p class="mail-meta">${items.length} signals  ·  sample inbox</p>
      ${nebiusMark()}
      ${latest ? `<button type="button" class="mail-now" data-i="0">
        <span class="watermark">${escapeHtml(senderInitial(latest.from))}</span>
        <p class="mail-kicker">NOW</p>
        <h3>${escapeHtml(latest.subject)}</h3>
        <p>${escapeHtml(latest.snippet)}</p>
        <div class="mail-now-foot"><span>${escapeHtml(latest.from.toUpperCase())}</span><span>${escapeHtml(latest.date)}</span></div>
      </button>` : `<p class="mail-kicker">NO SIGNAL</p><h2>Inbox is quiet.</h2>`}
      ${earlier.length ? `<p class="mail-earlier">EARLIER</p>` : ""}
      ${earlier.map((item, index) => `
        <button type="button" class="mail-row" data-i="${index + 1}">
          <span class="mail-rail"><i></i><b></b></span>
          <span class="mail-row-copy">
            <span class="mail-row-top"><span>${escapeHtml(item.from)}</span><span>${escapeHtml(item.date)}</span></span>
            <strong>${escapeHtml(item.subject)}</strong>
          </span>
        </button>`).join("")}
    </div></div>`;
  $("composeMail").onclick = () => {
    state.mailView = "compose";
    state.compose = { to: "", subject: "", body: "", hint: "", replyTo: null };
    renderMail();
  };
  $("sheetBody").querySelectorAll("[data-i]").forEach((btn) => {
    btn.onclick = () => {
      state.mailView = "read";
      state.mailIndex = Number(btn.dataset.i);
      renderMail();
    };
  });
}

function renderMailReader() {
  const message = state.mailItems[state.mailIndex];
  if (!message) {
    state.mailView = "inbox";
    return renderMailInbox();
  }
  setSheetChrome("Mail", "", "", "Inbox");
  $("sheetBody").innerHTML = `
    <div class="mail-reader"><div class="mail-reader-body">
      <p class="mail-kicker">MESSAGE</p>
      <h3>${escapeHtml(message.subject)}</h3>
      <div class="mail-from"><b>${escapeHtml(message.from)}</b><span>${escapeHtml(message.date)}</span></div>
      <div class="mail-hairline"></div>
      <p>${escapeHtml(message.body || message.snippet)}</p>
    </div>
    <div class="mail-actions">
      <button type="button" class="mail-action" id="mailReply">Reply</button>
      <button type="button" class="mail-action" id="mailArchive">Archive</button>
      <button type="button" class="mail-action" id="mailTrash">Trash</button>
    </div>
    <button type="button" class="mail-portal" id="mailPortal">Add to Portal</button>
    <div style="padding:0 20px 18px">${nebiusMark()}</div></div>`;
  $("mailReply").onclick = () => {
    state.mailView = "compose";
    state.compose = {
      to: message.from.toLowerCase().replace(/\s+/g, ".") + "@example.com",
      subject: message.subject.startsWith("Re:") ? message.subject : "Re: " + message.subject,
      body: "",
      hint: "",
      replyTo: message
    };
    renderMail();
  };
  const removeCurrent = () => {
    state.mailItems.splice(state.mailIndex, 1);
    state.mailView = "inbox";
    renderMail();
  };
  $("mailArchive").onclick = removeCurrent;
  $("mailTrash").onclick = removeCurrent;
  $("mailPortal").onclick = () => {
    $("appSheet").hidden = true;
    pinApp("Mail");
  };
}

function renderMailCompose() {
  const compose = state.compose || { to: "", subject: "", body: "", hint: "", replyTo: null };
  state.compose = compose;
  setSheetChrome("Mail", compose.replyTo ? "Reply" : "New Message", `<button type="button" class="accent" id="mailSend">Send</button>`, "Cancel");
  $("sheetBody").innerHTML = `
    <div class="mail-compose"><div class="mail-compose-body">
      <label><span>To</span><input id="mailTo" value="${escapeHtml(compose.to)}" placeholder="To" /></label>
      <label><span>Subject</span><input id="mailSubject" value="${escapeHtml(compose.subject)}" placeholder="Subject" /></label>
      <label><span>Direction for Token Factory</span><input id="mailHint" value="${escapeHtml(compose.hint)}" placeholder="Optional direction…" /></label>
      <button type="button" class="mail-draft" id="mailDraft" ${state.drafting ? "disabled" : ""}>${state.drafting ? "Nemotron is writing..." : "Write with Token Factory"}</button>
      <label><span>Body</span><textarea id="mailBody">${escapeHtml(compose.body)}</textarea></label>
      ${nebiusMark()}
    </div></div>`;
  const readCompose = () => {
    state.compose = {
      ...state.compose,
      to: $("mailTo").value,
      subject: $("mailSubject").value,
      hint: $("mailHint").value,
      body: $("mailBody").value
    };
  };
  ["mailTo", "mailSubject", "mailHint", "mailBody"].forEach((id) => { $(id).oninput = readCompose; });
  $("mailSend").onclick = () => {
    readCompose();
    state.mailView = "inbox";
    state.compose = null;
    renderMail();
  };
  $("mailDraft").onclick = () => draftCompose();
}

async function draftCompose() {
  if (state.drafting) return;
  state.compose = {
    ...state.compose,
    to: $("mailTo").value,
    subject: $("mailSubject").value,
    hint: $("mailHint").value,
    body: $("mailBody").value
  };
  state.drafting = true;
  renderMailCompose();
  try {
    const response = await fetch("/v1/insight", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        appName: "Mail",
        contextHint: `To: ${state.compose.to}\nSubject: ${state.compose.subject}\n${state.compose.replyTo ? "Original:\n" + state.compose.replyTo.body : ""}`,
        userPrompt: `Write a short email body only. No preamble. No thinking. ${state.compose.hint || "Keep it specific and polite."}`
      })
    });
    const data = await response.json();
    state.compose.body = scrubModelText(data.text || "");
  } catch (error) {
    state.compose.body = "Could not reach Token Factory. " + error.message;
  }
  state.drafting = false;
  renderMailCompose();
}

function renderMail() {
  if (state.mailView === "read") renderMailReader();
  else if (state.mailView === "compose") renderMailCompose();
  else renderMailInbox();
}

function closeSheet() {
  if (state.openAppId === "Mail" && state.mailView !== "inbox") {
    state.mailView = "inbox";
    state.compose = null;
    renderMail();
    return;
  }
  $("appSheet").hidden = true;
  state.openAppId = null;
}

function openApp(id) {
  state.openAppId = id;
  $("appSheet").hidden = false;
  if (id === "Notes") return renderNotes();
  if (id === "Mail") {
    state.mailView = "inbox";
    state.compose = null;
    return renderMail();
  }
  if (id === "Agent") {
    setSheetChrome("Agent", "Agent Channel", "");
    $("sheetBody").innerHTML = `
      <div class="mail-reader"><div class="mail-reader-body">
        <p class="mail-kicker">TOKEN FACTORY AGENT</p>
        <h3>Agent Channel</h3>
        <p>Plans week / month / year from Mail, Calendar, Notes, and Weather using NVIDIA Nemotron on Nebius Token Factory.</p>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:14px">
          <button type="button" class="mail-action" data-h="week">Plan week</button>
          <button type="button" class="mail-action" data-h="month">Plan month</button>
          <button type="button" class="mail-action" data-h="year">Plan year</button>
        </div>
        <button type="button" class="mail-portal" id="agentPortal" style="margin-top:16px">Add to Portal</button>
        <div style="padding:12px 0 0">${nebiusMark()}</div>
      </div></div>`;
    $("sheetBody").querySelectorAll("[data-h]").forEach((btn) => {
      btn.onclick = () => {
        $("appSheet").hidden = true;
        state.context = "Agent";
        state.messages = [];
        renderChat();
        ask(`Plan my ${btn.dataset.h}. Use mail, notes, calendar, weather. Short actionable bullets. Final answer only.`);
      };
    });
    $("agentPortal").onclick = () => {
      $("appSheet").hidden = true;
      pinApp("Agent");
    };
    return;
  }
  if (id === "Calendar") {
    setSheetChrome("Calendar", "Calendar", "");
    $("sheetBody").innerHTML = `
      <div class="mail-reader-body" style="padding:18px 20px">
        <p class="mail-kicker">DEMO CALENDAR</p>
        <h3 style="color:#fff;margin:0 0 10px">${escapeHtml(demoCalendar.hero)}</h3>
        <p>${escapeHtml(demoCalendar.detail)}</p>
        <button type="button" class="mail-portal" id="calPortal" style="margin-top:18px">Add to Portal</button>
        ${nebiusMark()}
      </div>`;
    $("calPortal").onclick = () => {
      $("appSheet").hidden = true;
      pinApp("Calendar");
    };
    return;
  }
  if (id === "Weather") {
    setSheetChrome("Weather", "Weather", "");
    $("sheetBody").innerHTML = `
      <div class="mail-reader-body" style="padding:18px 20px">
        <p class="mail-kicker">OPEN-METEO DEMO</p>
        <h3 style="color:#fff;margin:0 0 10px">New York</h3>
        <p>High 74° · Low 61° · Rain chance Wednesday. Otherwise mild.</p>
        <button type="button" class="mail-portal" id="wxPortal" style="margin-top:18px">Add to Portal</button>
        ${nebiusMark()}
      </div>`;
    $("wxPortal").onclick = () => {
      $("appSheet").hidden = true;
      pinApp("Weather");
    };
    return;
  }
  if (id === "Maps") {
    setSheetChrome("Maps", "Maps", "");
    $("sheetBody").innerHTML = `
      <div class="mail-reader-body" style="padding:18px 20px">
        <p class="mail-kicker">GOOGLE MAPS DEMO</p>
        <h3 style="color:#fff;margin:0 0 10px">${escapeHtml(demoMaps.name)}</h3>
        <p>${escapeHtml(demoMaps.address)}</p>
        <p style="margin-top:10px">${escapeHtml(demoMaps.route)}</p>
        <p>${escapeHtml(demoMaps.detail)}</p>
        <button type="button" class="mail-portal" id="mapsPortal" style="margin-top:18px">Add to Portal</button>
        ${nebiusMark()}
      </div>`;
    $("mapsPortal").onclick = () => {
      $("appSheet").hidden = true;
      pinApp("Maps");
    };
    return;
  }
  setSheetChrome(id, id, "");
  const body = $("sheetBody");
  if (id === "Camera") {
    body.innerHTML = `
      <p>Capture or choose a photo, then drop Camera into Insight.</p>
      <input id="cam" type="file" accept="image/*" capture="environment" />
      ${state.photo ? `<img class="preview" src="${state.photo}" alt="Captured" />` : ""}
      <button type="button" class="mail-portal" id="camPortal" style="margin-top:16px">Add to Portal</button>`;
    $("cam").onchange = (event) => {
      const file = event.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => { state.photo = reader.result; openApp("Camera"); };
      reader.readAsDataURL(file);
    };
    $("camPortal").onclick = () => {
      $("appSheet").hidden = true;
      pinApp("Camera");
    };
    return;
  }
  body.innerHTML = `
    <div class="browser-row">
      <input class="field" id="url" value="${escapeHtml(state.browserUrl)}" />
      <button type="button" id="go">Go</button>
    </div>
    <iframe title="Browser" src="${state.browserUrl}" style="width:100%;height:420px;border:0;border-radius:12px;background:white"></iframe>
    <button type="button" class="mail-portal" id="brPortal" style="margin-top:12px">Add to Portal</button>`;
  $("go").onclick = () => {
    let url = $("url").value.trim();
    if (!/^https?:/i.test(url)) url = "https://www.google.com/search?igu=1&q=" + encodeURIComponent(url);
    state.browserUrl = url;
    openApp("Browser");
  };
  $("brPortal").onclick = () => {
    $("appSheet").hidden = true;
    pinApp("Browser");
  };
}

function bind() {
  $("composer").addEventListener("submit", (event) => {
    event.preventDefault();
    ask($("prompt").value.trim());
  });
  $("newChat").onclick = newChat;
  $("closeSheet").onclick = closeSheet;
  $("drawerToggle").onclick = () => {
    state.drawerOpen = !state.drawerOpen;
    renderDrawer();
  };
  const zone = $("dropZone");
  zone.addEventListener("dragover", (event) => {
    event.preventDefault();
    zone.classList.add("target");
  });
  zone.addEventListener("dragleave", () => zone.classList.remove("target"));
  zone.addEventListener("drop", (event) => {
    event.preventDefault();
    zone.classList.remove("target");
    const id = event.dataTransfer.getData("text/plain");
    if (id) pinApp(id);
  });
}

renderClock();
renderDock();
renderDrawer();
stopAutopilot();
applySystemLayout();
renderChat();
bind();
setInterval(renderClock, 30000);
