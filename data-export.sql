-- Enable DBMS_OUTPUT to display results
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Set line size to handle long DDL statements
SET LINESIZE 32767;
SET PAGESIZE 0;

-- Optional: Set timing on to see execution time
SET TIMING ON;

DECLARE
  -- Comma separated list of tables to include (NULL = all tables)
  v_include_tables VARCHAR2(32767) := NULL; 
  -- Example: 'PG1_EMPLOYEE_MASTER,PG1_DEPARTMENT_MASTER'

  -- Comma separated list of tables to exclude (NULL = exclude nothing)
  v_exclude_tables VARCHAR2(32767) := 'DBTOOLS$EXECUTION_HISTORY';

  l_sql         VARCHAR2(32767);
  l_cursor      INTEGER;
  l_desc_tab    DBMS_SQL.DESC_TAB;
  l_col_cnt     INTEGER;
  l_vc          VARCHAR2(4000);
  l_row         VARCHAR2(32767);
  l_status      INTEGER;
  l_count       NUMBER;
  l_cols        VARCHAR2(32767);
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('-- PASS 4: Data Export');
  DBMS_OUTPUT.PUT_LINE('-- ===============================');
  DBMS_OUTPUT.PUT_LINE('');

  FOR t IN (
    SELECT table_name
    FROM user_tables
    WHERE NVL(num_rows,0) BETWEEN 1 AND 50
      -- include filter
      AND (v_include_tables IS NULL 
           OR INSTR(',' || UPPER(v_include_tables) || ',', ',' || UPPER(table_name) || ',') > 0)
      -- exclude filter
      AND (v_exclude_tables IS NULL 
           OR INSTR(',' || UPPER(v_exclude_tables) || ',', ',' || UPPER(table_name) || ',') = 0)
    ORDER BY table_name
  ) LOOP
    DBMS_OUTPUT.PUT_LINE('-- ===============================');
    DBMS_OUTPUT.PUT_LINE('-- DATA: ' || USER || '.' || t.table_name);
    DBMS_OUTPUT.PUT_LINE('-- ===============================');

    -- Get actual row count
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || t.table_name INTO l_count;

    IF l_count > 0 THEN
      l_sql := 'SELECT * FROM ' || t.table_name || ' WHERE ROWNUM <= 10';
      l_cursor := DBMS_SQL.OPEN_CURSOR;
      DBMS_SQL.PARSE(l_cursor, l_sql, DBMS_SQL.NATIVE);
      DBMS_SQL.DESCRIBE_COLUMNS(l_cursor, l_col_cnt, l_desc_tab);

      -- Build column list
      l_cols := '';
      FOR i IN 1..l_col_cnt LOOP
        IF i > 1 THEN l_cols := l_cols || ', '; END IF;
        l_cols := l_cols || l_desc_tab(i).col_name;
        DBMS_SQL.DEFINE_COLUMN(l_cursor, i, l_vc, 4000);
      END LOOP;

      l_status := DBMS_SQL.EXECUTE(l_cursor);

      -- Fetch rows
      WHILE DBMS_SQL.FETCH_ROWS(l_cursor) > 0 LOOP
        l_row := 'INSERT INTO ' || t.table_name || ' (' || l_cols || ') VALUES (';
        FOR i IN 1..l_col_cnt LOOP
          DBMS_SQL.COLUMN_VALUE(l_cursor, i, l_vc);
          IF i > 1 THEN l_row := l_row || ', '; END IF;

          IF l_vc IS NULL THEN
            l_row := l_row || 'NULL';
          ELSE
            l_row := l_row || '''' || REPLACE(l_vc, '''', '''''') || '''';
          END IF;
        END LOOP;
        l_row := l_row || ');';
        DBMS_OUTPUT.PUT_LINE(l_row);
      END LOOP;

      DBMS_SQL.CLOSE_CURSOR(l_cursor);
      DBMS_OUTPUT.PUT_LINE('-- ' || LEAST(l_count,10) || ' sample rows shown out of ' || l_count || ' total');
      DBMS_OUTPUT.PUT_LINE('');
    ELSE
      DBMS_OUTPUT.PUT_LINE('-- No rows in ' || t.table_name);
      DBMS_OUTPUT.PUT_LINE('');
    END IF;
  END LOOP;
END;
/


-- Reset settings
SET TIMING OFF;
SET PAGESIZE 14;
SET LINESIZE 80;
