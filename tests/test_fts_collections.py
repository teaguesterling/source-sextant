"""Tests for named FTS collection infrastructure."""

import pytest
from conftest import PROJECT_ROOT, load_sql


class TestCatalog:
    def test_catalog_table_exists(self, fts_macros):
        tables = fts_macros.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'fts' AND table_name = 'collections'"
        ).fetchall()
        assert len(tables) == 1

    def test_catalog_columns(self, fts_macros):
        cols = fts_macros.execute(
            "DESCRIBE fts.collections"
        ).fetchall()
        col_names = [c[0] for c in cols]
        assert "name" in col_names
        assert "created_at" in col_names
        assert "rebuilt_at" in col_names

    def test_catalog_starts_empty(self, fts_macros):
        count = fts_macros.execute(
            "SELECT count(*) FROM fts.collections"
        ).fetchone()[0]
        assert count == 0
