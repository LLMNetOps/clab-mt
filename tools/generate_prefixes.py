#!/usr/bin/env python3
"""Generate deterministic synthetic BGP announcements for the lab.

The generated prefixes are intentionally control-plane test routes.  They are
inside a documentation/lab-only pool and are not expected to have a usable
destination behind ISP or IDREN.
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
DEFAULT_IDREN_COUNT = 200
DEFAULT_DIRECT_COUNT = 100
DEFAULT_TRANSIT_COUNT = 100
DEFAULT_SHARED_COUNT = 50
DEFAULT_MIN_PREFIX_LENGTH = 16
DEFAULT_MAX_PREFIX_LENGTH = 24
MAX_ISP_COUNT = 500
MAX_IDREN_COUNT = 200

# Smaller prefixes are deliberately more common.  This makes a large route
# set practical while still exercising a range from /16 through /24.
PREFIX_LENGTHS = tuple(range(DEFAULT_MIN_PREFIX_LENGTH, DEFAULT_MAX_PREFIX_LENGTH + 1))
PREFIX_WEIGHTS = (1, 1, 2, 3, 5, 8, 14, 25, 41)

RESERVED_ASNS = {65000, 7713, 64302, 141682}
PRIVATE_ASNS = tuple(
    asn
    for asn in range(64512, 65535)
    if asn not in RESERVED_ASNS
)


class RouteCategory(str, Enum):
    ISP = "isp"
    IDREN_DIRECT = "direct"
    IDREN_TRANSIT = "transit-141682"


@dataclass(frozen=True)
class SyntheticRoute:
    prefix: IPv4Network
    shared: bool
    source_category: RouteCategory
    source_as: int | None
    as_path_tail: tuple[int, ...]
    expected_as_path: tuple[int, ...]

    def to_manifest(self) -> dict[str, object]:
        return {
            "prefix": str(self.prefix),
            "shared": self.shared,
            "source_category": self.source_category.value,
            "source_as": self.source_as,
            "as_path_tail": list(self.as_path_tail),
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
class IdrenRouteBudget:
    direct: int
    transit: int

    def shared_direct(self, shared: int) -> int:
        minimum = max(0, shared - self.transit)
        preferred = shared // 2
        return min(self.direct, max(minimum, preferred))


@dataclass(frozen=True)
class RouteCounts:
    isp: int
    idren: int
    idren_direct: int
    idren_transit_141682: int
    shared: int
    shared_direct: int
    shared_transit_141682: int

    def to_manifest(self) -> dict[str, int]:
        return {
            "isp": self.isp,
            "idren": self.idren,
            "idren_direct": self.idren_direct,
            "idren_transit_141682": self.idren_transit_141682,
            "shared": self.shared,
            "shared_direct": self.shared_direct,
            "shared_transit_141682": self.shared_transit_141682,
        }


@dataclass(frozen=True)
class AsnPlan:
    direct_sources: tuple[int, ...]
    transit_sources: tuple[int, ...]

    def to_manifest(self) -> dict[str, object]:
        return {
            "campus": 65000,
            "isp": 7713,
            "idren": 64302,
            "idren_transit": 141682,
            "idren_direct_sources": list(self.direct_sources),
            "idren_transit_sources": list(self.transit_sources),
        }


@dataclass(frozen=True)
class LabManifest:
    seed: int
    pool: IPv4Network
    counts: RouteCounts
    asns: AsnPlan
    isp_routes: tuple[SyntheticRoute, ...]
    idren_routes: tuple[SyntheticRoute, ...]

    def to_dict(self) -> dict[str, object]:
        return {
            "schema": 1,
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
                "idren": [route.to_manifest() for route in self.idren_routes],
            },
        }


ISP_SPEAKER = SpeakerConfig(
    name="ISP",
    local_address="10.255.2.2",
    peer_address="10.255.2.1",
    router_id="10.255.2.2",
    local_as=7713,
    peer_as=65000,
    md5="campus-isp-ebgp",
)
IDREN_SPEAKER = SpeakerConfig(
    name="IDREN",
    local_address="10.255.2.6",
    peer_address="10.255.2.5",
    router_id="10.255.2.6",
    local_as=64302,
    peer_as=65000,
    md5="campus-idren-ebgp",
)


def _static_route_lines(routes: Sequence[SyntheticRoute]) -> list[str]:
    lines = []
    for route in routes:
        prefix = route.prefix
        tail = route.as_path_tail
        if tail:
            lines.extend(
                [
                    f"        route {prefix} {{",
                    "            next-hop self;",
                    f"            as-path [ {' '.join(str(asn) for asn in tail)} ];",
                    "        }",
                ]
            )
        else:
            lines.append(f"        route {prefix} next-hop self;")
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


def _isp_route(
    rng: random.Random,
    prefix: IPv4Network,
    shared: bool,
) -> SyntheticRoute:
    path_length = rng.randint(0, 5)
    tail = tuple(rng.sample(PRIVATE_ASNS, path_length))
    return SyntheticRoute(
        prefix=prefix,
        shared=shared,
        source_category=RouteCategory.ISP,
        source_as=None,
        as_path_tail=tail,
        expected_as_path=(7713, *tail),
    )


def _idren_route(
    rng: random.Random,
    prefix: IPv4Network,
    category: RouteCategory,
    source_asns: list[int],
    shared: bool,
) -> SyntheticRoute:
    source_as = rng.choice(source_asns)
    if category is RouteCategory.IDREN_DIRECT:
        tail = (source_as,)
        expected = (64302, source_as)
    elif category is RouteCategory.IDREN_TRANSIT:
        tail = (141682, source_as)
        expected = (64302, 141682, source_as)
    else:
        raise ValueError(f"unsupported IDREN route category: {category}")
    return SyntheticRoute(
        prefix=prefix,
        shared=shared,
        source_category=category,
        source_as=source_as,
        as_path_tail=tail,
        expected_as_path=expected,
    )


def generate(
    *,
    seed: int = DEFAULT_SEED,
    isp_count: int = DEFAULT_ISP_COUNT,
    idren_count: int = DEFAULT_IDREN_COUNT,
    direct_count: int = DEFAULT_DIRECT_COUNT,
    transit_count: int = DEFAULT_TRANSIT_COUNT,
    shared_count: int = DEFAULT_SHARED_COUNT,
) -> LabManifest:
    pool = DEFAULT_POOL
    for name, value in (
        ("isp_count", isp_count),
        ("idren_count", idren_count),
        ("direct_count", direct_count),
        ("transit_count", transit_count),
        ("shared_count", shared_count),
    ):
        if value < 0:
            raise ValueError(f"{name} must be non-negative")
    if direct_count + transit_count != idren_count:
        raise ValueError("direct_count + transit_count must equal idren_count")
    if isp_count > MAX_ISP_COUNT:
        raise ValueError(f"isp_count must not exceed {MAX_ISP_COUNT}")
    if idren_count > MAX_IDREN_COUNT:
        raise ValueError(f"idren_count must not exceed {MAX_IDREN_COUNT}")
    if shared_count > isp_count or shared_count > idren_count:
        raise ValueError("shared_count cannot exceed either advertisement count")

    pool_network = ip_network(pool)
    total_unique = isp_count + idren_count - shared_count
    rng = random.Random(seed)
    prefixes = _allocate_prefixes(
        rng,
        pool_network,
        total_unique,
    )

    shared_prefixes = prefixes[:shared_count]
    isp_unique_end = shared_count + (isp_count - shared_count)
    isp_unique_prefixes = prefixes[shared_count:isp_unique_end]
    idren_unique_prefixes = prefixes[isp_unique_end:]

    isp_routes = [
        *[_isp_route(rng, prefix, True) for prefix in shared_prefixes],
        *[_isp_route(rng, prefix, False) for prefix in isp_unique_prefixes],
    ]
    idren_budget = IdrenRouteBudget(direct=direct_count, transit=transit_count)
    shared_direct_count = idren_budget.shared_direct(shared_count)
    shared_direct_prefixes = shared_prefixes[:shared_direct_count]
    shared_transit_prefixes = shared_prefixes[shared_direct_count:]
    direct_unique_count = direct_count - len(shared_direct_prefixes)
    direct_unique_prefixes = idren_unique_prefixes[:direct_unique_count]
    transit_unique_prefixes = idren_unique_prefixes[direct_unique_count:]

    source_asns = list(PRIVATE_ASNS)
    direct_source_asns = rng.sample(source_asns, min(10, direct_count))
    remaining_source_asns = [asn for asn in source_asns if asn not in direct_source_asns]
    transit_source_asns = rng.sample(
        remaining_source_asns,
        min(50, transit_count),
    )

    idren_routes = [
        *[
            _idren_route(
                rng,
                prefix,
                RouteCategory.IDREN_DIRECT,
                direct_source_asns,
                True,
            )
            for prefix in shared_direct_prefixes
        ],
        *[
            _idren_route(
                rng,
                prefix,
                RouteCategory.IDREN_TRANSIT,
                transit_source_asns,
                True,
            )
            for prefix in shared_transit_prefixes
        ],
        *[
            _idren_route(
                rng,
                prefix,
                RouteCategory.IDREN_DIRECT,
                direct_source_asns,
                False,
            )
            for prefix in direct_unique_prefixes
        ],
        *[
            _idren_route(
                rng,
                prefix,
                RouteCategory.IDREN_TRANSIT,
                transit_source_asns,
                False,
            )
            for prefix in transit_unique_prefixes
        ],
    ]

    return LabManifest(
        seed=seed,
        pool=pool_network,
        counts=RouteCounts(
            isp=len(isp_routes),
            idren=len(idren_routes),
            idren_direct=sum(
                route.source_category is RouteCategory.IDREN_DIRECT
                for route in idren_routes
            ),
            idren_transit_141682=sum(
                route.source_category is RouteCategory.IDREN_TRANSIT
                for route in idren_routes
            ),
            shared=sum(route.shared for route in isp_routes),
            shared_direct=shared_direct_count,
            shared_transit_141682=len(shared_transit_prefixes),
        ),
        asns=AsnPlan(
            direct_sources=tuple(direct_source_asns),
            transit_sources=tuple(transit_source_asns),
        ),
        isp_routes=tuple(isp_routes),
        idren_routes=tuple(idren_routes),
    )


def write_outputs(manifest: LabManifest, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    isp_config = _exabgp_config(
        ISP_SPEAKER,
        routes=manifest.isp_routes,
    )
    idren_config = _exabgp_config(
        IDREN_SPEAKER,
        routes=manifest.idren_routes,
    )
    (output_dir / "isp.conf").write_text(isp_config, encoding="utf-8")
    (output_dir / "idren.conf").write_text(idren_config, encoding="utf-8")
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest.to_dict(), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--isp-count", type=int, default=DEFAULT_ISP_COUNT)
    parser.add_argument("--idren-count", type=int, default=DEFAULT_IDREN_COUNT)
    parser.add_argument("--direct-count", type=int, default=DEFAULT_DIRECT_COUNT)
    parser.add_argument("--transit-count", type=int, default=DEFAULT_TRANSIT_COUNT)
    parser.add_argument("--shared-count", type=int, default=DEFAULT_SHARED_COUNT)
    parser.add_argument("--output-dir", type=Path, default=Path("generated"))
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        manifest = generate(
            seed=args.seed,
            isp_count=args.isp_count,
            idren_count=args.idren_count,
            direct_count=args.direct_count,
            transit_count=args.transit_count,
            shared_count=args.shared_count,
        )
        write_outputs(manifest, args.output_dir)
    except (ValueError, OSError) as exc:
        print(f"generate_prefixes: {exc}", file=sys.stderr)
        return 2
    print(
        f"generated {manifest.counts.isp} ISP routes and "
        f"{manifest.counts.idren} IDREN routes in {args.output_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
