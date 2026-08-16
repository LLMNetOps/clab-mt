---
status: accepted
---

# Derive local preference from standard BGP communities

The ExaBGP speakers emit standard communities and R1 applies local
preference only when the received route has a valid lab community set. The
source communities are `65000:10` for ISP and `65000:20` for REN. The
path-class communities are `65000:0` for adjacent-origin and `65000:99` for
transit-learned.

R1 assigns local preference 200 to either adjacent-origin category, 180 to REN
transit-learned, and 160 to ISP transit-learned. A route with no communities is
accepted without a local-preference assignment, retaining RouterOS's default
of 100. A non-empty community set that is malformed, contains an unsupported
category, or mixes ISP and REN source tags is rejected.

The numeric values are synthetic private-ASN lab values and are intentionally
not the production communities associated with any real provider.
