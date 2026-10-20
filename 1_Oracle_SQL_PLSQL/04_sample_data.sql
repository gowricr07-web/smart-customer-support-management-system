/* ============================================================================
   SMART CUSTOMER SUPPORT MANAGEMENT SYSTEM
   04_sample_data.sql
   Loads the scenario used throughout the normalization report (customers
   A. Rao, B. Iyer, Gowri, Avani; agents R. Singh, M. Kumar, P. Reddy; the
   four tickets T1-T4) plus a few extra rows so the demo script has enough
   data to show routing, AI suggestions, and reporting in action.

   Surrogate ids are generated automatically by the triggers in
   02_plsql_programs.sql, so column lists deliberately omit every *_id
   column that is a single-column surrogate primary key.
   ============================================================================ */

-- 1. Departments
INSERT INTO department (name) VALUES ('Billing');
INSERT INTO department (name) VALUES ('Technical');

-- 2. Customers
INSERT INTO customer (name, email) VALUES ('A. Rao',  'a.rao@mail.com');
INSERT INTO customer (name, email) VALUES ('B. Iyer',  'b.iyer@mail.com');
INSERT INTO customer (name, email) VALUES ('Gowri',    'gowri@mail.com');
INSERT INTO customer (name, email) VALUES ('Avani',    'avani@mail.com');

-- Customer phone numbers (multivalued attribute; A. Rao has two)
INSERT INTO customer_phone (customer_id, phone) VALUES (1, '9876543210');
INSERT INTO customer_phone (customer_id, phone) VALUES (1, '8765432109');
INSERT INTO customer_phone (customer_id, phone) VALUES (2, '9123456780');
INSERT INTO customer_phone (customer_id, phone) VALUES (3, '9988776655');
INSERT INTO customer_phone (customer_id, phone) VALUES (4, '9871234560');

-- 3. Agents (department_id 1 = Billing, 2 = Technical)
INSERT INTO agent (name, email, role, department_id) VALUES ('R. Singh', 'rsingh@corp.com', 'Support Agent', 1);
INSERT INTO agent (name, email, role, department_id) VALUES ('M. Kumar', 'mkumar@corp.com', 'Support Agent', 1);
INSERT INTO agent (name, email, role, department_id) VALUES ('P. Reddy', 'preddy@corp.com', 'Support Agent', 2);

-- Agent skills (multivalued attribute)
INSERT INTO agent_skill (agent_id, skill_tag) VALUES (1, 'SQL');
INSERT INTO agent_skill (agent_id, skill_tag) VALUES (1, 'Networking');
INSERT INTO agent_skill (agent_id, skill_tag) VALUES (2, 'Billing Systems');
INSERT INTO agent_skill (agent_id, skill_tag) VALUES (3, 'Java');

-- 4. Categories
INSERT INTO category (name) VALUES ('Payment Issue');
INSERT INTO category (name) VALUES ('Login Issue');
INSERT INTO category (name) VALUES ('Refund Delay');
INSERT INTO category (name) VALUES ('App Crash');

-- 5. Knowledge base articles
INSERT INTO knowledge_article (category_id, title, content) VALUES
   (1, 'Refund Policy Overview', 'Explains standard refund timelines and eligibility.');
INSERT INTO knowledge_article (category_id, title, content) VALUES
   (2, 'How to Reset Password', 'Step-by-step password reset walkthrough.');
INSERT INTO knowledge_article (category_id, title, content) VALUES
   (4, 'Troubleshooting App Crashes', 'Common causes of startup crashes and fixes.');
INSERT INTO knowledge_article (category_id, title, content) VALUES
   (3, 'Refund Delay Resolution Guide', 'How to investigate and expedite a delayed refund.');

-- 6. Tickets T1-T4 (agent_id assigned directly here to reproduce the report's
--    exact scenario; prc_raise_ticket / pkg_ticket_mgmt.raise_ticket is used
--    instead in 05_demo.sql to show automatic routing for NEW tickets).
INSERT INTO ticket (customer_id, agent_id, category_id, subject, description, priority, status, channel, created_at)
VALUES (1, 1, 1, 'Refund not received', 'Refund not received', 'High', 'Open', 'Email', SYSDATE - 5);          -- T1

INSERT INTO ticket (customer_id, agent_id, category_id, subject, description, priority, status, channel, created_at)
VALUES (2, 1, 2, 'Cannot login to account', 'Cannot login to account', 'Medium', 'Open', 'Chat', SYSDATE - 4); -- T2

INSERT INTO ticket (customer_id, agent_id, category_id, subject, description, priority, status, channel, created_at)
VALUES (3, 2, 3, 'Refund delayed by 10 days', 'Refund delayed by 10 days', 'High', 'Open', 'Portal', SYSDATE - 3); -- T3

INSERT INTO ticket (customer_id, agent_id, category_id, subject, description, priority, status, channel, created_at)
VALUES (4, 3, 4, 'App crashes on startup', 'App crashes on startup', 'Critical', 'Open', 'Phone', SYSDATE - 2); -- T4

-- 7. Messages (message_seq_no auto-assigned per ticket by trg_message_seqno)
INSERT INTO message (ticket_id, sender_type, content) VALUES (1, 'customer', 'When will I get refund?');
INSERT INTO message (ticket_id, sender_type, content) VALUES (1, 'agent',    'Checking now');
INSERT INTO message (ticket_id, sender_type, content) VALUES (2, 'customer', 'Forgot my password');
INSERT INTO message (ticket_id, sender_type, content) VALUES (3, 'customer', 'Please refund at earliest');
INSERT INTO message (ticket_id, sender_type, content) VALUES (4, 'customer', 'App closes immediately after opening');

-- 8. Attachment (attachment_seq_no auto-assigned by trg_attachment_seqno).
--    Ticket 4's first message is message_seq_no = 1.
INSERT INTO attachment (ticket_id, message_seq_no, file_url, file_type)
VALUES (4, 1, 'https://files.example.com/screenshot_crash.png', 'image/png');

COMMIT;
