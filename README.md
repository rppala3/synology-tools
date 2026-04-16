# synology-tools

Import a Let's Encrypt certificate managed by pfSense into Synology DSM.

The intended setup is:

1. pfSense renews the certificate with the ACME package.
2. pfSense runs `cert-update.sh` as a deploy/renewal action.
3. The script reads the renewed certificate files from pfSense and imports them into DSM over the LAN.

This keeps DSM off the public Internet while still letting DSM use the same public certificate.

## Setup

Copy the sample environment file and lock down the real one:

```sh
cp env-dist env
chmod go-rwx env
```

Edit `env`:

```sh
SYNO_HOST="nas.example.lan"
SYNO_PORT=5001
SYNO_USER="certificate-import-user"
SYNO_PASS="change-me"

ACME_PATH="/conf/acme"
ACME_CERT_FILE="$ACME_PATH/example.com.crt"
ACME_KEY_FILE="$ACME_PATH/example.com.key"
ACME_CA_FILE="$ACME_PATH/example.com.ca"
ACME_CERT_DESC="example.com"
```

If you are replacing an existing DSM certificate, set `ACME_CERT_ID` to that certificate id.
If `ACME_CERT_ID` is empty, DSM imports the certificate as a new certificate.

## pfSense Deploy Action

Install the repository on pfSense somewhere persistent, for example:

```sh
/root/synology-tools
```

In the pfSense ACME certificate configuration, add a deploy/renewal action that runs:

```sh
/root/synology-tools/cert-update.sh
```

The script loads `env` from the same directory as the script, so it does not depend on the current working directory used by the ACME hook.

## Requirements

The pfSense host running the script needs:

- `curl`
- `jq`
- read access to the pfSense ACME certificate, key, and CA files
- HTTPS access to DSM on the LAN

## Troubleshooting

Run the script manually on pfSense first:

```sh
/root/synology-tools/cert-update.sh
```

The script logs to syslog with a tag like `synotools/cert-update.sh`.
On failure, it prints and logs the DSM JSON response so you can see whether the problem is authentication, permissions, certificate id, or the import payload.

Common checks:

- Confirm the files in `ACME_CERT_FILE`, `ACME_KEY_FILE`, and `ACME_CA_FILE` exist on pfSense.
- Confirm the DSM account can manage certificates.
- Confirm `ACME_CERT_ID` is correct if you are replacing an existing certificate.
- Set `SYNO_VERIFY_TLS=false` if pfSense does not trust the current DSM certificate.

## Reference

[N4S4/synology-api](https://github.com/N4S4/synology-api)
