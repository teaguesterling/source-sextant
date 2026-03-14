-- Fledgling: Diagnostics Module (dr_fledgling)
--
-- Macro-only core module for runtime diagnostics. Reports version,
-- profile, session root, loaded modules, and active extensions.
-- Surfaced through the Help tool.

-- dr_fledgling: Runtime diagnostic summary.
-- Returns key-value pairs: version, profile, root, modules, extensions.
--
-- Examples:
--   SELECT * FROM dr_fledgling();
CREATE OR REPLACE MACRO dr_fledgling() AS TABLE
    SELECT * FROM (VALUES
        ('version',    getvariable('fledgling_version')),
        ('profile',    getvariable('fledgling_profile')),
        ('root',       getvariable('session_root')),
        ('modules',    array_to_string(getvariable('fledgling_modules'), ', ')),
        ('extensions', (
            SELECT array_to_string(list(extension_name ORDER BY extension_name), ', ')
            FROM duckdb_extensions() WHERE installed AND loaded
            AND extension_name IN ('duckdb_mcp','read_lines','sitting_duck','markdown','duck_tails')
        ))
    ) AS t(key, value);
