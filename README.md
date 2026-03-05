# Fledgling

A sandboxed DuckDB runtime for AI coding agents. Structured tools for code, git, docs, and self-analysis — plus access to 140+ DuckDB extensions through SQL.

## Before and After

Your agent wastes tokens parsing text. Fledgling gives it purpose-built MCP tools that return structured data.

**Find a function definition**

Before — grep returns raw text the agent has to parse:
```
grep -rn 'def parse_config' src/
src/config.py:42:def parse_config(path: str, strict: bool = False) -> Config:
src/legacy/config.py:18:def parse_config(raw: dict) -> LegacyConfig:
```

After — the agent calls `FindDefinitions`:
```
FindDefinitions(file_pattern="src/**/*.py", name_pattern="parse_config%")
```
```
| file_path            | name         | kind     | start_line | end_line | signature                                                    |
|----------------------|--------------|----------|------------|----------|--------------------------------------------------------------|
| src/config.py        | parse_config | function | 42         | 68       | def parse_config(path: str, strict: bool = False) -> Config  |
| src/legacy/config.py | parse_config | function | 18         | 31       | def parse_config(raw: dict) -> LegacyConfig                  |
```

No text parsing. The agent gets the file, the line range, the kind, and the full signature in one call across 30 languages.

**Read code with context**

Before — sed and mental arithmetic:
```
sed -n '37,47p' src/parser.py
```

After — the agent calls `ReadLines`:
```
ReadLines(file_path="src/parser.py", lines="42", ctx="5")
```

Returns numbered lines centered on line 42 with 5 lines of context. No counting, no off-by-one errors.

**Compose queries across domains**

Before — shell pipelines, string parsing, manual correlation:
```
git diff --name-only HEAD~3 HEAD | while read f; do grep -c 'if\|elif\|for\|while' "$f"; done
```

After — the agent writes one SQL query via the `query` tool:
```sql
SELECT * FROM changed_function_summary('HEAD~3', 'HEAD', 'src/**/*.py')
```

Returns functions in recently changed files ranked by cyclomatic complexity. Code analysis + git history in one call.

**Find a markdown section**

Before — read the entire file, scan for the heading:
```
cat README.md
```

After — the agent calls `MDSection`:
```
MDSection(file_path="README.md", section_id="installation")
```

Returns just the matched section. No wasted tokens on the rest of the document.

## What's Included

Fledgling publishes 11 MCP tools:

| MCP Tool | What it does |
|----------|-------------|
| `ReadLines` | Read file lines with range, context, and filtering — replaces cat/head/tail |
| `FindDefinitions` | AST-based search for functions, classes, variables across 30 languages |
| `CodeStructure` | Top-level overview of definitions with line counts |
| `MDSection` | Read a specific markdown section by ID |
| `GitDiffSummary` | File-level change summary between revisions |
| `GitShow` | File content at a specific git revision |
| `Help` | Skill guide with macro catalog, workflows, and examples |
| `ChatSessions` | Browse Claude Code conversation sessions |
| `ChatSearch` | Full-text search across conversation messages |
| `ChatToolUsage` | Tool usage patterns across sessions |
| `ChatDetail` | Deep view of a single session |

Plus 17 query-only macros available via the SQL `query` tool — `complexity_hotspots`, `function_callers`, `module_dependencies`, `structural_diff`, `list_files`, `doc_outline`, and more. These are composable: join code structure with git history, filter by complexity, correlate across domains.

### The quiet part

Fledgling also exposes a general-purpose SQL query tool backed by the full DuckDB engine. This means your agent can query anything DuckDB can read — Parquet, CSV, JSON, and any community extension loaded before sandbox lockdown.

There are [140+ community extensions](https://duckdb.org/community_extensions/list_of_extensions): Google Sheets, Elasticsearch, HDF5 scientific data, genomics formats, web archives, and more. All accessible through one MCP server, all via SQL.

The purpose-built tools get your agent productive. The SQL layer is there when it needs to go further.

## How It Works

Fledgling is a DuckDB init script. No Python runtime, no Node, no build step. It loads extensions, defines SQL macros, publishes them as MCP tools, locks down the sandbox, and starts an MCP server.

Everything runs read-only inside a filesystem sandbox restricted to your project directory. The agent gets structured access to your code — it can't write files, make network calls, or escape the sandbox.

## Configuration

Using the launcher (recommended):

```json
{
  "mcpServers": {
    "fledgling": {
      "command": "/path/to/fledgling/bin/fledgling",
      "args": ["serve", "--profile", "analyst"],
      "env": {
        "FLEDGLING_ROOT": "/path/to/your/project"
      }
    }
  }
}
```

Or invoke DuckDB directly:

```bash
duckdb -init init/init-fledgling.sql
```

## Status

Alpha. 11 MCP tools + 17 query-only macros, all tested.

- 222 tests across 6 macro tiers + MCP integration + sandbox + profiles
- See [docs/vision/PRODUCT_SPEC.md](docs/vision/PRODUCT_SPEC.md) for the full specification

## Requirements

- [DuckDB](https://duckdb.org/) >= 1.4.4
- Community extensions are installed automatically

## Development

```bash
pip install duckdb pytest
pytest
```

## Why "Fledgling"?

From the 1996 film *Fly Away Home* — a girl raises orphaned geese and teaches them their migration route by leading them with an ultralight aircraft. The geese imprint on her, learn the path, and eventually fly it on their own.

Fledgling gives AI agents structured tools so they can learn to navigate your codebase. A fledgling is a young bird learning to fly. This tool is what gets it airborne.

## License

Apache-2.0
