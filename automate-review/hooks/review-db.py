#!/usr/bin/env python3
"""
Gate de revisões automatizadas por (repositório, branch) — persistido em SQLite.

Cada invocação real da revisão automatizada vira uma linha em
review_invocations; a contagem por (repo, branch) é COUNT(*), então cada
linha já serve de auditoria mínima (quando, qual commit, qual PR).

Uso:
    review-db.py check-and-increment --db-path P --repo R --branch B --max N
        [--commit-sha S] [--pr-url U] [--invoked-at T]
    review-db.py count --db-path P --repo R --branch B
"""

import argparse
import os
import sqlite3
import sys
from datetime import datetime

SCHEMA = """
CREATE TABLE IF NOT EXISTS review_invocations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  repo        TEXT NOT NULL,
  branch      TEXT NOT NULL,
  invoked_at  TEXT NOT NULL,
  commit_sha  TEXT,
  pr_url      TEXT
);
CREATE INDEX IF NOT EXISTS idx_review_invocations_repo_branch
  ON review_invocations (repo, branch);
"""


def now_iso() -> str:
    """Timestamp ISO-8601 com offset, no mesmo padrão de `date -Iseconds`."""
    return datetime.now().astimezone().isoformat(timespec="seconds")


def ensure_schema(conn: sqlite3.Connection) -> None:
    """CREATE TABLE/INDEX IF NOT EXISTS — idempotente."""
    conn.executescript(SCHEMA)


def connect(db_path: str) -> sqlite3.Connection:
    """Abre em modo autocommit (isolation_level=None) para controlar a
    transação manualmente com BEGIN IMMEDIATE. `timeout` alto faz conexões
    concorrentes ESPERAREM o lock em vez de falhar na hora."""
    parent = os.path.dirname(db_path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    conn = sqlite3.connect(db_path, isolation_level=None, timeout=30)
    ensure_schema(conn)
    return conn


def count_invocations(conn: sqlite3.Connection, repo: str, branch: str) -> int:
    """Quantidade de invocações já registradas para (repo, branch)."""
    row = conn.execute(
        "SELECT COUNT(*) FROM review_invocations WHERE repo = ? AND branch = ?",
        (repo, branch),
    ).fetchone()
    return row[0]


def check_and_increment(
    conn: sqlite3.Connection,
    repo: str,
    branch: str,
    max_per_branch: int,
    invoked_at: str,
    commit_sha: str = None,
    pr_url: str = None,
):
    """Núcleo do gate, atômico. Retorna (allowed, count_before, count_after).

    BEGIN IMMEDIATE adquire o lock de escrita IMEDIATAMENTE (RESERVED), não
    no primeiro write como uma transação DEFERRED normal faria — evita o
    clássico deadlock do SQLite em que duas conexões fazem SELECT (lock
    compartilhado) e depois as duas tentam promover pra escrita ao mesmo
    tempo. Com BEGIN IMMEDIATE, a segunda chamada concorrente bloqueia aqui
    (até o `timeout` de connect()) e só prossegue depois que a primeira faz
    COMMIT — lendo então a contagem já atualizada. É isso que garante que
    duas invocações "simultâneas" (dois pushes rápidos na mesma repo+branch,
    dois pollers em paralelo) não perdem contagem nem estouram o limite por
    corrida.
    """
    conn.execute("BEGIN IMMEDIATE")
    try:
        count_before = count_invocations(conn, repo, branch)
        if count_before >= max_per_branch:
            conn.execute("COMMIT")
            return False, count_before, count_before
        conn.execute(
            "INSERT INTO review_invocations (repo, branch, invoked_at, commit_sha, pr_url)"
            " VALUES (?, ?, ?, ?, ?)",
            (repo, branch, invoked_at, commit_sha, pr_url),
        )
        conn.execute("COMMIT")
        return True, count_before, count_before + 1
    except Exception:
        conn.execute("ROLLBACK")
        raise


def _cmd_check_and_increment(args: argparse.Namespace) -> int:
    conn = connect(args.db_path)
    try:
        allowed, count_before, count_after = check_and_increment(
            conn,
            args.repo,
            args.branch,
            args.max,
            args.invoked_at or now_iso(),
            commit_sha=args.commit_sha,
            pr_url=args.pr_url,
        )
    finally:
        conn.close()

    if allowed:
        print(f"ALLOWED {count_after} {args.max}")
        return 0
    print(f"BLOCKED {count_before} {args.max}")
    return 2


def _cmd_count(args: argparse.Namespace) -> int:
    conn = connect(args.db_path)
    try:
        print(count_invocations(conn, args.repo, args.branch))
    finally:
        conn.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Gate de revisões automatizadas (SQLite)")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    check = subparsers.add_parser("check-and-increment")
    check.add_argument("--db-path", required=True)
    check.add_argument("--repo", required=True)
    check.add_argument("--branch", required=True)
    check.add_argument("--max", type=int, required=True)
    check.add_argument("--commit-sha", default=None)
    check.add_argument("--pr-url", default=None)
    check.add_argument("--invoked-at", default=None)
    check.set_defaults(func=_cmd_check_and_increment)

    count = subparsers.add_parser("count")
    count.add_argument("--db-path", required=True)
    count.add_argument("--repo", required=True)
    count.add_argument("--branch", required=True)
    count.set_defaults(func=_cmd_count)

    args = parser.parse_args()
    try:
        return args.func(args)
    except Exception as e:
        print(f"Erro ao acessar o banco de gate: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
