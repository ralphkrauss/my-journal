# Official multi-platform Caddy 2.11.4 image; pin reviewed updates to an immutable index.
FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0
# High container ports do not need the upstream binary’s low-port capability.
RUN setcap -r /usr/bin/caddy && chown -R 1000:1000 /data /config
USER 1000:1000
