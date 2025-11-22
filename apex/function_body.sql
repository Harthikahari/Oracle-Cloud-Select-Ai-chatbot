/*******************************************************************************
 * File: apex/function_body.sql
 * Purpose: Oracle APEX integration code for NL2SQL chatbot
 *
 * This PL/SQL function bridges the APEX frontend with Oracle Select AI.
 * It takes natural language input from users and returns AI-generated SQL
 * results using the DBMS_CLOUD_AI.GENERATE function.
 *
 * Implementation Options:
 * 1. AJAX Callback - For real-time chat interface (recommended)
 * 2. Page Process - For form-based submission
 * 3. Dynamic Action - For interactive UI updates
 *
 * Author: Principal Cloud Architect
 * Last Updated: 2024
 *******************************************************************************/

-- ============================================================================
-- OPTION 1: AJAX Callback Function (Recommended for Chat Interface)
-- ============================================================================
/*
 * Use this approach for a modern, real-time chat experience.
 * Setup in APEX:
 * 1. Create AJAX Callback process in page settings
 * 2. Set process name: 'GENERATE_SQL_FROM_NL'
 * 3. Paste the code below into the PL/SQL Code section
 */

DECLARE
    -- Input variables from APEX page items
    v_user_question     CLOB := APEX_APPLICATION.g_x01;  -- Natural language query
    v_action_type       VARCHAR2(20) := NVL(APEX_APPLICATION.g_x02, 'chat');  -- chat, narrate, or runsql
    v_profile_name      VARCHAR2(100) := 'GENAI_COHERE';

    -- Output variables
    v_ai_response       CLOB;
    v_generated_sql     CLOB;
    v_error_message     VARCHAR2(4000);
    v_execution_time    NUMBER;
    v_start_time        NUMBER;

    -- Configuration
    v_max_response_len  NUMBER := 10000;  -- Limit response size for UI
    v_timeout_seconds   NUMBER := 30;     -- Max wait time for AI response

