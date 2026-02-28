# P2-006: Fledgling MVP — Code Navigation MCP Server

## Task Type
Implementation (greenfield, from spec)

## Priority
P2 — Important, not urgent. Foundation for the broader tool suite.

## Overview

Build the MVP of **Fledgling**, a code navigation MCP server for AI agents. Fledgling gives agents the ability to explore, search, and understand codebases without requiring them to shell out to `grep`, `find`, `cat`, or `tree` and parse the results themselves. It returns structured, context-rich results via MCP tools, powered by DuckDB under the hood.

Fledgling is **ephemeral** — no persistent storage, no history, no memory between sessions. It indexes a codebase into an in-memory DuckDB instance at startup, then serves queries against it. When the server stops, everything is gone. This is by design: Fledgling is a read-only lens, not a database.

The name "Fledgling" is intentionally sardonic — a struggling baby bird, not yet capable of flight. It's part of a tool suite with shared naming energy: **blq** (bleak) for build logs, **duck_hunt** for log parsing, and a git workflow tool (name TBD) carrying similar commentary.

## Context: What Fledgling Is and Isn't

**IS:**
- An MCP server that agents connect to for code navigation
- A DuckDB-powered in-memory index of a codebase
- A set of high-level tools (search, read, explore, understand) that return structured results
- Security-profile gated — different profiles expose different capabilities
- Read-only — never modifies files

