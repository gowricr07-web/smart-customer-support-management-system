const express = require("express");
const path = require("path");
const { run } = require("./db");

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const wrap = fn => (req, res) => fn(req, res).catch(err => {
  console.error(err);
  res.status(500).json({ error: err.message });
});
const PRIORITIES = ["Low", "Medium", "High", "Critical"];
const STATUSES = ["Open", "In Progress", "Resolved", "Closed"];
const CHANNELS = ["Email", "Chat", "Phone", "Portal", "Social Media"];

// ---------- lookups ----------
app.get("/api/customers", wrap(async (_q, res) => res.json(await run(
  `MATCH (c:Customer) OPTIONAL MATCH (c)-[:HAS_PHONE]->(p:Phone)
   RETURN c.customerId AS customerId, c.name AS name, c.email AS email, collect(p.number) AS phones
   ORDER BY c.customerId`))));

app.get("/api/categories", wrap(async (_q, res) => res.json(await run(
  `MATCH (c:Category) RETURN c.categoryId AS categoryId, c.name AS name ORDER BY c.categoryId`))));

app.get("/api/departments", wrap(async (_q, res) => res.json(await run(
  `MATCH (d:Department) RETURN d.departmentId AS departmentId, d.name AS name ORDER BY d.departmentId`))));

app.get("/api/agents", wrap(async (_q, res) => res.json(await run(
  `MATCH (a:Agent)-[:WORKS_IN]->(d:Department)
   OPTIONAL MATCH (a)-[:HAS_SKILL]->(s:Skill)
   WITH a, d, collect(s.name) AS skills
   OPTIONAL MATCH (a)<-[:ASSIGNED_TO]-(t:Ticket)
   WITH a, d, skills, collect(t) AS ts
   OPTIONAL MATCH (a)<-[:ASSIGNED_TO]-(:Ticket)-[:HAS_FEEDBACK]->(f:Feedback)
   RETURN a.agentId AS agentId, a.name AS name, a.email AS email, d.name AS department, skills,
          size([x IN ts WHERE x.status IN ['Open','In Progress']]) AS openTickets,
          round(avg(f.rating) * 100) / 100 AS avgRating
   ORDER BY a.agentId`))));

// ---------- dashboard ----------
app.get("/api/stats", wrap(async (_q, res) => {
  const [totals] = await run(
    `MATCH (t:Ticket)
     RETURN count(t) AS tickets,
            count(CASE WHEN t.status IN ['Open','In Progress'] THEN 1 END) AS open,
            count(CASE WHEN t.status IN ['Resolved','Closed'] THEN 1 END) AS resolved`);
  const [fb] = await run(`MATCH (f:Feedback) RETURN round(avg(f.rating) * 100) / 100 AS avgRating, count(f) AS count`);
  const byCategory = await run(
    `MATCH (t:Ticket)-[:BELONGS_TO]->(c:Category) RETURN c.name AS category, count(t) AS tickets ORDER BY tickets DESC`);
  const byPriority = await run(
    `MATCH (t:Ticket) WHERE t.status IN ['Open','In Progress'] RETURN t.priority AS priority, count(t) AS tickets`);
  const dept = await run(
    `MATCH (d:Department)<-[:WORKS_IN]-(a:Agent)<-[:ASSIGNED_TO]-(t:Ticket)
     OPTIONAL MATCH (t)-[:HAS_FEEDBACK]->(f:Feedback)
     RETURN d.name AS department, count(DISTINCT a) AS agents, count(DISTINCT t) AS tickets,
            round(avg(f.rating) * 100) / 100 AS avgRating,
            round(avg(CASE WHEN t.resolvedAt IS NOT NULL THEN duration.between(t.createdAt, t.resolvedAt).hours END) * 10) / 10 AS avgResolutionHours`);
  const repeat = await run(
    `MATCH (c:Customer)-[:RAISED]->(t:Ticket)-[:BELONGS_TO]->(cat:Category)
     WITH c, cat, collect(t.ticketId) AS tickets WHERE size(tickets) > 1
     RETURN c.name AS customer, cat.name AS category, tickets`);
  res.json({ ...totals, feedback: fb, byCategory, byPriority, departments: dept, repeatIssues: repeat });
}));

