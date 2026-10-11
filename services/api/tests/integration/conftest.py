"""Session fixtures for integration tests: synthetic users and a temporary
owner-scoped table and private bucket, all removed afterwards."""

import uuid
from collections.abc import Iterator

import httpx2
import pytest
from support import (
    Stack,
    StackUser,
    create_user,
    delete_user,
    do_block,
    load_stack,
    run_sql,
    sign_in,
    unique_email,
    wait_until_exposed,
)


@pytest.fixture(scope="session")
def stack() -> Stack:
    return load_stack()


@pytest.fixture(scope="session")
def http() -> Iterator[httpx2.Client]:
    with httpx2.Client(timeout=15, trust_env=False) as client:
        yield client


@pytest.fixture(scope="session")
def provisioned(http: httpx2.Client, stack: Stack) -> Iterator[list[str]]:
    """Collects user IDs created by tests; all are deleted at the end."""
    user_ids: list[str] = []
    yield user_ids
    for user_id in user_ids:
        delete_user(http, stack, user_id)


@pytest.fixture(scope="session")
def user_a(http: httpx2.Client, stack: Stack, provisioned: list[str]) -> StackUser:
    email = unique_email("user-a")
    provisioned.append(create_user(http, stack, email))
    return sign_in(http, stack, email)


@pytest.fixture(scope="session")
def user_b(http: httpx2.Client, stack: Stack, provisioned: list[str]) -> StackUser:
    email = unique_email("user-b")
    provisioned.append(create_user(http, stack, email))
    return sign_in(http, stack, email)


@pytest.fixture(scope="session")
def fixture_table(http: httpx2.Client, stack: Stack, user_a: StackUser) -> Iterator[str]:
    """A temporary owner-scoped table with RLS and explicit grants."""
    table = f"isolation_fixture_{uuid.uuid4().hex[:8]}"
    own = "(select auth.uid()) = owner_id"
    statements = [
        f"create table public.{table} ("
        " id uuid primary key default gen_random_uuid(),"
        " owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,"
        " note text not null)",
        f"alter table public.{table} enable row level security",
        f"revoke all on public.{table} from anon, authenticated",
        f"grant select, insert, update, delete on public.{table} to authenticated",
        # Lets fixture helpers check what is really stored; never used by code under test.
        f"grant select on public.{table} to service_role",
        f"create policy select_own on public.{table} for select to authenticated using ({own})",
        f"create policy insert_own on public.{table} for insert to authenticated"
        f" with check ({own})",
        f"create policy update_own on public.{table} for update to authenticated"
        f" using ({own}) with check ({own})",
        f"create policy delete_own on public.{table} for delete to authenticated using ({own})",
        "perform pg_notify('pgrst', 'reload schema')",
    ]
    run_sql(stack, do_block(statements))
    wait_until_exposed(http, stack, user_a, table)
    yield table
    run_sql(
        stack,
        do_block([f"drop table public.{table}", "perform pg_notify('pgrst', 'reload schema')"]),
    )


@pytest.fixture(scope="session")
def fixture_bucket(http: httpx2.Client, stack: Stack) -> Iterator[str]:
    """A temporary private bucket; users may only touch `<their uid>/...`."""
    bucket = f"isolation-{uuid.uuid4().hex[:8]}"
    own_folder = (
        f"bucket_id = '{bucket}' and (storage.foldername(name))[1] = (select auth.uid())::text"
    )
    policies = {
        f"{bucket}_select": f"for select to authenticated using ({own_folder})",
        f"{bucket}_insert": f"for insert to authenticated with check ({own_folder})",
        f"{bucket}_update": f"for update to authenticated using ({own_folder})"
        f" with check ({own_folder})",
        f"{bucket}_delete": f"for delete to authenticated using ({own_folder})",
    }
    run_sql(
        stack,
        do_block(
            [
                "insert into storage.buckets (id, name, public)"
                f" values ('{bucket}', '{bucket}', false)",
                *(
                    f'create policy "{name}" on storage.objects {rule}'
                    for name, rule in policies.items()
                ),
            ]
        ),
    )
    yield bucket
    http.post(f"{stack.url}/storage/v1/bucket/{bucket}/empty", headers=stack.admin_headers())
    http.delete(f"{stack.url}/storage/v1/bucket/{bucket}", headers=stack.admin_headers())
    run_sql(
        stack,
        do_block([f'drop policy "{name}" on storage.objects' for name in policies]),
    )
