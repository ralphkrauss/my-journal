# Official multi-platform Caddy 2.11.4 image; pin reviewed updates to an immutable index.
FROM caddy:2.11.4-alpine@sha256:6aeddd44c3078b0f9a35206472a11420648a79c184603ef95957d0a20044cb2b
# High container ports do not need the upstream binary’s low-port capability.
RUN setcap -r /usr/bin/caddy && chown -R 1000:1000 /data /config
USER 1000:1000
