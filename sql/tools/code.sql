-- Fledgling: Code Intelligence Tool Publications
--
-- Publishes 7 MCP tools for AST-based code analysis.
-- Macros are defined in sql/code.sql; this file only creates MCP bindings.
--
-- Embeds session_root at publish time (getvariable is not available
-- in MCP tool execution context). Must be loaded after sandbox.sql
-- and code.sql, with session_root already set.

SELECT mcp_publish_tool(
    'FindDefinitions',
    'AST-based definition search — not grep. Finds functions, classes, and variable definitions. Use name_pattern with SQL LIKE wildcards (%) to filter by name.',
    'SELECT * FROM find_definitions(
        CASE WHEN $file_pattern[1] = ''/'' THEN $file_pattern
             ELSE ''' || getvariable('session_root') || '/'' || $file_pattern END,
        COALESCE(NULLIF($name_pattern, ''null''), ''%'')
    )',
    '{"file_pattern": {"type": "string", "description": "Glob pattern for files to search (e.g. src/**/*.py)"}, "name_pattern": {"type": "string", "description": "SQL LIKE pattern to filter by name (e.g. parse%). Default: % (all)"}}',
    '["file_pattern"]',
    'markdown'
);

SELECT mcp_publish_tool(
    'FindCalls',
    'Find where functions or methods are called. Uses AST parsing to identify call sites, not text matching. Use name_pattern with SQL LIKE wildcards (%) to filter.',
    'SELECT * FROM find_calls(
        CASE WHEN $file_pattern[1] = ''/'' THEN $file_pattern
             ELSE ''' || getvariable('session_root') || '/'' || $file_pattern END,
        COALESCE(NULLIF($name_pattern, ''null''), ''%'')
    )',
    '{"file_pattern": {"type": "string", "description": "Glob pattern for files to search (e.g. src/**/*.py)"}, "name_pattern": {"type": "string", "description": "SQL LIKE pattern to filter by call name (e.g. connect%). Default: % (all)"}}',
    '["file_pattern"]',
    'markdown'
);

SELECT mcp_publish_tool(
    'FindImports',
    'Find import/include/require statements in source files. Uses AST parsing to identify language-specific import constructs.',
    'SELECT * FROM find_imports(
        CASE WHEN $file_pattern[1] = ''/'' THEN $file_pattern
             ELSE ''' || getvariable('session_root') || '/'' || $file_pattern END
    )',
    '{"file_pattern": {"type": "string", "description": "Glob pattern for files to search (e.g. src/**/*.py)"}}',
    '["file_pattern"]',
    'markdown'
);

SELECT mcp_publish_tool(
    'CodeStructure',
    'Top-level structural overview of source files: definitions with line counts. Shows what is defined in each file without implementation details.',
    'SELECT * FROM code_structure(
        CASE WHEN $file_pattern[1] = ''/'' THEN $file_pattern
             ELSE ''' || getvariable('session_root') || '/'' || $file_pattern END
    )',
    '{"file_pattern": {"type": "string", "description": "Glob pattern for files to analyze (e.g. src/**/*.py)"}}',
    '["file_pattern"]',
    'markdown'
);

SELECT mcp_publish_tool(
    'ComplexityHotspots',
    'Find the most complex functions ranked by cyclomatic complexity. Returns structural metrics: conditionals, loops, return count, max nesting depth. Useful for identifying code that needs refactoring or careful review.',
    'SELECT * FROM complexity_hotspots(
        CASE WHEN $file_pattern[1] = ''/'' THEN $file_pattern
             ELSE ''' || getvariable('session_root') || '/'' || $file_pattern END,
        COALESCE(TRY_CAST(NULLIF($limit, ''null'') AS INT), 20)
    )',
    '{"file_pattern": {"type": "string", "description": "Glob pattern for files to analyze (e.g. src/**/*.py)"}, "limit": {"type": "string", "description": "Maximum number of results (default 20)"}}',
    '["file_pattern"]',
    'markdown'
);

SELECT mcp_publish_tool(
    'FunctionCallers',
    'Find all call sites for a named function across a codebase. Shows who calls a function and the enclosing function/class at each call site. The reverse of FindCalls.',
    'SELECT * FROM function_callers(
        CASE WHEN $file_pattern[1] = ''/'' THEN $file_pattern
             ELSE ''' || getvariable('session_root') || '/'' || $file_pattern END,
        $func_name
    )',
    '{"file_pattern": {"type": "string", "description": "Glob pattern for files to search (e.g. src/**/*.py)"}, "func_name": {"type": "string", "description": "Exact function name to find callers of"}}',
    '["file_pattern", "func_name"]',
    'markdown'
);

SELECT mcp_publish_tool(
    'ModuleDependencies',
    'Map internal import relationships across a codebase. Shows which modules import which, with fan-in count (how many modules depend on each target). Filters to imports matching a given package prefix.',
    'SELECT * FROM module_dependencies(
        CASE WHEN $file_pattern[1] = ''/'' THEN $file_pattern
             ELSE ''' || getvariable('session_root') || '/'' || $file_pattern END,
        $package_prefix
    )',
    '{"file_pattern": {"type": "string", "description": "Glob pattern for files to analyze (e.g. src/**/*.py)"}, "package_prefix": {"type": "string", "description": "Package prefix to filter imports (e.g. myapp, blq)"}}',
    '["file_pattern", "package_prefix"]',
    'markdown'
);
