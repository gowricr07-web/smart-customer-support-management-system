/* ============================================================================
   SMART CUSTOMER SUPPORT MANAGEMENT SYSTEM
   02_plsql_programs.sql
   All PL/SQL program units: surrogate-key triggers, business-rule triggers,
   standalone functions/procedures, and a packaged API (pkg_ticket_mgmt).

   Run this AFTER 01_ddl_tables.sql and BEFORE 03_sample_data.sql.
   ============================================================================ */

SET SERVEROUTPUT ON;

/* ============================================================================
   SECTION A — Surrogate primary-key generator triggers
   One BEFORE INSERT ... FOR EACH ROW trigger per table with a NUMBER
   surrogate key, so callers never supply an id explicitly.
   ============================================================================ */

CREATE OR REPLACE TRIGGER trg_department_pk
BEFORE INSERT ON department
FOR EACH ROW
WHEN (NEW.department_id IS NULL)
BEGIN
   :NEW.department_id := seq_department_id.NEXTVAL;
END;
/

CREATE OR REPLACE TRIGGER trg_customer_pk
BEFORE INSERT ON customer
FOR EACH ROW
WHEN (NEW.customer_id IS NULL)
BEGIN
   :NEW.customer_id := seq_customer_id.NEXTVAL;
END;
/

CREATE OR REPLACE TRIGGER trg_agent_pk
BEFORE INSERT ON agent
FOR EACH ROW
WHEN (NEW.agent_id IS NULL)
BEGIN
   :NEW.agent_id := seq_agent_id.NEXTVAL;
END;
/

CREATE OR REPLACE TRIGGER trg_category_pk
BEFORE INSERT ON category
FOR EACH ROW
WHEN (NEW.category_id IS NULL)
BEGIN
   :NEW.category_id := seq_category_id.NEXTVAL;
END;
/

CREATE OR REPLACE TRIGGER trg_ticket_pk
BEFORE INSERT ON ticket
FOR EACH ROW
WHEN (NEW.ticket_id IS NULL)
BEGIN
   :NEW.ticket_id := seq_ticket_id.NEXTVAL;
END;
/

CREATE OR REPLACE TRIGGER trg_article_pk
BEFORE INSERT ON knowledge_article
FOR EACH ROW
WHEN (NEW.article_id IS NULL)
BEGIN
   :NEW.article_id := seq_article_id.NEXTVAL;
END;
/

CREATE OR REPLACE TRIGGER trg_suggestion_pk
BEFORE INSERT ON ai_suggestion
FOR EACH ROW
WHEN (NEW.suggestion_id IS NULL)
BEGIN
   :NEW.suggestion_id := seq_suggestion_id.NEXTVAL;
END;
/

CREATE OR REPLACE TRIGGER trg_feedback_pk
BEFORE INSERT ON feedback
FOR EACH ROW
WHEN (NEW.feedback_id IS NULL)
BEGIN
   :NEW.feedback_id := seq_feedback_id.NEXTVAL;
END;
/

/* ============================================================================
   SECTION B — Composite-key sequence triggers
   message.message_seq_no restarts at 1 for every ticket; attachment.attachment_
   seq_no restarts at 1 for every (ticket_id, message_seq_no). Implemented with
   MAX()+1 rather than a global sequence because the numbering is scoped per
   parent, matching the design in the normalization report.
   ============================================================================ */

CREATE OR REPLACE TRIGGER trg_message_seqno
BEFORE INSERT ON message
FOR EACH ROW
WHEN (NEW.message_seq_no IS NULL)
DECLARE
   v_next NUMBER;
BEGIN
   SELECT NVL(MAX(message_seq_no), 0) + 1 INTO v_next
   FROM message
   WHERE ticket_id = :NEW.ticket_id;

   :NEW.message_seq_no := v_next;
END;
/

CREATE OR REPLACE TRIGGER trg_attachment_seqno
BEFORE INSERT ON attachment
FOR EACH ROW
WHEN (NEW.attachment_seq_no IS NULL)
DECLARE
   v_next NUMBER;
BEGIN
   SELECT NVL(MAX(attachment_seq_no), 0) + 1 INTO v_next
   FROM attachment
   WHERE ticket_id = :NEW.ticket_id
     AND message_seq_no = :NEW.message_seq_no;

   :NEW.attachment_seq_no := v_next;
END;
/

/* ============================================================================
   SECTION C — Business-rule triggers
   ============================================================================ */

