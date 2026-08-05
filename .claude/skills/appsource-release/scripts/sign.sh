#!/usr/bin/env bash
# sign.sh — code-sign a Business Central .app with jsign + Azure Trusted Signing,
# then verify the signature by extracting it (per README "Signing the .app Package").
#
# Usage: sign.sh <path-to.app>
# Prints SIGNATURE_VERIFIED=1 on success.
set -euo pipefail

APP_FILE="${1:-}"
[ -n "$APP_FILE" ] || { echo "Usage: sign.sh <path-to.app>" >&2; exit 1; }
[ -f "$APP_FILE" ] || { echo "ERROR: file not found: $APP_FILE" >&2; exit 1; }
case "$APP_FILE" in *.app) ;; *) echo "ERROR: expected a .app file, got: $APP_FILE" >&2; exit 1;; esac

command -v jsign >/dev/null || { echo "ERROR: jsign not installed. Run: brew install jsign" >&2; exit 1; }
command -v az >/dev/null    || { echo "ERROR: Azure CLI not installed. Run: brew install azure-cli" >&2; exit 1; }

az account show >/dev/null 2>&1 || { echo "ERROR: not logged into Azure. Run: az login" >&2; exit 1; }

# README troubleshooting: token errors are usually the wrong subscription.
az account set --subscription "Azure Signing Certificate" 2>/dev/null \
  || echo "WARN: could not switch to subscription 'Azure Signing Certificate' — continuing with current subscription." >&2

TOKEN="$(az account get-access-token --resource https://codesigning.azure.net --query accessToken -o tsv)"
[ -n "$TOKEN" ] || { echo "ERROR: failed to get Azure access token for codesigning.azure.net" >&2; exit 1; }

echo "Signing $(basename "$APP_FILE") with Azure Trusted Signing (RutterSigning/DynamicsCertificate)..."
jsign --storetype TRUSTEDSIGNING \
  --keystore "https://eus.codesigning.azure.net" \
  --storepass "$TOKEN" \
  --alias "RutterSigning/DynamicsCertificate" \
  "$APP_FILE"

# --- verify: jsign extract writes a .sig next to the file if (and only if) signed ---
DIR="$(cd "$(dirname "$APP_FILE")" && pwd)"
BASE="$(basename "$APP_FILE")"
( cd "$DIR" && jsign extract "$BASE" )
SIG_A="$DIR/${BASE}.sig"
SIG_B="$DIR/${BASE%.app}.sig"
if [ -f "$SIG_A" ] || [ -f "$SIG_B" ]; then
  rm -f "$SIG_A" "$SIG_B"
  echo "SIGNATURE_VERIFIED=1"
else
  echo "ERROR: signature verification failed — no signature could be extracted." >&2
  exit 1
fi
