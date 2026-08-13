# Prefer IDREN for shared prefixes

R1 will set inbound local preference to 200 for routes learned from IDREN and 100 for routes learned from ISP. When both peers advertise the same prefix, R1 will therefore select the IDREN path; the preference is a campus-edge policy applied by R1, not an attribute set by IDREN.
