# Official multi-platform Caddy 2.11.4 image; pin reviewed updates to an immutable index.
FROM caddy:2.11.8-alpine@sha256:f6228111e5fafa1a5238258d0858e103f10599b8d1659a146e7726681a002bb9
# High container ports do not need the upstream binary’s low-port capability.
RUN setcap -r /usr/bin/caddy && chown -R 1000:1000 /data /config
USER 1000:1000
