# P3-009: Structural Diff — Semantic Change Analysis

**Status:** In Progress (macro implemented, blocked on sitting_duck#48 for full functionality)
**Depends on:** sitting_duck#48, sitting_duck#49, duck_tails#10

## Motivation

Fledgling's git tools (GitChanges, GitBranches, GitDiffFile, GitDiffSummary,
GitStatus) overlap heavily with jetsam (`log`, `status`, `diff`) and Claude's
built-in bash git commands. The only differentiator is SQL composability, but
nothing in the current toolset actually exploits that.

The real opportunity is **semantic change analysis** — combining duck_tails'
git filesystem with sitting_duck's AST parsing to answer "what changed
structurally?" instead of "what lines changed?" This is something neither
jetsam nor bash git can do.

## Vision

Instead of:
```
47 lines changed in parser.py
```

An agent sees:
```
name           | kind     | change   | old_lines | new_lines | old_cc | new_cc | cc_delta
parse_expr     | function | modified |        23 |        31 |      3 |      5 |       +2
TokenStream    | class    | modified |        45 |        52 |      - |      - |        -
validate_ast   | function | added    |      NULL |        18 |   NULL |      2 |       +2
```

## Proof of Concept (working)

Using `git_read` + `parse_ast` + `ast_function_metrics` to bypass
sitting_duck#48 (read_ast ignoring git:// revision suffixes):

```sql
SET VARIABLE head_content = (
    SELECT text FROM git_read(git_uri('.', $file, 'HEAD'))
);
SET VARIABLE prev_content = (
    SELECT text FROM git_read(git_uri('.', $file, $from_rev))
);

CREATE TEMP TABLE head_ast AS
    FROM parse_ast(getvariable('head_content'), 'python');
CREATE TEMP TABLE prev_ast AS
    FROM parse_ast(getvariable('prev_content'), 'python');

-- Function-level structural diff with cyclomatic complexity
WITH head_metrics AS (SELECT * FROM ast_function_metrics(head_ast)),
     prev_metrics AS (SELECT * FROM ast_function_metrics(prev_ast))
SELECT
    COALESCE(h.name, p.name) AS name,
    CASE
        WHEN p.name IS NULL THEN 'added'
        WHEN h.name IS NULL THEN 'removed'
        WHEN h.cyclomatic != p.cyclomatic
          OR h.lines != p.lines THEN 'modified'
        ELSE 'unchanged'
    END AS change,
    p.lines AS old_lines, h.lines AS new_lines,
    p.cyclomatic AS old_cc, h.cyclomatic AS new_cc,
    COALESCE(h.cyclomatic, 0) - COALESCE(p.cyclomatic, 0) AS cc_delta
FROM head_metrics h
FULL OUTER JOIN prev_metrics p ON h.name = p.name
WHERE change != 'unchanged'
ORDER BY change, name;
```

Tested on `tests/conftest.py` at HEAD vs HEAD~15. Correctly shows:
- 9 functions added (including `_create_mcp_server` CC=4, `parse_json_rows` CC=10)
- `mcp_server` modified: 66→12 lines, CC 3→1 (refactored, logic extracted)

## Key Design Decisions

### Identity: how to match definitions across revisions

Join key: `(name, semantic_type, parent_def_name, parent_def_type)`

- `name` + `semantic_type` alone is ambiguous (two classes can have methods
  with the same name)
- `start_line`/`end_line` are **not** part of identity — they shift with
  unrelated edits above