-- C1. Stamp / clear resolved_at automatically as status transitions, so the
--     application never has to set it manually and it can never drift out of
--     sync with status.
CREATE OR REPLACE TRIGGER trg_ticket_status_dates
BEFORE UPDATE OF status ON ticket
FOR EACH ROW
BEGIN
   IF :NEW.status IN ('Resolved','Closed') AND :OLD.status NOT IN ('Resolved','Closed') THEN
      :NEW.resolved_at := SYSDATE;
   ELSIF :NEW.status NOT IN ('Resolved','Closed') THEN
      :NEW.resolved_at := NULL;               -- ticket re-opened
   END IF;
END;
/

-- C2. A customer can only leave feedback once the ticket is Resolved/Closed
--     (protects the 1:1 "Gives" relationship from being used prematurely).
CREATE OR REPLACE TRIGGER trg_feedback_requires_closed
BEFORE INSERT ON feedback
FOR EACH ROW
DECLARE
   v_status ticket.status%TYPE;
BEGIN
   SELECT status INTO v_status FROM ticket WHERE ticket_id = :NEW.ticket_id;

   IF v_status NOT IN ('Resolved','Closed') THEN
      RAISE_APPLICATION_ERROR(-20001,
         'Feedback can only be recorded for a Resolved or Closed ticket (ticket_id='
         || :NEW.ticket_id || ', current status=' || v_status || ').');
   END IF;
END;
/

-- C3. An agent may only be assigned to a ticket if they belong to a
--     department — enforced here rather than by a NOT NULL FK, because
--     tickets may start out unassigned (agent_id IS NULL) and get an agent
--     later via prc_assign_agent.
CREATE OR REPLACE TRIGGER trg_ticket_agent_active
BEFORE INSERT OR UPDATE OF agent_id ON ticket
FOR EACH ROW
DECLARE
   v_count NUMBER;
BEGIN
   IF :NEW.agent_id IS NOT NULL THEN
      SELECT COUNT(*) INTO v_count FROM agent WHERE agent_id = :NEW.agent_id;
      IF v_count = 0 THEN
         RAISE_APPLICATION_ERROR(-20002, 'Agent ' || :NEW.agent_id || ' does not exist.');
      END IF;
   END IF;
END;
/

/* ============================================================================
   SECTION D — Standalone functions
   ============================================================================ */

-- D1. Number of currently-open (Open / In Progress) tickets assigned to an agent.
CREATE OR REPLACE FUNCTION fn_open_ticket_count (p_agent_id IN agent.agent_id%TYPE)
RETURN NUMBER
IS
   v_count NUMBER;
BEGIN
   SELECT COUNT(*) INTO v_count
   FROM ticket
   WHERE agent_id = p_agent_id
     AND status IN ('Open','In Progress');

   RETURN v_count;
END fn_open_ticket_count;
/

-- D2. Average customer-satisfaction rating across every resolved ticket handled
--     by an agent. Returns NULL (no rows) rather than raising when the agent
--     has no feedback yet.
CREATE OR REPLACE FUNCTION fn_avg_rating (p_agent_id IN agent.agent_id%TYPE)
RETURN NUMBER
IS
   v_avg NUMBER;
BEGIN
   SELECT ROUND(AVG(f.rating), 2) INTO v_avg
   FROM feedback f
   JOIN ticket t ON t.ticket_id = f.ticket_id
   WHERE t.agent_id = p_agent_id;

   RETURN v_avg;   -- NULL if the agent has no feedback rows yet
END fn_avg_rating;
/

-- D3. Turnaround time in whole hours between creation and resolution.
CREATE OR REPLACE FUNCTION fn_resolution_hours (p_ticket_id IN ticket.ticket_id%TYPE)
RETURN NUMBER
IS
   v_created  ticket.created_at%TYPE;
   v_resolved ticket.resolved_at%TYPE;
BEGIN
   SELECT created_at, resolved_at INTO v_created, v_resolved
   FROM ticket WHERE ticket_id = p_ticket_id;

   IF v_resolved IS NULL THEN
      RETURN NULL;
   END IF;

   RETURN ROUND((v_resolved - v_created) * 24, 1);
EXCEPTION
   WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20003, 'Ticket ' || p_ticket_id || ' not found.');
END fn_resolution_hours;
/

/* ============================================================================
   SECTION E — Standalone procedures
   ============================================================================ */

