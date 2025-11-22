/*******************************************************************************
 * File: 01_setup_permissions.sql
 * Purpose: Setup permissions and credentials for Oracle Select AI with OCI GenAI
 *
 * Prerequisites:
 * - Oracle Autonomous Database (19c+)
 * - OCI Resource Principal configured for the database
 * - IAM policy allowing ADW to invoke generative-ai-family services
 *
 * Execution: Run as ADMIN or privileged user
 *******************************************************************************/

-- ============================================================================
-- SECTION 1: Configuration Variables
-- ============================================================================
-- Update these values for your environment
DEFINE target_schema = 'NLSQL_USER'
DEFINE compartment_id = 'ocid1.compartment.oc1..aaaaaaaexamplecompartmentid'
DEFINE oci_region = 'us-ashburn-1'

PROMPT ========================================================================
PROMPT Oracle Select AI - Permission Setup
PROMPT ========================================================================
PROMPT
PROMPT Target Schema: &target_schema
PROMPT OCI Region: &oci_region
PROMPT Compartment: &compartment_id
PROMPT

-- ============================================================================
-- SECTION 2: Create Schema (if needed)
-- ============================================================================
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM all_users
    WHERE username = '&target_schema';

    IF v_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER &target_schema IDENTIFIED BY "Welcome123!"';
        DBMS_OUTPUT.PUT_LINE('✓ Schema &target_schema created');
    ELSE
        DBMS_OUTPUT.PUT_LINE('ℹ Schema &target_schema already exists');
    END IF;
END;
/

-- ============================================================================
-- SECTION 3: Grant Database Privileges
-- ============================================================================
PROMPT
PROMPT Granting database privileges...
PROMPT

-- Core database privileges
GRANT CONNECT, RESOURCE TO &target_schema;
GRANT UNLIMITED TABLESPACE TO &target_schema;

-- Select AI specific privileges
GRANT EXECUTE ON DBMS_CLOUD TO &target_schema;
GRANT EXECUTE ON DBMS_CLOUD_AI TO &target_schema;

-- Additional required privileges
GRANT CREATE TABLE TO &target_schema;
GRANT CREATE VIEW TO &target_schema;
GRANT CREATE SYNONYM TO &target_schema;
GRANT CREATE PROCEDURE TO &target_schema;

-- Allow reading data dictionary for metadata
GRANT SELECT ON SYS.DBA_TABLES TO &target_schema;
GRANT SELECT ON SYS.DBA_TAB_COLUMNS TO &target_schema;
GRANT SELECT ON SYS.DBA_CONSTRAINTS TO &target_schema;

PROMPT ✓ Database privileges granted
PROMPT

-- ============================================================================
-- SECTION 4: Setup OCI Credential (Resource Principal)
-- ============================================================================
PROMPT Setting up OCI credentials...
PROMPT

-- Connect as target schema to create credential
CONNECT &target_schema/Welcome123!@your_database_high

-- Drop existing credential if present (for clean re-runs)
BEGIN
    DBMS_CLOUD.DROP_CREDENTIAL(
        credential_name => 'OCI_GENAI_CRED'
    );
    DBMS_OUTPUT.PUT_LINE('ℹ Existing credential dropped');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -20404 THEN  -- Credential doesn't exist
            RAISE;
        END IF;
END;
/

-- Create credential using Resource Principal authentication
-- This is the recommended approach for ADW in OCI
BEGIN
    DBMS_CLOUD.CREATE_CREDENTIAL(
        credential_name => 'OCI_GENAI_CRED',
        user_ocid       => NULL,  -- Not needed for Resource Principal
        tenancy_ocid    => NULL,  -- Not needed for Resource Principal
        private_key     => NULL,  -- Not needed for Resource Principal
        fingerprint     => NULL   -- Not needed for Resource Principal
    );
    DBMS_OUTPUT.PUT_LINE('✓ OCI credential created using Resource Principal');
END;
/

/*
 * Alternative: API Key Authentication (if Resource Principal is not available)
 * Uncomment and configure the following block if needed:
 *
 * BEGIN
 *     DBMS_CLOUD.CREATE_CREDENTIAL(
 *         credential_name => 'OCI_GENAI_CRED',
 *         user_ocid       => 'ocid1.user.oc1..aaaaaaaexampleuserocid',
 *         tenancy_ocid    => 'ocid1.tenancy.oc1..aaaaaaaexampletenancyocid',
 *         private_key     => 'MIIEowIBAAKCAQEA...<your_private_key>...',
 *         fingerprint     => 'aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99'
 *     );
 * END;
 * /
 */

