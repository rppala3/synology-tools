#!/bin/sh

. ./env

SCRIPT_NAME=$(basename "$0")

AUTH_ENDPOINT="https://$SYNO_HOST:$SYNO_PORT/webapi/auth.cgi"
IMPORT_ENDPOINT="https://$SYNO_HOST:$SYNO_PORT/webapi/entry.cgi"

# Certificate files
CERT_FILE="$ACME_PATH/gargantua.wilsley.xyz.crt"
KEY_FILE="$ACME_PATH/gargantua.wilsley.xyz.key"
CA_FILE="$ACME_PATH/gargantua.wilsley.xyz.ca"
CERT_DESC="gargantua.wilsley.xyz"

[ -f "$CERT_FILE" ] || echo "Missing certificate file: $CERT_FILE"
[ -f "$KEY_FILE" ] || echo "Missing key file: $KEY_FILE"
[ -f "$CA_FILE" ] || echo "Missing CA file: $CA_FILE"

session_id=""
syno_token="" # Not used
SYNO_APP="Core"

# Function: Login to DSM
dsm_login() {
  LOGIN_RESPONSE=$(curl -k -s -X POST $AUTH_ENDPOINT \
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
    logger -t $SCRIPT_NAME -p daemon.err $msg
    echo "Error: $msg"
    exit 1
  fi

  session_id=$(echo "$LOGIN_RESPONSE" | jq -r '.data.sid')
  # syno_token=$(echo "$LOGIN_RESPONSE" | jq -r '.data.synotoken')
  msg="Logged in successfully."
  # msg="Logged in successfully.\n  syno_token: $syno_token\n  Session ID: $session_id"
  logger -t $SCRIPT_NAME -p daemon.info $msg
  echo $msg
}

# Function: Logout from DSM
dsm_logout() {
  LOGOUT_RESPONSE=$(curl -k -s -X POST $AUTH_ENDPOINT \
    -d "api=SYNO.API.Auth" \
    -d "method=logout" \
    -d "version=7" \
    -d "session=$SYNO_APP" \
    -d "_sid=$session_id")
  LOGOUT_SUCCESS=$(echo "$LOGOUT_RESPONSE" | jq -r '.success')

  if [ "$LOGOUT_SUCCESS" != "true" ]; then
    msg="Logout failed. Session might still be active."
    logger -t $SCRIPT_NAME -p daemon.warning $msg
    echo "Warning: $msg"
    exit 1
  fi

  msg="Logged out successfully."
  logger -t $SCRIPT_NAME -p daemon.info $msg
  echo $msg
}

# Function: Import TLS Certificate
dsm_cert_import() {
  UPLOAD_RESPONSE=$(curl -k -s -X POST "$IMPORT_ENDPOINT?api=SYNO.Core.Certificate&version=1&method=import&session=$SYNO_APP&_sid=$session_id" \
    -F "as_default=false" \
    -F "id=$ACME_CERT_ID" \
    -F "desc=$CERT_DESC" \
    -F "key=@$KEY_FILE;type=application/x-x509-ca-cert" \
    -F "cert=@$CERT_FILE;type=application/x-x509-ca-cert" \
    -F "inter_cert=@$CA_FILE;type=application/x-x509-ca-cert")
  #   -H "X-SYNO-TOKEN: $syno_token" \

  UPLOAD_SUCCESS=$(echo "$UPLOAD_RESPONSE" | jq -r '.success')
  if [ "$UPLOAD_SUCCESS" != "true" ]; then
    msg="Upload certificate failed.\nResponse: $UPLOAD_RESPONSE"
    logger -t $SCRIPT_NAME -p daemon.err $msg
    echo "Error: $msg"
    dsm_logout
    exit 1
  fi

  msg="Certificate uploaded successfully."
  logger -t $SCRIPT_NAME -p daemon.info $msg
  echo $msg
}

# Main Script Execution
dsm_login
dsm_cert_import
dsm_logout