**IS NOT:**
- A git tool (that's the separate git workflow accelerator)
- A build log analyzer (that's blq + duck_hunt)
- Persistent (no state survives server restart)
- A general-purpose database server
- An embeddings/vector search system (it's structural, not semantic)

## Architecture

```
fledgling/
├── server.py                 # MCP server entrypoint (stdio + SSE)
├── index/
│   ├── builder.py            # Codebase indexer — walks filesystem, builds DuckDB tables
│   ├── files.py              # File metadata table (path, size, language, modified)
│   ├── content.py            # File content table (lines, with line numbers)
│   ├── structure.py          # Code structure table (functions, classes, imports)
│   └── languages.py          # Language detection and parser selection
├── tools/
│   ├── explore.py            # Directory listing, project overview, file tree
│   ├── read.py               # Read file (full, range, function, class)
│   ├── search.py             # Text search (grep-like), symbol search, reference search
│   ├── understand.py         # Summarize file/module, dependency graph, call graph
│   └── query.py              # Raw SQL query tool (analyst profile only)
├── security/
│   ├── profiles.py           # Profile loader and enforcer
│   ├── fledgling-core.sql    # Default profile: read files, search, explore
│   ├── fledgling-analyst.sql # Extended profile: + raw SQL queries
│   └── fledgling-outie.sql   # Future: Severance Protocol outie profile
├── extensions/               # DuckDB extensions loaded at startup
│   └── loader.py             # Extension discovery and loading
└── config/
    └── settings.py           # Server configuration (root path, profile, extensions)
```

### DuckDB Tables (In-Memory)

The indexer builds these tables at startup by walking the codebase:

#### `files`
```sql
CREATE TABLE files (
    path VARCHAR PRIMARY KEY,    -- relative to project root
    absolute_path VARCHAR,
    directory VARCHAR,
    filename VARCHAR,
    extension VARCHAR,
    language VARCHAR,             -- detected language (python, javascript, etc.)
    size_bytes INTEGER,
    line_count INTEGER,
    modified_at TIMESTAMP,
    is_binary BOOLEAN,
    is_generated BOOLEAN          -- heuristic: node_modules, .min.js, etc.
);
```

#### `content`
```sql
CREATE TABLE content (
    path VARCHAR,
    line_number INTEGER,
    line_text VARCHAR,
    indent_level INTEGER,
    is_blank BOOLEAN,
    is_comment BOOLEAN,           -- heuristic based on language
    PRIMARY KEY (path, line_number)
);
```

#### `symbols`
```sql
CREATE TABLE symbols (
    path VARCHAR,
    name VARCHAR,
    kind VARCHAR,                  -- function, class, method, variable, import, export
    line_start INTEGER,
    line_end INTEGER,
    parent_name VARCHAR,           -- enclosing class/module
    signature VARCHAR,             -- function signature if applicable
    docstring VARCHAR,             -- extracted docstring/comment
    language VARCHAR,
    visibility VARCHAR             -- public, private, protected (heuristic)
);
```

#### `imports`
```sql
CREATE TABLE imports (
    path VARCHAR,
    line_number INTEGER,
    module VARCHAR,                -- what's being imported
    alias VARCHAR,                 -- import alias if any
    is_relative BOOLEAN,
    is_stdlib BOOLEAN              -- heuristic
);
```

### Indexing Strategy

**Phase 1 (MVP):** Simple, fast, good-enough.
- Walk the filesystem respecting `.gitignore` patterns
- Detect language from file extension (no tree-sitter yet)
- Extract symbols using regex patterns per language (function defs, class defs, imports)
- Store all file content line-by-line for search
- Skip binary files, respect size limits (default: skip files > 1MB)
- Target: index a 10,000-file repo in under 10 seconds

**Phase 2 (Future):** Tree-sitter integration via sitting_duck extension.
- Proper AST parsing for accurate symbol extraction
- Cross-reference resolution (which function calls which)
- Type information where available

The MVP should be designed so tree-sitter integration is additive — the tables stay the same, the data just gets more accurate.

## MCP Tools

### Core Profile (`fledgling-core.sql`)

These tools are available in the default security profile.

#### `explore`
Overview and navigation tools.

```
explore(path?: string, depth?: int, pattern?: string) → DirectoryListing
```

Returns the project structure. If no path given, returns root. Respects `.gitignore`. Includes file count, language breakdown, and size summary per directory.

Example response:
```json
{
  "path": "src/",
  "directories": ["src/core/", "src/utils/", "src/api/"],
  "files": [
    {"path": "src/main.py", "language": "python", "lines": 142, "symbols": 8}
  ],
  "summary": {
    "total_files": 47,
    "total_lines": 3891,
    "languages": {"python": 32, "sql": 10, "yaml": 5},
    "largest_file": "src/core/engine.py (412 lines)"
  }
}
```

#### `read`
Read file content with smart defaults.

```
read(path: string, start_line?: int, end_line?: int, symbol?: string) → FileContent
```

If `symbol` is provided, reads just that function/class. If line range provided, reads that range. Otherwise reads full file (with truncation warning if very large).

Returns content with line numbers, language, and surrounding symbol context (e.g., "this is inside class Foo, method bar").

#### `search`
Text and symbol search.

```
search(query: string, path?: string, language?: string, kind?: string, max_results?: int) → SearchResults
```

- If `kind` is provided (function, class, import, etc.), searches the `symbols` table
- Otherwise searches `content` table with ILIKE matching
- Returns results with surrounding context lines (default: 2 above, 2 below)
- Groups results by file for readability
- Supports glob patterns in `path` filter

#### `symbols`
List symbols in a file or across the project.

```
symbols(path?: string, kind?: string, language?: string, name_pattern?: string) → SymbolList
```

Returns structured list of functions, classes, imports, etc. with their locations. If no path given, returns project-wide symbol index (potentially large — agent should filter by kind or pattern).

#### `dependencies`
Show import/dependency relationships.

```
dependencies(path: string, direction?: "imports" | "imported_by") → DependencyGraph
```

For a given file, shows what it imports and (if indexable) what imports it. Returns as an adjacency list with module resolution.

### Analyst Profile (`fledgling-analyst.sql`)

Includes all core tools plus:

#### `query`
Raw SQL against the index.

```
query(sql: string) → QueryResult
```

Executes arbitrary SELECT queries against the DuckDB tables. No writes allowed (enforced by profile). This is the escape hatch — if the structured tools don't answer the question, the agent can write SQL directly.

Example: "Find all Python functions longer than 50 lines that don't have docstrings"
```sql
SELECT path, name, line_start, line_end, (line_end - line_start) as length
FROM symbols
WHERE language = 'python'
  AND kind = 'function'
  AND docstring IS NULL
  AND (line_end - line_start) > 50
ORDER BY length DESC
```

## Security Profiles

Security profiles are SQL files that run at startup to configure what's available. They can:
- Create/drop views that limit visible data
- Set DuckDB configuration (memory limits, timeouts)
- Define which MCP tools are exposed

```sql
-- fledgling-core.sql
-- Default security profile: read-only code navigation

-- Enforce read-only mode
SET access_mode = 'read_only';

-- Memory limit for the session
SET memory_limit = '2GB';

-- Timeout for any single query
SET query_timeout = 30;  -- seconds

-- Tools exposed: explore, read, search, symbols, dependencies
-- (tool exposure is handled by the profile loader, not SQL)
```

```sql
-- fledgling-analyst.sql
-- Extended profile: adds raw SQL query capability

-- Same base constraints
SET access_mode = 'read_only';
SET memory_limit = '4GB';
SET query_timeout = 60;

-- Tools exposed: everything in core + query
```

The profile system should be extensible — users can write custom profiles. The server loads the profile at startup and refuses to expose tools not in the profile's allowlist.

## Server Configuration

```yaml
# fledgling.yaml (or CLI args)
root: "."                          # Project root to index
profile: "fledgling-core"          # Security profile
transport: "stdio"                 # stdio or sse
port: 3000                         # SSE port if applicable
extensions: []                     # Additional DuckDB extensions to load
exclude_patterns:                  # Additional patterns to exclude from indexing
  - "*.pyc"
  - "__pycache__"
  - ".git"
  - "node_modules"
max_file_size: 1048576             # Skip files larger than this (bytes)
max_files: 50000                   # Safety limit on indexed files
index_content: true                # Store file content (disable for huge repos)
```

## Implementation Plan

### Step 1: Skeleton (Day 1)
- [ ] Python project scaffold with `pyproject.toml`
- [ ] MCP server using `mcp` Python SDK (stdio transport)
- [ ] Single tool: `explore` returning hardcoded test data
- [ ] Verify server starts and responds to MCP tool calls

### Step 2: Indexer (Day 2-3)
- [ ] Filesystem walker with `.gitignore` support (use `pathspec` library)
- [ ] Language detection from file extension
- [ ] Build `files` table in DuckDB
- [ ] Build `content` table (line-by-line storage)
- [ ] Basic symbol extraction: Python functions/classes via regex
- [ ] Build `symbols` table
- [ ] Build `imports` table (Python imports via regex)
- [ ] Performance: index a real repo, target < 10s for 10K files

### Step 3: Core Tools (Day 4-5)
- [ ] `explore` — directory listing from `files` table with aggregations
- [ ] `read` — file content from `content` table, with line ranges and symbol lookup
- [ ] `search` — text search via `content` ILIKE, symbol search via `symbols`
- [ ] `symbols` — symbol listing with filters
- [ ] `dependencies` — import graph from `imports` table

### Step 4: Security Profiles (Day 6)
- [ ] Profile loader: reads SQL file, executes at startup
- [ ] Tool allowlist enforcement: profile declares which tools are exposed
- [ ] `query` tool (analyst profile only)
- [ ] Test: core profile cannot use `query` tool

### Step 5: Multi-Language Support (Day 7-8)
- [ ] Add regex-based symbol extractors for: JavaScript/TypeScript, Rust, Go, Java, C/C++, SQL
- [ ] Language-specific comment detection for `is_comment` in content table
- [ ] Test with polyglot repos

### Step 6: Polish & Package (Day 9-10)
- [ ] SSE transport option
- [ ] CLI for `fledgling serve`, `fledgling index --stats`, `fledgling query`
- [ ] Configuration file support
- [ ] Error handling: graceful failures for unreadable files, encoding issues, huge repos
- [ ] README with usage examples
- [ ] PyPI package

## Dependencies

- **Python 3.10+**
- **duckdb** — in-memory database
- **mcp** — MCP Python SDK (Anthropic)
- **click** — CLI framework
- **pathspec** — .gitignore pattern matching
- **pyyaml** — config file parsing

No tree-sitter dependency in MVP. No network dependencies. No LLM dependencies.

## Testing Strategy

### Unit Tests
- Indexer builds correct tables for a fixture repo (small directory with known files)
- Each tool returns expected results for known data
- Security profile correctly restricts tool access
- Symbol extraction regex works for each supported language

### Integration Tests
- Index a real open-source repo (e.g., Flask, Click) and verify:
  - File count matches `find . -type f | wc -l` (minus ignored)
  - Symbol count is reasonable
  - Search finds known strings
  - Read returns correct file content
- MCP tool calls work end-to-end via stdio

### Performance Tests
- Index time for repos of varying sizes (100, 1K, 10K, 50K files)
- Query response time for search, explore, symbols
- Memory usage stays within profile limits

## Success Criteria

- [ ] Agent (Claude Code, Claude Desktop, or similar) can connect via MCP and navigate a real codebase
- [ ] `explore` gives useful project overview without agent needing to `ls` and `cat`
- [ ] `search` finds relevant code faster than agent doing `grep` via shell
- [ ] `read` with `symbol` parameter extracts exactly the function/class requested
- [ ] Security profiles actually restrict capabilities
- [ ] Indexes a 10K-file repo in under 10 seconds
- [ ] Zero persistent state — restart is a clean slate
- [ ] Works with at least Python, JavaScript, and SQL codebases

## What This Enables

Once Fledgling exists, an agent can:

```
Agent: explore()
→ "This is a Python project with 47 files, mostly in src/core/ and src/api/"

Agent: symbols(kind="function", path="src/core/*")
→ [list of all functions in core module with signatures]

Agent: read(path="src/core/engine.py", symbol="process_batch")
→ [just that function, with docstring and line numbers]

Agent: search(query="timeout", language="python")
→ [all references to timeout with context, grouped by file]

Agent: dependencies(path="src/api/routes.py")
→ "routes.py imports: core.engine, core.auth, utils.validation"
```

This replaces dozens of `cat`, `grep`, `find`, `head`, `wc` calls with structured, context-rich responses. The agent spends tokens on understanding, not on parsing command output.

## Relationship to Other Tools

| Tool | Relationship |
|------|-------------|
| **blq** | Complementary — blq analyzes build logs, Fledgling navigates code |
| **[git tool TBD]** | Complementary — git tool ships changes, Fledgling reads code |
| **duck_hunt** | No dependency — duck_hunt is for log parsing, not code navigation |
| **sitting_duck** | Future integration — sitting_duck provides AST parsing for better symbol extraction |
| **duckdb_markdown** | Could integrate — render markdown docs as queryable tables |
| **duckdb_mcp** | Foundation — Fledgling's MCP server builds on similar patterns |
| **Severance Protocol** | Fledgling security profiles ARE the Innie/Outie enforcement layer |

## Notes for the Implementor

1. **Start with Python-only.** Get the full pipeline working for one language before adding others. Python is the best first target because you're writing the tool in Python — you can test against your own source.

2. **The indexer is the hardest part.** Getting `.gitignore` handling right, handling encoding issues gracefully, and building the tables efficiently is where most of the complexity lives. The MCP tools themselves are thin SQL wrappers.

3. **Regex symbol extraction is intentionally crude.** It will miss edge cases (decorators, nested functions, dynamic imports). That's fine — this is MVP. The table schema is designed so tree-sitter can slot in later without changing the interface.

4. **DuckDB's `read_text` and `glob` functions** can probably handle a lot of the file reading. Don't reinvent what DuckDB already does well.

5. **Test against real repos.** Pick 3-4 open source projects of different sizes and languages. If `explore` and `search` feel useful on those, the tool works.

6. **The security profile is not security theater.** The analyst profile exposes raw SQL. In a Severance Protocol context, the Innie runs core profile (no SQL escape hatch), the analyst runs analyst profile. This distinction matters.
