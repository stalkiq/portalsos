const apps = [
  { id: "Agent", icon: "✨", hint: "Agent Channel: plan your week from Mail, Notes, and demo context via NVIDIA Nemotron on Token Factory." },
  { id: "Browser", icon: "🌐", hint: "Open Browser and drop it here to talk about the page." },
  { id: "Camera", icon: "📷", hint: "Capture a photo, then drop Camera here." },
  { id: "Notes", icon: "📝", hint: "Write a note, then drop Notes here." },
  { id: "Mail", icon: "✉️", hint: "Demo inbox is pinned. Ask PortalOS to triage, draft, or save to Notes." }
];

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

const state = {
  systemOn: false,
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
  drafting: false
};

const $ = (id) => document.getElementById(id);

function saveNotes() {
  localStorage.setItem("portalsos.notes", JSON.stringify(state.notes));
}

function renderApps() {
  $("appRow").innerHTML = apps.map((app) => (
    `<button class="app" draggable="true" data-id="${app.id}" title="${app.id}">
      <span>${app.icon}</span><small>${app.id}</small>
    </button>`
  )).join("") + `<button type="button" class="toggle ${state.systemOn ? "on" : ""}" id="power" aria-pressed="${state.systemOn}" aria-label="Autopilot ${state.systemOn ? "on" : "off"}"></button>`;

  $("appRow").querySelectorAll(".app").forEach((el) => {
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
  $("power").onclick = togglePower;
}

function emptyCopy() {
  return `<div class="empty"><strong>Live PortalOS demo</strong>Ask Nemotron anything, open <b>Agent</b> to plan your week, or drag Mail / Notes into Insight. Red power = Autopilot.</div>`;
}

function renderTryRow() {
  const row = $("tryRow");
  if (!row) return;
  const show = !state.systemOn && state.messages.length === 0 && !state.busy;
  row.hidden = !show;
  if (!show) {
    row.innerHTML = "";
    return;
  }
  row.innerHTML = [
    ["Plan my week", "agent"],
    ["Triage Mail", "mail"],
    ["Ask Insight", "ask"]
  ].map(([label, id]) => `<button type="button" class="try-chip" data-try="${id}">${label}</button>`).join("");
  row.querySelectorAll("[data-try]").forEach((btn) => {
    btn.onclick = () => {
      const kind = btn.dataset.try;
      if (kind === "agent") {
        openApp("Agent");
        return;
      }
      if (kind === "mail") {
        pinApp("Mail");
        return;
      }
      $("prompt").focus();
      ask("In one short paragraph: what is PortalOS, and how does Nebius Token Factory + NVIDIA Nemotron power it?");
    };
  });
}

function renderChat() {
  const chip = $("contextChip");
  if (state.context) {
    chip.hidden = false;
    chip.textContent = state.context;
  } else {
    chip.hidden = true;
  }
  const box = $("transcript");
  if (!state.messages.length) {
    box.innerHTML = emptyCopy();
  } else {
    box.innerHTML = state.messages.map((m) => `<div class="bubble ${m.role}">${escapeHtml(m.text)}</div>`).join("");
    box.scrollTop = box.scrollHeight;
  }
  renderTryRow();
}

function escapeHtml(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function contextHint() {
  if (state.context === "Agent") {
    const note = state.notes[state.selectedNote];
    return [
      "PortalOS Agent Channel (web demo context).",
      "MAIL:\n" + demoMail.map((m) => `${m.unread ? "UNREAD" : "read"} ${m.from} | ${m.subject} | ${m.snippet}`).join("\n"),
      note ? `NOTES:\n${note.title}\n${note.body}` : "NOTES: none",
      "CALENDAR: demo — design review today 4pm; Monday standup done.",
      "WEATHER: mild week, rain chance midweek — pack a light jacket."
    ].join("\n\n");
  }
  if (state.context === "Mail") {
    return "Sample inbox (fictional):\n" + demoMail.map((m) => `${m.unread ? "UNREAD" : "read"} ${m.from} | ${m.subject} | ${m.snippet}`).join("\n");
  }
  if (state.context === "Notes") {
    const note = state.notes[state.selectedNote];
    return note ? `Open note: ${note.title}\n${note.body}` : "Notes app is open with no note selected.";
  }
  if (state.context === "Browser") {
    return `Browser is open at ${state.browserUrl}`;
  }
  if (state.context === "Camera") {
    return state.photo ? "A photo is captured on Camera. Describe useful next actions." : "Camera is open but no photo yet.";
  }
  return "";
}

async function ask(text) {
  if (!text || state.busy) return;
  state.messages.push({ role: "user", text });
  renderChat();
  state.busy = true;
  $("prompt").value = "";
  try {
    const response = await fetch("/v1/insight", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        appName: state.context || "PortalOS",
        contextHint: contextHint(),
        userPrompt: text,
        history: state.messages.slice(-8).map((m) => `${m.role}: ${m.text}`).join("\n")
      })
    });
    const data = await response.json();
    const reply = (data.text || (data.error && data.error.message) || "No reply").trim();
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
  renderChat();
}

function pinApp(id) {
  state.context = id;
  const app = apps.find((item) => item.id === id);
  state.messages.push({ role: "system", text: `Using ${id}.` });
  renderChat();
  if (id === "Mail") {
    ask("Triage this inbox. What is important, what is noise, and what is safe to ignore.");
    return;
  }
  if (id === "Agent") {
    ask("Plan my week. Prioritize the next 7 days using my mail, notes, calendar hints, and weather. Use NVIDIA Nemotron on Nebius Token Factory. Short actionable bullets.");
    return;
  }
  ask(`The user dropped ${id} into PortalOS. ${app ? app.hint : ""} Give a short briefing.`);
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
  $("dropZone").hidden = state.systemOn;
  renderApps();
}

function togglePower() {
  state.systemOn = !state.systemOn;
  applySystemLayout();
  if (state.systemOn) {
    startAutopilot();
  } else {
    stopAutopilot();
  }
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
      detail: "Northwind moved the review. Confirm you can make 4pm.\n\nTo studio@northwind.example: I can make the 4pm review and will bring the latest home-screen mock.",
      draft: { to: "studio@northwind.example" }
    });
  }, 1800));
  state.autoTimers.push(setTimeout(() => {
    if (!state.systemOn) return;
    const note = {
      title: "PortalOS Digest",
      body: "Two suggested replies are waiting. Nothing was sent."
    };
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
  if (state.selectedNote >= state.notes.length) {
    state.selectedNote = 0;
  }
}

function renderNotes() {
  ensureNotes();
  const note = state.notes[state.selectedNote] || state.notes[0];
  setSheetChrome(
    "Notes",
    "Notes",
    `<button type="button" id="addNote">New</button>
     <button type="button" class="danger" id="deleteNote">Delete</button>`
  );
  $("sheetBody").innerHTML = `
    <div class="notes-split">
      <div class="notes-list">
        ${state.notes.map((item, index) => `
          <button type="button" class="note-card ${index === state.selectedNote ? "selected" : ""}" data-i="${index}">
            <strong>${escapeHtml(item.title || "Untitled")}</strong>
            <span>${escapeHtml(item.body || "Empty note")}</span>
          </button>
        `).join("")}
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
  state.notes[state.selectedNote] = {
    title: $("noteTitle").value,
    body: $("noteBody").value
  };
  saveNotes();
}

function renderMailInbox() {
  const items = state.mailItems;
  const latest = items[0];
  const earlier = items.slice(1);
  setSheetChrome(
    "Mail",
    "",
    `<button type="button" class="sheet-icon" id="composeMail" aria-label="New message">✎</button>`
  );
  $("sheetBody").innerHTML = `
    <div class="mail-screen">
      <div class="mail-inbox">
        <div class="mail-incoming">
          <h2>Incoming</h2>
          <span class="mail-live"><i></i>LIVE</span>
        </div>
        <p class="mail-meta">${items.length} signals  ·  sample inbox</p>
        ${nebiusMark()}
        ${latest ? `
          <button type="button" class="mail-now" data-i="0">
            <span class="watermark">${escapeHtml(senderInitial(latest.from))}</span>
            <p class="mail-kicker">NOW</p>
            <h3>${escapeHtml(latest.subject)}</h3>
            <p>${escapeHtml(latest.snippet)}</p>
            <div class="mail-now-foot">
              <span>${escapeHtml(latest.from.toUpperCase())}</span>
              <span>${escapeHtml(latest.date)}</span>
            </div>
          </button>
        ` : `<p class="mail-kicker">NO SIGNAL</p><h2>Inbox is quiet.</h2>`}
        ${earlier.length ? `<p class="mail-earlier">EARLIER</p>` : ""}
        ${earlier.map((item, index) => `
          <button type="button" class="mail-row" data-i="${index + 1}">
            <span class="mail-rail"><i></i><b></b></span>
            <span class="mail-row-copy">
              <span class="mail-row-top"><span>${escapeHtml(item.from)}</span><span>${escapeHtml(item.date)}</span></span>
              <strong>${escapeHtml(item.subject)}</strong>
            </span>
          </button>
        `).join("")}
      </div>
    </div>`;
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
    renderMailInbox();
    return;
  }
  setSheetChrome("Mail", "", "", "Inbox");
  $("sheetBody").innerHTML = `
    <div class="mail-reader">
      <div class="mail-reader-body">
        <p class="mail-kicker">MESSAGE</p>
        <h3>${escapeHtml(message.subject)}</h3>
        <div class="mail-from">
          <b>${escapeHtml(message.from)}</b>
          <span>${escapeHtml(message.date)}</span>
        </div>
        <div class="mail-hairline"></div>
        <p>${escapeHtml(message.body || message.snippet)}</p>
      </div>
      <div class="mail-actions">
        <button type="button" class="mail-action" id="mailReply">Reply</button>
        <button type="button" class="mail-action" id="mailArchive">Archive</button>
        <button type="button" class="mail-action" id="mailTrash">Trash</button>
      </div>
      <button type="button" class="mail-portal" id="mailPortal">Add to Portal</button>
      <div style="padding: 0 20px 18px">${nebiusMark()}</div>
    </div>`;
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
  setSheetChrome(
    "Mail",
    compose.replyTo ? "Reply" : "New Message",
    `<button type="button" class="accent" id="mailSend">Send</button>`,
    "Cancel"
  );
  $("sheetBody").innerHTML = `
    <div class="mail-compose">
      <div class="mail-compose-body">
        <label><span>To</span><input id="mailTo" value="${escapeHtml(compose.to)}" placeholder="To" /></label>
        <label><span>Subject</span><input id="mailSubject" value="${escapeHtml(compose.subject)}" placeholder="Subject" /></label>
        <label>
          <span>Direction for Token Factory</span>
          <input id="mailHint" value="${escapeHtml(compose.hint)}" placeholder="Optional: keep it short, decline politely..." />
        </label>
        <button type="button" class="mail-draft" id="mailDraft" ${state.drafting ? "disabled" : ""}>
          ${state.drafting ? "Nemotron is writing..." : "Write with Token Factory"}
        </button>
        <label><span>Body</span><textarea id="mailBody">${escapeHtml(compose.body)}</textarea></label>
        ${nebiusMark()}
      </div>
    </div>`;
  const readCompose = () => {
    state.compose = {
      ...state.compose,
      to: $("mailTo").value,
      subject: $("mailSubject").value,
      hint: $("mailHint").value,
      body: $("mailBody").value
    };
  };
  ["mailTo", "mailSubject", "mailHint", "mailBody"].forEach((id) => {
    $(id).oninput = readCompose;
  });
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
  $("mailDraft").disabled = true;
  $("mailDraft").textContent = "Nemotron is writing...";
  try {
    const response = await fetch("/v1/insight", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        appName: "Mail",
        contextHint: `To: ${state.compose.to}\nSubject: ${state.compose.subject}\n${state.compose.replyTo ? "Original:\n" + state.compose.replyTo.body : ""}`,
        userPrompt: `Write a short email body only. No preamble. ${state.compose.hint || "Keep it specific and polite."}`
      })
    });
    const data = await response.json();
    let text = (data.text || "").trim();
    if (/thinking process/i.test(text)) {
      text = text.split(/\n\n+/).pop().trim();
    }
    state.compose.body = text;
  } catch (error) {
    state.compose.body = "Could not reach Token Factory. " + error.message;
  }
  state.drafting = false;
  renderMailCompose();
}

function renderMail() {
  if (state.mailView === "read") {
    renderMailReader();
  } else if (state.mailView === "compose") {
    renderMailCompose();
  } else {
    renderMailInbox();
  }
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
  if (id === "Notes") {
    renderNotes();
    return;
  }
  if (id === "Mail") {
    state.mailView = "inbox";
    state.compose = null;
    renderMail();
    return;
  }
  if (id === "Agent") {
    setSheetChrome("Agent", "Agent Channel", "");
    $("sheetBody").innerHTML = `
      <div class="mail-reader">
        <div class="mail-reader-body">
          <p class="mail-kicker">TOKEN FACTORY AGENT</p>
          <h3>Agent Channel</h3>
          <p>Your NVIDIA Nemotron agent on Nebius Token Factory. It plans week / month / year from Mail, Notes, and demo calendar + weather context.</p>
          <p>Tap a horizon, or drop Agent into Insight.</p>
          <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:14px">
            <button type="button" class="mail-action" data-h="week">Plan week</button>
            <button type="button" class="mail-action" data-h="month">Plan month</button>
            <button type="button" class="mail-action" data-h="year">Plan year</button>
          </div>
          <button type="button" class="mail-portal" id="agentPortal" style="margin-top:16px">Add to Portal</button>
          <div style="padding: 12px 0 0">${nebiusMark()}</div>
        </div>
      </div>`;
    $("sheetBody").querySelectorAll("[data-h]").forEach((btn) => {
      btn.onclick = () => {
        $("appSheet").hidden = true;
        state.context = "Agent";
        const horizon = btn.dataset.h;
        state.messages = [{ role: "system", text: "Using Agent." }];
        renderChat();
        ask(`Plan my ${horizon}. Use mail, notes, calendar hints, and weather. Be concrete. Powered by NVIDIA Nemotron on Nebius Token Factory.`);
      };
    });
    $("agentPortal").onclick = () => {
      $("appSheet").hidden = true;
      pinApp("Agent");
    };
    return;
  }
  setSheetChrome(id, id, "");
  const body = $("sheetBody");
  if (id === "Camera") {
    body.innerHTML = `
      <p>Capture or choose a photo, then drop Camera into chat.</p>
      <input id="cam" type="file" accept="image/*" capture="environment" />
      ${state.photo ? `<img class="preview" src="${state.photo}" alt="Captured" />` : ""}`;
    $("cam").onchange = (event) => {
      const file = event.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => { state.photo = reader.result; openApp("Camera"); };
      reader.readAsDataURL(file);
    };
  } else {
    body.innerHTML = `
      <div class="browser-row">
        <input class="field" id="url" value="${escapeHtml(state.browserUrl)}" />
        <button type="button" id="go">Go</button>
      </div>
      <iframe title="Browser" src="${state.browserUrl}" style="width:100%;height:460px;border:0;border-radius:12px;background:white"></iframe>`;
    $("go").onclick = () => {
      let url = $("url").value.trim();
      if (!/^https?:/i.test(url)) url = "https://www.google.com/search?igu=1&q=" + encodeURIComponent(url);
      state.browserUrl = url;
      openApp("Browser");
    };
  }
}

function bind() {
  $("composer").addEventListener("submit", (event) => {
    event.preventDefault();
    ask($("prompt").value.trim());
  });
  $("newChat").onclick = newChat;
  $("closeSheet").onclick = closeSheet;
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

renderApps();
stopAutopilot();
renderChat();
bind();