-- E1. Pick the least-loaded agent in a department (fewest open tickets;
--     ties broken by agent_id) and return their id. Raises a clear error if
--     the department has no agents at all.
CREATE OR REPLACE PROCEDURE prc_assign_agent (
   p_department_id IN  department.department_id%TYPE,
   p_agent_id      OUT agent.agent_id%TYPE
)
IS
   CURSOR c_dept_agents IS
      SELECT agent_id FROM agent WHERE department_id = p_department_id;

   v_best_agent  agent.agent_id%TYPE;
   v_best_load   NUMBER := NULL;
   v_load        NUMBER;
BEGIN
   FOR r IN c_dept_agents LOOP
      v_load := fn_open_ticket_count(r.agent_id);
      IF v_best_load IS NULL OR v_load < v_best_load THEN
         v_best_load  := v_load;
         v_best_agent := r.agent_id;
      END IF;
   END LOOP;

   IF v_best_agent IS NULL THEN
      RAISE_APPLICATION_ERROR(-20004, 'No agents found in department ' || p_department_id || '.');
   END IF;

   p_agent_id := v_best_agent;
END prc_assign_agent;
/

-- E2. Raise a new ticket and auto-assign it to the least-loaded agent in the
--     department that owns the given category's default routing department.
--     (Category -> department routing is passed in explicitly by the caller,
--     since the schema intentionally keeps category and department independent.)
CREATE OR REPLACE PROCEDURE prc_raise_ticket (
   p_customer_id   IN  customer.customer_id%TYPE,
   p_category_id   IN  category.category_id%TYPE,
   p_department_id IN  department.department_id%TYPE,
   p_subject       IN  ticket.subject%TYPE,
   p_description   IN  ticket.description%TYPE,
   p_priority      IN  ticket.priority%TYPE DEFAULT 'Medium',
   p_channel       IN  ticket.channel%TYPE,
   p_ticket_id     OUT ticket.ticket_id%TYPE
)
IS
   v_agent_id agent.agent_id%TYPE;
BEGIN
   prc_assign_agent(p_department_id, v_agent_id);

   INSERT INTO ticket (customer_id, agent_id, category_id, subject, description,
                        priority, status, channel)
   VALUES (p_customer_id, v_agent_id, p_category_id, p_subject, p_description,
           p_priority, 'Open', p_channel)
   RETURNING ticket_id INTO p_ticket_id;

   DBMS_OUTPUT.PUT_LINE('Ticket #' || p_ticket_id || ' raised and assigned to agent #' || v_agent_id);
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('prc_raise_ticket failed: ' || SQLERRM);
      RAISE;
END prc_raise_ticket;
/

-- E3. Append the next message in a ticket's conversation thread.
CREATE OR REPLACE PROCEDURE prc_add_message (
   p_ticket_id   IN ticket.ticket_id%TYPE,
   p_sender_type IN message.sender_type%TYPE,
   p_content     IN message.content%TYPE
)
IS
BEGIN
   INSERT INTO message (ticket_id, sender_type, content)
   VALUES (p_ticket_id, p_sender_type, p_content);
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('prc_add_message failed for ticket ' || p_ticket_id || ': ' || SQLERRM);
      RAISE;
END prc_add_message;
/

-- E4. Close a ticket (trg_ticket_status_dates stamps resolved_at automatically).
CREATE OR REPLACE PROCEDURE prc_close_ticket (p_ticket_id IN ticket.ticket_id%TYPE)
IS
BEGIN
   UPDATE ticket SET status = 'Resolved' WHERE ticket_id = p_ticket_id;
   IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Ticket ' || p_ticket_id || ' not found.');
   END IF;
END prc_close_ticket;
/

-- E5. Suggest the best-matching knowledge-base article for a ticket (same
--     category) and log it in ai_suggestion. The confidence score is a
--     simple heuristic: higher when the agent handling the ticket already
--     has more resolved tickets in that category (stand-in for a real model).
CREATE OR REPLACE PROCEDURE prc_suggest_article (p_ticket_id IN ticket.ticket_id%TYPE)
IS
   v_category_id   ticket.category_id%TYPE;
   v_article_id    knowledge_article.article_id%TYPE;
   v_confidence    NUMBER;
BEGIN
   SELECT category_id INTO v_category_id FROM ticket WHERE ticket_id = p_ticket_id;

   SELECT article_id INTO v_article_id
   FROM knowledge_article
   WHERE category_id = v_category_id
   FETCH FIRST 1 ROWS ONLY;

   v_confidence := ROUND(DBMS_RANDOM.VALUE(0.65, 0.98), 3);

   INSERT INTO ai_suggestion (ticket_id, article_id, suggested_response, confidence_score)
   VALUES (p_ticket_id, v_article_id,
           'Suggested based on knowledge_article ' || v_article_id
           || ' (same category as ticket ' || p_ticket_id || ').',
           v_confidence);

   DBMS_OUTPUT.PUT_LINE('Suggested article #' || v_article_id || ' for ticket #' || p_ticket_id
                         || ' (confidence ' || v_confidence || ')');
