"""Session fixtures for integration tests: synthetic users, removed afterwards."""

from collections.abc import Iterator

import httpx2
import pytest
from support import (
    Stack,
    StackUser,
    create_user,
    delete_user,
    load_stack,
    sign_in,
    unique_email,
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
