#!/bin/bash
# Write admin credentials for $1 to env file $2 (0600): ADMIN_PASSWORD from the environment, else /etc/admin-openrc.sh over ssh.
set -euo pipefail
target=$1 envf=$2
umask 077; : > "$envf"
if [ -n "${ADMIN_PASSWORD:-}" ]; then
    printf 'ADMIN_USER=%s\nADMIN_PASSWORD=%s\nADMIN_PROJECT=%s\n' "${ADMIN_USER:-admin}" "$ADMIN_PASSWORD" "${ADMIN_PROJECT:-admin}" > "$envf"
    exit 0
fi
cmd='. /etc/admin-openrc.sh >/dev/null 2>&1; printf "ADMIN_USER=%s\nADMIN_PASSWORD=%s\nADMIN_PROJECT=%s\n" "$OS_USERNAME" "$OS_PASSWORD" "$OS_PROJECT_NAME"'
"$(dirname "$0")/node-ssh.sh" "$target" "$cmd" > "$envf" || true
if ! grep -q '^ADMIN_PASSWORD=.' "$envf"; then
    rm -f "$envf"
    echo "==> ERROR: no admin credentials: set ADMIN_PASSWORD or ROOT_PASS (default Cube@<last two octets>), or an ssh key for root@$target" >&2
    exit 2
fi
