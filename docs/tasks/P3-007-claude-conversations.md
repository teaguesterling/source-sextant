# P3-007: Conversation Intelligence Tools

**Status:** Complete
**Depends on:** conversations.sql macros (complete), sandbox.sql (complete)
**PR:** #17 (merged)

## Motivation

The `conversations.sql` macros (13 macros across 4 layers) were fully
implemented and tested, but no MCP tools exposed them to agents. This task
publishes 4 tools as Tier 5: Conversation Intelligence, plus integrates
conversation data loading into the init script.

Unlike other tiers that wrap DuckDB extensions, this tier uses DuckDB's
built-in JSON parsing to query Claude Code's JSONL session logs.

## Tools

| Tool | Required | Optional | Maps To |
|------|----------|----------|---------|
| ChatSessions | — | project, days, limit | `session_summary()` + WHERE |
| ChatSearch | query | role, project, days, limit | `search_messages()` + `sessions()` JOIN |
| ChatToolUsage | — | project, session_id, days, limit | `tool_frequency()` + `sessions()` JOIN |
| ChatDetail | session_id | — | `session_summary()` + `tool_frequency()` JOIN |

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `sql/tools/conversations.sql` | Created | 4 `mcp_publish_tool()` calls |
| `init-fledgling.sql` | Modified | conversations_root variable, raw_conversations bootstrap with empty fallback, load conversations.sql + tools |
| `tests/conftest.py` | Modified | Wire synthetic JSONL into mcp_server fixture |
| `tests/test_mcp_server.py` | Modified | 16 V1 tools, 4 test classes (17 test methods) |
| `tests/test_conversations.py` | Modified | TestFallbackSchema class (2 tests) |

## Design Decisions

### Snapshot-based conversation loading

Conversation data is materialized into `raw_conversations` before filesystem
lockdown. `conversations_root` is intentionally excluded from
`allowed_directories` — the data is a point-in-time snapshot. Refreshing
requires a server restart. This avoids exposing `~/.claude/projects` to the
sandbox.

### Empty-table fallback with STRUCT type

When no JSONL files exist, the init script creates an empty
`raw_conversations` with the correct column types. The `message` column must
use a STRUCT type (not bare JSON) because DuckDB resolves types through the
macro chain at definition time — `token_usage()` and `session_summary()` need
numeric types for arithmetic on `message.usage.*` fields.

### Glob depth: `/*/*.jsonl`

Matches Claude Code's current layout: `~/.claude/projects/<hash>/<session>.jsonl`.
Single-level depth is correct for now; `**/*.jsonl` would be more resilient
but potentially slower.

## Acceptance Criteria

- [x] All 4 Chat* tools discoverable via `tools/list`
- [x] ChatSessions returns sessions, supports project/days/limit filters
- [x] ChatSearch finds messages by text, supports role/project/days filters
- [x] ChatToolUsage shows tool frequency, supports project/session/days filters
- [x] ChatDetail returns session metadata + per-tool breakdown
- [x] Days filter correctly applies interval arithmetic
- [x] Empty-table fallback schema allows all macros to define without error
- [x] All macros return empty results on empty table
- [x] 180 total tests passing (including 19 new conversation tool tests)
- [x] Init script starts without error with or without JSONL data
