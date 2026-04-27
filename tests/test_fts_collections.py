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


class TestSearchCollection:
    def test_search_returns_results(self, fledgling_con):
        fledgling_con.create_fts_collection("search_test", """
            SELECT '1' AS id, 'the quick brown fox' AS text, map{} AS metadata
            UNION ALL
            SELECT '2', 'lazy dog sleeping', map{}
            UNION ALL
            SELECT '3', 'quick fox jumping over', map{}
        """)
        results = fledgling_con.search_collection("search_test", "quick fox")
        assert len(results) > 0

    def test_search_returns_scored_rows(self, fledgling_con):
        fledgling_con.create_fts_collection("score_test", """
            SELECT '1' AS id, 'authentication login password' AS text, map{} AS metadata
            UNION ALL
            SELECT '2', 'database connection pooling', map{}
        """)
        results = fledgling_con.search_collection("score_test", "authentication")
        assert len(results) >= 1
        row = results[0]
        assert row[0] == "1"  # id
        assert row[3] is not None  # score

    def test_search_respects_limit(self, fledgling_con):
        rows_sql = " UNION ALL ".join(
            f"SELECT '{i}' AS id, 'common term repeated' AS text, map{{}} AS metadata"
            for i in range(20)
        )
        fledgling_con.create_fts_collection("limit_test", rows_sql)
        results = fledgling_con.search_collection("limit_test", "common term", limit=5)
        assert len(results) <= 5

    def test_search_empty_collection(self, fledgling_con):
        fledgling_con.create_fts_collection("empty_test", """
            SELECT '1' AS id, 'some text' AS text, map{} AS metadata
            WHERE false
        """)
        results = fledgling_con.search_collection("empty_test", "anything")
        assert results == []

    def test_search_nonexistent_collection_errors(self, fledgling_con):
        with pytest.raises(Exception):
            fledgling_con.search_collection("nonexistent", "query")


class TestContentCollectionCatalog:
    def test_rebuild_registers_content_in_catalog(self, fledgling_con):
        fledgling_con.rebuild_fts(
            docs_glob=PROJECT_ROOT + "/**/*.md",
            code_glob=PROJECT_ROOT + "/**/*.py",
        )
        row = fledgling_con.execute(
            "SELECT name, rebuilt_at FROM fts.collections WHERE name = 'content'"
        ).fetchone()
        assert row is not None
        assert row[0] == "content"
        assert row[1] is not None
