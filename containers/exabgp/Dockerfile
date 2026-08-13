# Keep the BGP speaker on the official ExaBGP release image.  The small
# derivative only adds iproute2 so the data-facing interface can be addressed
# before ExaBGP starts its session.
FROM ghcr.io/exa-networks/exabgp:5.0.9@sha256:5554ac053766e66ca3b99eb6b66e83e32113913729a184dcbaf0cc4abd2f4244

USER root
ENV DEBIAN_FRONTEND=noninteractive

COPY containers/common/debian.sources /etc/apt/sources.list.d/debian.sources

RUN apt-get update \
    && apt-get install -y --no-install-recommends iproute2=6.1.0-3 \
    && rm -rf /var/lib/apt/lists/*

COPY containers/common/wait-for-interface.sh /usr/local/lib/campus/wait-for-interface.sh
COPY containers/exabgp/entrypoint.sh /usr/local/bin/campus-exabgp
RUN chmod 0755 /usr/local/lib/campus/wait-for-interface.sh /usr/local/bin/campus-exabgp

ENTRYPOINT ["/usr/local/bin/campus-exabgp"]
CMD ["/etc/exabgp/exabgp.conf"]
