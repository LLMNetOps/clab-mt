# Campus core router with the H2 DHCP segment, RouterOS 7.21.5
/system identity set name=R3
/user set [find name=admin] password="lab-routeros-7.21.5"

/ip firewall filter remove [find]
/ip firewall nat remove [find]
/ip firewall raw remove [find]

/ip address
add address=10.255.0.3/32 interface=lo comment="R3 loopback"
add address=10.255.1.10/30 interface=ether2 comment="R3-R1"
add address=10.255.1.6/30 interface=ether3 comment="R3-R2"
add address=10.255.20.1/24 interface=ether4 comment="H2 LAN"

/ip pool
add name=pool-h2 ranges=10.255.20.100-10.255.20.199
/ip dhcp-server
add address-pool=pool-h2 disabled=no interface=ether4 lease-time=1h name=dhcp-h2
/ip dhcp-server network
add address=10.255.20.0/24 gateway=10.255.20.1 comment="H2 LAN"

/routing ospf instance
add name=campus-ospf version=2 router-id=10.255.0.3
/routing ospf area
add name=backbone area-id=0.0.0.0 instance=campus-ospf
/routing ospf interface-template
add area=backbone interfaces=ether2 type=ptp cost=10
add area=backbone interfaces=ether3 type=ptp cost=10
add area=backbone interfaces=ether4 passive
add area=backbone interfaces=lo passive
