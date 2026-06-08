#!/usr/bin/env bash
# Render the matrix-alertmanager-receiver runtime config from its template by
# injecting the @alertbot access token and alerts room ID.
#
# The observability stack runs on a DIFFERENT host than Matrix, so there is no
# OpenBao or internal Synapse here. The bot credentials are provisioned once on
# server01 (matrix/provision-alertbot.sh) and carried to this host.
#
# Sources, in priority order:
#   1. Environment overrides ALERTBOT_TOKEN / ALERTS_ROOM_ID.
#   2. A local secret file (default: alongside this script as `secret.env`),
#      gitignored, containing:
#        ALERTBOT_TOKEN=syt_...
#        ALERTS_ROOM_ID=!abc123:chat.datainmotion.com
#
# The rendered file (config/matrix-receiver/config.yaml) is gitignored.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/config.yaml.template"
OUTPUT="${SCRIPT_DIR}/config.yaml"
SECRET_ENV="${SECRET_ENV:-${SCRIPT_DIR}/secret.env}"

# Load the local secret file unless both values are already in the environment.
if [[ -z "${ALERTBOT_TOKEN:-}" || -z "${ALERTS_ROOM_ID:-}" ]]; then
  if [[ -f "${SECRET_ENV}" ]]; then
    # shellcheck disable=SC1090
    set -a; source "${SECRET_ENV}"; set +a
  fi
fi

TOKEN="${ALERTBOT_TOKEN:-}"
ROOM_ID="${ALERTS_ROOM_ID:-}"

if [[ -z "${TOKEN}" || -z "${ROOM_ID}" ]]; then
  echo "ERROR: ALERTBOT_TOKEN and/or ALERTS_ROOM_ID not set." >&2
  echo "       Provision them on server01 with matrix/provision-alertbot.sh," >&2
  echo "       then export them or write ${SECRET_ENV}." >&2
  exit 1
fi

python3 - "${TEMPLATE}" "${OUTPUT}" "${TOKEN}" "${ROOM_ID}" <<'PY'
import pathlib, sys
template, output, token, room_id = sys.argv[1:5]
text = pathlib.Path(template).read_text()
text = text.replace("ACCESS_TOKEN_PLACEHOLDER", token)
text = text.replace("ROOM_ID_PLACEHOLDER", room_id)
pathlib.Path(output).write_text(text)
PY

chmod 600 "${OUTPUT}"
echo "Rendered ${OUTPUT}"
