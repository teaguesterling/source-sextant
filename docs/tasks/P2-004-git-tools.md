# P2-004: Git Tools (GitChanges, GitBranches)

**Status:** Not started
**Depends on:** None (can be implemented independently)
**Estimated scope:** Tool publications only — existing macros match signatures

## Goal

Publish 2 MCP tools for git repository state. Both macros exist in `repo.sql`.
Param names differ slightly between tool and macro (by design — tool names
are user-facing, macro names follow SQL convention).

## Tools

| Tool | Required Params | Optional Params | Maps To |
|------|----------------|-----------------|---------|
| GitChanges | — | count, path | `recent_changes(n, repo)` |
| GitBranches | — | — | `branch_list(repo)` |

## Files

| File | Action | Description |
|------|--------|-------------|
| `sql/repo.sql` | No change | Macros already match tool signatures |
| `sql/tools/git.sql` | Create | 2 `mcp_publish_tool()` calls |

## Tool Publications (sql/tools/git.sql)

GitChanges has all-optional params. GitBranches has no params at all.

For GitBranches, the SQL template has no `$param` references so the
duckdb_mcp#19 bug doesn't apply — the template is just:
```sql
SELECT * FROM branch_list('.')
```

For GitChanges, both params are optional with defaults:
```sql
SELECT * FROM recent_changes(
    COALESCE(TRY_CAST(NULLIF($count, 'null') AS INT), 10),
    COALESCE(NULLIF($path, 'null'), '.')
)
```

Note: `path` defaults to `'.'` (current working directory). When running as
an MCP server, CWD is typically the project root.

Tool descriptions:
- **GitChanges**: "Recent commit history. Replaces `git log --oneline`."
- **GitBranches**: "List all branches with current branch marked."

## Acceptance Criteria

These tests in `test_mcp_server.py` must pass:
- `TestGitChanges` (2 tests): returns commits, count limit
- `TestGitBranches` (1 test): lists branches

Existing `test_repo.py` (18 tests) unaffected.
