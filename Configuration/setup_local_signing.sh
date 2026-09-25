#!/bin/bash
#
# Sign local builds with a certificate of your own, so macOS keeps the
# Accessibility grant (HUD replacement, media keys) across rebuilds.
#
# Ad-hoc builds are identified by their hash, which changes on every build, so
# macOS treats each one as a new app. A build signed with a fixed certificate
# is identified by that certificate and the bundle ID instead - the same from
# one build to the next.
#
# What this does, once:
#   1. makes a self-signed code-signing certificate in your login keychain,
#   2. trusts it for code signing only (macOS asks for your password),
#   3. writes Configuration/Signing.local.xcconfig, which Xcode picks up.
#
# After running it, build, grant Accessibility one last time, and remove the
# old Vornyx Notch entries from System Settings > Privacy & Security >
# Accessibility. Run it again at any time: it reuses the certificate.

set -euo pipefail

NAME="Vornyx Notch Local Signing"
ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCAL_XCCONFIG="$ROOT/Signing.local.xcconfig"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "==> Certificate \"$NAME\" already in the keychain and trusted"
else
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT

  if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    # There, but not trusted - an earlier run stopped at the password prompt.
    echo "==> Trusting the existing certificate \"$NAME\""
    security find-certificate -c "$NAME" -p "$KEYCHAIN" >"$WORK/cert.pem"
  else
    echo "==> Creating certificate \"$NAME\""
    cat >"$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
    # macOS's own openssl: its PKCS#12 files are the kind `security` imports.
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
      -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
    PASS="$(uuidgen)"
    /usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
      -out "$WORK/identity.p12" -passout "pass:$PASS" -name "$NAME"
    security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" \
      -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  fi

  echo "==> Trusting it for code signing (macOS will ask for your password)"
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

  security find-identity -v -p codesigning | grep -q "\"$NAME\"" \
    || { echo "error: the certificate is still not a valid signing identity" >&2; exit 1; }
fi

cat >"$LOCAL_XCCONFIG" <<XCCONFIG
// Written by setup_local_signing.sh - local to this Mac, not committed.
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = $NAME
CODE_SIGN_IDENTITY[sdk=macosx*] = $NAME
DEVELOPMENT_TEAM =
XCCONFIG

echo "==> Wrote $LOCAL_XCCONFIG"
echo
echo "Now: build and run once, grant Accessibility, and remove the older"
echo "Vornyx Notch entries from Privacy & Security > Accessibility."
echo "Xcode may ask once to let codesign use the key - choose Always Allow."
