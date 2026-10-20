# DA3 – Smart Customer Support Management System on Neo4j
*(Content to copy by hand into your handwritten report. Suggested: 5–6 pages.)*

## 1. Aim
Re-implement the 12-table, 5NF Smart Customer Support system using a **Graph Database (Neo4j)** and show CRUD plus graph-specific queries.

## 2. Why Neo4j for this project
- Support data is naturally connected: Customer → Ticket → Agent → Skill → Category → Article.
- Key features (skill-based routing, "which article solved similar tickets", repeat-issue detection, escalation paths) are multi-hop questions → each hop is a JOIN in SQL, a single pattern in Cypher.
- Weak entities (Message, Attachment) and multivalued attributes (phones, skills) become simple child nodes/relationships, no composite keys.
- The AI suggestion (ticket ↔ article + confidence score) is a **relationship with properties**, no associative table.

## 3. Graph model (mapping from relational schema)
| Relational table | Neo4j element |
|---|---|
| customer | `(:Customer {customerId,name,email,createdAt})` |
| customer_phone | `(:Phone {number})` via `(Customer)-[:HAS_PHONE]->(Phone)` |
| department | `(:Department)`; agent → `(Agent)-[:WORKS_IN]->(Department)` |
| agent / agent_skill | `(:Agent)`, `(:Skill)`, `(Agent)-[:HAS_SKILL]->(Skill)` |
| category | `(:Category)` (+ new `(Category)-[:REQUIRES_SKILL]->(Skill)`) |
| ticket | `(:Ticket {subject,priority,status,channel,createdAt,resolvedAt})` with `(Customer)-[:RAISED]->(Ticket)`, `(Ticket)-[:ASSIGNED_TO]->(Agent)`, `(Ticket)-[:BELONGS_TO]->(Category)` |
| message | `(:Message {seqNo,senderType,content})` via `(Ticket)-[:HAS_MESSAGE]->`, ordered with `(Message)-[:NEXT]->(Message)` |
| attachment | `(:Attachment)` via `(Message)-[:HAS_ATTACHMENT]->` |
| knowledge_article | `(:Article)-[:ORGANIZED_UNDER]->(Category)` |
| ai_suggestion | relationship `(Ticket)-[:SUGGESTED {confidence}]->(Article)` |
| feedback | `(:Feedback {rating,comments})` via `(Ticket)-[:HAS_FEEDBACK]->` |

Foreign keys disappear: relationships are stored as direct pointers. PK/UNIQUE → uniqueness constraints. PL/SQL trigger rules → guarded Cypher (`WHERE status IN [...]`) or application logic.
Draw this as a labelled node-relationship diagram in your report (run `MATCH p=(c:Customer)-[:RAISED]->(t:Ticket {ticketId:4})-[*1..2]-(x) RETURN p` and sketch it).

## 4. Implementation steps
1. Install Neo4j Desktop / create free AuraDB instance (or `docker run -p7474:7474 -p7687:7687 -e NEO4J_AUTH=neo4j/password neo4j:5`).
2. Open Neo4j Browser → run `01_model_and_import.cypher` block by block (constraints, indexes, data).
3. Verify counts (last two queries in file 01).
4. Run `02_crud.cypher`, then `03_graph_queries.cypher`.

## 5. Sample dataset
4 customers (+1 added in CRUD), 3 agents, 2 departments, 4 categories, 4 skills, 4 articles, 5 tickets, 6 messages, 1 attachment, 4 AI suggestions, 3 feedbacks (same scenario as your DA1/DA2 report; T1, T3, T4 are marked Resolved so analytics have feedback to work with).

## 6. CRUD (file 02) – summary
- Create: customer with phones; ticket with automatic least-loaded-agent routing; next message.
- Read: ticket with customer/agent/category; open tickets by priority; phones.
- Update: resolve ticket (sets resolvedAt); reassign agent; add skill.
- Delete: ticket with its messages/feedback (`DETACH DELETE`); remove one phone; duplicate email rejected by constraint.
- Business rule: feedback accepted only for Resolved/Closed tickets (returns 0 created for open ticket 5).

## 7. Technology-specific queries (file 03) – expected results on the seed data
| Query | Idea | Expected result |
|---|---|---|
| G1 | Conversation via `:NEXT*` chain | Ticket 1: msg1 customer, msg2 agent |
| G2 | Skill-based routing (Category→Skill←Agent) for ticket 5 | P. Reddy, Java, 1 open ticket |
| G3 | Article recommendation from similar rated tickets | "Troubleshooting App Crashes", avg rating 3.0, conf 0.91 |
| G4 | Article reach | Which customers each article was suggested to |
| G5 | Repeat issues | Avani – App Crash – [4, 5] |
| G6 | Department performance | agents, tickets, avg rating, avg resolution hours |
| G7 | Full-text KB search | refund / crash articles ranked |
| G8 | `shortestPath` | Avani → … → P. Reddy |

## 8. Graph DB vs relational (comparison to write)
| Aspect | Relational (Oracle) | Neo4j |
|---|---|---|
| Relationships | FKs + JOINs computed at query time | Stored as direct pointers (index-free adjacency) |
| Multi-hop queries (skill routing, similar tickets) | 4–6 table joins, slow as data grows | One `MATCH` pattern, cost depends on traversed part only |
| Schema change (new relation e.g. REQUIRES_SKILL) | ALTER/new junction table, migrations | Just create relationships |
| Weak entities / multivalued attrs | Composite keys, extra tables | Child nodes / properties |
| Relationship attributes (confidence score) | Separate associative table | Property on relationship |
| Path / network queries | Recursive CTE, awkward | Built-in `shortestPath`, variable-length paths |
| Integrity & transactions | Strong constraints, mature | ACID but fewer constraint types (checks must be in queries/app) |
| Heavy aggregation / reporting | Excellent | Adequate, not its strength |
**Conclusion:** the connected, recommendation-driven parts of the system (routing, KB suggestions, repeat-issue analysis) fit a graph; bulk reporting could stay relational (polyglot approach).

## 9. Demo script (3–4 minutes)
1. Show graph model slide/diagram. 2. Run file 01, show counts. 3. Show graph view of ticket 4. 4. CRUD: create ticket 6 (point out auto-assigned agent), resolve ticket 2, feedback guard on ticket 5, delete ticket 6. 5. Run G2, G3, G5, G8. 6. State the comparison conclusion.
