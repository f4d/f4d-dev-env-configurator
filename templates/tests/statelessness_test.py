"""
Cross-instance and restart tests. Copy into the project suite.

These are the only tests that can catch ST-* failures, because every other test
runs a single instance.

Requires the two-instance stack:  docker compose -f docker-compose.multi.yml up -d
"""
import os

import httpx
import pytest

LB = os.environ.get("LB_URL", "http://localhost:8080")
A1 = os.environ.get("APP1_URL", "http://localhost:8001")
A2 = os.environ.get("APP2_URL", "http://localhost:8002")


def test_st_cross_instance_write_then_read():
    """ST-01: write on instance 1, read on instance 2. Fails if state is in-process."""
    created = httpx.post(f"{A1}/api/v1/things", json={"name": "cross-instance"}).json()
    got = httpx.get(f"{A2}/api/v1/things/{created['id']}")
    assert got.status_code == 200, (
        "ST-01: instance 2 cannot see what instance 1 wrote. "
        "State is living in process memory."
    )


def test_st_session_survives_instance_switch():
    """ST-06: authenticate on one instance, use the session on the other."""
    tok = httpx.post(f"{A1}/api/v1/login", json={"user": "test", "password": "test"}).json()["token"]
    r = httpx.get(f"{A2}/api/v1/me", headers={"Authorization": f"Bearer {tok}"})
    assert r.status_code == 200, (
        "ST-06: session issued by instance 1 is not valid on instance 2. "
        "Sessions are in server memory."
    )


def test_st_rate_limit_is_shared():
    """ST-07: the limit is global, not per-instance. N instances must not mean N x limit."""
    limit = int(os.environ.get("RATE_LIMIT", "10"))
    codes = []
    for i in range(limit + 5):
        target = A1 if i % 2 == 0 else A2   # alternate instances
        codes.append(httpx.get(f"{target}/api/v1/limited").status_code)
    assert 429 in codes, (
        f"ST-07: sent {limit + 5} requests across two instances against a limit of "
        f"{limit} and never saw 429. The limiter is per-instance."
    )


def test_st_idempotent_write_via_load_balancer():
    """Retry through the LB may land on a different instance. Must not double-apply."""
    key = "idem-test-001"
    h = {"Idempotency-Key": key}
    a = httpx.post(f"{LB}/api/v1/things", json={"name": "x"}, headers=h).json()
    b = httpx.post(f"{LB}/api/v1/things", json={"name": "x"}, headers=h).json()
    assert a["id"] == b["id"], (
        "Retry with the same idempotency key created a second record. "
        "The key is not honored across instances."
    )


@pytest.mark.slow
def test_st_restart_loses_nothing():
    """Kill an instance mid-flow; nothing that mattered is lost."""
    created = httpx.post(f"{LB}/api/v1/things", json={"name": "survives"}).json()
    os.system("docker compose -f docker-compose.multi.yml restart app-1 >/dev/null 2>&1")
    got = httpx.get(f"{LB}/api/v1/things/{created['id']}")
    assert got.status_code == 200, "Restart lost committed state."
