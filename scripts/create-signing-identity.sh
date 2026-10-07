#!/usr/bin/env bash
# Creates a self-signed code-signing identity in the login keychain, once.
#
# Ad-hoc signatures change with every build, and the keychain ties "Always
# Allow" to the signature, so each rebuild asked for the login password again.
# Signing with a stable certificate keeps the app's identity across builds.
# The certificate is local only; it isn't trusted by Gatekeeper and isn't meant
# for distribution. Remove it with:
#   security delete-identity -c "SQL Viewer Local Signing"
set -euo pipefail

name="SQL Viewer Local Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
  echo "Ya existe: $name"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
# Security.framework can't read OpenSSL 3's default PKCS#12 encryption, hence
# -legacy; the system LibreSSL lacks the flag but already uses that format.
# -name labels the private key, so the partition list below only touches it.
p12=(pkcs12 -export -name "$name" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/identity.p12" -passout pass:import)
openssl "${p12[@]}" -legacy 2>/dev/null || openssl "${p12[@]}"
security import "$tmp/identity.p12" -k "$keychain" -P import -T /usr/bin/codesign
# Without this, every build asks (via a GUI dialog) to let codesign use the key,
# and an unanswered dialog fails the build with errSecInternalComponent.
echo "Contraseña de tu Mac, para que codesign use la clave sin preguntar:"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$name" "$keychain" >/dev/null
echo "Creado: $name"
