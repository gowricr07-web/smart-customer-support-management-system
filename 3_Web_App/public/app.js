const $ = s => document.querySelector(s);
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const fmt = d => d && d !== "null" ? new Date(d).toLocaleString() : "—";
async function api(path, opts = {}) {
  const res = await fetch("/api" + path, { headers: { "Content-Type": "application/json" }, ...opts,
    body: opts.body ? JSON.stringify(opts.body) : undefined });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}
function toast(msg, err) { const t = $("#toast"); t.textContent = msg; t.className = err ? "err" : ""; t.style.display = "block"; setTimeout(() => t.style.display = "none", 3500); }
const guard = fn => async (...a) => { try { await fn(...a); } catch (e) { toast(e.message, true); } };
const showModal = id => $("#" + id).classList.add("show");
function hideModal(id) { $("#" + id).classList.remove("show"); }
const pill = (v, pre = "") => `<span class="pill ${pre}${esc(String(v).replace(/ /g, "-"))}">${esc(v)}</span>`;

// ---------- tabs ----------
document.querySelectorAll("#nav button").forEach(b => b.onclick = () => {
  document.querySelectorAll("#nav button").forEach(x => x.classList.toggle("active", x === b));
  ["dash","tickets","agents","kb","graph"].forEach(t => $("#tab-" + t).classList.toggle("hide", t !== b.dataset.tab));
  ({ dash: loadDash, tickets: loadTickets, agents: loadAgents, kb: searchKb, graph: () => {} })[b.dataset.tab]();
});

// ---------- dashboard ----------
const loadDash = guard(async () => {
  const s = await api("/stats");
  $("#statCards").innerHTML = [
    ["Total tickets", s.tickets, ""], ["Open / In progress", s.open, "need attention"],
    ["Resolved", s.resolved, ""], ["Avg rating", s.feedback.avgRating ?? "—", `${s.feedback.count} feedbacks`]
  ].map(([a, b, c]) => `<div class="card"><h3>${a}</h3><div class="stat">${b}</div><div class="sub">${c}</div></div>`).join("");
  const max = Math.max(1, ...s.byCategory.map(x => x.tickets));
  $("#byCategory").innerHTML = s.byCategory.map(x => `<div style="margin:8px 0"><div class="row" style="justify-content:space-between"><span>${esc(x.category)}</span><b>${x.tickets}</b></div><div class="bar"><i style="width:${x.tickets / max * 100}%"></i></div></div>`).join("") || "<span class='sub'>No data</span>";
  $("#byPriority").innerHTML = s.byPriority.map(x => `<div class="row" style="justify-content:space-between;margin:8px 0">${pill(x.priority)}<b>${x.tickets}</b></div>`).join("") || "<span class='sub'>No open tickets</span>";
  $("#deptTable").innerHTML = `<table><tr><th>Dept</th><th>Agents</th><th>Tickets</th><th>Avg rating</th><th>Avg resolution (h)</th></tr>${s.departments.map(d => `<tr><td>${esc(d.department)}</td><td>${d.agents}</td><td>${d.tickets}</td><td>${d.avgRating ?? "—"}</td><td>${d.avgResolutionHours ?? "—"}</td></tr>`).join("")}</table>`;
  $("#repeatTable").innerHTML = s.repeatIssues.length ? `<table><tr><th>Customer</th><th>Category</th><th>Tickets</th></tr>${s.repeatIssues.map(r => `<tr><td>${esc(r.customer)}</td><td>${esc(r.category)}</td><td>${r.tickets.map(t => "#" + t).join(", ")}</td></tr>`).join("")}</table>` : "<span class='sub'>None</span>";
});

// ---------- tickets ----------
const loadTickets = guard(async () => {
  const st = $("#statusFilter").value;
  const rows = await api("/tickets" + (st ? "?status=" + encodeURIComponent(st) : ""));
  $("#ticketTable").innerHTML = `<table><tr><th>#</th><th>Subject</th><th>Customer</th><th>Agent</th><th>Category</th><th>Priority</th><th>Status</th><th>Created</th></tr>${rows.map(t =>
    `<tr class="click" onclick="openTicket(${t.ticketId})"><td>${t.ticketId}</td><td>${esc(t.subject)}</td><td>${esc(t.customer)}</td><td>${esc(t.agent || "—")}</td><td>${esc(t.category)}</td><td>${pill(t.priority)}</td><td>${pill(t.status, "s-")}</td><td>${fmt(t.createdAt)}</td></tr>`).join("")}</table>` || "";
});
$("#statusFilter").onchange = loadTickets;

