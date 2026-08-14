# Lab reference

## Address plan

| Segment | Prefix | Endpoints |
| --- | --- | --- |
| Management | `172.20.20.0/24` | R1 `.11`, R2 `.12`, R3 `.13`, ISP `.21`, IDREN `.22`, H1 `.31`, H2 `.32` |
| R1 loopback | `10.255.0.1/32` | R1 |
| R2 loopback | `10.255.0.2/32` | R2 |
| R3 loopback | `10.255.0.3/32` | R3 |
| R1–R2 | `10.255.1.0/30` | R1 `.1`, R2 `.2` |
| R2–R3 | `10.255.1.4/30` | R2 `.5`, R3 `.6` |
| R1–R3 | `10.255.1.8/30` | R1 `.9`, R3 `.10` |
| R1–ISP | `10.255.2.0/30` | R1 `.1`, ISP `.2` |
| R1–IDREN | `10.255.2.4/30` | R1 `.5`, IDREN `.6` |
| H1 LAN | `10.255.10.0/24` | R2 gateway `.1`, DHCP `.100–.199` |
| H2 LAN | `10.255.20.0/24` | R3 gateway `.1`, DHCP `.100–.199` |
| Generated routes | `10.64.0.0/10` | Control plane only |

## Route generation

The default generated advertisement set is deterministic:

| Input | Default | Limit or relationship |
| --- | ---: | --- |
| `SEED` | `20260812` | Deterministic random seed |
| `ISP_PREFIXES` | `500` | Maximum 500 |
| `IDREN_PREFIXES` | `200` | Maximum 200 |
| `IDREN_DIRECT_PREFIXES` | `100` | Direct + transit must equal IDREN |
| `IDREN_TRANSIT_PREFIXES` | `100` | Direct + transit must equal IDREN |
| `SHARED_PREFIXES` | `50` | Cannot exceed either peer total |

Preview a different advertisement set:

```bash
make generate \
  SEED=42 \
  ISP_PREFIXES=500 \
  IDREN_PREFIXES=200 \
  IDREN_DIRECT_PREFIXES=100 \
  IDREN_TRANSIT_PREFIXES=100 \
  SHARED_PREFIXES=50
```

`make deploy` runs generation again. Pass the same values to `make deploy` if
you want to deploy a customized set:

```bash
make deploy SEED=42
```

Generated files are:

- `generated/isp.conf`
- `generated/idren.conf`
- `generated/manifest.json`
- `configs/routeros/r1.rsc`
- `configs/routeros/r2.rsc`
- `configs/routeros/r3.rsc`

Generated prefixes come from `10.64.0.0/10` and have lengths from `/16`
through `/24`. Prefixes do not overlap, except for the shared set that both
external peers advertise.

IDREN advertisements use direct and transit source categories. Transit paths
contain AS 141682. ISP advertisements use deterministic synthetic AS paths
with lengths from zero through five.
