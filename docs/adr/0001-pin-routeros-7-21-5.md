# Pin the MikroTik RouterOS runtime to 7.21.5

The lab uses Containerlab’s VM-backed `mikrotik_ros` runtime with MikroTik RouterOS 7.21.5 pinned as the exact patch release. Pinning the patch version makes BGP, OSPF, DHCP, and startup-configuration behavior reproducible; the trade-off is that upgrading RouterOS becomes an explicit lab maintenance decision instead of following a floating release tag.
