# Campus core router with the H1 DHCP segment, RouterOS 7.21.5
/system identity set name=R2

/ip firewall filter remove [find]
/ip firewall nat remove [find]
/ip firewall raw remove [find]

/ip address
add address=10.255.0.2/32 interface=lo comment="R2 loopback"
add address=10.255.1.2/30 interface=ether2 comment="R2-R1"
add address=10.255.1.5/30 interface=ether3 comment="R2-R3"
add address=10.255.10.1/24 interface=ether4 comment="H1 LAN"

/ip pool
add name=pool-h1 ranges=10.255.10.100-10.255.10.199
/ip dhcp-server
add address-pool=pool-h1 disabled=no interface=ether4 lease-time=1h name=dhcp-h1
/ip dhcp-server network
add address=10.255.10.0/24 gateway=10.255.10.1 comment="H1 LAN"

/routing ospf instance
add name=campus-ospf version=2 router-id=10.255.0.2
/routing ospf area
add name=backbone area-id=0.0.0.0 instance=campus-ospf
/routing ospf interface-template
add area=backbone interfaces=ether2 type=ptp cost=10
add area=backbone interfaces=ether3 type=ptp cost=10
add area=backbone interfaces=ether4 passive
add area=backbone interfaces=lo passive
