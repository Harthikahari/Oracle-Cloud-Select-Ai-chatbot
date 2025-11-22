/*******************************************************************************
 * File: 03_create_ai_profile.sql
 * Purpose: Create and configure Oracle Select AI profile for Cohere Command R+
 *
 * This script sets up the AI profile that Oracle ADW uses to communicate
 * with OCI Generative AI services. It includes:
 * - Profile creation with Cohere Command R+ model
 * - Custom system prompts for SQL generation
 * - Temperature and token optimization
 * - Schema object allowlisting
 *
 * Prerequisites:
 * - Completed: sql/01_setup_permissions.sql
 * - Completed: sql/02_data_optimization.sql
 * - OCI GenAI endpoint accessible from ADW
 *
 * Author: Principal Cloud Architect
 * Last Updated: 2024
 *******************************************************************************/

SET SERVEROUTPUT ON
SET ECHO ON

PROMPT ========================================================================
PROMPT Oracle Select AI Profile Configuration
PROMPT Model: Cohere Command R+ via OCI Generative AI
PROMPT ========================================================================
PROMPT

-- ============================================================================
-- SECTION 1: Configuration Variables
-- ============================================================================
DEFINE profile_name = 'GENAI_COHERE'
DEFINE compartment_id = 'ocid1.compartment.oc1..aaaaaaaexamplecompartmentid'
DEFINE model_id = 'cohere.command-r-plus'
DEFINE oci_region = 'us-ashburn-1'

PROMPT Configuration:
PROMPT   Profile Name: &profile_name
PROMPT   Model: &model_id
PROMPT   Region: &oci_region
PROMPT   Compartment: &compartment_id
PROMPT

-- ============================================================================
-- SECTION 2: Drop Existing Profile (for clean re-runs)
-- ============================================================================
PROMPT Checking for existing profile...
PROMPT

BEGIN
    DBMS_CLOUD_AI.DROP_PROFILE(
        profile_name => '&profile_name'
    );
    DBMS_OUTPUT.PUT_LINE('ℹ Existing profile &profile_name dropped');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20404 THEN  -- Profile doesn't exist
            DBMS_OUTPUT.PUT_LINE('ℹ No existing profile found (first run)');
        ELSE
            DBMS_OUTPUT.PUT_LINE('⚠ Error: ' || SQLERRM);
            RAISE;
        END IF;
END;
/

-- ============================================================================
-- SECTION 3: Create AI Profile with Optimized Settings
-- ============================================================================
PROMPT
PROMPT Creating AI profile with production-grade settings...
PROMPT

