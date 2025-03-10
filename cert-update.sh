#!/bin/sh

USER=$(whoami) # DEBUG
SCRIPT_NAME=$(basename "$0")
LOG_TAG="synotools/$SCRIPT_NAME"

# DEBUG
msg="Run by $USER"
logger -t "$LOG_TAG" -p daemon.info "$msg"
echo "$msg"
# /DEBUG

logger -t "$LOG_TAG" -p daemon.info "Test info message" # DEBUG
logger -t "$LOG_TAG" -p daemon.warning "Test warning message" # DEBUG
logger -t "$LOG_TAG" -p daemon.err "Test erroro message" # DEBUG

. ./env

logger -t "$LOG_TAG" -p daemon.info "Test '. ./env'" # DEBUG

AUTH_ENDPOINT="https://$SYNO_HOST:$SYNO_PORT/webapi/auth.cgi"
IMPORT_ENDPOINT="https://$SYNO_HOST:$SYNO_PORT/webapi/entry.cgi"

check_file() {
  local file="$1"
  local err_msg="$2"
  if [ ! -f "$file" ]; then
    logger -t "$LOG_TAG" -p daemon.err "$err_msg"
    echo "$err_msg"
    exit 1
  fi
}

check_file "$ACME_CERT_FILE" "Missing certificate file: $ACME_CERT_FILE"
check_file "$ACME_KEY_FILE" "Missing key file: $ACME_KEY_FILE"
check_file "$ACME_CA_FILE" "Missing CA file: $ACME_CA_FILE"

session_id=""
syno_token="" # Not used
SYNO_APP="Core"

# Function: Login to DSM
dsm_login() {
  LOGIN_RESPONSE=$(curl -k -s -X POST "$AUTH_ENDPOINT" \
    -d "api=SYNO.API.Auth" \
    -d "method=login" \
    -d "version=7" \
    -d "account=$SYNO_USER" \
    -d "passwd=$SYNO_PASS" \
    -d "session=$SYNO_APP")
    #   -d "enable_syno_token=yes" \

  LOGIN_SUCCESS=$(echo "$LOGIN_RESPONSE" | jq -r '.success')
  if [ "$LOGIN_SUCCESS" != "true" ]; then
    msg="Authentication on $SYNO_HOST failed."
    logger -t "$LOG_TAG" -p daemon.err "$msg"
    echo "Error: $msg"
    exit 1
  fi

  session_id=$(echo "$LOGIN_RESPONSE" | jq -r '.data.sid')
  # syno_token=$(echo "$LOGIN_RESPONSE" | jq -r '.data.synotoken')
  # echo "Logged in successfully.\n  syno_token: $syno_token\n  Session ID: $session_id"
  echo "Logged in successfully."
}

# Function: Logout from DSM
dsm_logout() {
  LOGOUT_RESPONSE=$(curl -k -s -X POST "$AUTH_ENDPOINT" \
    -d "api=SYNO.API.Auth" \
    -d "method=logout" \
    -d "version=7" \
    -d "session=$SYNO_APP" \
    -d "_sid=$session_id")
  LOGOUT_SUCCESS=$(echo "$LOGOUT_RESPONSE" | jq -r '.success')

  if [ "$LOGOUT_SUCCESS" != "true" ]; then
    msg="Logout failed. Session might still be active."
    logger -t "$LOG_TAG" -p daemon.warning "$msg"
    echo "Warning: $msg"
    exit 1
  fi

  echo "Logged out successfully."
}

# Function: Import TLS Certificate
dsm_cert_import() {
  UPLOAD_RESPONSE=$(curl -k -s -X POST "$IMPORT_ENDPOINT?api=SYNO.Core.Certificate&version=1&method=import&session=$SYNO_APP&_sid=$session_id" \
    -F "as_default=false" \
    -F "id=$ACME_CERT_ID" \
    -F "desc=$ACME_CERT_DESC" \
    -F "key=@$ACME_KEY_FILE;type=application/x-x509-ca-cert" \
    -F "cert=@$ACME_CERT_FILE;type=application/x-x509-ca-cert" \
    -F "inter_cert=@$ACME_CA_FILE;type=application/x-x509-ca-cert")
  #   -H "X-SYNO-TOKEN: $syno_token" \

  UPLOAD_SUCCESS=$(echo "$UPLOAD_RESPONSE" | jq -r '.success')
  if [ "$UPLOAD_SUCCESS" != "true" ]; then
    msg="Upload certificate failed on $SYNO_HOST.\nResponse: $UPLOAD_RESPONSE"
    logger -t "$LOG_TAG" -p daemon.err "$msg"
    echo "Error: $msg"
    dsm_logout
    exit 1
  fi

  msg="Certificate uploaded successfully on $SYNO_HOST."
  logger -t "$LOG_TAG" -p daemon.info "$msg"
  echo "$msg"
}

# Main Script Execution
dsm_login
dsm_cert_import
dsm_logout
