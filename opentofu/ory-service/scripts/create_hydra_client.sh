#!/bin/bash
set -euo pipefail

LOG=/var/log/grafana-oidc-setup.log
mkdir -p "$(dirname "$LOG")"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG" ; }

need_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    log "ERROR: '$bin' not found in AMI. Aborting."
    exit 1
  fi
}

need_bin curl
need_bin openssl
need_bin docker

: "${hydra_admin_url:?hydra_admin_url missing}"
: "${hydra_public_url:?hydra_public_url missing}"
: "${grafana_client_id:?grafana_client_id missing}"
: "${grafana_org_role:=Viewer}"
: "${grafana_domain:=}"  # 비어 있으면 IP 기반으로 동작

# Docker 서비스 기동(설치 가정)
if ! systemctl is-active --quiet docker; then
  log "Docker service is not active. Trying to start..."
  systemctl start docker || { log "ERROR: failed to start docker service"; exit 1; }
fi

log "Checking Hydra Admin API..."
for i in {1..12}; do
  if curl -k -s -f -L "${hydra_admin_url}/clients" >/dev/null 2>&1; then
    log "Hydra Admin API reachable"
    break
  fi
  log "Attempt $i: not reachable, wait 5s..."
  [[ $i -eq 12 ]] && { log "ERROR: Hydra admin unreachable"; exit 1; }
  sleep 5
done

# ROOT_URL 계산 (기본: IP:3000)
META=http://169.254.169.254/latest/meta-data
PUBLIC_IP="$(curl -s "$META/public-ipv4" || true)"
if [[ -z "${PUBLIC_IP}" ]]; then
  # 메타데이터가 없을 때 대비 (옵션)
  PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

if [[ -n "${grafana_domain}" ]]; then
  ROOT_URL="${grafana_domain%/}"
else
  ROOT_URL="http://${PUBLIC_IP}:3000"
fi
log "Grafana ROOT_URL: $ROOT_URL"

CLIENT_ID="${grafana_client_id}"
CLIENT_SECRET="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)"

# Hydra 클라이언트 payload (ROOT_URL 기준으로 콜백 정렬)
mk_payload() {
  cat <<JSON
{
  "client_id": "${1}",
  "client_secret": "${2}",
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code", "token", "id_token"],
  "redirect_uris": ["${ROOT_URL}/login/generic_oauth"],
  "post_logout_redirect_uris": ["${ROOT_URL}/logout"],
  "scope": "openid offline_access profile email",
  "token_endpoint_auth_method": "client_secret_basic",
  "skip_consent": true,
  "skip_logout_consent": true
}
JSON
}

# 클라이언트 업서트: PUT -> 안되면 POST
log "Upserting Hydra OAuth2 client '${CLIENT_ID}' via PUT..."
RESP="$(mk_payload "$CLIENT_ID" "$CLIENT_SECRET" | \
  curl -k -s -L -w $'\n%{http_code}' -X PUT "${hydra_admin_url}/clients/${CLIENT_ID}" \
    -H "Content-Type: application/json" -d @-)"
CODE="$(tail -n1 <<<"$RESP")"
BODY="$(sed '$d' <<<"$RESP")"

if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
  log "Hydra client upserted via PUT (secret masked)."
  EFFECTIVE_ID="$CLIENT_ID"
  EFFECTIVE_SECRET="$CLIENT_SECRET"
else
  if [[ "$CODE" == "405" || "$CODE" == "403" || "$CODE" == "501" || "$CODE" == "404" ]]; then
    log "PUT not accepted (HTTP $CODE). Falling back to POST /clients…"
    RESP2="$(mk_payload "$CLIENT_ID" "$CLIENT_SECRET" | \
      curl -k -s -L -w $'\n%{http_code}' -X POST "${hydra_admin_url}/clients" \
        -H "Content-Type: application/json" -d @-)"
    CODE2="$(tail -n1 <<<"$RESP2")"
    BODY2="$(sed '$d' <<<"$RESP2")"

    if [[ "$CODE2" == "201" ]]; then
      log "Hydra client created via POST with id='${CLIENT_ID}'."
      EFFECTIVE_ID="$CLIENT_ID"
      EFFECTIVE_SECRET="$CLIENT_SECRET"
    elif [[ "$CODE2" == "409" ]]; then
      NEW_ID="${CLIENT_ID}-$(date +%s)"
      NEW_SECRET="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)"
      log "Client id '${CLIENT_ID}' already exists and cannot be updated. Creating new id '${NEW_ID}'…"
      RESP3="$(mk_payload "$NEW_ID" "$NEW_SECRET" | \
        curl -k -s -L -w $'\n%{http_code}' -X POST "${hydra_admin_url}/clients" \
          -H "Content-Type: application/json" -d @-)"
      CODE3="$(tail -n1 <<<"$RESP3")"
      BODY3="$(sed '$d' <<<"$RESP3")"
      if [[ "$CODE3" == "201" ]]; then
        log "Hydra client created with new id='${NEW_ID}'."
        EFFECTIVE_ID="$NEW_ID"
        EFFECTIVE_SECRET="$NEW_SECRET"
      else
        log "ERROR: Failed to create client with new id. HTTP $CODE3"
        log "Response: $BODY3"
        exit 1
      fi
    else
      log "ERROR: Failed to create client via POST. HTTP $CODE2"
      log "Response: $BODY2"
      exit 1
    fi
  else
    log "ERROR: Failed to upsert client via PUT. HTTP $CODE"
    log "Response: $BODY"
    exit 1
  fi
fi

# Grafana env 생성
mkdir -p /opt/grafana
ENV=/opt/grafana/grafana.env
umask 177
cat > "$ENV" <<EOF
GF_SERVER_ROOT_URL=${ROOT_URL}
GF_USERS_AUTO_ASSIGN_ORG_ROLE=${grafana_org_role}

GF_AUTH_DISABLE_LOGIN_FORM=true
GF_AUTH_SIGNOUT_REDIRECT_URL=${ROOT_URL}

GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_NAME=ORY
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=${EFFECTIVE_ID}
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${EFFECTIVE_SECRET}
GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email offline_access
GF_AUTH_GENERIC_OAUTH_AUTH_URL=${hydra_public_url}/oauth2/auth
GF_AUTH_GENERIC_OAUTH_TOKEN_URL=${hydra_public_url}/oauth2/token
GF_AUTH_GENERIC_OAUTH_API_URL=${hydra_public_url}/userinfo

GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_PATH=email
GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH=preferred_username
EOF
chmod 600 "$ENV"
log "Wrote Grafana env at $ENV"

# docker-compose 작성 (Compose v2: version 키 없이)
COMPOSE=/opt/grafana/docker-compose.yml
cat > "$COMPOSE" <<'YAML'
services:
  grafana:
    image: grafana/grafana-oss:10.4.6
    container_name: grafana
    ports:
      - "3000:3000"
    env_file:
      - /opt/grafana/grafana.env
    volumes:
      - /opt/grafana/data:/var/lib/grafana
    restart: unless-stopped
YAML

# 데이터 디렉터리 준비 + 권한 (UID 472)
mkdir -p /opt/grafana/data
chown -R 472:472 /opt/grafana/data || true
chmod -R u+rwX /opt/grafana/data || true

# 배포/재기동
docker compose -f /opt/grafana/docker-compose.yml up -d --force-recreate
log "Grafana deployment completed. Access: ${ROOT_URL} (client_id=${EFFECTIVE_ID})"
