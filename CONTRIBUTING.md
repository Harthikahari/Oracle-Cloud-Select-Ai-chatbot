# Contributing to Enterprise NL2SQL Agent

Thank you for your interest in contributing to the Enterprise NL2SQL Agent project! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)

---

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for all contributors, regardless of experience level, background, or identity.

### Expected Behavior

- Be respectful and considerate
- Provide constructive feedback
- Focus on what's best for the project and community
- Show empathy towards other contributors

### Unacceptable Behavior

- Harassment or discriminatory language
- Trolling or insulting comments
- Personal or political attacks
- Publishing others' private information

---

## Getting Started

### Prerequisites

Before contributing, ensure you have:
- Oracle Autonomous Database access (for testing)
- Basic understanding of SQL and PL/SQL
- Familiarity with Oracle Select AI and DBMS_CLOUD_AI
- Git installed locally

### Setting Up Development Environment

1. **Fork the repository**
   ```bash
   # Click "Fork" on GitHub, then clone your fork
   git clone https://github.com/YOUR_USERNAME/Oracle-Cloud-Select-Ai-chatbot.git
   cd Oracle-Cloud-Select-Ai-chatbot
   ```

2. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/Harthikahari/Oracle-Cloud-Select-Ai-chatbot.git
   ```

3. **Create a test database** (optional but recommended)
   ```bash
   # Run setup scripts in a test environment
   sqlplus test_user/password@test_db
   @sql/01_setup_permissions.sql
   @sql/02_data_optimization.sql
   @sql/03_create_ai_profile.sql
   ```

---

## How to Contribute

### Types of Contributions

We welcome various types of contributions:

1. **Bug Fixes** - Fix issues in SQL scripts, documentation, or configuration
2. **New Features** - Add new optimization techniques or functionality
3. **Documentation** - Improve README, comments, or blog post
4. **Performance Improvements** - Optimize queries or indexes
5. **Testing** - Add test cases or validation scripts
6. **Examples** - Contribute new use cases or sample queries

### Finding Issues to Work On

- Check the [Issues](https://github.com/Harthikahari/Oracle-Cloud-Select-Ai-chatbot/issues) page
- Look for issues labeled `good first issue` or `help wanted`
- Read through existing discussions

### Reporting Bugs

Use the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) template and include:
- Clear description of the bug
- Steps to reproduce
- Expected vs. actual behavior
- Environment details (Oracle version, OCI region, etc.)
- Error messages and logs
- Sample SQL queries (if applicable)

### Suggesting Features

Use the [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md) template and include:
- Problem statement
- Proposed solution
- Use case examples
- Impact assessment

---

## Development Workflow

### Branch Naming Convention

Use descriptive branch names:
- `feature/add-multi-table-joins` - New features
- `fix/hallucination-in-date-queries` - Bug fixes
- `docs/update-installation-guide` - Documentation
- `perf/optimize-employee-index` - Performance improvements

### Commit Message Guidelines

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `perf`: Performance improvement
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Examples:**
```bash
feat(schema): add customer table metadata optimization

- Added COMMENT ON statements for customer table
- Created business synonyms (clients, customers)
- Improved accuracy for customer-related queries from 67% to 94%

Closes #42

fix(ai-profile): correct temperature setting for deterministic output

Changed temperature from 0.1 to 0.0 to eliminate creative hallucinations
in column name generation.

Fixes #38

docs(readme): update installation instructions for OCI GenAI

- Added Resource Principal setup steps
- Clarified IAM policy requirements
- Added troubleshooting section for network ACLs
```

---

## Coding Standards

### SQL/PL-SQL Style Guide

**File Structure:**
```sql
/*******************************************************************************
 * File: filename.sql
 * Purpose: Brief description
 * Author: Your Name
 * Last Updated: YYYY-MM-DD
 *******************************************************************************/

-- Section 1: Configuration
DEFINE variable_name = 'value'

-- Section 2: Main Logic
BEGIN
    -- Implementation
END;
/
```

**Naming Conventions:**
- Tables: `UPPER_CASE_SNAKE` (e.g., `EMPLOYEES`, `DEPT_MASTER`)
- Columns: `lower_case_snake` (e.g., `employee_id`, `dept_name`)
- Variables: `v_descriptive_name` (e.g., `v_user_query`, `v_response`)
- Constants: `c_CONSTANT_NAME` (e.g., `c_MAX_TOKENS`)
- Procedures: `PascalCase` or `lower_case` (e.g., `ProcessQuery` or `process_query`)

**Formatting:**
```sql
-- Good: Clear formatting
SELECT e.employee_id,
       e.first_name,
       e.last_name,
       d.dept_name
FROM employees e
JOIN departments d
  ON e.dept_id = d.dept_id
WHERE e.is_active = 'Y'
  AND d.budget > 1000000
ORDER BY e.last_name;

-- Bad: Unreadable
SELECT e.employee_id,e.first_name,e.last_name,d.dept_name FROM employees e JOIN departments d ON e.dept_id=d.dept_id WHERE e.is_active='Y' AND d.budget>1000000 ORDER BY e.last_name;
```

**Comments:**
```sql
-- Use single-line comments for brief explanations
-- Each comment should explain WHY, not WHAT