// ---------- tickets: list / detail ----------
app.get("/api/tickets", wrap(async (req, res) => {
  const status = req.query.status || null;
  res.json(await run(
    `MATCH (cu:Customer)-[:RAISED]->(t:Ticket)-[:BELONGS_TO]->(c:Category)
     WHERE $status IS NULL OR t.status = $status
     OPTIONAL MATCH (t)-[:ASSIGNED_TO]->(a:Agent)
     RETURN t.ticketId AS ticketId, t.subject AS subject, t.priority AS priority, t.status AS status,
            t.channel AS channel, cu.name AS customer, a.name AS agent, c.name AS category,
            toString(t.createdAt) AS createdAt, toString(t.resolvedAt) AS resolvedAt
     ORDER BY t.ticketId DESC`, { status }));
}));

app.get("/api/tickets/:id", wrap(async (req, res) => {
  const id = Number(req.params.id);
  const [ticket] = await run(
    `MATCH (cu:Customer)-[:RAISED]->(t:Ticket {ticketId:$id})-[:BELONGS_TO]->(c:Category)
     OPTIONAL MATCH (t)-[:ASSIGNED_TO]->(a:Agent)
     RETURN t.ticketId AS ticketId, t.subject AS subject, t.description AS description,
            t.priority AS priority, t.status AS status, t.channel AS channel,
            cu.name AS customer, cu.customerId AS customerId, a.name AS agent, c.name AS category,
            toString(t.createdAt) AS createdAt, toString(t.resolvedAt) AS resolvedAt`, { id });
  if (!ticket) return res.status(404).json({ error: "Ticket not found" });

  // G1: conversation in order, with attachments
  const messages = await run(
    `MATCH (:Ticket {ticketId:$id})-[:HAS_MESSAGE]->(m:Message)
     OPTIONAL MATCH (m)-[:HAS_ATTACHMENT]->(att:Attachment)
     RETURN m.seqNo AS seqNo, m.senderType AS senderType, m.content AS content,
            toString(m.createdAt) AS createdAt,
            collect(att.fileUrl) AS attachments
     ORDER BY m.seqNo`, { id });

  const suggestions = await run(
    `MATCH (:Ticket {ticketId:$id})-[s:SUGGESTED]->(ar:Article)
     RETURN ar.articleId AS articleId, ar.title AS title, s.confidence AS confidence
     ORDER BY s.confidence DESC`, { id });

  const [feedback] = await run(
    `MATCH (:Ticket {ticketId:$id})-[:HAS_FEEDBACK]->(f:Feedback)
     RETURN f.rating AS rating, f.comments AS comments`, { id });

  res.json({ ...ticket, messages, suggestions, feedback: feedback || null });
}));

// G2: agents whose skills match what the ticket's category requires, ranked by workload
app.get("/api/tickets/:id/recommend-agents", wrap(async (req, res) => {
  res.json(await run(
    `MATCH (t:Ticket {ticketId:$id})-[:BELONGS_TO]->(:Category)-[:REQUIRES_SKILL]->(s:Skill)<-[:HAS_SKILL]-(a:Agent)
     OPTIONAL MATCH (a)<-[:ASSIGNED_TO]-(o:Ticket) WHERE o.status IN ['Open','In Progress']
     RETURN a.agentId AS agentId, a.name AS agent, s.name AS matchedSkill, count(o) AS openTickets
     ORDER BY openTickets`, { id: Number(req.params.id) }));
}));

// G3: articles that worked for similar (same-category) tickets with feedback
app.get("/api/tickets/:id/recommend-articles", wrap(async (req, res) => {
  res.json(await run(
    `MATCH (t:Ticket {ticketId:$id})-[:BELONGS_TO]->(c:Category)<-[:BELONGS_TO]-(old:Ticket)-[s:SUGGESTED]->(ar:Article)
     WHERE old <> t
     MATCH (old)-[:HAS_FEEDBACK]->(f:Feedback)
     RETURN ar.articleId AS articleId, ar.title AS title,
            round(avg(f.rating) * 100) / 100 AS avgRating,
            round(avg(s.confidence) * 1000) / 1000 AS avgConfidence, count(old) AS timesUsed
     ORDER BY avgRating DESC, avgConfidence DESC`, { id: Number(req.params.id) }));
}));

