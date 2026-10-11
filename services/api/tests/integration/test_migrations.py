"""T003-AC10: product migrations are recorded, and applying them again is a
no-op that keeps existing accounts and data."""

import subprocess
from pathlib import Path

import pytest
from support import Stack, StackUser, query_sql

pytestmark = pytest.mark.integration

MIGRATIONS = Path(__file__).resolve().parents[4] / "supabase" / "migrations"


def test_every_migration_file_is_applied(stack: Stack) -> None:
    files = sorted(path.name.split("_", 1)[0] for path in MIGRATIONS.glob("*.sql"))
    applied = query_sql(
        stack, "select version from supabase_migrations.schema_migrations order by version"
    )

    assert files
    assert [row["version"] for row in applied] == files


def test_reapplying_migrations_changes_nothing(stack: Stack, user_a: StackUser) -> None:
    def snapshot() -> list[dict[str, object]]:
        return query_sql(
            stack,
            "select (select count(*) from auth.users) as users,"
            " (select count(*) from public.ideas) as ideas,"
            " (select count(*) from public.sources) as sources",
        )

    before = snapshot()
    result = subprocess.run(  # noqa: S603 - fixed binary from the Makefile, local stack only
        [stack.supabase_bin, "migration", "up", "--local", "--agent", "no"],
        check=True,
        capture_output=True,
        text=True,
        timeout=120,
    )

    assert "up to date" in (result.stdout + result.stderr)
    assert snapshot() == before