/* Use multi-line comments for:
   - File headers
   - Complex logic explanations
   - Usage examples
*/

COMMENT ON TABLE employees IS
'Clear, business-focused description. Include purpose, update frequency,
and any important caveats. This is critical for AI understanding!';
```

### Schema Metadata Best Practices

**Table Comments:**
- Describe business purpose, not technical structure
- Mention update frequency
- Note relationships to other tables
- Include data scope (time range, filters)

```sql
-- Good
COMMENT ON TABLE sales_orders IS
'Customer sales orders from 2020 onward. Updated in real-time via order
processing system. Includes both B2B and B2C orders. Join to customers
table for account details and products table for item information.';

-- Bad
COMMENT ON TABLE sales_orders IS 'Stores orders';
```

**Column Comments:**
- Explain business meaning
- List valid values (for enums)
- Note calculation logic (for derived fields)
- Include units (for numeric fields)
- Mention related columns

```sql
-- Good
COMMENT ON COLUMN products.unit_price IS
'Current selling price per unit in USD. Excludes discounts and taxes.
Updated weekly by pricing team. Use order_items.actual_price for
historical transaction amounts.';

-- Bad
COMMENT ON COLUMN products.unit_price IS 'Price';
```

---

## Testing Guidelines

### Test Categories

1. **Unit Tests** - Individual SQL functions/procedures
2. **Integration Tests** - End-to-end query generation
3. **Regression Tests** - Ensure fixes don't break existing functionality
4. **Accuracy Tests** - Validate query correctness

### Creating Test Cases

Add test queries to `tests/test_queries.sql`:

```sql
-- Test Case: Basic employee count
PROMPT Test 1: Total active employee count
DECLARE
    v_query CLOB := 'How many active employees do we have?';
    v_result CLOB;
BEGIN
    v_result := DBMS_CLOUD_AI.GENERATE(
        prompt => v_query,
        profile_name => 'GENAI_COHERE'
    );

    -- Validate result contains expected SQL
    IF v_result LIKE '%SUM(headcount)%' AND v_result LIKE '%is_active%' THEN
        DBMS_OUTPUT.PUT_LINE('✓ PASS: Correct SQL generated');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✗ FAIL: Unexpected SQL: ' || v_result);
    END IF;
END;
/
```

### Testing Checklist

Before submitting:
- [ ] All SQL scripts run without errors
- [ ] New metadata improves query accuracy
- [ ] No regression in existing queries
- [ ] Documentation updated
- [ ] Code follows style guide
- [ ] Commit messages are clear

---

## Documentation

### What to Document

- **Code Comments**: Explain complex logic
- **README Updates**: New features or changed workflows
- **CHANGELOG**: All notable changes
- **Blog Post**: Major architectural changes
- **Examples**: New use cases

### Documentation Style

- Use clear, concise language
- Include examples
- Explain WHY, not just WHAT
- Update inline SQL comments
- Keep blog post synchronized with code

---

## Submitting Changes

### Pull Request Process

1. **Sync your fork**
   ```bash
   git fetch upstream
   git checkout main
   git merge upstream/main
   ```

2. **Create feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make changes**
   - Write code
   - Add tests
   - Update documentation

4. **Test thoroughly**
   ```bash
   # Run all SQL scripts in test environment
   sqlplus test_user/password@test_db
   @sql/01_setup_permissions.sql
   @sql/02_data_optimization.sql
   @sql/03_create_ai_profile.sql
   ```

5. **Commit changes**
   ```bash
   git add .
   git commit -m "feat(scope): descriptive message"
   ```

6. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Create Pull Request**
   - Go to GitHub
   - Click "New Pull Request"
   - Fill out PR template
   - Link related issues

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement

## Changes Made
- Bullet list of changes
- Include file names

## Testing Done
- Describe testing performed
- Include test results

## Impact
- Query accuracy impact: XX% → YY%
- Performance impact: X.Xs → Y.Ys
- Breaking changes: Yes/No

## Checklist
- [ ] Code follows style guide
- [ ] Tests pass
- [ ] Documentation updated
- [ ] CHANGELOG updated
- [ ] Commit messages are clear

## Related Issues
Closes #XX
```

### Review Process

1. **Automated Checks** - Linting, formatting (if configured)
2. **Code Review** - Maintainer reviews code quality
3. **Testing** - Verify functionality in test environment
4. **Approval** - Approved by maintainer(s)
5. **Merge** - Squash and merge to main branch

---

## Recognition

Contributors will be recognized in:
- README.md acknowledgments section
- Release notes
- GitHub contributors page

---

## Questions?

- **Technical Questions**: Open a [Discussion](https://github.com/Harthikahari/Oracle-Cloud-Select-Ai-chatbot/discussions)
- **Bug Reports**: Use [Issues](https://github.com/Harthikahari/Oracle-Cloud-Select-Ai-chatbot/issues)
- **General Contact**: See README.md for author contact info

---

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to making NL2SQL systems better! 🎉
