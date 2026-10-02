#!/bin/sh
# Writes the service description from JOURNAL_URL, the HTTPS address devices connect to, then runs Avahi.
set -eu
url="${JOURNAL_URL:-}"
if ! printf '%s' "$url" | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$'; then
  echo "Set JOURNAL_URL to the server's HTTPS address, for example https://journal.example.ts.net." >&2
  exit 2
fi
url="${url%/}"
port="${url##*:}"
case "$port" in
  //*) port=443 ;;
esac
mkdir -p /run/avahi-daemon
cat >/etc/avahi/services/my-journal.service <<SERVICE
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">My Journal on %h</name>
  <service>
    <type>_myjournal._tcp</type>
    <port>$port</port>
    <txt-record>v=1</txt-record>
    <txt-record>url=$url</txt-record>
  </service>
</service-group>
SERVICE
exec avahi-daemon --no-drop-root --no-chroot --no-rlimits --no-proc-title
