#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

[[ -f generated/isp.conf ]]
[[ -f generated/ren.conf ]]
[[ ! -e generated/idren.conf ]]

python3 - <<'PY'
import json
from pathlib import Path

manifest = json.loads(
    Path("generated/manifest.json").read_text(encoding="utf-8")
)
assert manifest["asns"] == {
    "campus": 65000,
    "generated_asn_range": [64512, 65534],
    "isp": 65001,
    "isp_transit_neighbors": list(range(65010, 65016)),
    "ren": 65002,
    "ren_transit_neighbors": list(range(65020, 65023)),
}
assert manifest["schema"] == 2

expected = {
    "isp-adjacent-origin": (65001, "adjacent-origin", ("65000:10", "65000:0")),
    "isp-transit-learned": (65001, "transit-learned", ("65000:10", "65000:99")),
    "ren-adjacent-origin": (65002, "adjacent-origin", ("65000:20", "65000:0")),
    "ren-transit-learned": (65002, "transit-learned", ("65000:20", "65000:99")),
}
transit_neighbors = {
    "isp": set(range(65010, 65016)),
    "ren": set(range(65020, 65023)),
}
reserved_asns = {
    65000,
    65001,
    65002,
    *transit_neighbors["isp"],
    *transit_neighbors["ren"],
}
for speaker, routes in manifest["routes"].items():
    observed_neighbors = set()
    for route in routes:
        speaker_as, path_class, expected_communities = expected[
            route["source_category"]
        ]
        path = route["expected_as_path"]
        assert route["path_class"] == path_class
        assert route["path_depth"] == len(path)
        assert route["origin_as"] == path[-1]
        assert path[0] == speaker_as
        assert len(path) == len(set(path))
        assert 65000 not in path
        assert tuple(route["communities"]) == expected_communities
        assert "source_as" not in route
        if path_class == "adjacent-origin":
            generated_asns = path[1:]
            assert route["transit_neighbor"] is None
            assert len(path) == 2
        else:
            generated_asns = path[2:]
            assert path[1] in transit_neighbors[speaker]
            assert route["transit_neighbor"] == path[1]
            assert 3 <= len(path) <= 6
            observed_neighbors.add(path[1])
        assert set(generated_asns).isdisjoint(reserved_asns)
        assert all(64512 <= asn <= 65534 for asn in path)
    assert observed_neighbors == transit_neighbors[speaker]

isp_shared_adjacent_origin = {
    route["prefix"]
    for route in manifest["routes"]["isp"]
    if route["shared"] and route["source_category"] == "isp-adjacent-origin"
}
ren_shared_adjacent_origin = {
    route["prefix"]
    for route in manifest["routes"]["ren"]
    if route["shared"] and route["source_category"] == "ren-adjacent-origin"
}
assert isp_shared_adjacent_origin == ren_shared_adjacent_origin

isp_shared_transit_learned = {
    route["prefix"]
    for route in manifest["routes"]["isp"]
    if route["shared"] and route["source_category"] == "isp-transit-learned"
}
ren_shared_transit_learned = {
    route["prefix"]
    for route in manifest["routes"]["ren"]
    if route["shared"] and route["source_category"] == "ren-transit-learned"
}
assert isp_shared_transit_learned == ren_shared_transit_learned
isp_shared_transit_routes = {
    route["prefix"]: route
    for route in manifest["routes"]["isp"]
    if route["shared"] and route["path_class"] == "transit-learned"
}
ren_shared_transit_routes = {
    route["prefix"]: route
    for route in manifest["routes"]["ren"]
    if route["shared"] and route["path_class"] == "transit-learned"
}
assert any(
    isp_shared_transit_routes[prefix]["path_depth"]
    < ren_shared_transit_routes[prefix]["path_depth"]
    for prefix in isp_shared_transit_routes
)

isp_config = Path("generated/isp.conf").read_text(encoding="utf-8")
ren_config = Path("generated/ren.conf").read_text(encoding="utf-8")
assert "# speaker=ISP local-as=65001" in isp_config
assert "neighbor 10.255.2.1 {" in isp_config
assert "local-as 65001;" in isp_config
assert "peer-as 65000;" in isp_config
assert "# speaker=REN local-as=65002" in ren_config
assert "neighbor 10.255.2.5 {" in ren_config
assert "local-as 65002;" in ren_config
assert "peer-as 65000;" in ren_config
for speaker, config in (("isp", isp_config), ("ren", ren_config)):
    for route in manifest["routes"][speaker]:
        rendered_tail = " ".join(str(asn) for asn in route["as_path_tail"])
        assert f"as-path [ {rendered_tail} ];" in config
assert "65000:20" not in isp_config
assert "65000:10" not in ren_config

PY

python3 tests/check_community_policy.py

for required in \
    "community [ 65000:10 65000:0 ];" \
    "community [ 65000:10 65000:99 ];" \
    "community [ 65000:20 65000:0 ];" \
    "community [ 65000:20 65000:99 ];"; do
    grep -Fq "$required" generated/isp.conf generated/ren.conf
done

for required in \
    "add list=community-isp-adjacent-origin communities=65000:10,65000:0" \
    "add list=community-isp-transit-learned communities=65000:10,65000:99" \
    "add list=community-ren-adjacent-origin communities=65000:20,65000:0" \
    "add list=community-ren-transit-learned communities=65000:20,65000:99" \
    "bgp-communities-empty) { accept }" \
    "set bgp-local-pref 200; accept" \
    "set bgp-local-pref 180; accept" \
    "set bgp-local-pref 160; accept"; do
    grep -Fq "$required" configs/routeros/r1.rsc
done

scan_status=0
legacy_matches=$(
    grep -RInEi --exclude='*.pyc' \
        'large-community|extended-community|idren|7713|64302|141682' \
        generated configs/routeros/r1.rsc clab.yml README.md CONTEXT.md \
        docs tools
) || scan_status=$?
if ((scan_status == 0)); then
    echo "Unexpected legacy identity or unsupported community type found." >&2
    echo "$legacy_matches" >&2
    exit 1
fi
if ((scan_status != 1)); then
    echo "Legacy identity and community-type scan failed." >&2
    exit 1
fi

echo "Private BGP community control-plane contract passed."