// ---------- tickets: create (auto-routing) ----------
app.post("/api/tickets", wrap(async (req, res) => {
  const { customerId, category, department, subject, description = "", priority = "Medium", channel } = req.body;
  if (!customerId || !category || !department || !subject || !channel)
    return res.status(400).json({ error: "customerId, category, department, subject and channel are required" });
  if (!PRIORITIES.includes(priority)) return res.status(400).json({ error: "Invalid priority" });
  if (!CHANNELS.includes(channel)) return res.status(400).json({ error: "Invalid channel" });

  const rows = await run(
    `MATCH (cu:Customer {customerId:$customerId}), (cat:Category {name:$category}), (d:Department {name:$department})
     CALL {
       WITH d
       MATCH (a:Agent)-[:WORKS_IN]->(d)
       OPTIONAL MATCH (a)<-[:ASSIGNED_TO]-(t:Ticket) WHERE t.status IN ['Open','In Progress']
       RETURN a AS best, count(t) AS load ORDER BY load ASC, a.agentId ASC LIMIT 1
     }
     CALL { MATCH (x:Ticket) RETURN coalesce(max(x.ticketId), 0) + 1 AS nid }
     CREATE (tk:Ticket {ticketId:nid, subject:$subject, description:$description, priority:$priority,
                        status:'Open', channel:$channel, createdAt:datetime()})
     CREATE (cu)-[:RAISED]->(tk)
     CREATE (tk)-[:BELONGS_TO]->(cat)
     CREATE (tk)-[:ASSIGNED_TO]->(best)
     RETURN tk.ticketId AS ticketId, best.name AS assignedTo, load AS agentLoadBefore`,
    { customerId: Number(customerId), category, department, subject, description, priority, channel }, true);
  if (!rows.length) return res.status(404).json({ error: "Customer, category, department or an agent in it was not found" });
  res.status(201).json(rows[0]);
}));

// ---------- tickets: messages ----------
app.post("/api/tickets/:id/messages", wrap(async (req, res) => {
  const { senderType, content } = req.body;
  if (!["customer", "agent", "system"].includes(senderType) || !content)
    return res.status(400).json({ error: "senderType (customer|agent|system) and content are required" });
  const rows = await run(
    `MATCH (tk:Ticket {ticketId:$id})
     OPTIONAL MATCH (tk)-[:HAS_MESSAGE]->(l:Message)
     WITH tk, l ORDER BY l.seqNo DESC LIMIT 1
     CREATE (m:Message {seqNo: coalesce(l.seqNo, 0) + 1, senderType:$senderType, content:$content, createdAt:datetime()})
     CREATE (tk)-[:HAS_MESSAGE]->(m)
     FOREACH (_ IN CASE WHEN l IS NULL THEN [] ELSE [1] END | CREATE (l)-[:NEXT]->(m))
     RETURN m.seqNo AS seqNo`, { id: Number(req.params.id), senderType, content }, true);
  if (!rows.length) return res.status(404).json({ error: "Ticket not found" });
  res.status(201).json(rows[0]);
}));

// ---------- tickets: status ----------
app.patch("/api/tickets/:id/status", wrap(async (req, res) => {
  const { status } = req.body;
  if (!STATUSES.includes(status)) return res.status(400).json({ error: "Invalid status" });
  const rows = await run(
    `MATCH (t:Ticket {ticketId:$id})
     SET t.status = $status,
         t.resolvedAt = CASE WHEN $status IN ['Resolved','Closed'] THEN coalesce(t.resolvedAt, datetime()) ELSE null END
     RETURN t.ticketId AS ticketId, t.status AS status, toString(t.resolvedAt) AS resolvedAt`,
    { id: Number(req.params.id), status }, true);
  if (!rows.length) return res.status(404).json({ error: "Ticket not found" });
  res.json(rows[0]);
}));

// ---------- tickets: reassign ----------
app.patch("/api/tickets/:id/agent", wrap(async (req, res) => {
  const rows = await run(
    `MATCH (t:Ticket {ticketId:$id}), (a:Agent {agentId:$agentId})
     OPTIONAL MATCH (t)-[r:ASSIGNED_TO]->(:Agent)
     DELETE r
     CREATE (t)-[:ASSIGNED_TO]->(a)
     RETURN t.ticketId AS ticketId, a.name AS agent`,
    { id: Number(req.params.id), agentId: Number(req.body.agentId) }, true);
  if (!rows.length) return res.status(404).json({ error: "Ticket or agent not found" });
  res.json(rows[0]);
}));

