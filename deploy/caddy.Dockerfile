# Official multi-platform Caddy 2.11.4 image; pin reviewed updates to an immutable index.
FROM caddy:2.11.7-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f
# High container ports do not need the upstream binary’s low-port capability.
RUN setcap -r /usr/bin/caddy && chown -R 1000:1000 /data /config
USER 1000:1000
