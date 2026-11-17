#!/bin/bash
# Creates a self-signed code-signing identity, "Kyo Local Signing", in the
# login keychain. Signing with it gives the app an identity that survives
# rebuilds, so macOS keeps the calendar permission. Run once per Mac.
# No trust settings are changed; the certificate only has to exist.
set -euo pipefail

NAME="Kyo Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cfg" <<CONFIG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CONFIG

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cfg" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# The passphrase only protects the bundle on its way into the keychain.
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/id.p12" -passout "pass:$PASS"
KEYCHAIN="$(security default-keychain | sed 's/^ *"//; s/"$//')"
# -x: the private key can be used for signing but never exported again.
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$PASS" -x -T /usr/bin/codesign
echo "Created \"$NAME\". Scripts/build-app.sh will use it from now on."
