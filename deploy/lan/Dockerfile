# Publishes the server on the local network with Bonjour so apps can offer it without typing its address.
# Alpine 3.22.6; pin reviewed updates to an immutable index.
FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
RUN apk add --no-cache avahi=0.8-r21
COPY avahi-daemon.conf /etc/avahi/avahi-daemon.conf
COPY announce.sh /usr/local/bin/announce
# Avahi runs without D-Bus, chroot or root; it only needs the unprivileged mDNS port 5353.
USER avahi
ENTRYPOINT ["/usr/local/bin/announce"]
