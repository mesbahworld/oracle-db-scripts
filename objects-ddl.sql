-- Enable DBMS_OUTPUT to display results
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Set line size to handle long DDL statements
SET LINESIZE 32767;
SET PAGESIZE 0;

-- Optional: Set timing on to see execution time
SET TIMING ON;

DECLARE
  l_ddl CLOB;
  
  -- ===== CONFIGURATION VARIABLES =====
  -- Specify object types as comma-separated list, or leave empty/NULL for all types
  -- Examples: 'TABLE,VIEW' or 'PACKAGE,FUNCTION' or NULL for all
  v_object_types VARCHAR2(1000) := NULL; -- Change this to specify object types
  -- ====================================
  
  v_default_types VARCHAR2(1000) := 'TYPE,SEQUENCE,TABLE,CONSTRAINT,INDEX,TRIGGER,FUNCTION,PROCEDURE,PACKAGE,PACKAGE BODY,VIEW,MATERIALIZED VIEW,SYNONYM,GRANT';

-- VERY SHORT LIST: 'TYPE,SEQUENCE,TABLE,VIEW,PACKAGE,PACKAGE BODY,FUNCTION,PROCEDURE,TRIGGER,INDEX'
-- SHORT LIST: 'TYPE,SEQUENCE,TABLE,CONSTRAINT,INDEX,TRIGGER,FUNCTION,PROCEDURE,PACKAGE,PACKAGE BODY,VIEW,MATERIALIZED VIEW,SYNONYM,GRANT'
-- FULL LIST:  'TYPE,SEQUENCE,TABLE,LOB STORAGE,CONSTRAINT,INDEX,TRIGGER,FUNCTION,PROCEDURE,PACKAGE,PACKAGE BODY,VIEW,MATERIALIZED VIEW,SYNONYM,DATABASE LINK,GRANT,ROLE,PROFILE'
-- COMPLETE LIST: 'CONTEXT,EDITION,EVALUATION CONTEXT,TYPE,TYPE BODY,CLUSTER,TABLE,TABLE PARTITION,TABLE SUBPARTITION,LOB,LOB PARTITION,SEQUENCE,INDEXTYPE,INDEX,INDEX PARTITION,SYNONYM,JAVA CLASS,JAVA DATA,JAVA RESOURCE,JAVA SOURCE,FUNCTION,PROCEDURE,PACKAGE,PACKAGE BODY,TRIGGER,RULE,RULE SET,RESOURCE PLAN,CONSUMER GROUP,OPERATOR,DESTINATION,DIRECTORY,PROGRAM,QUEUE,SCHEDULE,SCHEDULER GROUP,WINDOW,VIEW,XML SCHEMA,UNIFIED AUDIT POLICY,UNDEFINED'

 v_final_types VARCHAR2(1000);
