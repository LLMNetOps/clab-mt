#!/usr/bin/env bash

lab_link_names() {
    printf '%s\n' r2-r3 isp ren
}

lab_link_target() {
    case ${1:-} in
        r2-r3)
            printf '%s|%s|%s\n' R2 eth2 'R2:ether3 - R3:ether3'
            ;;
        isp)
            printf '%s|%s|%s\n' R1 eth3 'R1:ether4 - ISP:eth1'
            ;;
        ren)
            printf '%s|%s|%s\n' R1 eth4 'R1:ether5 - REN:eth1'
            ;;
        *)
            return 1
            ;;
    esac
}
