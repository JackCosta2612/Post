#!/bin/zsh
set -euo pipefail
SIGNING_NAME="Post Local Development"
if security find-certificate -c "$SIGNING_NAME" >/dev/null 2>&1; then
  echo "Post's local certificate already exists."
  exit 0
fi
umask 077
CERT_DIR="$(mktemp -d)"
trap 'rm -rf "$CERT_DIR"' EXIT
cat > "$CERT_DIR/extensions.cnf" <<'EOF'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = Post Local Development
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF
openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 -config "$CERT_DIR/extensions.cnf" -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/certificate.pem" 2>/dev/null
openssl rand -base64 32 > "$CERT_DIR/password"
openssl pkcs12 -export -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/certificate.pem" -out "$CERT_DIR/identity.p12" -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -passout "file:$CERT_DIR/password"
security import "$CERT_DIR/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$(cat "$CERT_DIR/password")" -T /usr/bin/codesign
echo "Created Post Local Development in your login Keychain."
echo "Build with ./build.sh. Approve codesign access if macOS asks."
