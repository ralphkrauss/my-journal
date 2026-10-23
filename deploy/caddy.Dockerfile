# Official multi-platform Caddy 2.11.4 image; pin reviewed updates to an immutable index.
FROM caddy:2.11.6-alpine@sha256:d44355d3c2149dc580ce2cac735955d1c08d3d00882c30489c241aa51a5c10d9
# High container ports do not need the upstream binary’s low-port capability.
RUN setcap -r /usr/bin/caddy && chown -R 1000:1000 /data /config
USER 1000:1000
