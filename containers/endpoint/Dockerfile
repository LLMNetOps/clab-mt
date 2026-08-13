FROM debian:12-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241

ENV DEBIAN_FRONTEND=noninteractive

COPY containers/common/debian.sources /etc/apt/sources.list.d/debian.sources

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        isc-dhcp-client=4.4.3-P1-2 \
        iproute2=6.1.0-3 \
        iputils-ping=3:20221126-1+deb12u1 \
        procps=2:4.0.2-3 \
        tcpdump=4.99.3-1 \
        traceroute=1:2.1.2-1 \
    && rm -rf /var/lib/apt/lists/*

COPY containers/common/wait-for-interface.sh /usr/local/lib/campus/wait-for-interface.sh
COPY containers/endpoint/dhclient.conf /etc/dhcp/dhclient.conf
COPY containers/endpoint/entrypoint.sh /usr/local/bin/campus-endpoint
RUN chmod 0755 /usr/local/lib/campus/wait-for-interface.sh /usr/local/bin/campus-endpoint

ENTRYPOINT ["/usr/local/bin/campus-endpoint"]
