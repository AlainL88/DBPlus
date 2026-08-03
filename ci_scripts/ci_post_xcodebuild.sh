#!/bin/sh
#
# ci_post_xcodebuild.sh
# Xcode Cloud: carica i dSYM su Firebase Crashlytics dopo l'archive.
# Viene eseguito automaticamente da Xcode Cloud (ci_scripts/ alla radice del repo).
#
# Perche' serve: il build phase "Crashlytics dSYM upload" usa lo script "run" di
# Firebase che lancia upload-symbols in background; su Xcode Cloud quel processo
# viene terminato a fine fase, quindi il dSYM non arriva mai (build verde ma
# "Missing dSYM" in console). Questo script carica i dSYM in modo sincrono
# dall'archive, dove sono sicuramente disponibili.
#
# Riferimento: https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports

set -u

# Niente archive (workstream senza distribuzione) -> niente da caricare.
if [ -z "${CI_ARCHIVE_PATH:-}" ] || [ ! -d "$CI_ARCHIVE_PATH/dSYMs" ]; then
  echo "Crashlytics: nessun archive disponibile, salto upload dSYM."
  exit 0
fi

UPLOAD_SYMBOLS="${CI_DERIVED_DATA_PATH:-}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
GSP="${CI_WORKSPACE:-}/DB+/GoogleService-Info.plist"

if [ ! -x "$UPLOAD_SYMBOLS" ]; then
  echo "Crashlytics: ERROR upload-symbols non trovato in $UPLOAD_SYMBOLS"
  exit 1
fi
if [ ! -f "$GSP" ]; then
  echo "Crashlytics: ERROR GoogleService-Info.plist non trovato in $GSP"
  exit 1
fi

echo "Crashlytics: upload dSYM da $CI_ARCHIVE_PATH/dSYMs"
find "$CI_ARCHIVE_PATH/dSYMs" -maxdepth 1 -name "*.dSYM" | while IFS= read -r dsym; do
  echo "Crashlytics: upload $dsym"
  if ! "$UPLOAD_SYMBOLS" -gsp "$GSP" -p ios "$dsym"; then
    echo "Crashlytics: ERRORE upload di $dsym"
  fi
done

echo "Crashlytics: upload dSYM completato."
