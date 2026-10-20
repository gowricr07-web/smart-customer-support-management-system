# Smart Customer Support – Neo4j app (DA3)

Express backend + Neo4j + single-page frontend (no build step).

## Run
1. Start Neo4j 5 (Desktop, AuraDB Free, or `docker run -p7474:7474 -p7687:7687 -e NEO4J_AUTH=neo4j/password neo4j:5`).
2. `cp .env.example .env` and set NEO4J_URI / NEO4J_USER / NEO4J_PASSWORD.
3. `npm install`
4. `npm run seed`   (**wipes the database** and loads constraints, indexes and sample data from `seed.cypher`)
5. `npm start` → open http://localhost:3000

## Screens
- Dashboard: totals, tickets by category/priority, department performance, repeat issues.
- Tickets: list/filter, create (auto-routed to least-loaded agent), detail with conversation, add message,
  change status (resolvedAt stamped), reassign, delete, feedback (only Resolved/Closed, once),
  graph insights (skill-matched agents, articles that worked for similar tickets).
- Agents: skills, open tickets, average rating.
- Knowledge Base: Neo4j full-text index search.
- Graph View: subgraph around any ticket id (try 4).

## REST API
GET /api/stats · /api/customers · /api/agents · /api/categories · /api/departments
GET /api/tickets[?status=] · /api/tickets/:id · /api/tickets/:id/recommend-agents · /api/tickets/:id/recommend-articles
POST /api/tickets · /api/tickets/:id/messages · /api/tickets/:id/feedback
PATCH /api/tickets/:id/status · /api/tickets/:id/agent
DELETE /api/tickets/:id
GET /api/articles/search?q= · /api/graph/:id
