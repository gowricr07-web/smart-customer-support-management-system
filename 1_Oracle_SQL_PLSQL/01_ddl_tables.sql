/* ============================================================================
   SMART CUSTOMER SUPPORT MANAGEMENT SYSTEM
   01_ddl_tables.sql
   Data Definition Language — creates all 12 normalized (5NF) tables,
   their primary/foreign keys, check constraints, and the sequences used
   by the surrogate-key generator triggers in 02_plsql_programs.sql.

   Target: Oracle Database 19c / 21c (SQL*Plus, SQL Developer, or Live SQL)
   Run order: 01_ddl_tables.sql -> 02_plsql_programs.sql ->
              03_sample_data.sql -> 04_demo.sql
   ============================================================================ */

-- Clean slate (ignore ORA-00942 "table does not exist" on first run)
BEGIN
   FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN (
      'FEEDBACK','AI_SUGGESTION','KNOWLEDGE_ARTICLE','ATTACHMENT','MESSAGE',
      'TICKET','AGENT_SKILL','AGENT','CATEGORY','CUSTOMER_PHONE','CUSTOMER',
      'DEPARTMENT')) LOOP
      EXECUTE IMMEDIATE 'DROP TABLE '||t.table_name||' CASCADE CONSTRAINTS PURGE';
   END LOOP;
END;
/

BEGIN
   FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name LIKE 'SEQ_%') LOOP
      EXECUTE IMMEDIATE 'DROP SEQUENCE '||s.sequence_name;
   END LOOP;
END;
/

/* ---------------------------------------------------------------------------
   1. DEPARTMENT  (strong entity)
   --------------------------------------------------------------------------*/
CREATE TABLE department (
   department_id   NUMBER(6)      NOT NULL,
   name            VARCHAR2(60)   NOT NULL,
   CONSTRAINT pk_department PRIMARY KEY (department_id),
   CONSTRAINT uq_department_name UNIQUE (name)
);

/* ---------------------------------------------------------------------------
   2. CUSTOMER  (strong entity)
   --------------------------------------------------------------------------*/
CREATE TABLE customer (
   customer_id     NUMBER(10)     NOT NULL,
   name            VARCHAR2(100)  NOT NULL,
   email           VARCHAR2(120)  NOT NULL,
   created_at      DATE           DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_customer PRIMARY KEY (customer_id),
   CONSTRAINT uq_customer_email UNIQUE (email)
);

/* ---------------------------------------------------------------------------
   3. CUSTOMER_PHONE  (weak/multivalued entity -> 1NF/4NF fix, all-key relation)
   --------------------------------------------------------------------------*/
CREATE TABLE customer_phone (
   customer_id     NUMBER(10)     NOT NULL,
   phone           VARCHAR2(20)   NOT NULL,
   CONSTRAINT pk_customer_phone PRIMARY KEY (customer_id, phone),
   CONSTRAINT fk_cphone_customer FOREIGN KEY (customer_id)
      REFERENCES customer (customer_id) ON DELETE CASCADE
);

/* ---------------------------------------------------------------------------
   4. AGENT  (strong entity)
   --------------------------------------------------------------------------*/
CREATE TABLE agent (
   agent_id        NUMBER(10)     NOT NULL,
   name            VARCHAR2(100)  NOT NULL,
   email           VARCHAR2(120)  NOT NULL,
   role            VARCHAR2(40)   DEFAULT 'Support Agent' NOT NULL,
   department_id   NUMBER(6)      NOT NULL,
   CONSTRAINT pk_agent PRIMARY KEY (agent_id),
   CONSTRAINT uq_agent_email UNIQUE (email),
   CONSTRAINT fk_agent_department FOREIGN KEY (department_id)
      REFERENCES department (department_id)
);

/* ---------------------------------------------------------------------------
   5. AGENT_SKILL  (multivalued attribute -> 1NF/4NF fix, all-key relation)
   --------------------------------------------------------------------------*/
