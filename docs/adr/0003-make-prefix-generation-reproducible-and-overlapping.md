# Make generated advertisements reproducible and intentionally overlapping

The prefix generator will use a configurable seed and produce bounded, non-overlapping allocations except for a deliberate shared set advertised by both ISP and IDREN. The default scale is 500 ISP advertisements and 200 IDREN advertisements, with 50 shared prefixes, so reruns are comparable while BGP best-path selection remains observable.
