/* ============================================================================
   SMART CUSTOMER SUPPORT MANAGEMENT SYSTEM
   03_views.sql — reporting views built on the normalized base tables.
   Run after 02_plsql_programs.sql.
   ============================================================================ */

-- All currently open/in-progress tickets with customer, agent and category
-- names resolved (a denormalized read-model for the support dashboard).
CREATE OR REPLACE VIEW v_open_tickets AS
SELECT t.ticket_id, c.name AS customer_name, a.name AS agent_name,
       d.name AS department_name, cat.name AS category_name,
       t.subject, t.priority, t.status, t.channel, t.created_at
FROM ticket t
JOIN customer c  ON c.customer_id = t.customer_id
LEFT JOIN agent a ON a.agent_id = t.agent_id
LEFT JOIN department d ON d.department_id = a.department_id
JOIN category cat ON cat.category_id = t.category_id
WHERE t.status IN ('Open','In Progress');

-- Per-agent workload and performance snapshot.
CREATE OR REPLACE VIEW v_agent_workload AS
SELECT a.agent_id, a.name AS agent_name, d.name AS department_name,
       fn_open_ticket_count(a.agent_id) AS open_tickets,
       fn_avg_rating(a.agent_id)        AS avg_rating
FROM agent a
JOIN department d ON d.department_id = a.department_id;

-- Ticket resolution-time report (hours from creation to resolution).
CREATE OR REPLACE VIEW v_ticket_resolution AS
SELECT t.ticket_id, t.subject, t.status,
       t.created_at, t.resolved_at,
       fn_resolution_hours(t.ticket_id) AS resolution_hours
FROM ticket t;

-- Knowledge-base usage: how often each article has been AI-suggested and
-- with what average confidence.
CREATE OR REPLACE VIEW v_article_usage AS
SELECT ka.article_id, ka.title, cat.name AS category_name,
       COUNT(s.suggestion_id) AS times_suggested,
       ROUND(AVG(s.confidence_score), 3) AS avg_confidence
FROM knowledge_article ka
JOIN category cat ON cat.category_id = ka.category_id
LEFT JOIN ai_suggestion s ON s.article_id = ka.article_id
GROUP BY ka.article_id, ka.title, cat.name;
