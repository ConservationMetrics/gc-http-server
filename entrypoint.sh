#!/bin/sh
set -eu

DATA_MOUNT="${DATA_MOUNT:-/data_mount}"

if [ -z "${DIRECTORY:-}" ]; then
  echo "error: DIRECTORY is required" >&2
  exit 1
fi

case "$DIRECTORY" in
  /*|*..*)
    echo "error: DIRECTORY must be a relative path without '..' (got: $DIRECTORY)" >&2
    exit 1
    ;;
esac

SERVE_PATH="${DATA_MOUNT}/${DIRECTORY}"

if [ ! -d "$SERVE_PATH" ]; then
  echo "error: serve path does not exist or is not a directory: $SERVE_PATH" >&2
  echo "hint: mount the host datalake at $DATA_MOUNT, then set DIRECTORY to a folder under it" >&2
  exit 1
fi

HTTP_ROOT="$SERVE_PATH"

if [ -n "${DATA_DIRECTORY:-}" ]; then
  case "$DATA_DIRECTORY" in
    .|/*|*..*)
      echo "error: DATA_DIRECTORY must be a non-root relative path without '..' (got: $DATA_DIRECTORY)" >&2
      exit 1
      ;;
  esac

  DATA_PATH="${DATA_MOUNT}/${DATA_DIRECTORY}"
  if [ ! -d "$DATA_PATH" ]; then
    echo "error: data path does not exist or is not a directory: $DATA_PATH" >&2
    exit 1
  fi

  if [ -e "$SERVE_PATH/data" ] || [ -L "$SERVE_PATH/data" ]; then
    echo "error: app directory already contains the reserved path: $SERVE_PATH/data" >&2
    exit 1
  fi

  HTTP_ROOT="/tmp/gc-http-server-root"
  rm -rf "$HTTP_ROOT"
  mkdir -p "$HTTP_ROOT"
  find "$SERVE_PATH" -mindepth 1 -maxdepth 1 -exec ln -s {} "$HTTP_ROOT/" \;
  ln -s "$DATA_PATH" "$HTTP_ROOT/data"
fi

auth_enabled=$(printf '%s' "${AUTH_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
case "$auth_enabled" in
  true) ;;
  false | "")
    exec httpd -f -p 8080 -h "$HTTP_ROOT" -c /etc/httpd.conf
    ;;
  *)
    echo "error: AUTH_ENABLED must be true or false (got: $auth_enabled)" >&2
    exit 1
    ;;
esac

missing=""
require_line() {
  if [ -z "$2" ]; then
    missing="$missing $1"
    return
  fi
  case "$2" in
    *"
"*)
      echo "error: $1 must be a single line" >&2
      exit 1
      ;;
  esac
}
require_line OAUTH2_PROXY_CLIENT_ID "${OAUTH2_PROXY_CLIENT_ID:-}"
require_line OAUTH2_PROXY_CLIENT_SECRET "${OAUTH2_PROXY_CLIENT_SECRET:-}"
require_line OAUTH2_PROXY_OIDC_ISSUER_URL "${OAUTH2_PROXY_OIDC_ISSUER_URL:-}"
require_line OAUTH2_PROXY_REDIRECT_URL "${OAUTH2_PROXY_REDIRECT_URL:-}"
require_line OAUTH2_PROXY_COOKIE_SECRET "${OAUTH2_PROXY_COOKIE_SECRET:-}"
if [ -n "$missing" ]; then
  echo "error: AUTH_ENABLED=true requires:$missing" >&2
  exit 1
fi

cookie_secure=$(printf '%s' "${OAUTH2_PROXY_COOKIE_SECURE:-true}" | tr '[:upper:]' '[:lower:]')
case "$cookie_secure" in
  true | false) ;;
  *)
    echo "error: OAUTH2_PROXY_COOKIE_SECURE must be true or false" >&2
    exit 1
    ;;
esac

issuer=$OAUTH2_PROXY_OIDC_ISSUER_URL
redirect=$OAUTH2_PROXY_REDIRECT_URL

case "$cookie_secure" in
  true)
    case "$redirect" in
      https://*/oauth2/callback) ;;
      http://*)
        echo "error: OAUTH2_PROXY_COOKIE_SECURE=false is required for an http redirect URL (local testing only)" >&2
        exit 1
        ;;
      *)
        echo "error: OAUTH2_PROXY_REDIRECT_URL must be an absolute https URL ending in /oauth2/callback" >&2
        exit 1
        ;;
    esac
    case "$issuer" in
      https://*) ;;
      *)
        echo "error: OAUTH2_PROXY_OIDC_ISSUER_URL must use https" >&2
        exit 1
        ;;
    esac
    cookie_name=__Host-gc_auth
    ;;
  false)
    case "$redirect" in
      https://*)
        echo "error: OAUTH2_PROXY_COOKIE_SECURE must be true when OAUTH2_PROXY_REDIRECT_URL is https" >&2
        exit 1
        ;;
    esac
    case "$issuer" in
      https://* | http://*) ;;
      *)
        echo "error: OAUTH2_PROXY_OIDC_ISSUER_URL must be an absolute http(s) URL" >&2
        exit 1
        ;;
    esac
    case "$redirect" in
      http://*/oauth2/callback) ;;
      *)
        echo "error: OAUTH2_PROXY_REDIRECT_URL must be an absolute URL ending in /oauth2/callback" >&2
        exit 1
        ;;
    esac
    cookie_name=_gc_auth
    ;;
