# Campus edge router, RouterOS 7.21.5
/system identity set name=R1

# The lab is intentionally permissive; it has no NAT and no external access.
/ip firewall filter remove [find]
/ip firewall nat remove [find]
/ip firewall raw remove [find]

/ip address
add address=10.255.0.1/32 interface=lo comment="R1 loopback"
add address=10.255.1.1/30 interface=ether2 comment="R1-R2"
add address=10.255.1.9/30 interface=ether3 comment="R1-R3"
add address=10.255.2.1/30 interface=ether4 comment="R1-ISP"
add address=10.255.2.5/30 interface=ether5 comment="R1-IDREN"

# One OSPFv2 area; only the triangle participates in adjacency formation.
/routing ospf instance
add name=campus-ospf version=2 router-id=10.255.0.1 originate-default=never out-filter-chain=ospf-default
/routing ospf area
add name=backbone area-id=0.0.0.0 instance=campus-ospf
/routing ospf interface-template
add area=backbone interfaces=ether2 type=ptp cost=10
add area=backbone interfaces=ether3 type=ptp cost=10
add area=backbone interfaces=lo passive

# The conditional default enters OSPF as external type 1 with metric 20.
/routing filter rule
add chain=ospf-default rule="if (dst == 0.0.0.0/0) { set ospf-ext-type type1; set ospf-ext-metric 20; accept } else { reject }"

/routing bgp instance
add name=campus-bgp as=65000 router-id=10.255.0.1

# Inbound policy is applied on R1.  IDREN wins shared prefixes locally.
/routing filter rule
add chain=bgp-in-isp rule="if (dst in 10.64.0.0/10 && dst-len >= 16 && dst-len <= 24) { set bgp-local-pref 100; accept } else { reject }"
add chain=bgp-in-idren rule="if (dst in 10.64.0.0/10 && dst-len >= 16 && dst-len <= 24) { set bgp-local-pref 200; accept } else { reject }"
add chain=bgp-out-campus rule="if (dst == 10.255.10.0/24 || dst == 10.255.20.0/24) { accept } else { reject }"

/routing bgp connection
add name=to-isp instance=campus-bgp remote.address=10.255.2.2 remote.as=7713 local.address=10.255.2.1 local.role=ebgp tcp-md5-key="campus-isp-ebgp" connect=yes listen=yes hold-time=30s afi=ip input.filter=bgp-in-isp input.limit-process-routes-ipv4=1000 output.redistribute=ospf output.filter-chain=bgp-out-campus
add name=to-idren instance=campus-bgp remote.address=10.255.2.6 remote.as=64302 local.address=10.255.2.5 local.role=ebgp tcp-md5-key="campus-idren-ebgp" connect=yes listen=yes hold-time=30s afi=ip input.filter=bgp-in-idren input.limit-process-routes-ipv4=1000 output.redistribute=ospf output.filter-chain=bgp-out-campus

# Track the ISP BGP FSM directly; IDREN does not qualify as Internet default.
/system script
add name=sync-isp-ospf-default dont-require-permissions=no policy=read,write source={
    :local ospfInstances [/routing/ospf/instance find where name="campus-ospf"]
    :if ([:len $ospfInstances] != 1) do={
        :log error "ISP default sync: campus-ospf instance missing or ambiguous"
        :error "campus-ospf lookup failed"
    }

    :local desired "never"
    :onerror err in={
        :local ispSessions [/routing/bgp/session find where remote.address=10.255.2.2 and established]
        :if ([:len $ispSessions] = 1) do={
            :set desired "always"
        }
    } do={
        :log error ("ISP default sync: BGP state query failed: " . $err)
        :set desired "never"
    }

    :local current [/routing/ospf/instance get $ospfInstances originate-default]
    :if ($current != $desired) do={
        /routing/ospf/instance set $ospfInstances originate-default=$desired
        :log info ("ISP default sync: originate-default=" . $desired)
    }
}

/system scheduler
add name=sync-isp-default-startup start-time=startup interval=0s on-event=sync-isp-ospf-default policy=read,write
add name=sync-isp-default-periodic interval=2s on-event=sync-isp-ospf-default policy=read,write
