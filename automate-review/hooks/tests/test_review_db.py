#!/usr/bin/env python3
"""Testes do gate de revisões (review-db.py) — unittest da stdlib, sem dependências extras."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import threading
import unittest

# O script tem um hífen no nome, então é carregado por caminho.
_HERE = os.path.dirname(os.path.abspath(__file__))
_SCRIPT_PATH = os.path.join(os.path.dirname(_HERE), "review-db.py")
_spec = importlib.util.spec_from_file_location("review_db", _SCRIPT_PATH)
review_db = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(review_db)


class SchemaTest(unittest.TestCase):
    def test_ensure_schema_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            db_path = os.path.join(tmp, "reviews.db")
            conn = review_db.connect(db_path)
            review_db.ensure_schema(conn)  # segunda chamada não deve quebrar
            tables = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='review_invocations'"
            ).fetchall()
            self.assertEqual(len(tables), 1)
            conn.close()


class CountInvocationsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.tmp.name, "reviews.db")
        self.conn = review_db.connect(self.db_path)

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def test_count_starts_at_zero(self):
        self.assertEqual(review_db.count_invocations(self.conn, "org/repo", "feature/x"), 0)

    def test_check_and_increment_increments(self):
        allowed, before, after = review_db.check_and_increment(
            self.conn, "org/repo", "feature/x", max_per_branch=3, invoked_at="2026-01-01T00:00:00"
        )
        self.assertTrue(allowed)
        self.assertEqual((before, after), (0, 1))
        self.assertEqual(review_db.count_invocations(self.conn, "org/repo", "feature/x"), 1)

    def test_isolation_between_repo_branch_pairs(self):
        review_db.check_and_increment(self.conn, "org/repo", "feature/x", 5, "t")
        review_db.check_and_increment(self.conn, "org/repo", "feature/y", 5, "t")
        review_db.check_and_increment(self.conn, "org/other", "feature/x", 5, "t")
        self.assertEqual(review_db.count_invocations(self.conn, "org/repo", "feature/x"), 1)
        self.assertEqual(review_db.count_invocations(self.conn, "org/repo", "feature/y"), 1)
        self.assertEqual(review_db.count_invocations(self.conn, "org/other", "feature/x"), 1)

    def test_gate_blocks_exactly_at_max(self):
        r1 = review_db.check_and_increment(self.conn, "org/repo", "feature/x", 2, "t")
        r2 = review_db.check_and_increment(self.conn, "org/repo", "feature/x", 2, "t")
        r3 = review_db.check_and_increment(self.conn, "org/repo", "feature/x", 2, "t")
        self.assertTrue(r1[0])
        self.assertTrue(r2[0])
        self.assertFalse(r3[0])
        self.assertEqual(review_db.count_invocations(self.conn, "org/repo", "feature/x"), 2)


class ConcurrencyTest(unittest.TestCase):
    def test_concurrent_check_and_increment_never_loses_or_duplicates(self):
        # :memory: não é compartilhável entre conexões — precisa de arquivo real em disco.
        with tempfile.TemporaryDirectory() as tmp:
            db_path = os.path.join(tmp, "reviews.db")
            n_threads = 10
            max_allowed = 4
            results = [None] * n_threads

            def worker(i):
                conn = review_db.connect(db_path)
                try:
                    allowed, _, _ = review_db.check_and_increment(
                        conn, "org/repo", "feature/x", max_allowed, f"t{i}"
                    )
                    results[i] = allowed
                finally:
                    conn.close()

            threads = [threading.Thread(target=worker, args=(i,)) for i in range(n_threads)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()

            conn = review_db.connect(db_path)
            try:
                final_count = review_db.count_invocations(conn, "org/repo", "feature/x")
            finally:
                conn.close()

            self.assertEqual(sum(1 for r in results if r), max_allowed)
            self.assertEqual(final_count, max_allowed)


class CliTest(unittest.TestCase):
    def test_check_and_increment_cli_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            db_path = os.path.join(tmp, "reviews.db")

            def run():
                return subprocess.run(
                    [
                        sys.executable, _SCRIPT_PATH, "check-and-increment",
                        "--db-path", db_path, "--repo", "org/repo", "--branch", "feature/x",
                        "--max", "1",
                    ],
                    capture_output=True, text=True,
                )

            first = run()
            self.assertEqual(first.returncode, 0)
            self.assertTrue(first.stdout.startswith("ALLOWED"))

            second = run()
            self.assertEqual(second.returncode, 2)
            self.assertTrue(second.stdout.startswith("BLOCKED"))


if __name__ == "__main__":
    unittest.main()
