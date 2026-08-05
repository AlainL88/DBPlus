#!/bin/sh
#
# ci_post_clone.sh
# Xcode Cloud: ricostruisce DB+/GoogleService-Info.plist dal secret base64
# configurato nel workflow (variabile "GoogleService_Base64", segnata come secret).
# Viene eseguito da Xcode Cloud dopo il clone e prima della build.
#
# Il plist non e' versionato nel repo pubblico: senza questo script il build
# andrebbe avanti comunque (guarda DB_App.swift) ma Crashlytics non si attiverebbe
# e ci_post_xcodebuild.sh non troverebbe il plist per l'upload dei dSYM.

set -e

if [ -z "${GoogleService_Base64:-}" ]; then
  echo "Crashlytics: variabile GoogleService_Base64 non configurata, salto ricostruzione plist."
  exit 0
fi

# Radice del repo ricavata dalla posizione dello script (stesso pattern di ci_post_xcodebuild.sh).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "$GoogleService_Base64" | base64 --decode > "$REPO_ROOT/DB+/GoogleService-Info.plist"
echo "Crashlytics: GoogleService-Info.plist ricostruito da secret."
