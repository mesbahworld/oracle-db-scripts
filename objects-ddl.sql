-- Enable DBMS_OUTPUT to display results
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Set line size to handle long DDL statements
SET LINESIZE 32767;
SET PAGESIZE 0;

-- Optional: Set timing on to see execution time
SET TIMING ON;

DECLARE
  l_ddl CLOB;
BEGIN
  -- Configure DBMS_METADATA session transforms
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'STORAGE', FALSE);
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'TABLESPACE', FALSE);
  DBMS_METADATA.set_transform_param(DBMS_METADATA.session_transform, 'SQLTERMINATOR', TRUE);
  
  -- Output header
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('-- DDL Export for Schema: ' || USER);
  DBMS_OUTPUT.PUT_LINE('-- Generated: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('');
  
  -- Ordered object types
  FOR t IN (
      SELECT object_name, object_type
        FROM user_objects
       WHERE object_type IN ('TABLE','VIEW','SEQUENCE','PACKAGE','PACKAGE BODY',
                             'FUNCTION','PROCEDURE','TRIGGER','INDEX','TYPE')
         AND status = 'VALID'  -- Only include valid objects
       ORDER BY 
         CASE object_type
           WHEN 'TYPE'         THEN 1  -- Types first (dependencies)
           WHEN 'SEQUENCE'     THEN 2  -- Sequences before tables
           WHEN 'TABLE'        THEN 3  -- Tables before views
           WHEN 'INDEX'        THEN 4  -- Indexes after tables
           WHEN 'VIEW'         THEN 5  -- Views after tables
           WHEN 'PACKAGE'      THEN 6  -- Package specs before bodies
           WHEN 'FUNCTION'     THEN 7  -- Functions
           WHEN 'PROCEDURE'    THEN 8  -- Procedures
           WHEN 'PACKAGE BODY' THEN 9  -- Package bodies after specs
           WHEN 'TRIGGER'      THEN 10 -- Triggers last
           ELSE 99
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
        
        -- Get table constraints (this will include the proper constraint definitions)
        BEGIN
          FOR constraint_rec IN (
            SELECT constraint_name, constraint_type
            FROM user_constraints
            WHERE table_name = t.object_name
              AND constraint_type IN ('P', 'U', 'R', 'C')
              AND constraint_name NOT LIKE 'SYS_C%'  -- Exclude system-named constraints
          ) LOOP
            BEGIN
              l_ddl := DBMS_METADATA.GET_DDL('CONSTRAINT', constraint_rec.constraint_name, USER);
              DBMS_OUTPUT.PUT_LINE('-- Constraint: ' || constraint_rec.constraint_name);
              DBMS_OUTPUT.PUT_LINE(l_ddl);
              DBMS_OUTPUT.PUT_LINE('/');
            EXCEPTION
              WHEN OTHERS THEN
                NULL; -- Skip problematic constraints
            END;
          END LOOP;
        EXCEPTION
          WHEN OTHERS THEN
            NULL; -- Skip if constraint extraction fails
        END;
        
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
