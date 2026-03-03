# P3-006: Packaging and Distribution

**Status:** Complete
**Depends on:** P2-006 (security profiles)
**Estimated scope:** New files (CLI launcher, config support)

## Motivation

Fledgling currently runs via `duckdb -init init-fledgling.sql` with the
working directory as the implicit project root. This works for development
and Claude Code integration, but has friction for distribution:

- Users must know the correct `duckdb` invocation and init script path
- Profile selection requires using a different init script
- There's no way to pass configuration (exclude patterns, extra dirs) without
  editing SQL files
- No `--help`, no discoverability

A thin CLI wrapper and config file support would make Fledgling runnable
without understanding the DuckDB internals.

## Implementation

### Approach: Single bash script

The original design proposed Python CLI with `click`, `pyyaml`, and
`pyproject.toml` entry points. During planning, this was simplified to a
single bash script — no Python dependencies, no pip packaging. The CLI is
a launcher, not a runtime. All logic stays in SQL.

### `bin/fledgling`

~120-line bash script with two subcommands:

- **`fledgling serve`** — Builds and `exec`s the right `duckdb -init`
  command. Uses `-cmd` flags for variable injection (`.cd`, `SET VARIABLE`)
  before `-init` loads the profile entry point.

- **`fledgling info`** — Prints diagnostic info (paths, config, duckdb
  version, file counts) without starting DuckDB as a server.

### Config file (`.fledgling`)

Shell-sourceable key=value file in the project root. No parser needed —
just `source` it.

```bash
# .fledgling (or fledgling.conf)
FLEDGLING_PROFILE=core
FLEDGLING_TRANSPORT=stdio
# FLEDGLING_EXTRA_DIRS="['/data/shared']"
```

### Precedence

CLI flags > environment variables > config file > defaults.

Env var values are saved before sourcing the config to prevent config from
clobbering them.

### SQL changes

Transport is parameterized in both profile entry points:

```sql
SELECT mcp_server_start(COALESCE(getvariable('transport'), 'stdio'), getvariable('mcp_server_options'));
```

Backward compatible — defaults to `stdio` when no variable is set.

## Files

| File | Action | Description |
|------|--------|-------------|
| `bin/fledgling` | Create | Bash launcher script |
| `init-fledgling-analyst.sql` | Update | Parameterize transport (1 line) |
| `init-fledgling-core.sql` | Update | Parameterize transport (1 line) |
| `config/claude-code.example.json` | Update | Show launcher usage |

## Acceptance Criteria

- [x] `fledgling serve` starts the MCP server (stdio transport)
- [x] `fledgling serve --profile analyst` starts with analyst profile
- [x] `fledgling info` prints diagnostics (paths, config, duckdb, file counts)
- [x] Config file is read if present, CLI flags override config values
- [x] Env vars override config, CLI flags override env vars
- [x] Profile validation rejects unknown profiles
- [x] Existing `duckdb -init` workflow continues to work unchanged
- [x] Existing test suite passes
