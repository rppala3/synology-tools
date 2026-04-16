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

The script looks up an existing DSM certificate by `ACME_CERT_DESC`.
If no certificate with that description exists, DSM imports it as a new certificate.
If exactly one matching certificate exists, DSM replaces that certificate.
Keep certificate descriptions unique in DSM so renewals update the right certificate.

## pfSense Deploy Action

Install the repository on pfSense somewhere persistent, for example:

```sh
git clone git@github.com:rppala3/synology-tools.git /opt/synotools
```

In the pfSense ACME certificate configuration, add a deploy/renewal action that runs:

```sh
/opt/synotools/cert-update.sh
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
/opt/synotools/cert-update.sh
```

The script logs to syslog with a tag like `synotools/cert-update.sh`.
On failure, it prints and logs the DSM JSON response so you can see whether the problem is authentication, permissions, certificate id, or the import payload.

Common checks:

- Confirm the files in `ACME_CERT_FILE`, `ACME_KEY_FILE`, and `ACME_CA_FILE` exist on pfSense.
- Confirm the DSM account can manage certificates.
- Confirm `ACME_CERT_DESC` matches a unique DSM certificate description if you are replacing an existing certificate.
- Set `SYNO_VERIFY_TLS=false` if pfSense does not trust the current DSM certificate.

## Reference

[N4S4/synology-api](https://github.com/N4S4/synology-api)
