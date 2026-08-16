#!/usr/bin/env python3
"""Generate deterministic synthetic BGP announcements for the lab.

The generated prefixes are intentionally control-plane test routes.  They are
inside a documentation/lab-only pool and are not expected to have a usable
destination behind ISP or REN.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from dataclasses import dataclass
from enum import Enum
from ipaddress import IPv4Address, IPv4Network, ip_network
from pathlib import Path
from typing import Sequence


DEFAULT_SEED = 20260812
DEFAULT_POOL = "10.64.0.0/10"
DEFAULT_ISP_COUNT = 500
DEFAULT_ISP_TRANSIT_LEARNED_COUNT = 100
DEFAULT_REN_COUNT = 200
DEFAULT_REN_ADJACENT_ORIGIN_COUNT = 100
DEFAULT_REN_TRANSIT_LEARNED_COUNT = 100
DEFAULT_SHARED_COUNT = 50
DEFAULT_MIN_PREFIX_LENGTH = 16
DEFAULT_MAX_PREFIX_LENGTH = 24
MAX_ISP_COUNT = 500
MAX_REN_COUNT = 200

CAMPUS_AS = 65000
ISP_AS = 65001
REN_AS = 65002
ISP_TRANSIT_NEIGHBORS = tuple(range(65010, 65016))
REN_TRANSIT_NEIGHBORS = tuple(range(65020, 65023))
PRIVATE_ASN_MIN = 64512
PRIVATE_ASN_MAX = 65534
RESERVED_ASNS = frozenset(
    {
        CAMPUS_AS,
        ISP_AS,
        REN_AS,
        *ISP_TRANSIT_NEIGHBORS,
        *REN_TRANSIT_NEIGHBORS,
    }
)
GENERATED_ASNS = tuple(
    asn
    for asn in range(PRIVATE_ASN_MIN, PRIVATE_ASN_MAX + 1)
    if asn not in RESERVED_ASNS
)
ISP_SOURCE_COMMUNITY = f"{CAMPUS_AS}:10"
REN_SOURCE_COMMUNITY = f"{CAMPUS_AS}:20"
ADJACENT_ORIGIN_COMMUNITY = f"{CAMPUS_AS}:0"
TRANSIT_LEARNED_COMMUNITY = f"{CAMPUS_AS}:99"

# Smaller prefixes are deliberately more common.  This makes a large route
# set practical while still exercising a range from /16 through /24.
PREFIX_LENGTHS = tuple(range(DEFAULT_MIN_PREFIX_LENGTH, DEFAULT_MAX_PREFIX_LENGTH + 1))
PREFIX_WEIGHTS = (1, 1, 2, 3, 5, 8, 14, 25, 41)

class PathClass(str, Enum):
    ADJACENT_ORIGIN = "adjacent-origin"
    TRANSIT_LEARNED = "transit-learned"

    @property
    def community(self) -> str:
        if self is PathClass.ADJACENT_ORIGIN:
            return ADJACENT_ORIGIN_COMMUNITY
        return TRANSIT_LEARNED_COMMUNITY


class RouteCategory(str, Enum):
    ISP_ADJACENT_ORIGIN = "isp-adjacent-origin"
    ISP_TRANSIT_LEARNED = "isp-transit-learned"
    REN_ADJACENT_ORIGIN = "ren-adjacent-origin"
    REN_TRANSIT_LEARNED = "ren-transit-learned"

    @property
    def path_class(self) -> PathClass:
        if self in {
            RouteCategory.ISP_ADJACENT_ORIGIN,
            RouteCategory.REN_ADJACENT_ORIGIN,
        }:
            return PathClass.ADJACENT_ORIGIN
        return PathClass.TRANSIT_LEARNED

    @property
    def speaker_as(self) -> int:
        if self in {
            RouteCategory.ISP_ADJACENT_ORIGIN,
            RouteCategory.ISP_TRANSIT_LEARNED,
        }:
            return ISP_AS
        return REN_AS

    @property
    def transit_neighbors(self) -> tuple[int, ...]:
        if self is RouteCategory.ISP_TRANSIT_LEARNED:
            return ISP_TRANSIT_NEIGHBORS
        if self is RouteCategory.REN_TRANSIT_LEARNED:
            return REN_TRANSIT_NEIGHBORS
        return ()

    @property
    def source_community(self) -> str:
        if self in {
            RouteCategory.ISP_ADJACENT_ORIGIN,
            RouteCategory.ISP_TRANSIT_LEARNED,
        }:
            return ISP_SOURCE_COMMUNITY
        return REN_SOURCE_COMMUNITY


@dataclass(frozen=True)
class SyntheticRoute:
    prefix: IPv4Network
    shared: bool
    source_category: RouteCategory
    transit_neighbor: int | None
    origin_as: int
    as_path_tail: tuple[int, ...]
    expected_as_path: tuple[int, ...]
    communities: tuple[str, ...]

    def to_manifest(self) -> dict[str, object]:
        return {
            "prefix": str(self.prefix),
            "shared": self.shared,
            "source_category": self.source_category.value,
            "path_class": self.source_category.path_class.value,
            "transit_neighbor": self.transit_neighbor,
            "origin_as": self.origin_as,
            "path_depth": len(self.expected_as_path),
            "as_path_tail": list(self.as_path_tail),
            "communities": list(self.communities),
            "expected_as_path": list(self.expected_as_path),
        }


@dataclass(frozen=True)
class SpeakerConfig:
    name: str
    local_address: str
    peer_address: str
    router_id: str
    local_as: int
    peer_as: int
    md5: str


@dataclass(frozen=True)
class RouteBudget:
    adjacent_origin: int
    transit_learned: int


@dataclass(frozen=True)
class RouteCounts:
    isp: int
    ren: int
    isp_adjacent_origin: int
    isp_transit_learned: int
    ren_adjacent_origin: int
    ren_transit_learned: int
    shared: int
    shared_isp_adjacent_origin: int
    shared_isp_transit_learned: int
    shared_ren_adjacent_origin: int
    shared_ren_transit_learned: int

    def to_manifest(self) -> dict[str, int]:
        return {
            "isp": self.isp,
            "ren": self.ren,
            "isp_adjacent_origin": self.isp_adjacent_origin,
            "isp_transit_learned": self.isp_transit_learned,
            "ren_adjacent_origin": self.ren_adjacent_origin,
            "ren_transit_learned": self.ren_transit_learned,
            "shared": self.shared,
            "shared_isp_adjacent_origin": self.shared_isp_adjacent_origin,
            "shared_isp_transit_learned": self.shared_isp_transit_learned,
            "shared_ren_adjacent_origin": self.shared_ren_adjacent_origin,
            "shared_ren_transit_learned": self.shared_ren_transit_learned,
        }


@dataclass(frozen=True)
class AsnPlan:
    campus: int
    isp: int
    ren: int
    isp_transit_neighbors: tuple[int, ...]
    ren_transit_neighbors: tuple[int, ...]

    def to_manifest(self) -> dict[str, object]:
        return {
            "campus": self.campus,
            "isp": self.isp,
            "ren": self.ren,
            "isp_transit_neighbors": list(self.isp_transit_neighbors),
            "ren_transit_neighbors": list(self.ren_transit_neighbors),
            "generated_asn_range": [PRIVATE_ASN_MIN, PRIVATE_ASN_MAX],
        }


@dataclass(frozen=True)
class LabManifest:
    seed: int
    pool: IPv4Network
    counts: RouteCounts
    asns: AsnPlan
    isp_routes: tuple[SyntheticRoute, ...]
    ren_routes: tuple[SyntheticRoute, ...]

    def to_dict(self) -> dict[str, object]:
        return {
            "schema": 2,
            "seed": self.seed,
            "pool": str(self.pool),
            "prefix_length_range": [
                DEFAULT_MIN_PREFIX_LENGTH,
                DEFAULT_MAX_PREFIX_LENGTH,
            ],
            "counts": self.counts.to_manifest(),
            "asns": self.asns.to_manifest(),
            "routes": {
                "isp": [route.to_manifest() for route in self.isp_routes],
                "ren": [route.to_manifest() for route in self.ren_routes],
            },
        }


ISP_SPEAKER = SpeakerConfig(
    name="ISP",
    local_address="10.255.2.2",
    peer_address="10.255.2.1",
    router_id="10.255.2.2",
    local_as=ISP_AS,
    peer_as=CAMPUS_AS,
    md5="campus-isp-ebgp",
)
REN_SPEAKER = SpeakerConfig(
    name="REN",
    local_address="10.255.2.6",
    peer_address="10.255.2.5",
    router_id="10.255.2.6",
    local_as=REN_AS,
    peer_as=CAMPUS_AS,
    md5="campus-ren-ebgp",
)


def _static_route_lines(routes: Sequence[SyntheticRoute]) -> list[str]:
    lines = []
    for route in routes:
        prefix = route.prefix
        tail = route.as_path_tail
        attributes = [
            f"        route {prefix} {{",
            "            next-hop self;",
        ]
        if tail:
            attributes.append(
                f"            as-path [ {' '.join(str(asn) for asn in tail)} ];"
            )
        attributes.extend(
            [
                f"            community [ {' '.join(route.communities)} ];",
                "        }",
            ]
        )
        lines.extend(attributes)
    return lines


def _exabgp_config(
    speaker: SpeakerConfig,
    routes: Sequence[SyntheticRoute],
) -> str:
    lines = [
        "# Generated file; run `make generate` to reproduce it.",
        f"# speaker={speaker.name} local-as={speaker.local_as} route-count={len(routes)}",
        "",
        f"neighbor {speaker.peer_address} {{",
        f"    router-id {speaker.router_id};",
        f"    local-address {speaker.local_address};",
        f"    local-as {speaker.local_as};",
        f"    peer-as {speaker.peer_as};",
        "    hold-time 30;",
        "    adj-rib-out true;",
        f'    md5-password "{speaker.md5}";',
        "    family {",
        "        ipv4 unicast;",
        "    }",
        "    static {",
        *_static_route_lines(routes),
        "    }",
        "}",
        "",
    ]
    return "\n".join(lines)


def _candidate_network(
    pool: IPv4Network,
    prefix_length: int,
    slot: int,
) -> IPv4Network:
    block_size = 1 << (32 - prefix_length)
    address = IPv4Address(int(pool.network_address) + slot * block_size)
    return ip_network(f"{address}/{prefix_length}")


def _candidate_slot_count(pool: IPv4Network, prefix_length: int) -> int:
    return pool.num_addresses // (1 << (32 - prefix_length))


def _candidate_if_available(
    pool: IPv4Network,
    prefix_length: int,
    slot: int,
    allocated: Sequence[IPv4Network],
) -> IPv4Network | None:
    candidate = _candidate_network(pool, prefix_length, slot)
    if not candidate.subnet_of(pool) or any(
        candidate.overlaps(existing) for existing in allocated
    ):
        return None
    return candidate


def _allocate_prefixes(
    rng: random.Random,
    pool: IPv4Network,
    count: int,
) -> list[IPv4Network]:
    """Allocate non-overlapping networks with a deterministic fallback scan."""

    if count == 0:
        return []

    lengths = PREFIX_LENGTHS

    allocated: list[IPv4Network] = []
    max_random_attempts = max(5000, count * 100)
    for _ in range(count):
        found = None
        # With the default scale, guarantee that every requested prefix
        # length is represented at least once.  The remaining allocations
        # retain the weighted random distribution.
        forced_length = (
            lengths[len(allocated)]
            if len(allocated) < len(lengths) and count >= len(lengths)
            else None
        )
        for _attempt in range(max_random_attempts):
            prefix_length = forced_length or rng.choices(
                lengths,
                weights=PREFIX_WEIGHTS,
                k=1,
            )[0]
            found = _candidate_if_available(
                pool,
                prefix_length,
                rng.randrange(_candidate_slot_count(pool, prefix_length)),
                allocated,
            )
            if found is not None:
                break

        if found is None:
            # Fragmentation can make random allocation inefficient near the
            # end of a set.  Scan from /max to /min so a free small block is
            # always preferred before trying a larger block.
            for prefix_length in reversed(PREFIX_LENGTHS):
                for slot in range(_candidate_slot_count(pool, prefix_length)):
                    found = _candidate_if_available(
                        pool,
                        prefix_length,
                        slot,
                        allocated,
                    )
                    if found is not None:
                        break
                if found is not None:
                    break

        if found is None:
            raise ValueError(
                f"could not allocate prefix {len(allocated) + 1} from {pool} "
                f"within /{DEFAULT_MIN_PREFIX_LENGTH}-/{DEFAULT_MAX_PREFIX_LENGTH}"
            )
        allocated.append(found)

    return allocated


def _route(
    prefix: IPv4Network,
    category: RouteCategory,
    shared: bool,
    as_path_tail: tuple[int, ...],
    transit_neighbor: int | None,
) -> SyntheticRoute:
    return SyntheticRoute(
        prefix=prefix,
        shared=shared,
        source_category=category,
        transit_neighbor=transit_neighbor,
        origin_as=as_path_tail[-1],
        as_path_tail=as_path_tail,
        expected_as_path=(category.speaker_as, *as_path_tail),
        communities=(category.source_community, category.path_class.community),
    )


def _balanced_choices(
    rng: random.Random,
    choices: Sequence[int],
    count: int,
) -> list[int]:
    selected: list[int] = []
    while len(selected) < count:
        cycle = list(choices)
        rng.shuffle(cycle)
        selected.extend(cycle)
    return selected[:count]


def _path_profiles(
    seed: int,
    category: RouteCategory,
    count: int,
) -> list[tuple[tuple[int, ...], int | None]]:
    asn_rng = random.Random(f"{seed}:{category.value}:generated-asns")
    if category.path_class is PathClass.ADJACENT_ORIGIN:
        return [((asn_rng.choice(GENERATED_ASNS),), None) for _ in range(count)]

    neighbor_rng = random.Random(f"{seed}:{category.value}:transit-neighbors")
    depth_rng = random.Random(f"{seed}:{category.value}:path-depths")
    neighbors = _balanced_choices(neighbor_rng, category.transit_neighbors, count)
    depths = _balanced_choices(depth_rng, range(3, 7), count)
    profiles = []
    for neighbor, depth in zip(neighbors, depths, strict=True):
        generated_asns = asn_rng.sample(GENERATED_ASNS, depth - 2)
        profiles.append(((neighbor, *generated_asns), neighbor))
    return profiles


def _category_routes(
    *,
    seed: int,
    category: RouteCategory,
    shared_prefixes: Sequence[IPv4Network],
    unique_prefixes: Sequence[IPv4Network],
) -> list[SyntheticRoute]:
    route_inputs = [
        *((prefix, True) for prefix in shared_prefixes),
        *((prefix, False) for prefix in unique_prefixes),
    ]
    profiles = _path_profiles(seed, category, len(route_inputs))
    return [
        _route(prefix, category, shared, as_path_tail, transit_neighbor)
        for (prefix, shared), (as_path_tail, transit_neighbor) in zip(
            route_inputs,
            profiles,
            strict=True,
        )
    ]


def generate(
    *,
    seed: int = DEFAULT_SEED,
    isp_count: int = DEFAULT_ISP_COUNT,
    isp_transit_learned_count: int = DEFAULT_ISP_TRANSIT_LEARNED_COUNT,
    ren_count: int = DEFAULT_REN_COUNT,
    ren_adjacent_origin_count: int = DEFAULT_REN_ADJACENT_ORIGIN_COUNT,
    ren_transit_learned_count: int = DEFAULT_REN_TRANSIT_LEARNED_COUNT,
    shared_count: int = DEFAULT_SHARED_COUNT,
) -> LabManifest:
    pool = DEFAULT_POOL
    for name, value in (
        ("isp_count", isp_count),
        ("isp_transit_learned_count", isp_transit_learned_count),
        ("ren_count", ren_count),
        ("ren_adjacent_origin_count", ren_adjacent_origin_count),
        ("ren_transit_learned_count", ren_transit_learned_count),
        ("shared_count", shared_count),
    ):
        if value < 0:
            raise ValueError(f"{name} must be non-negative")
    if isp_transit_learned_count > isp_count:
        raise ValueError("isp_transit_learned_count must not exceed isp_count")
    if ren_adjacent_origin_count + ren_transit_learned_count != ren_count:
        raise ValueError(
            "ren_adjacent_origin_count + ren_transit_learned_count "
            "must equal ren_count"
        )
    if isp_count > MAX_ISP_COUNT:
        raise ValueError(f"isp_count must not exceed {MAX_ISP_COUNT}")
    if ren_count > MAX_REN_COUNT:
        raise ValueError(f"ren_count must not exceed {MAX_REN_COUNT}")
    if shared_count > isp_count or shared_count > ren_count:
        raise ValueError("shared_count cannot exceed either advertisement count")

    pool_network = ip_network(pool)
    total_unique = isp_count + ren_count - shared_count
    rng = random.Random(seed)
    prefixes = _allocate_prefixes(
        rng,
        pool_network,
        total_unique,
    )

    shared_prefixes = prefixes[:shared_count]
    isp_unique_end = shared_count + (isp_count - shared_count)
    isp_unique_prefixes = prefixes[shared_count:isp_unique_end]
    ren_unique_prefixes = prefixes[isp_unique_end:]

    isp_budget = RouteBudget(
        adjacent_origin=isp_count - isp_transit_learned_count,
        transit_learned=isp_transit_learned_count,
    )
    ren_budget = RouteBudget(
        adjacent_origin=ren_adjacent_origin_count,
        transit_learned=ren_transit_learned_count,
    )
    shared_adjacent_origin_minimum = max(
        0,
        shared_count - isp_budget.transit_learned,
        shared_count - ren_budget.transit_learned,
    )
    shared_adjacent_origin_maximum = min(
        shared_count,
        isp_budget.adjacent_origin,
        ren_budget.adjacent_origin,
    )
    if shared_adjacent_origin_minimum > shared_adjacent_origin_maximum:
        raise ValueError(
            "shared route adjacent-origin/transit-learned budgets cannot use "
            "one path-class split at both speakers"
        )
    shared_adjacent_origin_count = min(
        shared_adjacent_origin_maximum,
        max(shared_adjacent_origin_minimum, shared_count // 2),
    )
    shared_isp_adjacent_origin_count = shared_adjacent_origin_count
    shared_ren_adjacent_origin_count = shared_adjacent_origin_count
    shared_isp_adjacent_origin_prefixes = shared_prefixes[
        :shared_isp_adjacent_origin_count
    ]
    shared_isp_transit_learned_prefixes = shared_prefixes[
        shared_isp_adjacent_origin_count:
    ]
    shared_ren_adjacent_origin_prefixes = shared_prefixes[
        :shared_ren_adjacent_origin_count
    ]
    shared_ren_transit_learned_prefixes = shared_prefixes[
        shared_ren_adjacent_origin_count:
    ]

    isp_adjacent_origin_unique_count = (
        isp_budget.adjacent_origin - shared_isp_adjacent_origin_count
    )
    isp_adjacent_origin_unique_prefixes = isp_unique_prefixes[
        :isp_adjacent_origin_unique_count
    ]
    isp_transit_learned_unique_prefixes = isp_unique_prefixes[
        isp_adjacent_origin_unique_count:
    ]
    ren_adjacent_origin_unique_count = (
        ren_budget.adjacent_origin - shared_ren_adjacent_origin_count
    )
    ren_adjacent_origin_unique_prefixes = ren_unique_prefixes[
        :ren_adjacent_origin_unique_count
    ]
    ren_transit_learned_unique_prefixes = ren_unique_prefixes[
        ren_adjacent_origin_unique_count:
    ]

    isp_routes = [
        *_category_routes(
            seed=seed,
            category=RouteCategory.ISP_ADJACENT_ORIGIN,
            shared_prefixes=shared_isp_adjacent_origin_prefixes,
            unique_prefixes=isp_adjacent_origin_unique_prefixes,
        ),
        *_category_routes(
            seed=seed,
            category=RouteCategory.ISP_TRANSIT_LEARNED,
            shared_prefixes=shared_isp_transit_learned_prefixes,
            unique_prefixes=isp_transit_learned_unique_prefixes,
        ),
    ]

    ren_routes = [
        *_category_routes(
            seed=seed,
            category=RouteCategory.REN_ADJACENT_ORIGIN,
            shared_prefixes=shared_ren_adjacent_origin_prefixes,
            unique_prefixes=ren_adjacent_origin_unique_prefixes,
        ),
        *_category_routes(
            seed=seed,
            category=RouteCategory.REN_TRANSIT_LEARNED,
            shared_prefixes=shared_ren_transit_learned_prefixes,
            unique_prefixes=ren_transit_learned_unique_prefixes,
        ),
    ]

    return LabManifest(
        seed=seed,
        pool=pool_network,
        counts=RouteCounts(
            isp=len(isp_routes),
            ren=len(ren_routes),
            isp_adjacent_origin=sum(
                route.source_category is RouteCategory.ISP_ADJACENT_ORIGIN
                for route in isp_routes
            ),
            isp_transit_learned=sum(
                route.source_category is RouteCategory.ISP_TRANSIT_LEARNED
                for route in isp_routes
            ),
            ren_adjacent_origin=sum(
                route.source_category is RouteCategory.REN_ADJACENT_ORIGIN
                for route in ren_routes
            ),
            ren_transit_learned=sum(
                route.source_category is RouteCategory.REN_TRANSIT_LEARNED
                for route in ren_routes
            ),
            shared=sum(route.shared for route in isp_routes),
            shared_isp_adjacent_origin=shared_isp_adjacent_origin_count,
            shared_isp_transit_learned=(
                shared_count - shared_isp_adjacent_origin_count
            ),
            shared_ren_adjacent_origin=shared_ren_adjacent_origin_count,
            shared_ren_transit_learned=(
                shared_count - shared_ren_adjacent_origin_count
            ),
        ),
        asns=AsnPlan(
            campus=CAMPUS_AS,
            isp=ISP_AS,
            ren=REN_AS,
            isp_transit_neighbors=ISP_TRANSIT_NEIGHBORS,
            ren_transit_neighbors=REN_TRANSIT_NEIGHBORS,
        ),
        isp_routes=tuple(isp_routes),
        ren_routes=tuple(ren_routes),
    )


def write_outputs(manifest: LabManifest, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    isp_config = _exabgp_config(
        ISP_SPEAKER,
        routes=manifest.isp_routes,
    )
    ren_config = _exabgp_config(
        REN_SPEAKER,
        routes=manifest.ren_routes,
    )
    (output_dir / "isp.conf").write_text(isp_config, encoding="utf-8")
    (output_dir / "ren.conf").write_text(ren_config, encoding="utf-8")
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest.to_dict(), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--isp-count", type=int, default=DEFAULT_ISP_COUNT)
    parser.add_argument(
        "--isp-transit-learned-count",
        type=int,
        default=DEFAULT_ISP_TRANSIT_LEARNED_COUNT,
    )
    parser.add_argument("--ren-count", type=int, default=DEFAULT_REN_COUNT)
    parser.add_argument(
        "--ren-adjacent-origin-count",
        type=int,
        default=DEFAULT_REN_ADJACENT_ORIGIN_COUNT,
    )
    parser.add_argument(
        "--ren-transit-learned-count",
        type=int,
        default=DEFAULT_REN_TRANSIT_LEARNED_COUNT,
    )
    parser.add_argument("--shared-count", type=int, default=DEFAULT_SHARED_COUNT)
    parser.add_argument("--output-dir", type=Path, default=Path("generated"))
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        manifest = generate(
            seed=args.seed,
            isp_count=args.isp_count,
            isp_transit_learned_count=args.isp_transit_learned_count,
            ren_count=args.ren_count,
            ren_adjacent_origin_count=args.ren_adjacent_origin_count,
            ren_transit_learned_count=args.ren_transit_learned_count,
            shared_count=args.shared_count,
        )
        write_outputs(manifest, args.output_dir)
    except (ValueError, OSError) as exc:
        print(f"generate_prefixes: {exc}", file=sys.stderr)
        return 2
    print(
        f"generated {manifest.counts.isp} ISP routes and "
        f"{manifest.counts.ren} REN routes in {args.output_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
