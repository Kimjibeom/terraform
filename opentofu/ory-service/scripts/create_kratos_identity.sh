#!/bin/bash
set -euo pipefail

LOG=/var/log/kratos-provisioning.log
mkdir -p "$(dirname "$LOG")"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG" ; }

need_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "missing"
    return 1
  fi
}

ensure_jq() {
  if need_bin jq >/dev/null 2>&1; then
    return 0
  fi
  log "jq not found. Installing minimal dependency (APT)…"
  export DEBIAN_FRONTEND=noninteractive
  # 간단한 3회 재시도 로직
  for i in {1..3}; do
    (apt-get update && apt-get install -y jq) && break || sleep 3
    [[ $i -eq 3 ]] && { log "ERROR: failed to install jq"; exit 1; }
  done
  log "jq installed."
}

# 필수 도구 확인 (curl/openssl은 기본 탑재 가정)
command -v curl >/dev/null 2>&1 || { log "ERROR: curl is required"; exit 1; }
command -v openssl >/dev/null 2>&1 || { log "ERROR: openssl is required"; exit 1; }
ensure_jq

: "${kratos_admin_url:?kratos_admin_url missing}"
: "${user_email:?user_email missing}"
: "${user_name:?user_name missing}"
USER_ROLE="${user_role:-user}"

log "Starting Kratos identity provisioning..."
log "Using role: $USER_ROLE"
log "Testing connection to Kratos Admin API..."
for i in {1..12}; do
  if curl -k -s -f "${kratos_admin_url}/identities" >/dev/null 2>&1; then
    log "Kratos Admin API is accessible"
    break
  fi
  log "Attempt $i: not ready, wait 5s..."
  [[ $i -eq 12 ]] && { log "ERROR: Kratos admin unreachable"; exit 1; }
  sleep 5
done

PW="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)"
log "Generated temporary password for in-memory use"

log "Checking if user already exists..."
EXISTING_USER="$(curl -k -s "${kratos_admin_url}/identities" \
  | jq -r --arg email "${user_email}" '.[] | select(.traits.email == $email) | .id' 2>/dev/null || echo "")"

if [[ -n "$EXISTING_USER" ]]; then
  log "User ${user_email} already exists (ID: $EXISTING_USER). Skipping."
  unset PW
  exit 0
fi

TRAITS="$(jq -nc --arg email "${user_email}" --arg name "${user_name}" --arg role "$USER_ROLE" \
  '{email:$email,name:$name,role:$role}')"
JSON_DATA="$(jq -nc --argjson traits "$TRAITS" --arg pw "$PW" \
  '{schema_id:"default",state:"active",traits:$traits,credentials:{password:{config:{password:$pw}}},verifiable_addresses:[{value:$traits.email,via:"email",verified:true,status:"completed"}],recovery_addresses:[{value:$traits.email,via:"email"}]}')"

JSON_DATA_MASKED="$(echo "$JSON_DATA" | sed 's/"password":"[^"]*"/"password":"***MASKED***"/g')"
log "Request JSON: $JSON_DATA_MASKED"

log "Creating identity..."
RESPONSE="$(curl -k -s -w $'\n%{http_code}' -X POST "${kratos_admin_url}/identities" \
  -H "Content-Type: application/json" -H "Accept: application/json" -d "$JSON_DATA" \
  --connect-timeout 30 --max-time 60)"

unset PW
log "Temporary password variable has been unset from memory."

HTTP_CODE="$(tail -n1 <<<"$RESPONSE")"
BODY="$(sed '$d' <<<"$RESPONSE")"
log "HTTP Response Code: $HTTP_CODE"
[[ "$HTTP_CODE" != "201" ]] && log "Response Body: $BODY"

if [[ "$HTTP_CODE" == "201" ]]; then
  IDENTITY_ID="$(echo "$BODY" | jq -r '.id // "unknown"')"
  log "SUCCESS: Identity created (ID: $IDENTITY_ID)"
  {
    echo "========================================"
    echo "🔐 ORY Kratos Identity Created"
    echo "========================================"
    echo "Email     : ${user_email}"
    echo "Name      : ${user_name}"
    echo "Role      : $USER_ROLE"
    echo "ID        : $IDENTITY_ID"
    echo "Created   : $(date)"
    echo "Admin URL : ${kratos_admin_url}"
    echo "----------------------------------------"
    echo "ACTION: Use 'Forgot Password' to set initial password."
    echo "========================================"
  } > /tmp/kratos_user_info.txt
elif [[ "$HTTP_CODE" == "409" ]]; then
  log "WARNING: Identity may already exist (409)"
else
  log "ERROR: Failed to create identity. HTTP $HTTP_CODE"
  exit 1
fi

log "Kratos provisioning done."
