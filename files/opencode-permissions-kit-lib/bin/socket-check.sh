#!/bin/sh
# opencode permissions kit -- socket-check.sh
#
# Verifies that a unix socket path exists and is actually a socket. The wrapper
# uses this as the reachability probe for the rootless container backends
# (docker-rootless / podman-rootless): those sockets live in the opencode user's
# runtime dir (/run/user/<uid>, mode 700 opencode:opencode), which a
# developer-running wrapper cannot stat. The wrapper therefore re-runs this
# check as the opencode user via the kit's NOPASSWD sudoers rule, so the probe
# runs from the same context that will actually connect to the daemon.
#
# Accepts "unix://..." or a plain path. Exits 0 if the socket is reachable,
# non-zero otherwise. Deliberately does nothing but `test -S` — it is gated to
# this exact script in sudoers and must never gain extra power.
sock="${1:-}"
case "$sock" in unix://*) sock="${sock#unix://}";; esac
[ -n "$sock" ] && [ -S "$sock" ]