-- ============================================================================
-- SECTION 5: Network ACL Configuration (if required)
-- ============================================================================
PROMPT
PROMPT Configuring network access...
PROMPT

-- Reconnect as ADMIN for ACL configuration
CONNECT admin/<your_admin_password>@your_database_high

-- Grant network access for OCI GenAI endpoints
BEGIN
    -- Allow access to OCI GenAI service endpoints
    DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host       => '*.generativeai.*.oci.oraclecloud.com',
        lower_port => 443,
        upper_port => 443,
        ace        => xs$ace_type(
            privilege_list => xs$name_list('http', 'http_proxy'),
            principal_name => UPPER('&target_schema'),
            principal_type => xs_acl.ptype_db
        )
    );

    DBMS_OUTPUT.PUT_LINE('✓ Network ACL configured for OCI GenAI endpoints');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -46118 THEN  -- ACE already exists
            DBMS_OUTPUT.PUT_LINE('ℹ Network ACL already configured');
        ELSE
            RAISE;
        END IF;
END;
/

-- ============================================================================
-- SECTION 6: Validation
-- ============================================================================
PROMPT
PROMPT ========================================================================
PROMPT Validating Configuration...
PROMPT ========================================================================
PROMPT

-- Switch back to target schema
CONNECT &target_schema/Welcome123!@your_database_high

-- Test 1: Verify DBMS_CLOUD_AI access
DECLARE
    v_status VARCHAR2(100);
BEGIN
    SELECT 'GRANTED' INTO v_status
    FROM USER_TAB_PRIVS
    WHERE TABLE_NAME = 'DBMS_CLOUD_AI'
    AND PRIVILEGE = 'EXECUTE';

    DBMS_OUTPUT.PUT_LINE('✓ Test 1 PASSED: DBMS_CLOUD_AI execute privilege confirmed');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('✗ Test 1 FAILED: DBMS_CLOUD_AI execute privilege missing');
        RAISE;
END;
/

-- Test 2: Verify credential creation
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM USER_CREDENTIALS
    WHERE CREDENTIAL_NAME = 'OCI_GENAI_CRED';

    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('✓ Test 2 PASSED: OCI credential exists');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✗ Test 2 FAILED: OCI credential not found');
        RAISE_APPLICATION_ERROR(-20001, 'Credential validation failed');
    END IF;
END;
/

-- Test 3: Verify network connectivity (optional - comment out if not using ACL)
DECLARE
    v_response CLOB;
BEGIN
    -- Simple test to verify outbound HTTPS connectivity
    v_response := UTL_HTTP.REQUEST('https://www.oracle.com');
    DBMS_OUTPUT.PUT_LINE('✓ Test 3 PASSED: Network connectivity confirmed');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('⚠ Test 3 WARNING: Network test failed - ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('  (This may be expected if wallet or ACL is not configured)');
END;
/

PROMPT
PROMPT ========================================================================
PROMPT Setup Complete!
PROMPT ========================================================================
PROMPT
PROMPT Next Steps:
PROMPT   1. Run: @sql/02_data_optimization.sql
PROMPT   2. Run: @sql/03_create_ai_profile.sql
PROMPT   3. Test your first query:
PROMPT      SELECT DBMS_CLOUD_AI.GENERATE(
PROMPT          prompt => 'Show all tables in my schema',
PROMPT          profile_name => 'GENAI_COHERE'
PROMPT      ) FROM dual;
PROMPT
PROMPT ========================================================================

-- ============================================================================
-- SECTION 7: Cleanup Commands (for reference)
-- ============================================================================
/*
-- To reset and start over, run:

-- As target schema:
CONNECT &target_schema/Welcome123!@your_database_high
EXEC DBMS_CLOUD.DROP_CREDENTIAL('OCI_GENAI_CRED');

-- As ADMIN:
CONNECT admin/<password>@your_database_high
DROP USER &target_schema CASCADE;
EXEC DBMS_NETWORK_ACL_ADMIN.UNASSIGN_ACL(host => '*.generativeai.*.oci.oraclecloud.com');
*/
