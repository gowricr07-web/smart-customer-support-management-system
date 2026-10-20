// ============================================================================
// DA3 - Smart Customer Support Management System on Neo4j (Graph Database)
// 01_model_and_import.cypher : constraints, indexes, sample dataset
// Target: Neo4j 5.x (Desktop / AuraDB Free / Docker). Run in Neo4j Browser,
// one block at a time (blocks are separated by blank lines + comments).
// ============================================================================

// ---------- 0. Start clean (demo only) ----------
MATCH (n) DETACH DELETE n;

// ---------- 1. Constraints (uniqueness = the old PRIMARY KEYs / UNIQUEs) ----------
CREATE CONSTRAINT customer_id IF NOT EXISTS FOR (n:Customer)   REQUIRE n.customerId   IS UNIQUE;
CREATE CONSTRAINT customer_email IF NOT EXISTS FOR (n:Customer) REQUIRE n.email       IS UNIQUE;
CREATE CONSTRAINT agent_id IF NOT EXISTS FOR (n:Agent)         REQUIRE n.agentId      IS UNIQUE;
CREATE CONSTRAINT dept_id IF NOT EXISTS FOR (n:Department)     REQUIRE n.departmentId IS UNIQUE;
CREATE CONSTRAINT category_id IF NOT EXISTS FOR (n:Category)   REQUIRE n.categoryId   IS UNIQUE;
CREATE CONSTRAINT ticket_id IF NOT EXISTS FOR (n:Ticket)       REQUIRE n.ticketId     IS UNIQUE;
CREATE CONSTRAINT article_id IF NOT EXISTS FOR (n:Article)     REQUIRE n.articleId    IS UNIQUE;
CREATE CONSTRAINT skill_name IF NOT EXISTS FOR (n:Skill)       REQUIRE n.name         IS UNIQUE;
CREATE CONSTRAINT phone_number IF NOT EXISTS FOR (n:Phone)     REQUIRE n.number       IS UNIQUE;
CREATE CONSTRAINT feedback_id IF NOT EXISTS FOR (n:Feedback)   REQUIRE n.feedbackId   IS UNIQUE;

// ---------- 2. Indexes for common filters ----------
CREATE INDEX ticket_status   IF NOT EXISTS FOR (t:Ticket) ON (t.status);
CREATE INDEX ticket_priority IF NOT EXISTS FOR (t:Ticket) ON (t.priority);
CREATE FULLTEXT INDEX article_text IF NOT EXISTS FOR (a:Article) ON EACH [a.title, a.content];

// ---------- 3. Departments, categories, skills ----------
UNWIND [{id:1,name:'Billing'},{id:2,name:'Technical'}] AS d
CREATE (:Department {departmentId:d.id, name:d.name});

UNWIND [{id:1,name:'Payment Issue'},{id:2,name:'Login Issue'},
        {id:3,name:'Refund Delay'},{id:4,name:'App Crash'}] AS c
CREATE (:Category {categoryId:c.id, name:c.name});

UNWIND ['SQL','Networking','Billing Systems','Java'] AS s
CREATE (:Skill {name:s});

// Category -> skill needed (graph-only knowledge used for smart routing)
UNWIND [['Payment Issue','Billing Systems'],['Refund Delay','Billing Systems'],
        ['Login Issue','SQL'],['App Crash','Java']] AS r
MATCH (c:Category {name:r[0]}), (s:Skill {name:r[1]})
CREATE (c)-[:REQUIRES_SKILL]->(s);

// ---------- 4. Agents ----------
UNWIND [{id:1,name:'R. Singh',email:'rsingh@corp.com',dept:1,skills:['SQL','Networking']},
        {id:2,name:'M. Kumar',email:'mkumar@corp.com',dept:1,skills:['Billing Systems']},
        {id:3,name:'P. Reddy',email:'preddy@corp.com',dept:2,skills:['Java']}] AS a
MATCH (d:Department {departmentId:a.dept})
CREATE (ag:Agent {agentId:a.id, name:a.name, email:a.email, role:'Support Agent'})
CREATE (ag)-[:WORKS_IN]->(d)
WITH ag, a
UNWIND a.skills AS sk
MATCH (s:Skill {name:sk})
CREATE (ag)-[:HAS_SKILL]->(s);

// ---------- 5. Customers + phone numbers (multivalued attr -> Phone nodes) ----------
UNWIND [{id:1,name:'A. Rao',email:'a.rao@mail.com',phones:['9876543210','8765432109']},
        {id:2,name:'B. Iyer',email:'b.iyer@mail.com',phones:['9123456780']},
        {id:3,name:'Gowri',email:'gowri@mail.com',phones:['9988776655']},
        {id:4,name:'Avani',email:'avani@mail.com',phones:['9871234560']}] AS c
CREATE (cu:Customer {customerId:c.id, name:c.name, email:c.email,
                     createdAt: datetime('2026-09-01T10:00:00')})
WITH cu, c
UNWIND c.phones AS ph
CREATE (cu)-[:HAS_PHONE]->(:Phone {number:ph});

