#!/usr/bin/env bash

lab_link_names() {
    printf '%s\n' r1-r2 r1-r3 r2-r3 isp ren
}

    lab_link_name_for_pair() {
        local first=${1,,}
        local second=${2,,}
        case "$first $second" in
            'r1 r2'|'r2 r1') printf '%s\n' r1-r2 ;;
            'r1 r3'|'r3 r1') printf '%s\n' r1-r3 ;;
            'r2 r3'|'r3 r2') printf '%s\n' r2-r3 ;;
            'r1 isp'|'isp r1') printf '%s\n' isp ;;
            'r1 ren'|'ren r1') printf '%s\n' ren ;;
            *) return 1 ;;
        esac
    }

lab_link_target() {
    case ${1:-} in
        r1-r2)
            printf '%s|%s|%s\n' R1 eth1 'R1:ether2 - R2:ether2'
            ;;
        r1-r3)
            printf '%s|%s|%s\n' R1 eth2 'R1:ether3 - R3:ether2'
            ;;
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
