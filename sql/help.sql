-- Fledgling: Help System Macro
--
-- Provides agent-accessible skill documentation from a materialized
-- table. Bootstraps _help_sections from the skill guide on load.

-- Bootstrap: Materialize _help_sections from the skill guide.
-- Path priority: _help_path variable > SKILL.md in current directory.
-- The installer sets _help_path to '.fledgling-help.md'.
-- init-fledgling-base.sql sets it to 'SKILL.md' (or leaves default).
CREATE TABLE IF NOT EXISTS _help_sections AS
SELECT section_id, section_path, level, title, content, start_line, end_line
FROM read_markdown_sections(
    COALESCE(getvariable('_help_path'), 'SKILL.md'),
    content_mode := 'full',
    include_content := true, include_filepath := false
);

-- help: Browse the Fledgling skill guide.
-- With no arguments, returns an outline (section IDs and titles).
-- With a section ID, returns matching sections with full content.
-- Supports path prefix matching so parent IDs return children.
--
-- Examples:
--   SELECT * FROM help();
--   SELECT * FROM help('workflows');
--   SELECT * FROM help('code-intelligence');
CREATE OR REPLACE MACRO help(target_id := NULL) AS TABLE
    SELECT
        section_id,
        title,
        level,
        CASE WHEN target_id IS NOT NULL THEN content END AS content
    FROM _help_sections
    WHERE (target_id IS NULL AND level <= 3)
       OR section_id = target_id
       OR section_path LIKE '%/' || target_id
       OR section_path LIKE '%/' || target_id || '/%'
    ORDER BY start_line;