BEGIN
    -- Record start time for performance monitoring
    v_start_time := DBMS_UTILITY.GET_TIME;

    -- ────────────────────────────────────────────────────────────────────────
    -- Input Validation
    -- ────────────────────────────────────────────────────────────────────────
    IF v_user_question IS NULL OR LENGTH(TRIM(v_user_question)) = 0 THEN
        APEX_JSON.open_object;
        APEX_JSON.write('status', 'error');
        APEX_JSON.write('message', 'Please enter a question');
        APEX_JSON.close_object;
        RETURN;
    END IF;

    -- Sanitize input (prevent SQL injection attempts)
    IF REGEXP_LIKE(v_user_question, '(DROP|DELETE|TRUNCATE|ALTER|CREATE)\s+(TABLE|USER|DATABASE)', 'i') THEN
        APEX_JSON.open_object;
        APEX_JSON.write('status', 'error');
        APEX_JSON.write('message', 'Query contains restricted keywords. Please rephrase your question.');
        APEX_JSON.close_object;
        RETURN;
    END IF;

    -- ────────────────────────────────────────────────────────────────────────
    -- Call Oracle Select AI
    -- ────────────────────────────────────────────────────────────────────────
    BEGIN
        v_ai_response := DBMS_CLOUD_AI.GENERATE(
            prompt       => v_user_question,
            profile_name => v_profile_name,
            action       => v_action_type
        );

        -- Calculate execution time
        v_execution_time := (DBMS_UTILITY.GET_TIME - v_start_time) / 100;  -- Convert to seconds

        -- ────────────────────────────────────────────────────────────────────
        -- Parse and format response
        -- ────────────────────────────────────────────────────────────────────

        -- For 'chat' action, extract SQL from JSON response
        IF v_action_type = 'chat' THEN
            BEGIN
                -- Try to parse JSON response
                DECLARE
                    v_json_obj JSON_OBJECT_T;
                BEGIN
                    v_json_obj := JSON_OBJECT_T.parse(v_ai_response);

                    -- Extract SQL query (structure may vary by model)
                    IF v_json_obj.has('sql') THEN
                        v_generated_sql := v_json_obj.get_string('sql');
                    ELSIF v_json_obj.has('query') THEN
                        v_generated_sql := v_json_obj.get_string('query');
                    ELSE
                        -- Fallback: use entire response
                        v_generated_sql := v_ai_response;
                    END IF;
                END;
            EXCEPTION
                WHEN OTHERS THEN
                    -- If JSON parsing fails, treat entire response as SQL
                    v_generated_sql := v_ai_response;
            END;

            -- Return formatted JSON response
            APEX_JSON.open_object;
            APEX_JSON.write('status', 'success');
            APEX_JSON.write('sql', v_generated_sql);
            APEX_JSON.write('execution_time', v_execution_time);
            APEX_JSON.write('timestamp', TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
            APEX_JSON.close_object;

        -- For 'narrate' action, return explanation with SQL
        ELSIF v_action_type = 'narrate' THEN
            APEX_JSON.open_object;
            APEX_JSON.write('status', 'success');
            APEX_JSON.write('narration', SUBSTR(v_ai_response, 1, v_max_response_len));
            APEX_JSON.write('execution_time', v_execution_time);
            APEX_JSON.close_object;

        -- For 'runsql' action, return executed results
        ELSIF v_action_type = 'runsql' THEN
            APEX_JSON.open_object;
            APEX_JSON.write('status', 'success');
            APEX_JSON.write('results', SUBSTR(v_ai_response, 1, v_max_response_len));
            APEX_JSON.write('execution_time', v_execution_time);
            APEX_JSON.close_object;

        ELSE
            -- Unknown action type
            APEX_JSON.open_object;
            APEX_JSON.write('status', 'error');
            APEX_JSON.write('message', 'Invalid action type: ' || v_action_type);
            APEX_JSON.close_object;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Handle AI generation errors
            v_error_message := SQLERRM;

            APEX_JSON.open_object;
            APEX_JSON.write('status', 'error');
            APEX_JSON.write('message', 'AI Service Error: ' || SUBSTR(v_error_message, 1, 500));
            APEX_JSON.write('error_code', SQLCODE);
            APEX_JSON.close_object;

            -- Log error for debugging (optional)
            INSERT INTO apex_error_log (
                app_id,
                page_id,
                error_message,
                error_timestamp,
                username
            ) VALUES (
                :APP_ID,
                :APP_PAGE_ID,
                'Select AI Error: ' || v_error_message,
                SYSDATE,
                :APP_USER
            );
            COMMIT;
    END;

EXCEPTION
    WHEN OTHERS THEN
        -- Catch-all error handler
        APEX_JSON.open_object;
        APEX_JSON.write('status', 'error');
        APEX_JSON.write('message', 'Unexpected error: ' || SQLERRM);
        APEX_JSON.close_object;
END;

-- ============================================================================
-- OPTION 2: Page Process (For Form-Based Submission)
-- ============================================================================
/*
 * Use this approach for a traditional form submission workflow.
 * Setup in APEX:
 * 1. Create page items: P1_USER_QUERY (Textarea), P1_AI_RESPONSE (Display Only)
 * 2. Create page process: Type = PL/SQL Code
 * 3. Paste the code below
 */

/*
DECLARE
    v_user_query    CLOB := :P1_USER_QUERY;
    v_response      CLOB;
    v_profile_name  VARCHAR2(100) := 'GENAI_COHERE';
BEGIN
    IF v_user_query IS NOT NULL THEN
        -- Generate SQL using Select AI
        v_response := DBMS_CLOUD_AI.GENERATE(
            prompt       => v_user_query,
            profile_name => v_profile_name,
            action       => 'narrate'  -- Returns SQL with explanation
        );

        -- Store response in page item for display
        :P1_AI_RESPONSE := v_response;

        -- Optional: Show success message
        APEX_APPLICATION.g_print_success_message := 'Query processed successfully';
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message => 'Please enter a question',
            p_display_location => APEX_ERROR.c_inline_in_notification
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        APEX_ERROR.ADD_ERROR(
            p_message => 'Error generating SQL: ' || SQLERRM,
            p_display_location => APEX_ERROR.c_inline_in_notification
        );
END;
*/

-- ============================================================================
-- OPTION 3: Dynamic Action (For Interactive Updates)
-- ============================================================================
/*
 * Use this for real-time SQL generation as user types.
 * Setup in APEX:
 * 1. Create Dynamic Action: Event = Change, Selection Type = Item, Item = P1_USER_QUERY
 * 2. Action = Execute PL/SQL Code
 * 3. Paste the code below
 * 4. Items to Return: P1_GENERATED_SQL
 */

/*
DECLARE
    v_query CLOB := :P1_USER_QUERY;
    v_sql   CLOB;
BEGIN
    IF LENGTH(v_query) > 10 THEN  -- Only trigger after meaningful input
        v_sql := DBMS_CLOUD_AI.GENERATE(
            prompt       => v_query,
            profile_name => 'GENAI_COHERE',
            action       => 'chat'
        );

        -- Extract SQL from response
        :P1_GENERATED_SQL := v_sql;
    END IF;
END;
*/

-- ============================================================================
-- SUPPORTING OBJECTS
-- ============================================================================

-- Optional: Create error logging table
CREATE TABLE apex_error_log (
    log_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_id          NUMBER,
    page_id         NUMBER,
    error_message   VARCHAR2(4000),
    error_timestamp DATE,
    username        VARCHAR2(255)
);

-- Optional: Create usage tracking table for analytics
CREATE TABLE nl2sql_usage_log (
    log_id              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_question       CLOB,
    generated_sql       CLOB,
    action_type         VARCHAR2(20),
    execution_time_sec  NUMBER,
    success_flag        CHAR(1),
    error_message       VARCHAR2(4000),
    created_by          VARCHAR2(255),
    created_date        TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- Grant access to APEX workspace schema
GRANT INSERT, SELECT ON nl2sql_usage_log TO apex_workspace_schema;

-- ============================================================================
-- ENHANCED VERSION: With Usage Logging and Caching
-- ============================================================================
/*
 * Production-grade version with:
 * - Query caching (avoid redundant AI calls)
 * - Usage analytics
 * - Rate limiting
 * - Error categorization
 */

/*
DECLARE
    v_user_question     CLOB := APEX_APPLICATION.g_x01;
    v_action_type       VARCHAR2(20) := NVL(APEX_APPLICATION.g_x02, 'chat');
    v_profile_name      VARCHAR2(100) := 'GENAI_COHERE';
    v_ai_response       CLOB;
    v_cached_response   CLOB;
    v_cache_hit         BOOLEAN := FALSE;
    v_start_time        NUMBER;
    v_execution_time    NUMBER;
    v_success_flag      CHAR(1) := 'Y';
    v_error_message     VARCHAR2(4000);

    -- Rate limiting
    v_user_query_count  NUMBER;
    v_max_queries_per_hour NUMBER := 100;

BEGIN
    v_start_time := DBMS_UTILITY.GET_TIME;

    -- ────────────────────────────────────────────────────────────────────────
    -- Rate Limiting Check
    -- ────────────────────────────────────────────────────────────────────────
    SELECT COUNT(*)
    INTO v_user_query_count
    FROM nl2sql_usage_log
    WHERE created_by = :APP_USER
    AND created_date > SYSTIMESTAMP - INTERVAL '1' HOUR;

    IF v_user_query_count >= v_max_queries_per_hour THEN
        APEX_JSON.open_object;
        APEX_JSON.write('status', 'error');
        APEX_JSON.write('message', 'Rate limit exceeded. Please try again later.');
        APEX_JSON.close_object;
        RETURN;
    END IF;

    -- ────────────────────────────────────────────────────────────────────────
    -- Check Cache (for identical questions)
    -- ────────────────────────────────────────────────────────────────────────
    BEGIN
        SELECT generated_sql
        INTO v_cached_response
        FROM nl2sql_usage_log
        WHERE LOWER(TRIM(user_question)) = LOWER(TRIM(v_user_question))
        AND success_flag = 'Y'
        AND created_date > SYSTIMESTAMP - INTERVAL '24' HOUR
        ORDER BY created_date DESC
        FETCH FIRST 1 ROW ONLY;

        v_cache_hit := TRUE;
        v_ai_response := v_cached_response;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- No cached result, proceed with AI generation
            v_cache_hit := FALSE;
    END;

    -- ────────────────────────────────────────────────────────────────────────
    -- Generate SQL (if not cached)
    -- ────────────────────────────────────────────────────────────────────────
    IF NOT v_cache_hit THEN
        BEGIN
            v_ai_response := DBMS_CLOUD_AI.GENERATE(
                prompt       => v_user_question,
                profile_name => v_profile_name,
                action       => v_action_type
            );
        EXCEPTION
            WHEN OTHERS THEN
                v_success_flag := 'N';
                v_error_message := SQLERRM;
                RAISE;
        END;
    END IF;

    v_execution_time := (DBMS_UTILITY.GET_TIME - v_start_time) / 100;

    -- ────────────────────────────────────────────────────────────────────────
    -- Log Usage
    -- ────────────────────────────────────────────────────────────────────────
    INSERT INTO nl2sql_usage_log (
        user_question,
        generated_sql,
        action_type,
        execution_time_sec,
        success_flag,
        error_message,
        created_by
    ) VALUES (
        v_user_question,
        v_ai_response,
        v_action_type,
        v_execution_time,
        v_success_flag,
        v_error_message,
        :APP_USER
    );
    COMMIT;

    -- ────────────────────────────────────────────────────────────────────────
    -- Return Response
    -- ────────────────────────────────────────────────────────────────────────
    APEX_JSON.open_object;
    APEX_JSON.write('status', 'success');
    APEX_JSON.write('sql', v_ai_response);
    APEX_JSON.write('execution_time', v_execution_time);
    APEX_JSON.write('cache_hit', CASE WHEN v_cache_hit THEN 'true' ELSE 'false' END);
    APEX_JSON.close_object;

EXCEPTION
    WHEN OTHERS THEN
        APEX_JSON.open_object;
        APEX_JSON.write('status', 'error');
        APEX_JSON.write('message', SQLERRM);
        APEX_JSON.close_object;
END;
*/

-- ============================================================================
-- JAVASCRIPT (for APEX page)
-- ============================================================================
/*
 * Add this JavaScript to your APEX page to handle AJAX calls
 * Location: Page Properties > JavaScript > Execute when Page Loads
 */

/*
// Send natural language query to backend
function sendQuery() {
    const userQuery = apex.item('P1_USER_QUERY').getValue();

    if (!userQuery) {
        apex.message.showErrors([{
            type: 'error',
            message: 'Please enter a question',
            location: 'page'
        }]);
        return;
    }

    // Show loading indicator
    apex.message.clearErrors();
    apex.util.showSpinner($('#query-results'));

    // AJAX call to PL/SQL process
    apex.server.process(
        'GENERATE_SQL_FROM_NL',  // Process name
        {
            x01: userQuery,          // User question
            x02: 'chat'             // Action type
        },
        {
            dataType: 'json',
            success: function(response) {
                if (response.status === 'success') {
                    // Display generated SQL
                    apex.item('P1_GENERATED_SQL').setValue(response.sql);

                    // Show execution time
                    $('#execution-time').text(
                        'Generated in ' + response.execution_time + ' seconds'
                    );

                    // Optional: Execute SQL and show results
                    // executeGeneratedSQL(response.sql);
                } else {
                    apex.message.showErrors([{
                        type: 'error',
                        message: response.message,
                        location: 'page'
                    }]);
                }
            },
            error: function(xhr, status, error) {
                apex.message.showErrors([{
                    type: 'error',
                    message: 'Request failed: ' + error,
                    location: 'page'
                }]);
            },
            complete: function() {
                apex.util.hideSpinner($('#query-results'));
            }
        }
    );
}

// Bind to button click
$('#send-query-btn').on('click', sendQuery);

// Allow Enter key to submit
$('#P1_USER_QUERY').on('keypress', function(e) {
    if (e.which === 13 && !e.shiftKey) {  // Enter without Shift
        e.preventDefault();
        sendQuery();
    }
});
*/