// ---------- tickets: feedback (only Resolved/Closed, once) ----------
app.post("/api/tickets/:id/feedback", wrap(async (req, res) => {
  const id = Number(req.params.id);
  const rating = Number(req.body.rating);
  if (!(rating >= 1 && rating <= 5)) return res.status(400).json({ error: "rating must be 1-5" });
  const rows = await run(
    `MATCH (t:Ticket {ticketId:$id}) WHERE t.status IN ['Resolved','Closed'] AND NOT (t)-[:HAS_FEEDBACK]->()
     CALL { MATCH (x:Feedback) RETURN coalesce(max(x.feedbackId), 0) + 1 AS nid }
     CREATE (t)-[:HAS_FEEDBACK]->(f:Feedback {feedbackId:nid, rating:$rating, comments:$comments, createdAt:datetime()})
     RETURN f.feedbackId AS feedbackId`,
    { id, rating, comments: req.body.comments || "" }, true);
  if (rows.length) return res.status(201).json(rows[0]);
  const [t] = await run(
    `MATCH (t:Ticket {ticketId:$id}) RETURN t.status AS status, EXISTS { (t)-[:HAS_FEEDBACK]->() } AS has`, { id });
  if (!t) return res.status(404).json({ error: "Ticket not found" });
  res.status(409).json({ error: t.has
    ? "This ticket already has feedback."
    : `Feedback is only allowed for Resolved or Closed tickets (current status: ${t.status}).` });
}));

// ---------- tickets: delete ----------
app.delete("/api/tickets/:id", wrap(async (req, res) => {
  const rows = await run(
    `MATCH (t:Ticket {ticketId:$id})
     OPTIONAL MATCH (t)-[:HAS_MESSAGE]->(m:Message)
     OPTIONAL MATCH (m)-[:HAS_ATTACHMENT]->(att:Attachment)
     OPTIONAL MATCH (t)-[:HAS_FEEDBACK]->(f:Feedback)
     WITH t, collect(DISTINCT att) AS atts, collect(DISTINCT m) AS ms, collect(DISTINCT f) AS fs
     DETACH DELETE t
     FOREACH (x IN atts | DETACH DELETE x)
     FOREACH (x IN ms | DETACH DELETE x)
     FOREACH (x IN fs | DETACH DELETE x)
     RETURN 1 AS deleted`, { id: Number(req.params.id) }, true);
  if (!rows.length) return res.status(404).json({ error: "Ticket not found" });
  res.json({ deleted: true });
}));

// ---------- knowledge base: full-text search ----------
app.get("/api/articles/search", wrap(async (req, res) => {
  const q = (req.query.q || "").trim();
  if (!q) return res.json(await run(
    `MATCH (a:Article)-[:ORGANIZED_UNDER]->(c:Category)
     RETURN a.articleId AS articleId, a.title AS title, a.content AS content, c.name AS category, null AS score
     ORDER BY a.articleId`));
  // escape Lucene special characters
  const lucene = q.replace(/([+\-!(){}\[\]^"~*?:\\\/]|&&|\|\|)/g, "\\$1");
  res.json(await run(
    `CALL db.index.fulltext.queryNodes('article_text', $q) YIELD node, score
     MATCH (node)-[:ORGANIZED_UNDER]->(c:Category)
     RETURN node.articleId AS articleId, node.title AS title, node.content AS content,
            c.name AS category, round(score * 1000) / 1000 AS score
     ORDER BY score DESC`, { q: lucene }));
}));

// ---------- graph subgraph for visualisation ----------
app.get("/api/graph/:id", wrap(async (req, res) => {
  const { driver } = require("./db");
  const session = driver.session();
  try {
    const result = await session.run(
      `MATCH p=(:Ticket {ticketId:$id})-[*1..2]-(x) RETURN p`, { id: Number(req.params.id) });
    const nodes = new Map(); const edges = new Map();
    const caption = n => n.properties.name || n.properties.subject || n.properties.title ||
      n.properties.number || (n.properties.content ? n.properties.content.slice(0, 22) : null) ||
      n.properties.fileUrl || (n.properties.rating ? `Rating ${n.properties.rating}` : n.labels[0]);
    for (const rec of result.records) {
      for (const seg of rec.get("p").segments) {
        for (const n of [seg.start, seg.end])
          nodes.set(n.elementId, { id: n.elementId, label: n.labels[0], caption: String(caption(n)) });
        const r = seg.relationship;
        edges.set(r.elementId, { from: r.startNodeElementId, to: r.endNodeElementId, type: r.type });
      }
    }
    const [root] = await run(`MATCH (t:Ticket {ticketId:$id}) RETURN elementId(t) AS id`, { id: Number(req.params.id) });
    res.json({ root: root ? root.id : null, nodes: [...nodes.values()], edges: [...edges.values()] });
  } finally { await session.close(); }
}));

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Smart Support app running at http://localhost:${port}`));