CREATE TABLE agent_skill (
   agent_id        NUMBER(10)     NOT NULL,
   skill_tag       VARCHAR2(40)   NOT NULL,
   CONSTRAINT pk_agent_skill PRIMARY KEY (agent_id, skill_tag),
   CONSTRAINT fk_askill_agent FOREIGN KEY (agent_id)
      REFERENCES agent (agent_id) ON DELETE CASCADE
);

/* ---------------------------------------------------------------------------
   6. CATEGORY  (strong entity)
   --------------------------------------------------------------------------*/
CREATE TABLE category (
   category_id     NUMBER(6)      NOT NULL,
   name            VARCHAR2(60)   NOT NULL,
   CONSTRAINT pk_category PRIMARY KEY (category_id),
   CONSTRAINT uq_category_name UNIQUE (name)
);

/* ---------------------------------------------------------------------------
   7. TICKET  (central strong entity; 1:N from customer, agent, category)
   --------------------------------------------------------------------------*/
CREATE TABLE ticket (
   ticket_id       NUMBER(12)     NOT NULL,
   customer_id     NUMBER(10)     NOT NULL,
   agent_id        NUMBER(10),                 -- nullable: may be unassigned
   category_id     NUMBER(6)      NOT NULL,
   subject         VARCHAR2(200)  NOT NULL,
   description     VARCHAR2(4000),
   priority        VARCHAR2(10)   DEFAULT 'Medium' NOT NULL,
   status          VARCHAR2(15)   DEFAULT 'Open'   NOT NULL,
   channel         VARCHAR2(15)   NOT NULL,
   created_at      DATE           DEFAULT SYSDATE NOT NULL,
   resolved_at     DATE,
   CONSTRAINT pk_ticket PRIMARY KEY (ticket_id),
   CONSTRAINT fk_ticket_customer FOREIGN KEY (customer_id) REFERENCES customer (customer_id),
   CONSTRAINT fk_ticket_agent    FOREIGN KEY (agent_id)    REFERENCES agent (agent_id),
   CONSTRAINT fk_ticket_category FOREIGN KEY (category_id) REFERENCES category (category_id),
   CONSTRAINT ck_ticket_priority CHECK (priority IN ('Low','Medium','High','Critical')),
   CONSTRAINT ck_ticket_status   CHECK (status IN ('Open','In Progress','Resolved','Closed')),
   CONSTRAINT ck_ticket_channel  CHECK (channel IN ('Email','Chat','Phone','Portal','Social Media')),
   CONSTRAINT ck_ticket_resolved_after CHECK (resolved_at IS NULL OR resolved_at >= created_at)
);

/* ---------------------------------------------------------------------------
   8. MESSAGE  (weak entity, identifying relationship "Contains" on ticket;
      composite PK = ticket_id + message_seq_no)
   --------------------------------------------------------------------------*/
CREATE TABLE message (
   ticket_id        NUMBER(12)    NOT NULL,
   message_seq_no   NUMBER(6)     NOT NULL,
   sender_type      VARCHAR2(10)  NOT NULL,
   content          VARCHAR2(4000) NOT NULL,
   created_at       DATE          DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_message PRIMARY KEY (ticket_id, message_seq_no),
   CONSTRAINT fk_message_ticket FOREIGN KEY (ticket_id)
      REFERENCES ticket (ticket_id) ON DELETE CASCADE,
   CONSTRAINT ck_message_sender CHECK (sender_type IN ('customer','agent','system'))
);

/* ---------------------------------------------------------------------------
   9. ATTACHMENT  (weak entity nested under MESSAGE; composite PK =
      ticket_id + message_seq_no + attachment_seq_no)
   --------------------------------------------------------------------------*/
CREATE TABLE attachment (
   ticket_id           NUMBER(12)   NOT NULL,
   message_seq_no      NUMBER(6)    NOT NULL,
   attachment_seq_no   NUMBER(6)    NOT NULL,
   file_url            VARCHAR2(400) NOT NULL,
   file_type           VARCHAR2(40)  NOT NULL,
   CONSTRAINT pk_attachment PRIMARY KEY (ticket_id, message_seq_no, attachment_seq_no),
   CONSTRAINT fk_attachment_message FOREIGN KEY (ticket_id, message_seq_no)
      REFERENCES message (ticket_id, message_seq_no) ON DELETE CASCADE
);

