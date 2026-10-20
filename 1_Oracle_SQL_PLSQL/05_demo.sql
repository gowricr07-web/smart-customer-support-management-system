/* ============================================================================
   SMART CUSTOMER SUPPORT MANAGEMENT SYSTEM
   05_demo.sql — end-to-end demonstration of the PL/SQL API.
   Run after 01-04. Requires SET SERVEROUTPUT ON (already set below).
   ============================================================================ */

SET SERVEROUTPUT ON SIZE UNLIMITED;

PROMPT ============================================================
PROMPT STEP 1 - Raise a brand-new ticket through the package API.
PROMPT           prc_assign_agent picks the Technical agent with the
PROMPT           fewest open tickets (P. Reddy, department_id = 2).
PROMPT ============================================================
DECLARE
   v_ticket1 ticket.ticket_id%TYPE;
   v_ticket2 ticket.ticket_id%TYPE;
BEGIN
   -- Technical department currently has only P. Reddy with open work,
   -- so both new Technical tickets should land on P. Reddy.
   pkg_ticket_mgmt.raise_ticket(
      p_customer_id => 4, p_category_id => 4, p_department_id => 2,
      p_subject => 'App still crashing after update',
      p_description => 'Crash persists after the latest patch.',
      p_priority => 'High', p_channel => 'Chat', p_ticket_id => v_ticket1
   );

   -- Billing department has R. Singh (2 open) and M. Kumar (1 open) ->
   -- the least-loaded agent, M. Kumar, should be auto-assigned here.
   pkg_ticket_mgmt.raise_ticket(
      p_customer_id => 3, p_category_id => 1, p_department_id => 1,
      p_subject => 'Duplicate charge on invoice',
      p_description => 'Charged twice for the same invoice.',
      p_priority => 'Medium', p_channel => 'Email', p_ticket_id => v_ticket2
   );
END;
/

PROMPT ============================================================
PROMPT STEP 2 - Add a follow-up message to ticket T2 and suggest a
PROMPT           knowledge article for it (category = Login Issue).
PROMPT ============================================================
BEGIN
   prc_add_message(p_ticket_id => 2, p_sender_type => 'agent',
                    p_content => 'Password reset link sent to your email.');
   prc_suggest_article(p_ticket_id => 2);
END;
/

PROMPT ============================================================
PROMPT STEP 3 - Close ticket T2. The trg_ticket_status_dates trigger
PROMPT           stamps resolved_at automatically.
PROMPT ============================================================
BEGIN
   pkg_ticket_mgmt.close_ticket(p_ticket_id => 2);
   DBMS_OUTPUT.PUT_LINE('Ticket 2 status/resolved_at after close:');
END;
/
SELECT ticket_id, status, created_at, resolved_at FROM ticket WHERE ticket_id = 2;

PROMPT ============================================================
PROMPT STEP 4 - Record customer feedback for the now-closed ticket.
PROMPT ============================================================
INSERT INTO feedback (ticket_id, rating, comments) VALUES (2, 5, 'Quick fix, thanks!');
COMMIT;

PROMPT ============================================================
PROMPT STEP 5 - Negative test: feedback on a still-OPEN ticket (T1)
PROMPT           must be rejected by trg_feedback_requires_closed with
PROMPT           ORA-20001.
PROMPT ============================================================
BEGIN
   INSERT INTO feedback (ticket_id, rating, comments) VALUES (1, 4, 'Should fail - ticket still open');
   DBMS_OUTPUT.PUT_LINE('UNEXPECTED: insert succeeded');
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Expected failure caught: ' || SQLERRM);
END;
/
ROLLBACK;

PROMPT ============================================================
PROMPT STEP 6 - Function calls: open-ticket count and average rating
PROMPT           per agent.
PROMPT ============================================================
SET SERVEROUTPUT ON
DECLARE
   CURSOR c_agents IS SELECT agent_id, name FROM agent ORDER BY agent_id;
BEGIN
   FOR a IN c_agents LOOP
      DBMS_OUTPUT.PUT_LINE(
         a.name || ' -> open tickets: ' || pkg_ticket_mgmt.open_ticket_count(a.agent_id)
         || ', avg rating: ' || NVL(TO_CHAR(pkg_ticket_mgmt.avg_rating(a.agent_id)), 'n/a')
      );
   END LOOP;
END;
/

PROMPT ============================================================
PROMPT STEP 7 - Packaged department-wise summary report (explicit
PROMPT           cursor + %ROWTYPE demonstration).
PROMPT ============================================================
BEGIN
   pkg_ticket_mgmt.department_summary;
END;
/

PROMPT ============================================================
PROMPT STEP 8 - Reporting views.
PROMPT ============================================================
SELECT * FROM v_open_tickets ORDER BY ticket_id;
SELECT * FROM v_agent_workload ORDER BY agent_id;
SELECT * FROM v_ticket_resolution ORDER BY ticket_id;
SELECT * FROM v_article_usage ORDER BY article_id;
