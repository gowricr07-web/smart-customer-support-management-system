// ============================================================================
// 03_graph_queries.cypher : technology-specific (graph) queries
// ============================================================================

// G1. Ordered conversation of a ticket by walking the NEXT chain
MATCH (t:Ticket {ticketId:1})-[:HAS_MESSAGE]->(first:Message {seqNo:1})
MATCH path = (first)-[:NEXT*0..]->(m:Message)
RETURN m.seqNo, m.senderType, m.content ORDER BY m.seqNo;

// G2. Smart routing: agents who HAVE the skill the ticket's category REQUIRES,
//     ranked by current workload (3-hop skill matching - needs 4 joins in SQL)
MATCH (t:Ticket {ticketId:5})-[:BELONGS_TO]->(:Category)-[:REQUIRES_SKILL]->(s:Skill)<-[:HAS_SKILL]-(a:Agent)
OPTIONAL MATCH (a)<-[:ASSIGNED_TO]-(o:Ticket) WHERE o.status IN ['Open','In Progress']
RETURN a.name AS agent, s.name AS matchedSkill, count(o) AS openTickets
ORDER BY openTickets;

// G3. Recommendation: articles that solved SIMILAR tickets (same category, good rating)
MATCH (t:Ticket {ticketId:5})-[:BELONGS_TO]->(c:Category)<-[:BELONGS_TO]-(old:Ticket)-[s:SUGGESTED]->(ar:Article)
MATCH (old)-[:HAS_FEEDBACK]->(f:Feedback)
RETURN ar.title, round(avg(f.rating),2) AS avgRating, round(avg(s.confidence),3) AS avgConfidence, count(old) AS timesUsed
ORDER BY avgRating DESC, avgConfidence DESC;

// G4. Reach of each article: which customers were pointed to it (3-hop traversal)
MATCH (c:Customer)-[:RAISED]->(:Ticket)-[:SUGGESTED]->(ar:Article)
RETURN ar.title, collect(DISTINCT c.name) AS customersHelped, count(*) AS suggestions
ORDER BY suggestions DESC;

// G5. Repeat-issue detection: customers with 2+ tickets in the same category
MATCH (c:Customer)-[:RAISED]->(t:Ticket)-[:BELONGS_TO]->(cat:Category)
WITH c, cat, collect(t.ticketId) AS tickets WHERE size(tickets) > 1
RETURN c.name, cat.name, tickets;

// G6. Department performance in one traversal
MATCH (d:Department)<-[:WORKS_IN]-(a:Agent)<-[:ASSIGNED_TO]-(t:Ticket)
OPTIONAL MATCH (t)-[:HAS_FEEDBACK]->(f:Feedback)
RETURN d.name AS department, count(DISTINCT a) AS agents, count(t) AS tickets,
       round(avg(f.rating),2) AS avgRating,
       round(avg(duration.between(t.createdAt, t.resolvedAt).hours),1) AS avgResolutionHours;

// G7. Full-text search of the knowledge base (uses fulltext index)
CALL db.index.fulltext.queryNodes('article_text', 'refund OR crash') YIELD node, score
RETURN node.title, round(score,3) AS score ORDER BY score DESC;

// G8. Shortest path between a customer and an agent
MATCH p = shortestPath((c:Customer {name:'Avani'})-[*..6]-(a:Agent {name:'P. Reddy'}))
RETURN [n IN nodes(p) | coalesce(n.name, n.subject)] AS path, length(p) AS hops;

// G9. Whole-ticket subgraph for visual demo (use the graph view in Neo4j Browser)
MATCH p=(cu:Customer)-[:RAISED]->(t:Ticket {ticketId:4})-[*1..2]-(x) RETURN p;
