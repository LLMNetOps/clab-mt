---
status: superseded by ADR-0006
---

# Propagate external BGP routes through the campus OSPF domain

R1 will redistribute the generated prefixes learned from ISP and IDREN into the single-area campus OSPF domain so R2, R3, H1, and H2 can observe the external routes through the internal network. This deliberately models the lab’s inter-domain-to-campus routing boundary; the trade-off is that the OSPF domain carries hundreds of generated external routes instead of only a default route.
