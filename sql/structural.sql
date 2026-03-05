-- Fledgling: Structural Analysis Macros (sitting_duck + duck_tails)
--
-- Cross-tier macros combining AST analysis with git repository state.
-- Must load AFTER both sitting_duck and duck_tails extensions.

-- structural_diff: Compare definitions between two revisions of a file.
-- Shows which functions/classes were added, removed, or modified, with
-- complexity change signals (descendant_count, children_count).
--
-- Uses read_ast with git:// URIs to parse both revisions. Identity is
-- (name, semantic_type) — line number shifts from unrelated edits do not
-- count as modifications. Change detection uses descendant_count and
-- children_count from the AST, which reflect structural complexity
-- independent of formatting.
--
-- Requires: sitting_duck with git:// URI support (sitting_duck#48).
--
-- Examples:
--   SELECT * FROM structural_diff('src/main.py', 'HEAD~1', 'HEAD');
--   SELECT * FROM structural_diff('lib/parser.py', 'main', 'feature-branch');
CREATE OR REPLACE MACRO structural_diff(file, from_rev, to_rev, repo := '.') AS TABLE
    WITH from_defs AS (
        SELECT
            name,
            semantic_type,
            semantic_type_to_string(semantic_type) AS kind,
            end_line - start_line + 1 AS line_count,
            descendant_count,
            children_count
        FROM read_ast(git_uri(repo, file, from_rev))
        WHERE is_definition(semantic_type)
          AND depth <= 2
          AND name != ''
    ),
    to_defs AS (
        SELECT
            name,
            semantic_type,
            semantic_type_to_string(semantic_type) AS kind,
            end_line - start_line + 1 AS line_count,
            descendant_count,
            children_count
        FROM read_ast(git_uri(repo, file, to_rev))
        WHERE is_definition(semantic_type)
          AND depth <= 2
          AND name != ''
    )
    SELECT
        COALESCE(t.name, f.name) AS name,
        COALESCE(t.kind, f.kind) AS kind,
        CASE
            WHEN f.name IS NULL THEN 'added'
            WHEN t.name IS NULL THEN 'removed'
            WHEN t.descendant_count != f.descendant_count
              OR t.children_count != f.children_count THEN 'modified'
            ELSE 'unchanged'
        END AS change,
        f.line_count AS old_lines,
        t.line_count AS new_lines,
        f.descendant_count AS old_complexity,
        t.descendant_count AS new_complexity,
        COALESCE(t.descendant_count::INT, 0)
            - COALESCE(f.descendant_count::INT, 0) AS complexity_delta
    FROM to_defs t
    FULL OUTER JOIN from_defs f
        ON t.name = f.name AND t.semantic_type = f.semantic_type
    WHERE change != 'unchanged'
    ORDER BY change, name;
