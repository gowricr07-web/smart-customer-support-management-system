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

// ---------- tabs (Your exact navigation preserved) ----------
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
  $("#byCategory").innerHTML = s.byCategory.map(x => `<div style="margin:8px 0"><div class="row" style="justify-content:space-between"><span>${esc(x.category)}</span><b>${x.tickets}</b></div><div class="bar"><i style="width:${Math.round(x.tickets / max * 100)}%"></i></div></div>`).join("") || "<span class='sub'>No data</span>";
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

window.openTicket = guard(async id => {
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
    <div>${t.messages.map(m => `<div class="msg ${esc(m.senderType)}"><small>#${m.seqNo} · ${esc(m.senderType)} ·${fmt(m.createdAt)}</small>${esc(m.content)}${m.attachments.length ? `<small>📎 ${m.attachments.map(esc).join(", ")}</small>` : ""}</div>`).join("") || "<span class='sub'>No messages</span>"}</div>
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

window.sendMsg = guard(async id => { 
  const v = $("#mText").value.trim(); if (!v) return;
  await api(`/tickets/${id}/messages`, { method: "POST", body: { senderType: $("#mSender").value, content: v } }); 
  toast("Message added"); 
  window.openTicket(id); 
});

window.setStatus = guard(async id => { 
  await api(`/tickets/${id}/status`, { method: "PATCH", body: { status: $("#stSel").value } }); 
  toast("Status updated"); 
  window.openTicket(id); 
  loadTickets(); 
});

window.reassign = guard(async id => { 
  await api(`/tickets/${id}/agent`, { method: "PATCH", body: { agentId: $("#agSel").value } }); 
  toast("Agent reassigned"); 
  window.openTicket(id); 
  loadTickets(); 
});

window.sendFb = guard(async id => { 
  await api(`/tickets/${id}/feedback`, { method: "POST", body: { rating: $("#fbRating").value, comments: $("#fbText").value } }); 
  toast("Feedback saved"); 
  window.openTicket(id); 
});

window.delTicket = guard(async id => { 
  if (!confirm("Delete ticket #" + id + " with its messages and feedback?")) return;
  await api("/tickets/" + id, { method: "DELETE" }); 
  hideModal("detailModal"); 
  toast("Ticket deleted"); 
  loadTickets(); 
});

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

// ---------- knowledge base with complete articles text ----------
const ARTICLES_DATA = {
  "Refund Policy Overview": {
    category: "Payment Issue",
    summary: "Explains standard refund timelines and eligibility.",
    fullContent: `1. Introduction
Our Refund Policy outlines the terms and conditions under which customers may request refunds for purchases made through our platform. We aim to ensure a fair, transparent, and hassle-free refund process while maintaining customer satisfaction and trust. Customers are encouraged to review this policy carefully before making a purchase or submitting a refund request.

2. Eligibility for Refunds
Refund eligibility depends on the nature of the product or service purchased and the circumstances surrounding the request. Customers may be eligible for a refund if they receive a defective, damaged, incorrect, or incomplete product, experience a service failure, or are charged incorrectly. Requests must comply with the applicable terms and conditions. Certain products or services, including customized items, completed services, digital products that have already been accessed, or purchases explicitly marked as non-refundable, may not qualify for refunds, subject to applicable consumer protection laws.

3. Refund Request Process
To request a refund, customers should contact our customer support team through the designated support channels. Each request should include the order or transaction reference number, purchase date, reason for the refund, and any supporting evidence, such as receipts, photographs, or relevant correspondence. Providing accurate and complete information helps us review requests efficiently. Additional information may be requested when necessary to verify the transaction or assess the circumstances.

4. Review and Approval
All refund requests are reviewed individually. Our support team will assess the request against the applicable eligibility criteria, transaction records, and relevant policy provisions. Customers will be informed of the decision and any additional steps required. Submitting a request does not automatically guarantee approval. Decisions will be made fairly and consistently, without limiting any rights customers may have under applicable laws.

5. Refund Processing Time
Once a refund is approved, the amount will generally be returned through the original payment method whenever possible. Processing times may vary depending on the payment provider, bank, or financial institution involved. Customers should allow a reasonable period for the refund to appear in their accounts. If the refund has not been received within the communicated timeframe, they may contact customer support for assistance.

6. Cancellations and Exceptions
Customers should submit cancellation requests as early as possible. Whether a cancellation qualifies for a refund depends on the purchase terms, the stage of order processing, and any costs already incurred. Shipping fees, transaction charges, promotional discounts, and other deductions may be treated according to the applicable terms and relevant laws. Exceptions may be considered when justified by the circumstances.

7. Policy Updates and Contact
We reserve the right to update this policy when necessary, subject to applicable legal requirements. Any revisions will be communicated through the appropriate platform or official channels. Customers are encouraged to review the latest version periodically.
For questions, clarification, or assistance with a refund request, customers may contact our customer support team through the contact details provided on our platform. Our goal is to resolve concerns promptly, communicate decisions clearly, and provide a reliable customer experience.`
  },
  "How to Reset Password": {
    category: "Login Issue",
    summary: "Step-by-step password reset walkthrough.",
    fullContent: `1. Introduction
Resetting your password is an important security measure that helps protect your account and personal information. If you have forgotten your password, are unable to log in, or suspect that someone else may have accessed your account, you should reset your password as soon as possible. This guide explains the steps required to reset your password safely and regain access to your account.

2. Access the Login Page
Begin by opening the official website or application where your account is registered. Navigate to the login page and locate the “Forgot Password?” or “Reset Password” option, usually displayed below the password field. Select this option to begin the password recovery process. Always ensure that you are using the official website or application to avoid phishing attempts and fraudulent pages.

3. Enter Your Registered Email Address
After selecting the password reset option, you will generally be asked to enter the email address associated with your account. Enter the correct registered email address and submit the request. Some platforms may use a registered phone number or username instead. Make sure the information is accurate so that the system can identify your account and send the appropriate recovery instructions.

4. Verify Your Identity
To protect your account from unauthorized access, the system may send a password reset link or verification code to your registered email address or mobile number. Check your inbox for the recovery email, including the spam or junk folder if necessary. If a verification code is sent, enter it in the designated field. Never share verification codes or password reset links with other people.

5. Create a New Password
Once your identity has been verified, open the password reset page or enter the verification code as instructed. Create a new password that meets the platform's security requirements. A strong password should be sufficiently long, unique, and difficult to guess. Consider using a combination of letters, numbers, and special characters where supported. Avoid using easily identifiable information, such as your name, birthday, or commonly used passwords.
Enter the new password in the required field and confirm it if prompted. Ensure both entries match before submitting the form.

6. Confirm the Password Reset
After submitting your new password, wait for the confirmation message indicating that the reset was successful. Return to the login page and sign in using your registered account details and new password. If the login attempt fails, verify that you entered the correct email address and password. You may need to repeat the recovery process if the reset link has expired.

7. Troubleshooting and Security Tips
If you do not receive a recovery email or verification code, check your spam folder, verify your registered contact information, and wait briefly before requesting another message. If you no longer have access to your registered email address or phone number, contact the platform's official support team for assistance.
For improved security, never reuse passwords across multiple accounts, avoid sharing login credentials, and enable two-factor authentication whenever available. If you suspect unauthorized access, secure your email account as well and sign out of other active sessions if the platform provides that option.`
  },
  "Troubleshooting App Crashes": {
    category: "App Crash",
    summary: "Common causes of startup crashes and fixes.",
    fullContent: `1. Introduction
App crashes occur when an application unexpectedly closes, freezes, or stops responding during use. These issues can interrupt important tasks, cause data loss, and negatively affect the user experience. App crashes may result from software bugs, insufficient memory, outdated versions, corrupted files, network problems, or compatibility issues. Understanding the possible causes and following systematic troubleshooting steps can help users restore normal application functionality.

2. Restart the Application
The first step in troubleshooting an app crash is to close the application completely and reopen it. Temporary errors or background processes may prevent the application from functioning correctly. On mobile devices, remove the application from the recent apps list before launching it again. On desktop computers, close the application and check whether it is still running in the background. If the issue persists, restart the device to clear temporary system problems.

3. Check for Updates
Using an outdated application may cause compatibility problems, unexpected errors, or security vulnerabilities. Visit the official application store or the developer's website to check for available updates. Install the latest compatible version and restart the application. It is also important to keep the device's operating system updated, as newer application versions may require recent system components or security patches.

4. Check Device Storage and Memory
Applications require sufficient storage space and available memory to operate properly. When a device runs low on storage or RAM, applications may become slow, freeze, or crash unexpectedly. Remove unnecessary files, uninstall unused applications, and close background programs that consume excessive resources. After freeing up space, restart the application and check whether its performance improves.

5. Clear Cache and Application Data
Temporary files stored by an application can become corrupted and cause unexpected behavior. On supported devices, clearing the application's cache may resolve these problems without removing personal information. Navigate to the device settings, open the application management section, select the affected application, and choose the option to clear its cache.

6. Check Internet Connectivity
Some applications depend on a stable internet connection to load information or communicate with servers. Weak Wi-Fi signals, unstable mobile data, or temporary server outages can cause applications to freeze or crash. Switch between available networks, restart the router if appropriate, and check whether the application's service is operational.

7. Reinstall the Application
If the previous steps do not resolve the issue, uninstalling and reinstalling the application may help repair corrupted installation files. Download the application again from an official source and test its functionality after installation.

8. Contact Technical Support
If crashes continue, record the error messages, device model, operating system version, application version, and actions that trigger the problem. Share these details with the application's support team to help identify the underlying cause.`
  },
  "Refund Delay Resolution Guide": {
    category: "Refund Delay",
    summary: "How to investigate and expedite a delayed refund.",
    fullContent: `1. Introduction
A delayed refund can be frustrating, especially when customers expect their money to be returned within a specific period. Refund delays may occur because of payment processing times, bank procedures, merchant verification, technical issues, or incorrect transaction details. This guide explains how to identify the cause of a refund delay, track its progress, and take appropriate steps to resolve the issue efficiently.

2. Check the Refund Status
The first step is to verify the current status of the refund. Log in to the relevant website or application and navigate to the order history, transaction history, or refund section. Check whether the refund is marked as requested, approved, processed, or completed.

3. Understand the Expected Processing Time
Refund processing times vary depending on the payment method and financial institution. Card refunds, bank transfers, digital wallets, and other payment services may follow different timelines. Weekends, public holidays, security checks, and banking procedures can also affect when the funds become available.

4. Verify Payment Details
Incorrect or outdated payment information can complicate refund processing. Confirm that the original payment method is still active and that the transaction details are accurate.

5. Contact Customer Support
If the refund exceeds the communicated processing timeframe, contact the merchant's customer support team through its official website, application, or designated support channel. Provide the relevant transaction details, refund request date, and confirmation of approval.

6. Contact Your Bank or Payment Provider
If the merchant confirms that the refund has been processed, but the funds remain unavailable, contact your bank or payment provider to trace the payment.

7. Escalation and Prevention
If the issue remains unresolved, request escalation to a supervisor or formal complaints team. Retain transaction records, review refund terms before purchasing, and monitor refund notifications regularly.`
  }
};

let kbArticlesCache = [];

async function searchKb() {
  const box = $("#kbResults");
  box.innerHTML = "<span class='sub'>Searching…</span>";
  try {
    const query = $("#kbq").value.trim();
    const rows = await api("/articles/search?q=" + encodeURIComponent(query));
    
    // Merge backend search results with our rich local text content
    kbArticlesCache = rows.map(r => {
      const match = ARTICLES_DATA[r.title];
      return {
        title: r.title,
        category: r.category || (match ? match.category : "General"),
        content: match ? match.fullContent : (r.content || r.summary || "No content available."),
        score: r.score
      };
    });

    if (!kbArticlesCache.length) {
      // Fallback display if search API is empty
      kbArticlesCache = Object.keys(ARTICLES_DATA).map(title => ({
        title: title,
        category: ARTICLES_DATA[title].category,
        content: ARTICLES_DATA[title].fullContent,
        score: null
      }));
    }

    box.innerHTML = kbArticlesCache.map((a, i) => `
      <div class="card" style="margin-bottom:8px;cursor:pointer" onclick="openArticle(${i})">
        <div class="row" style="justify-content:space-between">
          <b>${esc(a.title)}</b>
          <span class="sub">${esc(a.category)}${a.score != null ? " · score " + a.score : ""}</span>
        </div>
        <div class="sub" style="margin-top:4px;">${esc(a.content.slice(0, 140))}…</div>
      </div>
    `).join("") || "<span class='sub'>No results</span>";

  } catch (e) {
    box.innerHTML = `<span style="color:var(--bad)">Search failed: ${esc(e.message)}</span>`;
    toast(e.message, true);
  }
}

$("#kbBtn").addEventListener("click", searchKb);
$("#kbq").addEventListener("keydown", e => { if (e.key === "Enter") searchKb(); });

window.openArticle = index => {
  const a = kbArticlesCache[index];
  if (!a) { toast("Article not found", true); return; }

  $("#detailBody").innerHTML = `
    <span class="close" onclick="hideModal('detailModal')">×</span>
    <h2 style="margin:0 0 8px; color:#2c2a30;">${esc(a.title)}</h2>
    <div class="row sub" style="margin-bottom:12px;">
      <span>Category: <b>${esc(a.category)}</b></span>
    </div>
    <div style="background:#fdfdfd; padding:16px; border:1px solid #eae6eb; border-radius:8px; line-height:1.7; color:#3a3740; max-height:480px; overflow-y:auto; white-space:pre-wrap;">${esc(a.content)}</div>
  `;
  showModal("detailModal");
};

// ---------- graph visualisation (dependency-free SVG, radial layout) ----------
const COLORS = {
  Ticket: "#7068a8", Customer: "#7fa58d", Agent: "#c38769", Category: "#a77bbd",
  Message: "#817d86", Attachment: "#9a9691", Article: "#b95d52", Feedback: "#d49b55",
  Phone: "#75a7a1", Department: "#625d72", Skill: "#8799b8"
};
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
    return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="#c9c4c8" stroke-width="1.5" opacity=".82"/><text x="${(x1 + x2) / 2}" y="${(y1 + y2) / 2}" fill="#8d858b" text-anchor="middle" style="font-size:9px;letter-spacing:.02em">${esc(e.type)}</text>`;
  }).join("");
  const dots = g.nodes.filter(n => pos.has(n.id)).map(n => { const [x, y] = pos.get(n.id);
    const radius = n.id === g.root ? 22 : 15;
    return `<circle cx="${x}" cy="${y}" r="${radius}" fill="${COLORS[n.label] || "#817d86"}" stroke="#f8f5f1" stroke-width="4" paint-order="stroke"/><text x="${x}" y="${y + (n.id === g.root ? 37 : 30)}" fill="#4e4a52" text-anchor="middle" style="font-weight:${n.id === g.root ? 700 : 500}">${esc(n.caption.slice(0, 26))}</text>`; }).join("");
  svg.innerHTML = lines + dots;
  $("#legend").innerHTML = [...new Set(g.nodes.map(n => n.label))].map(l => `<span><i style="background:${COLORS[l] || "#555"}"></i>${l}</span>`).join("");
});
$("#graphBtn").onclick = drawGraph;

loadDash();