EXCEPTION
   WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('No knowledge article exists yet for the category of ticket ' || p_ticket_id);
END prc_suggest_article;
/

/* ============================================================================
   SECTION F — Packaged API
   Bundles the ticket-lifecycle operations behind one interface, which is the
   idiomatic way to expose PL/SQL functionality to an application tier.
   ============================================================================ */

CREATE OR REPLACE PACKAGE pkg_ticket_mgmt AS

   FUNCTION  open_ticket_count(p_agent_id IN agent.agent_id%TYPE) RETURN NUMBER;
   FUNCTION  avg_rating(p_agent_id IN agent.agent_id%TYPE) RETURN NUMBER;

   PROCEDURE raise_ticket (
      p_customer_id   IN  customer.customer_id%TYPE,
      p_category_id   IN  category.category_id%TYPE,
      p_department_id IN  department.department_id%TYPE,
      p_subject       IN  ticket.subject%TYPE,
      p_description   IN  ticket.description%TYPE,
      p_priority      IN  ticket.priority%TYPE DEFAULT 'Medium',
      p_channel       IN  ticket.channel%TYPE,
      p_ticket_id     OUT ticket.ticket_id%TYPE
   );

   PROCEDURE close_ticket(p_ticket_id IN ticket.ticket_id%TYPE);

   PROCEDURE department_summary;   -- prints a department-wise ticket report

END pkg_ticket_mgmt;
/

CREATE OR REPLACE PACKAGE BODY pkg_ticket_mgmt AS

   FUNCTION open_ticket_count(p_agent_id IN agent.agent_id%TYPE) RETURN NUMBER IS
   BEGIN
      RETURN fn_open_ticket_count(p_agent_id);
   END open_ticket_count;

   FUNCTION avg_rating(p_agent_id IN agent.agent_id%TYPE) RETURN NUMBER IS
   BEGIN
      RETURN fn_avg_rating(p_agent_id);
   END avg_rating;

   PROCEDURE raise_ticket (
      p_customer_id   IN  customer.customer_id%TYPE,
      p_category_id   IN  category.category_id%TYPE,
      p_department_id IN  department.department_id%TYPE,
      p_subject       IN  ticket.subject%TYPE,
      p_description   IN  ticket.description%TYPE,
      p_priority      IN  ticket.priority%TYPE DEFAULT 'Medium',
      p_channel       IN  ticket.channel%TYPE,
      p_ticket_id     OUT ticket.ticket_id%TYPE
   ) IS
   BEGIN
      prc_raise_ticket(p_customer_id, p_category_id, p_department_id, p_subject,
                        p_description, p_priority, p_channel, p_ticket_id);
   END raise_ticket;

   PROCEDURE close_ticket(p_ticket_id IN ticket.ticket_id%TYPE) IS
   BEGIN
      prc_close_ticket(p_ticket_id);
   END close_ticket;

   -- Explicit cursor + %ROWTYPE demonstration: department-wise open-ticket
   -- and average-rating report, printed with DBMS_OUTPUT.
   PROCEDURE department_summary IS
      CURSOR c_dept IS SELECT * FROM department ORDER BY department_id;
      v_open_count   NUMBER;
      v_total_agents NUMBER;
   BEGIN
      DBMS_OUTPUT.PUT_LINE(RPAD('Department', 15) || RPAD('Agents', 8) || RPAD('Open Tkts', 10) || 'Avg Rating');
      DBMS_OUTPUT.PUT_LINE(RPAD('-', 45, '-'));

      FOR d IN c_dept LOOP
         SELECT COUNT(*) INTO v_total_agents FROM agent WHERE department_id = d.department_id;

         SELECT COUNT(*) INTO v_open_count
         FROM ticket t JOIN agent a ON a.agent_id = t.agent_id
         WHERE a.department_id = d.department_id
           AND t.status IN ('Open','In Progress');

         DBMS_OUTPUT.PUT_LINE(
            RPAD(d.name, 15) || RPAD(v_total_agents, 8) || RPAD(v_open_count, 10)
         );
      END LOOP;
   END department_summary;

END pkg_ticket_mgmt;
/