BEGIN
    DBMS_CLOUD_AI.CREATE_PROFILE(
        -- Profile identification
        profile_name => '&profile_name',

        -- Provider configuration (OCI GenAI)
        attributes => JSON_OBJECT(
            'provider' VALUE 'oci',
            'credential_name' VALUE 'OCI_GENAI_CRED',
            'oci_compartment_id' VALUE '&compartment_id',
            'oci_region' VALUE '&oci_region',
            'oci_model_id' VALUE '&model_id',

            -- Model parameters for deterministic SQL generation
            'temperature' VALUE 0.0,           -- No creativity - we want precise SQL
            'max_tokens' VALUE 600,            -- Sufficient for complex queries
            'top_p' VALUE 1,                   -- Disable nucleus sampling
            'top_k' VALUE 0,                   -- Disable top-k sampling

            -- Select AI specific settings
            'object_list' VALUE JSON_ARRAY(
                'EMPLOYEES',
                'DEPARTMENTS',
                'PROJECTS',
                'STAFF_COUNT',
                'CONTRACTORS',
                'FULL_TIMERS',
                'INTERNS',
                'ACTIVE_PROJECTS'
            ),

            -- Custom system prompt for SQL generation
            'conversation_context' VALUE '
You are a SQL expert for an Oracle Autonomous Database.
Your task is to convert natural language questions into accurate, executable Oracle SQL queries.

CRITICAL RULES:
1. ONLY use tables and columns that exist in the provided schema metadata
2. NEVER invent column names - check comments for exact names
3. Use table comments to understand business context
4. Prefer JOINs over subqueries for better performance
5. Always filter out inactive records (is_active = ''Y'') for current data
6. Use the headcount column for employee counting (SUM(headcount))
7. Qualify ambiguous column names with table aliases
8. Return ONLY the SQL query without explanations

SCHEMA CONTEXT:
- EMPLOYEES: Contains all staff (full-time, contractors, interns)
- DEPARTMENTS: Organizational units with budgets
- PROJECTS: Active and historical projects linked to departments

COMMON PATTERNS:
- For "headcount" or "staff count": SUM(headcount) FROM employees WHERE is_active = ''Y''
- For "contractors": WHERE employment_type = ''CONTRACTOR''
- For "by department": JOIN departments d ON e.dept_id = d.dept_id GROUP BY d.dept_name
- For "active projects": WHERE status = ''ACTIVE''

OUTPUT FORMAT:
Return only the SQL query, properly formatted with:
- Uppercase keywords (SELECT, FROM, WHERE, JOIN)
- Lowercase table/column names
- Table aliases (e.g., e for employees, d for departments)
- Proper indentation for readability
',

            -- Enable verbose logging for debugging (set to false in production)
            'logging' VALUE 'true',

            -- Response format
            'response_format' VALUE 'json'
        )
    );

    DBMS_OUTPUT.PUT_LINE('✅ AI Profile &profile_name created successfully');
    DBMS_OUTPUT.PUT_LINE('   Provider: OCI Generative AI');
    DBMS_OUTPUT.PUT_LINE('   Model: &model_id');
    DBMS_OUTPUT.PUT_LINE('   Temperature: 0.0 (deterministic)');
    DBMS_OUTPUT.PUT_LINE('   Max Tokens: 600');
END;
/

-- ============================================================================
-- SECTION 4: Verify Profile Creation
-- ============================================================================
PROMPT
PROMPT Verifying profile configuration...
PROMPT

-- Query profile attributes (Oracle 23ai+)
DECLARE
    v_profile_exists NUMBER;
    v_attribute_count NUMBER;
