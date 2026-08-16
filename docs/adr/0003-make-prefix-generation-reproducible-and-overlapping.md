# Make generated advertisements and AS paths reproducible

The prefix generator will use a configurable seed and produce bounded,
non-overlapping allocations except for a deliberate shared set advertised by
both ISP and REN. The default scale is 500 ISP advertisements and 200 REN
advertisements, with 50 shared prefixes, so reruns are comparable while BGP
best-path selection remains observable.

The seed also controls each route's complete synthetic AS path. Adjacent-origin
paths contain the external speaker and one generated origin AS. Transit-learned
paths contain the speaker, a speaker-specific transit neighbor, zero through
three generated intermediate ASes, and a generated origin AS. ISP uses AS
65010 through 65015 as transit neighbors; REN uses AS 65020 through 65022.
Generated intermediate and origin ASNs come from the RFC 6996 private-use range
and exclude all reserved campus, speaker, and transit-neighbor ASNs.

Transit-neighbor allocation and path depth are separate seeded dimensions.
When a category has enough routes, allocation covers every configured transit
neighbor; path depths remain independently varied from 3 through 6.
