#!/usr/bin/env python3
"""Evaluate representative BGP community inputs against the rendered R1 policy."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


COMMUNITY_LIST_RE = re.compile(
    r"^add list=(community-(?:isp|ren)-(?:adjacent-origin|transit-learned)) communities=([^\s]+)$"
)
POLICY_RE = re.compile(
    r'^add chain=bgp-in-(isp|ren) rule=".*?bgp-communities equal-list '
    r'(community-(?:isp|ren)-(?:adjacent-origin|transit-learned))\) \{ set bgp-local-pref '
    r'(\d+); accept \}"$'
)


def parse_policy(config_path: Path) -> dict[tuple[str, frozenset[str]], int]:
    community_lists: dict[str, frozenset[str]] = {}
    policies: dict[tuple[str, frozenset[str]], int] = {}

    for raw_line in config_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        community_match = COMMUNITY_LIST_RE.match(line)
        if community_match:
            name, values = community_match.groups()
            community_lists[name] = frozenset(values.split(","))
            continue

        policy_match = POLICY_RE.match(line)
        if policy_match:
            peer, list_name, local_pref = policy_match.groups()
            if list_name not in community_lists:
                raise AssertionError(
                    f"policy references community list before declaration: {list_name}"
                )
            policies[(peer, community_lists[list_name])] = int(local_pref)

    expected_lists = {
        "community-isp-adjacent-origin": frozenset({"65000:10", "65000:0"}),
        "community-isp-transit-learned": frozenset({"65000:10", "65000:99"}),
        "community-ren-adjacent-origin": frozenset({"65000:20", "65000:0"}),
        "community-ren-transit-learned": frozenset({"65000:20", "65000:99"}),
    }
    assert community_lists == expected_lists, community_lists
    return policies


def evaluate(
    fixture: dict[str, object],
    policy: dict[tuple[str, frozenset[str]], int],
) -> tuple[str, int | None]:
    communities = frozenset(fixture["communities"])
    if not communities:
        return "accept", 100
    local_pref = policy.get((str(fixture["peer"]), communities))
    if local_pref is None:
        return "reject", None
    return "accept", local_pref


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--config", type=Path, default=Path("configs/routeros/r1.rsc")
    )
    parser.add_argument(
        "--fixtures", type=Path, default=Path("tests/fixtures/community-policy.json")
    )
    args = parser.parse_args()

    policy = parse_policy(args.config)
    fixtures = json.loads(args.fixtures.read_text(encoding="utf-8"))
    for fixture in fixtures:
        actual = evaluate(fixture, policy)
        expected = (fixture["expected"], fixture["local_pref"])
        assert actual == expected, f"{fixture['name']}: {actual} != {expected}"

    print("Community policy fixtures passed.")


if __name__ == "__main__":
    main()