// ---------- 6. Knowledge articles ----------
UNWIND [{id:1,cat:1,title:'Refund Policy Overview',content:'Explains standard refund timelines and eligibility.'},
        {id:2,cat:2,title:'How to Reset Password',content:'Step-by-step password reset walkthrough.'},
        {id:3,cat:4,title:'Troubleshooting App Crashes',content:'Common causes of startup crashes and fixes.'},
        {id:4,cat:3,title:'Refund Delay Resolution Guide',content:'How to investigate and expedite a delayed refund.'}] AS a
MATCH (c:Category {categoryId:a.cat})
CREATE (ar:Article {articleId:a.id, title:a.title, content:a.content,
                    createdAt: datetime('2026-09-02T09:00:00')})
CREATE (ar)-[:ORGANIZED_UNDER]->(c);

// ---------- 7. Tickets (T1,T3,T4 resolved so analytics have data; T2,T5 open) ----------
UNWIND [
 {id:1,cust:1,agent:1,cat:1,subject:'Refund not received',priority:'High',status:'Resolved',channel:'Email',created:'2026-10-01T09:00:00',resolved:'2026-10-02T15:00:00'},
 {id:2,cust:2,agent:1,cat:2,subject:'Cannot login to account',priority:'Medium',status:'Open',channel:'Chat',created:'2026-10-03T11:00:00',resolved:null},
 {id:3,cust:3,agent:2,cat:3,subject:'Refund delayed by 10 days',priority:'High',status:'Resolved',channel:'Portal',created:'2026-10-04T08:30:00',resolved:'2026-10-05T10:30:00'},
 {id:4,cust:4,agent:3,cat:4,subject:'App crashes on startup',priority:'Critical',status:'Resolved',channel:'Phone',created:'2026-10-05T14:00:00',resolved:'2026-10-07T09:00:00'},
 {id:5,cust:4,agent:3,cat:4,subject:'App still crashing after update',priority:'High',status:'Open',channel:'Chat',created:'2026-10-12T16:00:00',resolved:null}
] AS t
MATCH (cu:Customer {customerId:t.cust}), (ag:Agent {agentId:t.agent}), (cat:Category {categoryId:t.cat})
CREATE (tk:Ticket {ticketId:t.id, subject:t.subject, description:t.subject, priority:t.priority,
                   status:t.status, channel:t.channel, createdAt:datetime(t.created),
                   resolvedAt: CASE WHEN t.resolved IS NULL THEN null ELSE datetime(t.resolved) END})
CREATE (cu)-[:RAISED]->(tk)
CREATE (tk)-[:ASSIGNED_TO]->(ag)
CREATE (tk)-[:BELONGS_TO]->(cat);

// ---------- 8. Messages (weak entity -> child node, ordered by seqNo) ----------
UNWIND [
 {t:1,s:1,who:'customer',c:'When will I get refund?'},
 {t:1,s:2,who:'agent',c:'Checking now'},
 {t:2,s:1,who:'customer',c:'Forgot my password'},
 {t:3,s:1,who:'customer',c:'Please refund at earliest'},
 {t:4,s:1,who:'customer',c:'App closes immediately after opening'},
 {t:5,s:1,who:'customer',c:'Crash persists after the latest patch'}
] AS m
MATCH (tk:Ticket {ticketId:m.t})
CREATE (tk)-[:HAS_MESSAGE]->(:Message {seqNo:m.s, senderType:m.who, content:m.c,
                                       createdAt: tk.createdAt + duration({minutes:m.s*10})});

// Chain messages in order: (m1)-[:NEXT]->(m2)
MATCH (t:Ticket)-[:HAS_MESSAGE]->(a:Message), (t)-[:HAS_MESSAGE]->(b:Message)
WHERE b.seqNo = a.seqNo + 1
CREATE (a)-[:NEXT]->(b);

// ---------- 9. Attachment ----------
MATCH (:Ticket {ticketId:4})-[:HAS_MESSAGE]->(m:Message {seqNo:1})
CREATE (m)-[:HAS_ATTACHMENT]->(:Attachment {seqNo:1, fileUrl:'screenshot_crash.png', fileType:'image/png'});

// ---------- 10. AI suggestions = relationship WITH properties ----------
UNWIND [{t:1,a:1,conf:0.87},{t:3,a:4,conf:0.75},{t:4,a:3,conf:0.91},{t:5,a:3,conf:0.88}] AS s
MATCH (tk:Ticket {ticketId:s.t}), (ar:Article {articleId:s.a})
CREATE (tk)-[:SUGGESTED {confidence:s.conf, suggestedAt:tk.createdAt + duration({minutes:5})}]->(ar);

// ---------- 11. Feedback ----------
UNWIND [{id:1,t:1,r:4,c:'Quick resolution'},{id:2,t:3,r:5,c:'Very satisfied'},{id:3,t:4,r:3,c:'Took a while to fix'}] AS f
MATCH (tk:Ticket {ticketId:f.t})
CREATE (tk)-[:HAS_FEEDBACK]->(:Feedback {feedbackId:f.id, rating:f.r, comments:f.c,
                                         createdAt: tk.resolvedAt + duration({hours:2})});

// ---------- 12. Verify ----------
MATCH (n) RETURN labels(n)[0] AS label, count(*) AS nodes ORDER BY nodes DESC;
MATCH ()-[r]->() RETURN type(r) AS relationship, count(*) AS total ORDER BY total DESC;