esac

case "$issuer$redirect" in
  *'?'* | *'#'* | *' '*)
    echo "error: OIDC issuer and redirect URLs must not contain a query, fragment, or space" >&2
    exit 1
    ;;
esac

# Percent-encode the filesystem path so spaces survive the file:// upstream URL.
encoded_root=$(
  printf '%s' "$HTTP_ROOT" | od -An -tu1 | tr -s '[:space:]' '\n' | awk '
    $1 == "" { next }
    {
      n = $1 + 0
      c = sprintf("%c", n)
      if (c ~ /^[A-Za-z0-9._~-]$/ || c == "/") printf "%s", c
      else printf "%%%02X", n
    }
  '
)
app_host=${redirect#*://}
app_host=${app_host%%/*}
issuer_host=${issuer#*://}
issuer_host=${issuer_host%%/*}

# Drop the inherited environment so OAUTH2_PROXY_SKIP_AUTH_* and other proxy
# settings cannot exempt mounted paths. Only the arguments below are honored.
exec env -i \
  SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}" \
  /bin/oauth2-proxy \
  --provider=oidc \
  --provider-display-name=Auth0 \
  --oidc-issuer-url="$issuer" \
  --client-id="$OAUTH2_PROXY_CLIENT_ID" \
  --client-secret="$OAUTH2_PROXY_CLIENT_SECRET" \
  --redirect-url="$redirect" \
  --scope="openid email profile" \
  --skip-claims-from-profile-url=true \
  --insecure-oidc-allow-unverified-email=true \
  --oidc-groups-claim=urn:gc:roles \
  --allowed-group=Member \
  --allowed-group=Admin \
  --code-challenge-method=S256 \
  --email-domain="*" \
  --cookie-secret="$OAUTH2_PROXY_COOKIE_SECRET" \
  --cookie-secure="$cookie_secure" \
  --cookie-httponly=true \
  --cookie-samesite=lax \
  --cookie-name="$cookie_name" \
  --session-cookie-minimal=true \
  --skip-provider-button=true \
  --reverse-proxy=true \
  --trusted-proxy-ip=127.0.0.1 \
  --trusted-proxy-ip=10.0.0.0/8 \
  --trusted-proxy-ip=172.16.0.0/12 \
  --trusted-proxy-ip=192.168.0.0/16 \
  --trusted-proxy-ip=::1 \
  --trusted-proxy-ip=fc00::/7 \
  --whitelist-domain="$app_host" \
  --whitelist-domain="$issuer_host" \
  --http-address=0.0.0.0:8080 \
  --upstream="file://${encoded_root}/#/" \
  --silence-ping-logging=true
