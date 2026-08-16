---
status: accepted
---

# Originate an ISP-gated default into OSPF

This supersedes ADR-0002: R1 will keep generated BGP prefixes at the campus
edge and originate only an OSPF external type-1 default with metric 20 while
its ISP BGP session is established. ISP session state is polled because neither
external peer advertises a default, accepting a small convergence delay and
fail-stale scheduler risk in exchange for preventing generated-prefix growth in
the OSPF link-state database; REN availability alone does not qualify the
default.
