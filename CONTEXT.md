# Campus Routing Lab Context

This context describes a miniature campus network testbed that exercises external BGP connectivity to an ISP and a research-and-education network alongside an internal OSPF network.

## Network roles

**Campus edge**:
The R1 router and its external BGP adjacencies to ISP and IDREN.
_Avoid_: border router when referring to the whole edge role.

**Campus core**:
The OSPF-connected R1, R2, and R3 router triangle that provides internal campus transit.
_Avoid_: backbone when referring to this lab topology.

**Campus autonomous system**:
The local autonomous system represented by R1 for external BGP connectivity; in this lab it is AS 65000.

**Shared test prefix**:
A generated IPv4 route intentionally advertised by both ISP and IDREN so the campus edge can demonstrate BGP best-path selection and policy.

**ISP**:
An ExaBGP-speaking external autonomous system with AS 7713 that advertises generated test prefixes toward R1.

**IDREN**:
An ExaBGP-speaking research-and-education external autonomous system with AS 64302 that advertises generated test prefixes toward R1, including prefixes associated with directly connected customer autonomous systems and AS paths containing 141682.

**ExaBGP speaker**:
A Linux-based external BGP peer that emits the lab’s generated advertisements without acting as a forwarding router.

**Endpoint host**:
A Linux host attached to the campus core that obtains its address and default route through DHCP rather than running a routing protocol. In this lab H1 is attached to R2 and H2 is attached to R3.
_Avoid_: workstation, client router

## Routing and advertisements

**External BGP session**:
An eBGP adjacency between R1 and one external ExaBGP autonomous system: ISP or IDREN.

**Inbound local-preference policy**:
The R1 policy that assigns local preference to received external routes; this lab assigns 200 to IDREN routes and 100 to ISP routes so IDREN wins when both peers advertise the same prefix.

**Internal OSPF domain**:
The single campus routing domain formed by R1, R2, and R3.

**External-route propagation**:
The campus behavior in which R1 makes externally learned BGP routes available to the internal OSPF domain.

**Test prefix**:
An IPv4 route generated for the lab to exercise advertisement, path selection, policy, and reachability; generated prefixes may range from /16 through /24.

**Generated AS path**:
The synthetic AS_SEQUENCE attached to a test prefix so the lab can exercise realistic-looking path selection without requiring additional autonomous-system nodes.

**Directly connected IDREN AS**:
One of up to ten synthetic autonomous systems represented by IDREN as directly connected sources of advertised prefixes.

**IDREN transit AS**:
One of up to fifty synthetic autonomous systems represented by IDREN through AS paths containing 141682.

**Prefix advertisement set**:
The bounded collection of generated test prefixes an external peer advertises during a lab run: up to 500 from ISP and up to 200 from IDREN.

**Control-plane test route**:
A generated route used to exercise BGP and OSPF behavior even when the lab does not model a reachable host behind the advertised prefix.

**Prefix source category**:
The modeled origin relationship represented in an external AS path, such as a directly connected IDREN AS, an IDREN path through 141682, or a generated ISP upstream path.

**Shared-prefix preference test**:
A routing-policy scenario in which the same test prefix is received from both external BGP peers and R1 selects IDREN using the higher inbound local preference.

**IPv4 unicast lab**:
The initial address-family scope of the testbed; IPv6 and other BGP address families are outside this lab’s contract.

**Prefix generator**:
The deterministic tool that allocates test prefixes, assigns source categories and generated AS paths, and renders the external advertisements.

**Generated-prefix pool**:
The reserved `10.64.0.0/10` IPv4 space from which the prefix generator allocates test routes, kept separate from infrastructure and DHCP-served campus segments.

**eBGP session protection**:
The lab-only TCP MD5 authentication applied independently to the R1–ISP and R1–IDREN sessions.

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
- ISP and IDREN use ExaBGP `5.0.9`; their generated advertisements are static
  control-plane routes, not forwarding destinations.
- The triangle uses OSPFv2 area 0. R1 redistributes accepted generated BGP
  routes as external type 1 with metric 20.
- H1 is on R2's `10.255.10.0/24` DHCP-served segment; H2 is on R3's
  `10.255.20.0/24` DHCP-served segment.
- The generated-prefix pool is `10.64.0.0/10`; infrastructure and endpoint
  segments use `10.255.0.0/16` subdivisions and do not overlap it.
