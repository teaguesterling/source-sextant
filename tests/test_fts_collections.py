"""Tests for named FTS collection infrastructure."""

import pytest
from conftest import PROJECT_ROOT, load_sql
from fledgling.connection import connect


@pytest.fixture
def fledgling_con():
    """Fledgling Connection with fts module loaded."""
    con = connect(root=PROJECT_ROOT, modules=["sandbox", "code", "docs", "fts"])
    return con


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


class TestCreateCollection:
    def test_creates_table(self, fledgling_con):
        fledgling_con.create_fts_collection("test_col", """
            SELECT '1' AS id, 'hello world' AS text,
                   map{'kind': 'test'} AS metadata
        """)
        count = fledgling_con.execute(
            "SELECT count(*) FROM fts.test_col"
        ).fetchone()[0]
        assert count == 1

    def test_table_has_correct_schema(self, fledgling_con):
        fledgling_con.create_fts_collection("test_col", """
            SELECT '1' AS id, 'hello world' AS text,
                   map{'kind': 'test'} AS metadata
        """)
        cols = fledgling_con.execute("DESCRIBE fts.test_col").fetchall()
        col_names = [c[0] for c in cols]
        assert "id" in col_names
        assert "text" in col_names
        assert "metadata" in col_names

    def test_updates_catalog(self, fledgling_con):
        fledgling_con.create_fts_collection("test_col", """
            SELECT '1' AS id, 'hello world' AS text,
                   map{'kind': 'test'} AS metadata
        """)
        row = fledgling_con.execute(
            "SELECT name, rebuilt_at FROM fts.collections WHERE name = 'test_col'"
        ).fetchone()
        assert row is not None
        assert row[0] == "test_col"
        assert row[1] is not None

    def test_idempotent_replace(self, fledgling_con):
        for i in range(2):
            fledgling_con.create_fts_collection("test_col", f"""
                SELECT '{i}' AS id, 'version {i}' AS text,
                       map{{'run': '{i}'}} AS metadata
            """)
        rows = fledgling_con.execute(
            "SELECT * FROM fts.test_col"
        ).fetchall()
        assert len(rows) == 1
        assert rows[0][0] == "1"

    def test_catalog_count_after_multiple_collections(self, fledgling_con):
        fledgling_con.create_fts_collection("alpha", """
            SELECT '1' AS id, 'alpha text' AS text, map{} AS metadata
        """)
        fledgling_con.create_fts_collection("beta", """
            SELECT '1' AS id, 'beta text' AS text, map{} AS metadata
        """)
        count = fledgling_con.execute(
            "SELECT count(*) FROM fts.collections"
        ).fetchone()[0]
        assert count >= 2