const openTicket = guard(async id => {
  const [t, agents, recAgents, recArticles] = await Promise.all([
    api("/tickets/" + id), api("/agents"), api(`/tickets/${id}/recommend-agents`), api(`/tickets/${id}/recommend-articles`)]);
  const done = ["Resolved", "Closed"].includes(t.status);
  $("#detailBody").innerHTML = `
    <span class="close" onclick="hideModal('detailModal')">×</span>
    <h2 style="margin:0 0 4px">#${t.ticketId} · ${esc(t.subject)}</h2>
    <div class="row sub">${pill(t.priority)} ${pill(t.status, "s-")} <span>${esc(t.channel)}</span> <span>· ${esc(t.category)}</span></div>
    <p>${esc(t.description)}</p>
    <div class="grid g2">
      <div><b>Customer:</b> ${esc(t.customer)}<br><b>Agent:</b> ${esc(t.agent || "—")}<br><b>Created:</b> ${fmt(t.createdAt)}<br><b>Resolved:</b> ${fmt(t.resolvedAt)}</div>
      <div><b>Feedback:</b> ${t.feedback ? "★".repeat(t.feedback.rating) + " – " + esc(t.feedback.comments) : "<span class='sub'>none yet</span>"}</div>
    </div>
    <h3 style="margin:16px 0 4px">Conversation</h3>
    <div>${t.messages.map(m => `<div class="msg ${esc(m.senderType)}"><small>#${m.seqNo} · ${esc(m.senderType)} · ${fmt(m.createdAt)}</small>${esc(m.content)}${m.attachments.length ? `<small>📎 ${m.attachments.map(esc).join(", ")}</small>` : ""}</div>`).join("") || "<span class='sub'>No messages</span>"}</div>
    <div class="row" style="margin-top:8px"><select id="mSender" style="width:120px"><option>customer</option><option selected>agent</option><option>system</option></select><input id="mText" placeholder="Write a message…" style="flex:1"><button class="btn" onclick="sendMsg(${id})">Send</button></div>
    <h3 style="margin:16px 0 4px">AI suggestions on this ticket</h3>
    ${t.suggestions.map(s => `<div class="row" style="justify-content:space-between"><span>${esc(s.title)}</span><b>${Math.round(s.confidence * 100)}%</b></div>`).join("") || "<span class='sub'>None</span>"}
    <h3 style="margin:16px 0 4px">Graph insight: best-matching agents (skill required by category)</h3>
    ${recAgents.map(a => `<div class="row" style="justify-content:space-between"><span>${esc(a.agent)} <span class="sub">skill: ${esc(a.matchedSkill)}</span></span><span class="sub">${a.openTickets} open</span></div>`).join("") || "<span class='sub'>No skill match</span>"}
    <h3 style="margin:16px 0 4px">Graph insight: articles that worked for similar tickets</h3>
    ${recArticles.map(a => `<div class="row" style="justify-content:space-between"><span>${esc(a.title)}</span><span class="sub">avg rating ${a.avgRating} · conf ${a.avgConfidence} · used ${a.timesUsed}×</span></div>`).join("") || "<span class='sub'>No history yet</span>"}
    <h3 style="margin:16px 0 4px">Actions</h3>
    <div class="row">
      <select id="stSel" style="width:150px">${["Open", "In Progress", "Resolved", "Closed"].map(s => `<option ${s === t.status ? "selected" : ""}>${s}</option>`).join("")}</select>
      <button class="btn" onclick="setStatus(${id})">Update status</button>
      <select id="agSel" style="width:150px">${agents.map(a => `<option value="${a.agentId}">${esc(a.name)}</option>`).join("")}</select>
      <button class="btn ghost" onclick="reassign(${id})">Reassign</button>
      <button class="btn danger" onclick="delTicket(${id})">Delete</button>
    </div>
    <div class="row" style="margin-top:10px">
      <select id="fbRating" style="width:90px">${[5, 4, 3, 2, 1].map(r => `<option>${r}</option>`).join("")}</select>
      <input id="fbText" placeholder="Feedback comment" style="flex:1"><button class="btn ok" onclick="sendFb(${id})">Submit feedback</button>
    </div>
    ${done ? "" : "<div class='sub'>Feedback is only accepted once the ticket is Resolved/Closed.</div>"}`;
  showModal("detailModal");
});
const sendMsg = guard(async id => { const v = $("#mText").value.trim(); if (!v) return;
  await api(`/tickets/${id}/messages`, { method: "POST", body: { senderType: $("#mSender").value, content: v } }); toast("Message added"); openTicket(id); });
const setStatus = guard(async id => { await api(`/tickets/${id}/status`, { method: "PATCH", body: { status: $("#stSel").value } }); toast("Status updated"); openTicket(id); loadTickets(); });
const reassign = guard(async id => { await api(`/tickets/${id}/agent`, { method: "PATCH", body: { agentId: $("#agSel").value } }); toast("Agent reassigned"); openTicket(id); loadTickets(); });
const sendFb = guard(async id => { await api(`/tickets/${id}/feedback`, { method: "POST", body: { rating: $("#fbRating").value, comments: $("#fbText").value } }); toast("Feedback saved"); openTicket(id); });
const delTicket = guard(async id => { if (!confirm("Delete ticket #" + id + " with its messages and feedback?")) return;
  await api("/tickets/" + id, { method: "DELETE" }); hideModal("detailModal"); toast("Ticket deleted"); loadTickets(); });

// ---------- new ticket ----------
$("#newTicketBtn").onclick = guard(async () => {
  const [cu, ca, de] = await Promise.all([api("/customers"), api("/categories"), api("/departments")]);
  $("#nCustomer").innerHTML = cu.map(c => `<option value="${c.customerId}">${esc(c.name)}</option>`).join("");
  $("#nCategory").innerHTML = ca.map(c => `<option>${esc(c.name)}</option>`).join("");
  $("#nDepartment").innerHTML = de.map(d => `<option>${esc(d.name)}</option>`).join("");
  showModal("newModal");
});
$("#createBtn").onclick = guard(async () => {
  const r = await api("/tickets", { method: "POST", body: { customerId: $("#nCustomer").value, category: $("#nCategory").value,
    department: $("#nDepartment").value, subject: $("#nSubject").value, description: $("#nDesc").value,
    priority: $("#nPriority").value, channel: $("#nChannel").value } });
  hideModal("newModal"); $("#nSubject").value = ""; $("#nDesc").value = "";
  toast(`Ticket #${r.ticketId} assigned to ${r.assignedTo} (load before: ${r.agentLoadBefore})`); loadTickets();
});

