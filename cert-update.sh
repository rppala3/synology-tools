#!/bin/sh

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
LOG_TAG="synotools/$SCRIPT_NAME"
ENV_FILE="$SCRIPT_DIR/env"

log_info() {
  logger -t "$LOG_TAG" -p daemon.info "$1"
  echo "$1"
}

log_warning() {
  logger -t "$LOG_TAG" -p daemon.warning "$1"
  echo "Warning: $1" >&2
}

die() {
  logger -t "$LOG_TAG" -p daemon.err "$1"
  echo "Error: $1" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  command_exists "$1" || die "Missing required command: $1"
}

require_var() {
  eval "value=\${$1:-}"
  [ -n "$value" ] || die "Missing required configuration value: $1"
}

check_file() {
  file="$1"
  [ -f "$file" ] || die "Missing file: $file"
  [ -r "$file" ] || die "File is not readable: $file"
}

json_value() {
  input="$1"
  shift
  printf '%s' "$input" | jq -r "$@"
}

curl_post() {
  if [ "${SYNO_VERIFY_TLS:-false}" = "true" ]; then
    curl -sS -X POST "$@"
  else
    curl -k -sS -X POST "$@"
  fi
}

session_id=""
syno_token=""
cert_id=""
cert_list_response=""
cert_list_error=""
SYNO_APP="${SYNO_APP:-Core}"

cleanup() {
  [ -n "$session_id" ] && dsm_logout
}

require_command curl
require_command jq

[ -f "$ENV_FILE" ] || die "Missing environment file: $ENV_FILE"
# shellcheck source=/dev/null
. "$ENV_FILE"

require_var SYNO_HOST
require_var SYNO_PORT
require_var SYNO_USER
require_var SYNO_PASS
require_var ACME_CERT_FILE
require_var ACME_KEY_FILE
require_var ACME_CA_FILE
require_var ACME_CERT_DESC

check_file "$ACME_CERT_FILE"
check_file "$ACME_KEY_FILE"
check_file "$ACME_CA_FILE"

AUTH_ENDPOINT="https://$SYNO_HOST:$SYNO_PORT/webapi/auth.cgi"
IMPORT_ENDPOINT="https://$SYNO_HOST:$SYNO_PORT/webapi/entry.cgi"
ACME_AS_DEFAULT="${ACME_AS_DEFAULT:-false}"

dsm_login() {
  LOGIN_RESPONSE=$(curl_post "$AUTH_ENDPOINT" \
    -d "api=SYNO.API.Auth" \
    -d "method=login" \
    -d "version=7" \
    -d "account=$SYNO_USER" \
    -d "passwd=$SYNO_PASS" \
    -d "session=$SYNO_APP" \
    -d "enable_syno_token=yes") || die "Authentication request to $SYNO_HOST failed."

  LOGIN_SUCCESS=$(json_value "$LOGIN_RESPONSE" '.success // false') || die "Authentication response was not valid JSON: $LOGIN_RESPONSE"
  if [ "$LOGIN_SUCCESS" != "true" ]; then
    die "Authentication on $SYNO_HOST failed. Response: $LOGIN_RESPONSE"
  fi

  session_id=$(json_value "$LOGIN_RESPONSE" '.data.sid // empty')
  syno_token=$(json_value "$LOGIN_RESPONSE" '.data.synotoken // empty')
  [ -n "$session_id" ] || die "Authentication on $SYNO_HOST did not return a session id. Response: $LOGIN_RESPONSE"

  log_info "Logged in successfully on $SYNO_HOST."
}

dsm_logout() {
  LOGOUT_RESPONSE=$(curl_post "$AUTH_ENDPOINT" \
    -d "api=SYNO.API.Auth" \
    -d "method=logout" \
    -d "version=7" \
    -d "session=$SYNO_APP" \
    -d "_sid=$session_id")
  LOGOUT_SUCCESS=$(json_value "$LOGOUT_RESPONSE" '.success // false')

  session_id=""

  if [ "$LOGOUT_SUCCESS" != "true" ]; then
    log_warning "Logout from $SYNO_HOST failed. Response: $LOGOUT_RESPONSE"
    return 1
  fi

  log_info "Logged out successfully from $SYNO_HOST."
}