/* ---------------------------------------------------------------------------
   10. KNOWLEDGE_ARTICLE  (strong entity, organized by category)
   --------------------------------------------------------------------------*/
CREATE TABLE knowledge_article (
   article_id      NUMBER(10)     NOT NULL,
   category_id     NUMBER(6)      NOT NULL,
   title           VARCHAR2(200)  NOT NULL,
   content         VARCHAR2(4000) NOT NULL,
   created_at      DATE           DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_article PRIMARY KEY (article_id),
   CONSTRAINT fk_article_category FOREIGN KEY (category_id) REFERENCES category (category_id)
);

/* ---------------------------------------------------------------------------
   11. AI_SUGGESTION  (associative entity: ticket <-> knowledge_article,
       proven irreducible / 5NF in the normalization report)
   --------------------------------------------------------------------------*/
CREATE TABLE ai_suggestion (
   suggestion_id     NUMBER(12)    NOT NULL,
   ticket_id         NUMBER(12)    NOT NULL,
   article_id        NUMBER(10)    NOT NULL,
   suggested_response VARCHAR2(4000),
   confidence_score  NUMBER(4,3)   NOT NULL,
   created_at        DATE          DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_ai_suggestion PRIMARY KEY (suggestion_id),
   CONSTRAINT fk_suggestion_ticket  FOREIGN KEY (ticket_id)  REFERENCES ticket (ticket_id) ON DELETE CASCADE,
   CONSTRAINT fk_suggestion_article FOREIGN KEY (article_id) REFERENCES knowledge_article (article_id),
   CONSTRAINT ck_suggestion_confidence CHECK (confidence_score BETWEEN 0 AND 1)
);

/* ---------------------------------------------------------------------------
   12. FEEDBACK  (1:1 with TICKET -> ticket_id is UNIQUE, a candidate key)
   --------------------------------------------------------------------------*/
CREATE TABLE feedback (
   feedback_id     NUMBER(12)     NOT NULL,
   ticket_id       NUMBER(12)     NOT NULL,
   rating          NUMBER(1)      NOT NULL,
   comments        VARCHAR2(1000),
   created_at      DATE           DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_feedback PRIMARY KEY (feedback_id),
   CONSTRAINT uq_feedback_ticket UNIQUE (ticket_id),          -- enforces the 1:1 "Gives" relationship
   CONSTRAINT fk_feedback_ticket FOREIGN KEY (ticket_id) REFERENCES ticket (ticket_id) ON DELETE CASCADE,
   CONSTRAINT ck_feedback_rating CHECK (rating BETWEEN 1 AND 5)
);

/* ---------------------------------------------------------------------------
   Sequences backing the surrogate-key generator triggers
   (see 02_plsql_programs.sql, section A)
   --------------------------------------------------------------------------*/
CREATE SEQUENCE seq_department_id   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_customer_id     START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_agent_id        START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_category_id     START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_ticket_id       START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_article_id      START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_suggestion_id   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_feedback_id     START WITH 1 INCREMENT BY 1 NOCACHE;

-- Helpful indexes on FK columns (Oracle does not auto-index FKs)
CREATE INDEX ix_agent_department      ON agent (department_id);
CREATE INDEX ix_ticket_customer       ON ticket (customer_id);
CREATE INDEX ix_ticket_agent          ON ticket (agent_id);
CREATE INDEX ix_ticket_category       ON ticket (category_id);
CREATE INDEX ix_ticket_status         ON ticket (status);
CREATE INDEX ix_article_category      ON knowledge_article (category_id);
CREATE INDEX ix_suggestion_ticket     ON ai_suggestion (ticket_id);
CREATE INDEX ix_suggestion_article    ON ai_suggestion (article_id);

COMMIT;