BEGIN
  -- Use specified types if provided, otherwise use default fallback
  IF v_object_types IS NULL OR TRIM(v_object_types) = '' OR UPPER(TRIM(v_object_types)) = 'ALL' THEN
    v_final_types := v_default_types;
    DBMS_OUTPUT.PUT_LINE('-- Using default object types (all)');
  ELSE
    v_final_types := UPPER(TRIM(v_object_types));
    DBMS_OUTPUT.PUT_LINE('-- Using specified object types: ' || v_final_types);
  END IF;
  
  -- Configure DBMS_METADATA session transforms
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'STORAGE', FALSE);
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'TABLESPACE', FALSE);
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'SQLTERMINATOR', TRUE);
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'CONSTRAINTS_AS_ALTER', FALSE);
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'REF_CONSTRAINTS', FALSE);
  
  -- Output header
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('-- DDL Export for Schema: ' || USER);
  DBMS_OUTPUT.PUT_LINE('-- Generated: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('-- Object Types: ' || v_final_types);
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('');
  
  -- PASS 1: Create specs and structure objects
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('-- PASS 1: Object Specs and Structure');
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('');
  
  -- Ordered object types with variable support (Pass 1)
  FOR t IN (
      SELECT object_name, object_type
        FROM user_objects
       WHERE status = 'VALID'  -- Only include valid objects
         -- Dynamic object type filtering using INSTR
         AND INSTR(',' || v_final_types || ',', ',' || object_type || ',') > 0
         -- Pass 1: Structure and specs only
         AND object_type IN ('TYPE', 'SEQUENCE', 'TABLE', 'INDEX', 'PACKAGE', 'FUNCTION', 'PROCEDURE')
         -- Exclude system-generated indexes that are better handled with constraints
         AND NOT (object_type = 'INDEX' AND (
           object_name LIKE 'SYS_C%'           -- Primary key indexes
           OR object_name LIKE 'SYS_IL%$'     -- LOB indexes
           OR object_name LIKE 'SYS_IOT%'      -- IOT indexes
           OR object_name LIKE 'BIN$%'         -- Recycle bin objects
         ))
        ORDER BY 
          CASE object_type
            WHEN 'TYPE'                 THEN 1   -- Base types first
            WHEN 'TYPE BODY'            THEN 2   -- After type specs
            WHEN 'SEQUENCE'             THEN 3   -- Before tables that may reference them
            WHEN 'TABLE'                THEN 4   -- Base tables
            WHEN 'TABLE PARTITION'      THEN 5   -- After base table
            WHEN 'TABLE SUBPARTITION'   THEN 6   -- After partitions
            WHEN 'LOB'                  THEN 7   -- After tables
            WHEN 'LOB PARTITION'        THEN 8   -- After LOBs
            WHEN 'INDEXTYPE'            THEN 9   -- Before indexes that use them
            WHEN 'INDEX'                THEN 10  -- After tables
            WHEN 'INDEX PARTITION'      THEN 11  -- After indexes
            WHEN 'SYNONYM'              THEN 12  -- Can reference any object
            WHEN 'JAVA SOURCE'          THEN 13  -- Java source before compiled classes
            WHEN 'JAVA CLASS'           THEN 14  -- After Java source
            WHEN 'JAVA DATA'            THEN 15  -- After Java classes
            WHEN 'JAVA RESOURCE'        THEN 16  -- After Java classes
            WHEN 'PACKAGE'              THEN 17  -- Package specs before functions (for circular deps)
            WHEN 'FUNCTION'             THEN 18  -- Function specs after packages
            WHEN 'PROCEDURE'            THEN 19  -- Procedure specs after functions
            WHEN 'VIEW'                 THEN 20  -- Views after function/procedure specs
            WHEN 'MATERIALIZED VIEW'    THEN 21  -- After regular views
            WHEN 'PACKAGE BODY'         THEN 22  -- Package bodies after views
            WHEN 'TRIGGER'              THEN 23  -- Triggers last among table-dependent objects
            WHEN 'CONTEXT'              THEN 24  -- System objects
            WHEN 'EDITION'              THEN 25  -- System objects
            WHEN 'EVALUATION CONTEXT'   THEN 26  -- System objects
            WHEN 'RULE'                 THEN 27  -- System objects
            WHEN 'RULE SET'             THEN 28  -- System objects
            WHEN 'RESOURCE PLAN'        THEN 29  -- System objects
            WHEN 'CONSUMER GROUP'       THEN 30  -- System objects
            WHEN 'OPERATOR'             THEN 31  -- System objects
            WHEN 'DESTINATION'          THEN 32  -- System objects
            WHEN 'DIRECTORY'            THEN 33  -- System objects
            WHEN 'PROGRAM'              THEN 34  -- System objects
            WHEN 'QUEUE'                THEN 35  -- System objects
            WHEN 'SCHEDULE'             THEN 36  -- System objects
            WHEN 'SCHEDULER GROUP'      THEN 37  -- System objects
            WHEN 'WINDOW'               THEN 38  -- System objects
            WHEN 'XML SCHEMA'           THEN 39  -- System objects
            WHEN 'UNIFIED AUDIT POLICY' THEN 40  -- System objects
            WHEN 'UNDEFINED'            THEN 99  -- Unknown objects
            ELSE 100
          END,
          object_name
  )
  LOOP
    BEGIN
      -- Fetch DDL
      l_ddl := DBMS_METADATA.GET_DDL(t.object_type, t.object_name, USER);
      
      -- Clean up unnecessary USING INDEX clauses for tables
      IF t.object_type = 'TABLE' THEN
        l_ddl := REGEXP_REPLACE(l_ddl, 
                               '\s+USING INDEX\s+ENABLE', 
                               ' ENABLE', 1, 0, 'i');
        l_ddl := REGEXP_REPLACE(l_ddl, 
                               '\s+USING INDEX\s*\n', 
                               CHR(10), 1, 0, 'i');
      END IF;
      
      -- Output object header
      DBMS_OUTPUT.PUT_LINE('-- ===============================');
      DBMS_OUTPUT.PUT_LINE('-- ' || t.object_type || ': ' || USER || '.' || t.object_name);
      DBMS_OUTPUT.PUT_LINE('-- ===============================');
      
      -- Output the DDL
      DBMS_OUTPUT.PUT_LINE(l_ddl);
      
      -- Add separator
      DBMS_OUTPUT.PUT_LINE('/');
      DBMS_OUTPUT.PUT_LINE('');
      
      -- Add comments and constraints if object is a table
      IF t.object_type = 'TABLE' THEN
        -- Table comments
        FOR c IN (SELECT table_name, comments 
                    FROM user_tab_comments
                   WHERE table_name = t.object_name
                     AND comments IS NOT NULL)
        LOOP
          DBMS_OUTPUT.PUT_LINE('COMMENT ON TABLE ' || c.table_name || ' IS ''' || REPLACE(c.comments, '''', '''''') || ''';');
        END LOOP;
        
        -- Column comments
        FOR cc IN (SELECT table_name, column_name, comments
                     FROM user_col_comments
                    WHERE table_name = t.object_name
                      AND comments IS NOT NULL)
        LOOP
          DBMS_OUTPUT.PUT_LINE('COMMENT ON COLUMN ' || cc.table_name || '.' || cc.column_name || 
                               ' IS ''' || REPLACE(cc.comments, '''', '''''') || ''';');
        END LOOP;
        
        -- Add separator
        DBMS_OUTPUT.PUT_LINE('');
      END IF;
      
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('-- ERROR: Could not get DDL for ' || t.object_type || ' ' || t.object_name);
        DBMS_OUTPUT.PUT_LINE('-- Error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('');
    END;
  END LOOP;
  
  -- PASS 2: Create views and dependent objects
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('-- PASS 2: Views and Dependent Objects');
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('');
  
  FOR t IN (
      SELECT object_name, object_type
        FROM user_objects
       WHERE status = 'VALID'
         AND INSTR(',' || v_final_types || ',', ',' || object_type || ',') > 0
         AND object_type IN ('VIEW', 'PACKAGE BODY', 'TRIGGER')
       ORDER BY 
         CASE object_type
           WHEN 'VIEW'         THEN 1  -- Views after function specs
           WHEN 'PACKAGE BODY' THEN 2  -- Package bodies after views
           WHEN 'TRIGGER'      THEN 3  -- Triggers last
           ELSE 99
         END,
         object_name
  )
  LOOP
    BEGIN
      -- Fetch DDL
      l_ddl := DBMS_METADATA.GET_DDL(t.object_type, t.object_name, USER);
      
      -- Output object header
      DBMS_OUTPUT.PUT_LINE('-- ===============================');
      DBMS_OUTPUT.PUT_LINE('-- ' || t.object_type || ': ' || USER || '.' || t.object_name);
      DBMS_OUTPUT.PUT_LINE('-- ===============================');
      
      -- Output the DDL
      DBMS_OUTPUT.PUT_LINE(l_ddl);
      
      -- Add separator
      DBMS_OUTPUT.PUT_LINE('/');
      DBMS_OUTPUT.PUT_LINE('');
      
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('-- ERROR: Could not get DDL for ' || t.object_type || ' ' || t.object_name);
        DBMS_OUTPUT.PUT_LINE('-- Error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('');
    END;
  END LOOP;
  
  -- PASS 3: Recompile any invalid objects
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('-- PASS 3: Recompile Invalid Objects');
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('');
  
  FOR invalid_obj IN (
    SELECT object_name, object_type 
    FROM user_objects 
    WHERE status = 'INVALID'
    AND INSTR(',' || v_final_types || ',', ',' || object_type || ',') > 0
    ORDER BY object_name
  ) LOOP
    DBMS_OUTPUT.PUT_LINE('-- Recompile: ' || invalid_obj.object_type || ' ' || invalid_obj.object_name);
    DBMS_OUTPUT.PUT_LINE('ALTER ' || invalid_obj.object_type || ' ' || 
                         invalid_obj.object_name || ' COMPILE;');
    DBMS_OUTPUT.PUT_LINE('/');
  END LOOP;
  
  -- Output footer
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('-- DDL Export Complete');
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  
END;
/

-- Reset settings
SET TIMING OFF;
SET PAGESIZE 14;
SET LINESIZE 80;