dsm_cert_import() {
  import_url="$IMPORT_ENDPOINT?api=SYNO.Core.Certificate&version=1&method=import&session=$SYNO_APP&_sid=$session_id"

  set -- "$import_url"

  if [ -n "$syno_token" ]; then
    set -- "$@" -H "X-SYNO-TOKEN: $syno_token"
  fi

  set -- "$@" -F "as_default=$ACME_AS_DEFAULT"

  if [ -n "$cert_id" ]; then
    log_info "Found existing DSM certificate '$ACME_CERT_DESC' with id $cert_id. Replacing it."
    set -- "$@" -F "id=$cert_id"
  else
    log_info "No existing DSM certificate '$ACME_CERT_DESC' found. Importing it as a new certificate."
  fi

  UPLOAD_RESPONSE=$(curl_post "$@" \
    -F "desc=$ACME_CERT_DESC" \
    -F "key=@$ACME_KEY_FILE;type=application/x-x509-ca-cert" \
    -F "cert=@$ACME_CERT_FILE;type=application/x-x509-ca-cert" \
    -F "inter_cert=@$ACME_CA_FILE;type=application/x-x509-ca-cert")

  UPLOAD_SUCCESS=$(json_value "$UPLOAD_RESPONSE" '.success // false') || die "Upload certificate response was not valid JSON: $UPLOAD_RESPONSE"
  if [ "$UPLOAD_SUCCESS" != "true" ]; then
    die "Upload certificate failed on $SYNO_HOST. Response: $UPLOAD_RESPONSE"
  fi

  log_info "Certificate uploaded successfully on $SYNO_HOST."
}

dsm_fetch_cert_list() {
  cert_api="$1"
  list_url="$IMPORT_ENDPOINT?api=$cert_api&version=1&method=list&session=$SYNO_APP&_sid=$session_id"

  set -- "$list_url"

  if [ -n "$syno_token" ]; then
    set -- "$@" -H "X-SYNO-TOKEN: $syno_token"
  fi

  cert_list_response=$(curl_post "$@") || {
    cert_list_error="Certificate list request using $cert_api failed."
    return 1
  }

  cert_list_success=$(json_value "$cert_list_response" '.success // false') || {
    cert_list_error="Certificate list response from $cert_api was not valid JSON: $cert_list_response"
    return 1
  }

  if [ "$cert_list_success" != "true" ]; then
    cert_list_error="Certificate list using $cert_api failed. Response: $cert_list_response"
    return 1
  fi
}

dsm_find_cert_id_by_desc() {
  if ! dsm_fetch_cert_list "SYNO.Core.Certificate"; then
    log_warning "$cert_list_error"
    dsm_fetch_cert_list "SYNO.Core.Certificate.CRT" || die "$cert_list_error"
  fi

  cert_match_count=$(json_value "$cert_list_response" --arg desc "$ACME_CERT_DESC" '[.data.certificates[]? | select(.desc == $desc)] | length')
  case "$cert_match_count" in
    0)
      cert_id=""
      return 0
      ;;
    1)
      cert_id=$(json_value "$cert_list_response" --arg desc "$ACME_CERT_DESC" '.data.certificates[]? | select(.desc == $desc) | .id')
      ;;
    *)
      die "Found $cert_match_count DSM certificates with description '$ACME_CERT_DESC'. Make certificate descriptions unique before importing."
      ;;
  esac
}

trap cleanup EXIT HUP INT TERM

log_info "Starting certificate import for $ACME_CERT_DESC."
dsm_login
dsm_find_cert_id_by_desc
dsm_cert_import
dsm_logout
trap - EXIT HUP INT TERM
