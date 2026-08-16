# Campus Routing Lab Context

This context describes a miniature campus network testbed that exercises
external BGP connectivity to a commercial ISP and a non-commercial research
and education network alongside an internal OSPF network.

## Lab operation

**Lab operator**:
A network engineer who prepares, deploys, validates, explores, and destroys the campus routing lab without needing knowledge of the repository's implementation.
_Avoid_: user, when the operator role is specifically intended.

## Network roles

**Campus edge**:
The R1 router and its external BGP adjacencies to ISP and REN.
_Avoid_: border router when referring to the whole edge role.

**Campus core**:
The OSPF-connected R1, R2, and R3 router triangle that provides internal campus transit.
_Avoid_: backbone when referring to this lab topology.

**Campus autonomous system**:
The local autonomous system represented by R1 for external BGP connectivity; in this lab it is AS 65000.

**Shared test prefix**:
A generated IPv4 route intentionally advertised by both ISP and REN so the
campus edge can demonstrate BGP best-path selection and policy.

**ISP**:
An ExaBGP-speaking commercial-transit autonomous system with private lab AS
65001 that advertises generated test prefixes toward R1. Its external BGP
session is the lab's signal that R1 may originate the ISP-gated OSPF default.

**REN**:
An ExaBGP-speaking non-commercial research-and-education autonomous system
with private lab AS 65002 that advertises generated test prefixes toward R1.
REN availability does not qualify R1 to originate the ISP-gated OSPF default.

**ExaBGP speaker**:
A Linux-based external BGP peer that emits the lab’s generated advertisements without acting as a forwarding router.

**Endpoint host**:
A Linux host attached to the campus core that obtains its address and default route through DHCP rather than running a routing protocol. In this lab H1 is attached to R2 and H2 is attached to R3.
_Avoid_: workstation, client router

## Routing and advertisements

**External BGP session**:
An eBGP adjacency between R1 and one external ExaBGP autonomous system: ISP or
REN.

**Inbound local-preference policy**:
The R1 policy that maps validated standard communities to local preference.
Adjacent-origin routes use 200, REN transit-learned routes use 180, ISP
transit-learned routes use 160, and routes with no communities retain
RouterOS's default 100. Non-empty communities that do not match the lab
contract are rejected.

**Internal OSPF domain**:
The single campus routing domain formed by R1, R2, and R3.

**ISP-gated OSPF default**:
The sole external route R1 originates into the internal OSPF domain. It is
present only while R1's external BGP session with ISP is established; the REN
session does not qualify it.

**Test prefix**:
An IPv4 route generated for the lab to exercise advertisement, path selection, and policy on R1; generated prefixes may range from /16 through /24.

**Generated AS path**:
The synthetic AS_SEQUENCE attached to a test prefix. It starts with the
external speaker, ends with the origin AS, and can include transit neighbors
and intermediate ASes without requiring additional autonomous-system nodes.
All values are private-use ASNs, every path contains unique ASNs, and campus AS
65000 is excluded from the path.

**Adjacent-origin route**:
A generated route that an external speaker learned directly from the origin
AS. Its generated AS path contains the speaker followed by the origin AS.

**Transit-learned route**:
A generated route that an external speaker learned through a transit neighbor
before the origin AS. Its generated AS path can also contain intermediate ASes.

**Transit neighbor**:
An AS adjacent to an external speaker from which the speaker learns a
transit-learned route.
_Avoid_: upstream ISP, when the relationship is not otherwise defined

**Transit-neighbor pool**:
The bounded set of transit neighbors available to one external speaker. The
ISP and REN have separate pools so the lab can model different path diversity.
ISP uses AS 65010 through AS 65015; REN uses AS 65020 through AS 65022.

**Path depth**:
The number of ASNs in a generated AS path. Path depth is separate from the
number of transit neighbors available to an external speaker.

**Path class**:
The policy classification of a generated route as adjacent-origin or
transit-learned. Standard communities carry the path class independently of
the generated AS-path depth.

**ISP adjacent-origin route**:
An adjacent-origin route emitted by ISP with standard communities `65000:10`
and `65000:0`.

**ISP transit-learned route**:
A transit-learned route emitted by ISP with standard communities `65000:10`
and `65000:99`.

**REN adjacent-origin route**:
An adjacent-origin route emitted by REN with standard communities `65000:20`
and `65000:0`.

**REN transit-learned route**:
A transit-learned route emitted by REN with standard communities `65000:20`
and `65000:99`.

**Prefix advertisement set**:
The bounded collection of generated test prefixes an external peer advertises
during a lab run: up to 500 from ISP and up to 200 from REN.

**Control-plane test route**:
A generated route used to exercise BGP behavior even when the lab does not model a reachable host behind the advertised prefix.

**Prefix source category**:
The modeled origin relationship represented by an external speaker's route
category and AS path: ISP adjacent-origin, ISP transit-learned, REN
adjacent-origin, or REN transit-learned.

**Shared-prefix preference test**:
A routing-policy scenario in which the same test prefix is received from both
external BGP peers and R1 selects the path with the higher community-derived
local preference.

**IPv4 unicast lab**:
The initial address-family scope of the testbed; IPv6 and other BGP address families are outside this lab’s contract.

**Prefix generator**:
The deterministic tool that allocates test prefixes, assigns source categories
and generated AS paths, and renders the external advertisements.

**Generated-prefix pool**:
The reserved `10.64.0.0/10` IPv4 space from which the prefix generator allocates test routes, kept separate from infrastructure and DHCP-served campus segments.

**eBGP session protection**:
The lab-only TCP MD5 authentication applied independently to the R1–ISP and
R1–REN sessions.

## Address assignment

**DHCP-served campus segment**:
A LAN segment on which an endpoint host receives its IPv4 address and default gateway from a campus router.

**Management network**:
The Containerlab-provided `campus-ebgp-mgmt` control network used to access lab
nodes and kept separate from the routed data links. It uses the fixed
`172.20.20.0/24` subnet and fixed per-node addresses so management access is
stable across destroy/deploy cycles.

**Failure scenario**:
A controlled withdrawal or link event used to validate convergence, such as stopping an external speaker or disabling one campus-core link.

**Campus reachability test**:
The endpoint acceptance test in which H1 and H2 receive DHCP configuration and can reach each other with both ping and traceroute across the OSPF campus core.

## Implemented lab contract

- RouterOS nodes R1/R2/R3 use the exact `7.21.5` CHR image built as
  `vrnetlab/mikrotik_routeros:7.21.5`.
- ISP and REN use ExaBGP `5.0.9`; their generated advertisements are static
  control-plane routes, not forwarding destinations.
- The triangle uses OSPFv2 area 0. R1 originates the ISP-gated OSPF default as
  external type 1 with metric 20 and does not redistribute generated BGP routes.
- H1 is on R2's `10.255.10.0/24` DHCP-served segment; H2 is on R3's
  `10.255.20.0/24` DHCP-served segment.
- The generated-prefix pool is `10.64.0.0/10`; infrastructure and endpoint
  segments use `10.255.0.0/16` subdivisions and do not overlap it.