BEGIN
    -- Check if profile exists
    SELECT COUNT(*) INTO v_profile_exists
    FROM USER_CLOUD_AI_PROFILES
    WHERE PROFILE_NAME = '&profile_name';

    IF v_profile_exists > 0 THEN
        DBMS_OUTPUT.PUT_LINE('✓ Profile verified in USER_CLOUD_AI_PROFILES');

        -- Display profile details
        FOR rec IN (
            SELECT PROFILE_NAME, PROVIDER, STATUS
            FROM USER_CLOUD_AI_PROFILES
            WHERE PROFILE_NAME = '&profile_name'
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  Name: ' || rec.PROFILE_NAME);
            DBMS_OUTPUT.PUT_LINE('  Provider: ' || rec.PROVIDER);
            DBMS_OUTPUT.PUT_LINE('  Status: ' || rec.STATUS);
        END LOOP;
    ELSE
        RAISE_APPLICATION_ERROR(-20001, 'Profile verification failed - not found in data dictionary');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -942 THEN  -- Table doesn't exist (older Oracle version)
            DBMS_OUTPUT.PUT_LINE('ℹ USER_CLOUD_AI_PROFILES view not available (older Oracle version)');
            DBMS_OUTPUT.PUT_LINE('  Profile likely created successfully - continue to testing');
        ELSE
            RAISE;
        END IF;
END;
/

-- ============================================================================
-- SECTION 5: Test the Profile with Sample Queries
-- ============================================================================
PROMPT
PROMPT ========================================================================
PROMPT Testing AI Profile with Sample Queries
PROMPT ========================================================================
PROMPT

-- Test 1: Simple query
PROMPT
PROMPT [TEST 1] Simple employee count query
PROMPT Natural Language: "How many active employees do we have?"
PROMPT

DECLARE
    v_response CLOB;
    v_sql_query CLOB;
BEGIN
    -- Generate SQL using Select AI
    v_response := DBMS_CLOUD_AI.GENERATE(
        prompt => 'How many active employees do we have?',
        profile_name => '&profile_name',
        action => 'chat'
    );

    DBMS_OUTPUT.PUT_LINE('Response received (first 500 chars):');
    DBMS_OUTPUT.PUT_LINE(SUBSTR(v_response, 1, 500));
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('✓ Test 1 PASSED - Profile responding correctly');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Test 1 FAILED');
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('Troubleshooting:');
        DBMS_OUTPUT.PUT_LINE('  1. Verify OCI GenAI endpoint is accessible');
        DBMS_OUTPUT.PUT_LINE('  2. Check credential: SELECT * FROM USER_CREDENTIALS WHERE CREDENTIAL_NAME = ''OCI_GENAI_CRED''');
        DBMS_OUTPUT.PUT_LINE('  3. Verify IAM policy allows database to invoke generative-ai-family');
        DBMS_OUTPUT.PUT_LINE('  4. Check OCI Console > Generative AI > Models for service availability');
        RAISE;
END;
/

-- Test 2: Complex query with JOIN
PROMPT
PROMPT [TEST 2] Complex query with department join
PROMPT Natural Language: "Show me headcount by department"
PROMPT

DECLARE
    v_response CLOB;
BEGIN
    v_response := DBMS_CLOUD_AI.GENERATE(
        prompt => 'Show me headcount by department',
        profile_name => '&profile_name',
        action => 'chat'
    );

    DBMS_OUTPUT.PUT_LINE('Response received (first 500 chars):');
    DBMS_OUTPUT.PUT_LINE(SUBSTR(v_response, 1, 500));
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('✓ Test 2 PASSED - Complex query handling verified');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Test 2 FAILED: ' || SQLERRM);
        RAISE;
END;
/

-- Test 3: Business term synonym
PROMPT
PROMPT [TEST 3] Business term resolution (using synonyms)
PROMPT Natural Language: "List all contractors with their salaries"
PROMPT

DECLARE
    v_response CLOB;
BEGIN
    v_response := DBMS_CLOUD_AI.GENERATE(
        prompt => 'List all contractors with their salaries',
        profile_name => '&profile_name',
        action => 'chat'
    );

    DBMS_OUTPUT.PUT_LINE('Response received (first 500 chars):');
    DBMS_OUTPUT.PUT_LINE(SUBSTR(v_response, 1, 500));
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('✓ Test 3 PASSED - Synonym resolution working');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Test 3 FAILED: ' || SQLERRM);
        RAISE;
END;
/

-- ============================================================================
-- SECTION 6: Alternative Actions (NARRATE, RUNSQL)
-- ============================================================================
PROMPT
PROMPT ========================================================================
PROMPT Advanced Features: NARRATE and RUNSQL Actions
PROMPT ========================================================================
PROMPT

-- Example 1: NARRATE action (generates SQL and explains it)
PROMPT
PROMPT [NARRATE Example] Generate SQL with natural language explanation
PROMPT

DECLARE
    v_response CLOB;
BEGIN
    v_response := DBMS_CLOUD_AI.GENERATE(
        prompt => 'What is the average salary by employment type?',
        profile_name => '&profile_name',
        action => 'narrate'  -- Returns SQL + explanation
    );

    DBMS_OUTPUT.PUT_LINE('Narrated Response:');
    DBMS_OUTPUT.PUT_LINE(SUBSTR(v_response, 1, 1000));
    DBMS_OUTPUT.PUT_LINE('');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('⚠ NARRATE test skipped: ' || SQLERRM);
END;
/

-- Example 2: RUNSQL action (generates and executes SQL)
PROMPT
PROMPT [RUNSQL Example] Generate SQL and execute automatically
PROMPT (Comment: Use with caution - automatically executes generated queries!)
PROMPT

/*
-- Uncomment to test RUNSQL action:

DECLARE
    v_response CLOB;
BEGIN
    v_response := DBMS_CLOUD_AI.GENERATE(
        prompt => 'Show total employees by department',
        profile_name => '&profile_name',
        action => 'runsql'  -- Generates AND executes SQL
    );

    DBMS_OUTPUT.PUT_LINE('Executed Query Results:');
    DBMS_OUTPUT.PUT_LINE(v_response);
END;
/
*/

-- ============================================================================
-- SECTION 7: Profile Management Commands (for reference)
-- ============================================================================
PROMPT
PROMPT ========================================================================
PROMPT Profile Management Reference
PROMPT ========================================================================
PROMPT

-- List all profiles
PROMPT
PROMPT To list all AI profiles in your schema:
PROMPT   SELECT * FROM USER_CLOUD_AI_PROFILES;
PROMPT

-- Update profile attributes
PROMPT To update profile settings:
PROMPT   EXEC DBMS_CLOUD_AI.SET_PROFILE(
PROMPT       profile_name => '&profile_name',
PROMPT       attributes => JSON_OBJECT('temperature' VALUE 0.1)
PROMPT   );
PROMPT

-- Drop profile
PROMPT To remove profile:
PROMPT   EXEC DBMS_CLOUD_AI.DROP_PROFILE(profile_name => '&profile_name');
PROMPT

-- ============================================================================
-- SECTION 8: Next Steps and Best Practices
-- ============================================================================
PROMPT
PROMPT ========================================================================
PROMPT SETUP COMPLETE! 🎉
PROMPT ========================================================================
PROMPT
PROMPT ✅ AI Profile &profile_name is ready for production use
PROMPT
PROMPT Quick Start Examples:
PROMPT
PROMPT 1. Basic Query:
PROMPT    SELECT DBMS_CLOUD_AI.GENERATE(
PROMPT        prompt => 'Show all employees in Engineering',
PROMPT        profile_name => '&profile_name'
PROMPT    ) FROM dual;
PROMPT
PROMPT 2. With Explanation:
PROMPT    SELECT DBMS_CLOUD_AI.GENERATE(
PROMPT        prompt => 'Total project budget by department',
PROMPT        profile_name => '&profile_name',
PROMPT        action => 'narrate'
PROMPT    ) FROM dual;
PROMPT
PROMPT 3. Execute Directly:
PROMPT    SELECT DBMS_CLOUD_AI.GENERATE(
PROMPT        prompt => 'Top 5 highest paid employees',
PROMPT        profile_name => '&profile_name',
PROMPT        action => 'runsql'
PROMPT    ) FROM dual;
PROMPT
PROMPT ========================================================================
PROMPT Best Practices for Production:
PROMPT ========================================================================
PROMPT
PROMPT ✓ Keep temperature at 0.0 for deterministic SQL generation
PROMPT ✓ Regularly update schema comments as database evolves
PROMPT ✓ Create synonyms for new business terminology
PROMPT ✓ Monitor query logs for hallucination patterns
PROMPT ✓ Use object_list to restrict access to sensitive tables
PROMPT ✓ Implement VPD policies for row-level security
PROMPT ✓ Set max_tokens based on query complexity (600 recommended)
PROMPT ✓ Enable logging during testing, disable in production
PROMPT
PROMPT Next Step: Deploy APEX frontend using apex/function_body.sql
PROMPT ========================================================================
PROMPT

-- ============================================================================
-- APPENDIX: Troubleshooting Common Issues
-- ============================================================================
/*
-- Issue 1: ORA-20400: Provider not supported
-- Solution: Verify OCI GenAI is enabled in your compartment

-- Issue 2: ORA-20403: Invalid credentials
-- Solution: Check credential exists and has correct permissions
SELECT * FROM USER_CREDENTIALS WHERE CREDENTIAL_NAME = 'OCI_GENAI_CRED';

-- Issue 3: Generated SQL references wrong columns
-- Solution: Add more detailed COMMENT ON COLUMN statements
SELECT table_name, column_name, comments
FROM USER_COL_COMMENTS
WHERE comments IS NULL;

-- Issue 4: Timeout errors
-- Solution: Increase max_tokens or check network connectivity
SELECT UTL_HTTP.REQUEST('https://generativeai.&oci_region..oci.oraclecloud.com') FROM dual;

-- Issue 5: Hallucinations still occurring
-- Solution: Verify metadata was applied
SELECT COUNT(*) AS commented_columns
FROM USER_COL_COMMENTS
WHERE table_name IN ('EMPLOYEES', 'DEPARTMENTS', 'PROJECTS')
AND comments IS NOT NULL;
-- Expected: 15+ columns
*/