// ---------- agents ----------
const loadAgents = guard(async () => {
  const rows = await api("/agents");
  $("#agentTable").innerHTML = `<table><tr><th>ID</th><th>Name</th><th>Department</th><th>Skills</th><th>Open tickets</th><th>Avg rating</th></tr>${rows.map(a =>
    `<tr><td>${a.agentId}</td><td>${esc(a.name)}<div class="sub">${esc(a.email)}</div></td><td>${esc(a.department)}</td><td>${a.skills.map(s => pill(s)).join(" ")}</td><td>${a.openTickets}</td><td>${a.avgRating ?? "—"}</td></tr>`).join("")}</table>`;
});

// ---------- knowledge base ----------
const searchKb = guard(async () => {
  const rows = await api("/articles/search?q=" + encodeURIComponent($("#kbq").value));
  $("#kbResults").innerHTML = rows.map(a => `<div class="card" style="margin-bottom:8px"><div class="row" style="justify-content:space-between"><b>${esc(a.title)}</b><span class="sub">${esc(a.category)}${a.score != null ? " · score " + a.score : ""}</span></div><div class="sub">${esc(a.content)}</div></div>`).join("") || "<span class='sub'>No results</span>";
});
$("#kbBtn").onclick = searchKb; $("#kbq").onkeydown = e => { if (e.key === "Enter") searchKb(); };

// ---------- graph visualisation (dependency-free SVG, radial layout) ----------
const COLORS = { Ticket: "#2f5496", Customer: "#1a8a4a", Agent: "#b7791f", Category: "#8e44ad", Message: "#667085", Attachment: "#999",
  Article: "#c0392b", Feedback: "#e67e22", Phone: "#16a085", Department: "#34495e", Skill: "#2980b9" };
const drawGraph = guard(async () => {
  const g = await api("/graph/" + $("#graphId").value);
  const svg = $("#graphSvg"); const W = 1000, H = 620, cx = W / 2, cy = H / 2;
  if (!g.root) { svg.innerHTML = `<text x="20" y="30">Ticket not found</text>`; return; }
  const adj = new Map(g.nodes.map(n => [n.id, new Set()]));
  g.edges.forEach(e => { adj.get(e.from)?.add(e.to); adj.get(e.to)?.add(e.from); });
  const level = new Map([[g.root, 0]]); const q = [g.root];
  while (q.length) { const u = q.shift(); adj.get(u).forEach(v => { if (!level.has(v)) { level.set(v, level.get(u) + 1); q.push(v); } }); }
  const pos = new Map([[g.root, [cx, cy]]]);
  for (const lv of [1, 2]) {
    const ns = g.nodes.filter(n => level.get(n.id) === lv); const r = lv === 1 ? 170 : 285;
    ns.forEach((n, i) => { const a = 2 * Math.PI * i / Math.max(1, ns.length) + (lv === 2 ? 0.2 : 0);
      pos.set(n.id, [cx + r * 1.45 * Math.cos(a), cy + r * 0.95 * Math.sin(a)]); });
  }
  const lines = g.edges.filter(e => pos.has(e.from) && pos.has(e.to)).map(e => {
    const [x1, y1] = pos.get(e.from), [x2, y2] = pos.get(e.to);
    return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="#c5cee0"/><text x="${(x1 + x2) / 2}" y="${(y1 + y2) / 2}" fill="#8a94a8" text-anchor="middle" style="font-size:9px">${esc(e.type)}</text>`;
  }).join("");
  const dots = g.nodes.filter(n => pos.has(n.id)).map(n => { const [x, y] = pos.get(n.id);
    return `<circle cx="${x}" cy="${y}" r="${n.id === g.root ? 20 : 14}" fill="${COLORS[n.label] || "#555"}"/><text x="${x}" y="${y + (n.id === g.root ? 34 : 28)}" text-anchor="middle">${esc(n.caption.slice(0, 26))}</text>`; }).join("");
  svg.innerHTML = lines + dots;
  $("#legend").innerHTML = [...new Set(g.nodes.map(n => n.label))].map(l => `<span><i style="background:${COLORS[l] || "#555"}"></i>${l}</span>`).join("");
});
$("#graphBtn").onclick = drawGraph;

loadDash();
