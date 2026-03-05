-- Fledgling: Structural Analysis Tool Publications
--
-- MCP tool publications for cross-tier analysis (sitting_duck + duck_tails).
-- Wraps macros from sql/structural.sql.
--
-- Embeds session_root at publish time (getvariable is not available
-- in MCP tool execution context). Must be loaded after sandbox.sql
-- and structural.sql, with session_root already set.

SELECT mcp_publish_tool(
    'StructuralDiff',
    'Semantic diff between two git revisions of a file. Shows which functions/classes were added, removed, or modified with complexity metrics. Unlike line diffs, ignores formatting changes and line shifts — only reports structural changes. Requires sitting_duck git:// URI support.',
    'SELECT * FROM structural_diff(
        $file,
        $from_rev,
        $to_rev,
        COALESCE(resolve(NULLIF($repo, ''null'')), ''' || getvariable('session_root') || ''')
    )',
    '{"file": {"type": "string", "description": "Repository-relative file path (e.g. src/main.py)"}, "from_rev": {"type": "string", "description": "Base revision (e.g. HEAD~1, main)"}, "to_rev": {"type": "string", "description": "Target revision (e.g. HEAD, feature-branch)"}, "repo": {"type": "string", "description": "Repository path (default: project root)"}}',
    '["file", "from_rev", "to_rev"]',
    'markdown'
);

SELECT mcp_publish_tool(
    'ChangedFunctionSummary',
    'All functions in files that changed between two revisions, ranked by complexity. Answers "what functions should I review for this change?" Broader than StructuralDiff — shows every function in changed files, not just the ones that changed.',
    'SELECT * FROM changed_function_summary(
        $from_rev,
        $to_rev,
        CASE WHEN $file_pattern[1] = ''/'' THEN $file_pattern
             ELSE ''' || getvariable('session_root') || '/'' || $file_pattern END,
        COALESCE(resolve(NULLIF($repo, ''null'')), ''' || getvariable('session_root') || ''')
    )',
    '{"from_rev": {"type": "string", "description": "Base revision (e.g. HEAD~1, main)"}, "to_rev": {"type": "string", "description": "Target revision (e.g. HEAD, feature-branch)"}, "file_pattern": {"type": "string", "description": "Glob pattern for files to analyze (e.g. **/*.py, src/**/*.py)"}, "repo": {"type": "string", "description": "Repository path (default: project root)"}}',
    '["from_rev", "to_rev", "file_pattern"]',
    'markdown'
);
