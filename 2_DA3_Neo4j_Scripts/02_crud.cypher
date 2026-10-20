// ============================================================================
// 02_crud.cypher : CRUD demonstration (run after 01)
// ============================================================================

// ================= CREATE =================
// C1. New customer with two phones
CREATE (c:Customer {customerId:5, name:'Kiran', email:'kiran@mail.com', createdAt:datetime()})
CREATE (c)-[:HAS_PHONE]->(:Phone {number:'9000011111'})
CREATE (c)-[:HAS_PHONE]->(:Phone {number:'9000022222'})
RETURN c;

// C2. Raise a ticket and AUTO-ROUTE to least-loaded agent in Billing
//     (replaces the PL/SQL prc_raise_ticket + prc_assign_agent)
MATCH (cu:Customer {customerId:5}), (cat:Category {name:'Payment Issue'}),
      (d:Department {name:'Billing'})
CALL {
  WITH d
  MATCH (a:Agent)-[:WORKS_IN]->(d)
  OPTIONAL MATCH (a)<-[:ASSIGNED_TO]-(t:Ticket)
    WHERE t.status IN ['Open','In Progress']
  RETURN a AS best, count(t) AS load
  ORDER BY load ASC, a.agentId ASC
  LIMIT 1
}
CREATE (tk:Ticket {ticketId:6, subject:'Duplicate charge on invoice',
        description:'Charged twice for the same invoice', priority:'Medium',
        status:'Open', channel:'Email', createdAt:datetime()})
CREATE (cu)-[:RAISED]->(tk)
CREATE (tk)-[:BELONGS_TO]->(cat)
CREATE (tk)-[:ASSIGNED_TO]->(best)
RETURN tk.ticketId AS ticket, best.name AS assignedTo, load AS agentLoadBefore;

// C3. Add the next message (seqNo = max+1) and chain it
MATCH (tk:Ticket {ticketId:2})-[:HAS_MESSAGE]->(last:Message)
WITH tk, last ORDER BY last.seqNo DESC LIMIT 1
CREATE (m:Message {seqNo:last.seqNo+1, senderType:'agent',
                   content:'Password reset link sent to your email.', createdAt:datetime()})
CREATE (tk)-[:HAS_MESSAGE]->(m)
CREATE (last)-[:NEXT]->(m)
RETURN m.seqNo, m.content;

// ================= READ =================
// R1. One ticket with customer, agent, category
MATCH (cu:Customer)-[:RAISED]->(t:Ticket {ticketId:2})-[:ASSIGNED_TO]->(a:Agent),
      (t)-[:BELONGS_TO]->(c:Category)
RETURN t.ticketId, t.subject, t.status, cu.name AS customer, a.name AS agent, c.name AS category;

// R2. All open tickets, highest priority first
MATCH (t:Ticket) WHERE t.status IN ['Open','In Progress']
RETURN t.ticketId, t.subject, t.priority, t.status
ORDER BY CASE t.priority WHEN 'Critical' THEN 1 WHEN 'High' THEN 2 WHEN 'Medium' THEN 3 ELSE 4 END;

// R3. Customer's phone numbers
MATCH (:Customer {name:'A. Rao'})-[:HAS_PHONE]->(p:Phone) RETURN p.number;

// ================= UPDATE =================
// U1. Resolve a ticket (resolvedAt stamped, like trg_ticket_status_dates)
MATCH (t:Ticket {ticketId:2})
SET t.status = 'Resolved', t.resolvedAt = datetime()
RETURN t.ticketId, t.status, t.resolvedAt;

// U2. Reassign ticket 5 to another agent (swap the relationship)
MATCH (t:Ticket {ticketId:5})-[r:ASSIGNED_TO]->(:Agent)
DELETE r
WITH t
MATCH (a:Agent {name:'R. Singh'})
CREATE (t)-[:ASSIGNED_TO]->(a)
RETURN t.ticketId, a.name;

// U3. Add a skill to an agent
MATCH (a:Agent {name:'M. Kumar'}) MERGE (s:Skill {name:'Networking'}) MERGE (a)-[:HAS_SKILL]->(s) RETURN a.name, s.name;

// ================= FEEDBACK RULE (guard) =================
// Only Resolved/Closed tickets accept feedback. Ticket 2 is now Resolved -> created:
MATCH (t:Ticket {ticketId:2}) WHERE t.status IN ['Resolved','Closed'] AND NOT (t)-[:HAS_FEEDBACK]->()
CREATE (t)-[:HAS_FEEDBACK]->(:Feedback {feedbackId:4, rating:5, comments:'Quick fix, thanks!', createdAt:datetime()})
RETURN count(*) AS feedbackCreated;
// Ticket 5 is still Open -> returns feedbackCreated = 0 (rule enforced)
MATCH (t:Ticket {ticketId:5}) WHERE t.status IN ['Resolved','Closed'] AND NOT (t)-[:HAS_FEEDBACK]->()
CREATE (t)-[:HAS_FEEDBACK]->(:Feedback {feedbackId:5, rating:4, comments:'should not be created', createdAt:datetime()})
RETURN count(*) AS feedbackCreated;

// ================= DELETE =================
// D1. Delete a ticket together with its messages/attachments/feedback
MATCH (t:Ticket {ticketId:6})
OPTIONAL MATCH (t)-[:HAS_MESSAGE]->(m:Message)
OPTIONAL MATCH (m)-[:HAS_ATTACHMENT]->(att:Attachment)
OPTIONAL MATCH (t)-[:HAS_FEEDBACK]->(f:Feedback)
DETACH DELETE att, m, f, t;

// D2. Constraint demo: duplicate email is rejected
CREATE (:Customer {customerId:99, name:'Dup', email:'a.rao@mail.com'});   // ConstraintValidationFailed

// D3. Remove one phone number only
MATCH (:Customer {customerId:5})-[r:HAS_PHONE]->(p:Phone {number:'9000022222'})
DELETE r, p;