- Parent resolution requires walking past `ORGANIZATION_BLOCK` nodes to find
  the nearest definition ancestor (sitting_duck#49)

### Change detection: what counts as "modified"

Compare `ast_function_metrics` output:
- `cyclomatic` — cyclomatic complexity (conditionals + loops + 1)
- `lines` — function body line count
- `conditionals`, `loops`, `return_count` — structural detail
- `descendant_count`, `children_count` — AST node counts

Changes to `start_line`/`end_line` alone do NOT count as modified — the
function just moved.

### Parent resolution (sitting_duck#49)

Python's AST has organizational nodes between classes and methods:
`module → class → ORGANIZATION_BLOCK → method`. A recursive CTE walks
`parent_id` upward until it finds an `is_definition()` node:

```sql
WITH RECURSIVE def_parent AS (
    SELECT d.node_id, d.name AS def_name, d.semantic_type AS def_type,
           d.parent_id AS current_parent_id, 0 AS hops
    FROM ast d
    WHERE is_definition(d.semantic_type) AND d.depth >= 1
    UNION ALL
    SELECT dp.node_id, dp.def_name, dp.def_type,
           p.parent_id, dp.hops + 1
    FROM def_parent dp
    JOIN ast p ON dp.current_parent_id = p.node_id
    WHERE NOT is_definition(p.semantic_type) AND dp.hops < 10
)
SELECT dp.node_id, dp.def_name,
       p.name AS parent_def_name,
       semantic_type_to_string(p.semantic_type) AS parent_def_kind
FROM def_parent dp
JOIN ast p ON dp.current_parent_id = p.node_id
WHERE is_definition(p.semantic_type);
```

## sitting_duck Capabilities Discovered

The full `read_ast` schema is richer than what Fledgling currently exposes:

| Column | Current use | Structural diff use |
|--------|------------|-------------------|
| `node_id` | unused | tree traversal, parent joins |
| `parent_id` | unused | ancestor resolution |
| `descendant_count` | unused | coarse complexity signal |
| `children_count` | unused | structural change signal |
| `parameters` | unused | function signature changes |
| `qualified_name` | unused | NULL for Python, may help other langs |

Macro-level helpers available but not yet used in Fledgling:
- `ast_function_metrics(table)` — cyclomatic complexity, conditionals, loops
- `ast_ancestors(table, node_id)` — walk up the tree
- `ast_descendants(table, node_id)` — walk down the tree
- `ast_nesting_analysis(table)` — nesting depth analysis
- `parse_ast(text, language)` — parse inline text (no file needed)

## Git Tool Tier Restructuring

### Keep (no overlap or unique capability)
- **GitShow** — reading file content at a revision
- **GitTags** — jetsam doesn't cover tags

### Deprecate (direct overlap with jetsam)
- **GitChanges** → jetsam `log`
- **GitBranches** → jetsam branch awareness
- **GitStatus** → jetsam `status`
- **GitDiffFile** → jetsam `diff`

### Evolve
- **GitDiffSummary** → structural summary (file-level + definition-level)

### New tools
- **StructuralDiff** or **SemanticChanges** — the core AST-diff tool
- **ComplexityReport** — structural metrics across a file/tree (useful
  standalone, not just for diffs)

## Upstream Dependencies

| Issue | Repo | What | Impact |
|-------|------|------|--------|
| [#48](https://github.com/teaguesterling/sitting_duck/issues/48) | sitting_duck | `read_ast` ignores `@rev` in git:// URIs | Blocker for clean API; workaround exists via `git_read` + `parse_ast` |
| [#49](https://github.com/teaguesterling/sitting_duck/issues/49) | sitting_duck | `ast_definition_parent` macro | Enhancement; recursive CTE workaround exists |
| [#10](https://github.com/teaguesterling/duck_tails/issues/10) | duck_tails | Working tree diff (modified file detection) | Needed for "what changed since last commit" |

## Implementation

### Macro: `structural_diff(file, from_rev, to_rev, repo)`

Implemented in `sql/structural.sql` as a cross-tier macro (requires both
sitting_duck and duck_tails). Uses `read_ast(git_uri(...))` which composes
cleanly in a single CTE — no temp tables, no variables, fits the duckdb_mcp
single-statement constraint.

Loaded after both `code.sql` and `repo.sql` in `init-fledgling-base.sql`.

### Tests

`tests/test_structural.py` with `structural_macros` fixture (both extensions).
- 2 passing: column schema, unchanged filtering
- 3 xfail (sitting_duck#48): added/modified detection, complexity delta signs

### Macro design note

The initial POC used `SET VARIABLE` + `CREATE TEMP TABLE` + `parse_ast` to
work around sitting_duck#48. That approach cannot be a macro (multi-statement)
or a duckdb_mcp tool template (single-statement only). The clean implementation
uses `read_ast(git_uri(...))` directly, which will work correctly once #48 is
fixed upstream. No workaround needed in the macro layer.

## Future: Documentation Bundling

Ship sitting_duck and duck_tails docs with Fledgling so agents have API
references available in the sandbox (where `enable_external_access = false`).
Approach: sparse-checkout git submodules, materialized at deploy time. Agents
access via Fledgling's `read_markdown` tooling (MDOutline, MDSection).
