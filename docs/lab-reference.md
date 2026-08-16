# Lab reference

## Address plan

| Segment | Prefix | Endpoints |
| --- | --- | --- |
| Management | `172.20.20.0/24` | R1 `.11`, R2 `.12`, R3 `.13`, ISP `.21`, REN `.22`, H1 `.31`, H2 `.32` |
| R1 loopback | `10.255.0.1/32` | R1 |
| R2 loopback | `10.255.0.2/32` | R2 |
| R3 loopback | `10.255.0.3/32` | R3 |
| R1–R2 | `10.255.1.0/30` | R1 `.1`, R2 `.2` |
| R2–R3 | `10.255.1.4/30` | R2 `.5`, R3 `.6` |
| R1–R3 | `10.255.1.8/30` | R1 `.9`, R3 `.10` |
| R1–ISP | `10.255.2.0/30` | R1 `.1`, ISP `.2` |
| R1–REN | `10.255.2.4/30` | R1 `.5`, REN `.6` |
| H1 LAN | `10.255.10.0/24` | R2 gateway `.1`, DHCP `.100–.199` |
| H2 LAN | `10.255.20.0/24` | R3 gateway `.1`, DHCP `.100–.199` |
| Generated routes | `10.64.0.0/10` | Control plane only |

## Routing behavior

R1 retains the generated ISP and REN routes in BGP and does not redistribute
them into OSPF. While the R1–ISP BGP session is established, R1 originates
`0.0.0.0/0` into OSPF as external type 1 with metric 20. The default is
withdrawn when ISP is unavailable even if REN remains established. Neither
external speaker advertises a default or provides data-plane forwarding.

## Route generation

The default generated advertisement set is deterministic:

| Input | Default | Limit or relationship |
| --- | ---: | --- |
| `SEED` | `20260812` | Deterministic random seed |
| `ISP_PREFIXES` | `500` | Maximum 500 |
| `ISP_TRANSIT_LEARNED_PREFIXES` | `100` | ISP transit-learned routes; cannot exceed ISP total |
| `REN_PREFIXES` | `200` | Maximum 200 |
| `REN_ADJACENT_ORIGIN_PREFIXES` | `100` | Adjacent-origin + transit-learned must equal REN |
| `REN_TRANSIT_LEARNED_PREFIXES` | `100` | Adjacent-origin + transit-learned must equal REN |
| `SHARED_PREFIXES` | `50` | Cannot exceed either peer total |

Preview a different advertisement set:

```bash
make generate \
  SEED=42 \
  ISP_PREFIXES=500 \
  ISP_TRANSIT_LEARNED_PREFIXES=100 \
  REN_PREFIXES=200 \
  REN_ADJACENT_ORIGIN_PREFIXES=100 \
  REN_TRANSIT_LEARNED_PREFIXES=100 \
  SHARED_PREFIXES=50
```

`make deploy` runs generation again. Pass the same values to `make deploy` if
you want to deploy a customized set:

```bash
make deploy SEED=42
```

Generated files are:

- `generated/isp.conf`
- `generated/ren.conf`
- `generated/manifest.json`
- `configs/routeros/r1.rsc`
- `configs/routeros/r2.rsc`
- `configs/routeros/r3.rsc`

Generated prefixes come from `10.64.0.0/10` and have lengths from `/16`
through `/24`. Prefixes do not overlap, except for the shared set that both
external peers advertise.

ISP and REN advertisements use four deterministic categories: ISP
adjacent-origin, ISP transit-learned, REN adjacent-origin, and REN
transit-learned. The speakers emit standard communities using `65000:10` for
ISP, `65000:20` for REN, `65000:0` for adjacent-origin, and `65000:99` for
transit-learned.

Every adjacent-origin path has depth 2: the external speaker followed by a
generated origin AS. A transit-learned path has depth 3 through 6: the external
speaker, one transit neighbor, zero through three intermediate ASes, and a
generated origin AS. ISP uses transit neighbors AS 65010 through AS 65015; REN
uses AS 65020 through AS 65022. Default generation uses every member of both
pools, while transit-neighbor choice and path depth vary independently.

The seed controls prefix allocation, transit-neighbor selection, path depth,
intermediate ASes, and origin ASes. Reusing all generation inputs reproduces
the manifest and both ExaBGP configurations exactly. A different seed can
change valid paths without changing route-category budgets or the deliberate
shared-prefix overlap.

The private lab ASN plan reserves campus AS 65000, ISP AS 65001, REN AS 65002,
and both transit-neighbor pools. Generated intermediate and origin ASNs come
from the RFC 6996 16-bit private-use range, AS 64512 through AS 65534, excluding
all reserved ASNs. Every path contains unique ASNs and excludes campus AS
65000. These values are synthetic and must not be copied into an operational
network.

For each route, `generated/manifest.json` records its source category, path
class, transit neighbor (when applicable), origin AS, path depth, complete
expected AS path, communities, and the tail rendered into ExaBGP configuration.
