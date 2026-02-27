# P2-005: Init Script, Test Fixture & Config

**Status:** Not started
**Depends on:** P2-001 through P2-004 (all tool categories)
**Estimated scope:** New files + fixture update

## Goal

Create the entry point that ties everything together: the init SQL script
that loads extensions, macros, and tool modules, then starts the MCP server.
Also update the test fixture to load modular tool files and provide an
example Claude Code configuration.

## Files

| File | Action | Description |
|------|--------|-------------|
| `init-source-sextant.sql` | Create | Entry point for `duckdb -init` |
| `config/claude-code.example.json` | Create | Example MCP server config |
| `tests/conftest.py` | Update | Load `sql/tools/*.sql` instead of `sql/tools.sql` |

## init-source-sextant.sql

Following duckdb_mcp example-06 pattern. Uses `.read` for modularity —
any tool category can be disabled by commenting out its line.

```sql
-- Suppress output during initialization
.headers off
.mode csv
.output /dev/null

-- Load extensions
LOAD duckdb_mcp;
LOAD read_lines;
LOAD sitting_duck;
LOAD markdown;
LOAD duck_tails;

-- Fix sitting_duck read_lines collision (sitting_duck#22)
DROP MACRO TABLE IF EXISTS read_lines;

-- Load macro definitions
.read sql/source.sql
.read sql/code.sql
.read sql/docs.sql
.read sql/repo.sql

-- Publish MCP tools (comment out to disable a category)
.read sql/tools/files.sql
.read sql/tools/code.sql
.read sql/tools/docs.sql
.read sql/tools/git.sql

-- Restore output and start server
.output stdout
SELECT mcp_server_start('stdio', '{
    "enable_query_tool": true,
    "enable_describe_tool": true,
    "enable_list_tables_tool": true,
    "enable_database_info_tool": false,
    "enable_export_tool": false,
    "enable_execute_tool": false,
    "default_result_format": "markdown"
}');
```

**Note:** `.read` paths are relative to CWD where `duckdb` is invoked,
not relative to the init script. The Claude Code config must set the
correct working directory or use absolute paths.

## Test Fixture Update

Replace `load_sql(con, "tools.sql")` with individual category loads:

```python
@pytest.fixture(scope="session")
def mcp_server():
    con = duckdb.connect(":memory:")
    # ... extensions and macros as before ...
    con.execute("LOAD duckdb_mcp")
    for tool_file in ["tools/files.sql", "tools/code.sql",
                      "tools/docs.sql", "tools/git.sql"]:
        load_sql(con, tool_file)
    con.execute("SELECT mcp_server_start('memory')")
    yield con
    con.close()
```

## Example Config (config/claude-code.example.json)

```json
{
  "mcpServers": {
    "source_sextant": {
      "command": "duckdb",
      "args": ["-init", "/absolute/path/to/source-sextant/init-source-sextant.sql"],
      "cwd": "/absolute/path/to/source-sextant"
    }
  }
}
```

Goes in `~/.claude/settings.json` (global) or `.mcp.json` (per-project).

## Acceptance Criteria

- All 27 MCP tests pass (requires P2-001 through P2-004 complete)
- All 94 existing tests still pass
- `duckdb -init init-source-sextant.sql` starts without errors (manual smoke test)
- Tools discoverable via `tools/list` JSON-RPC request
