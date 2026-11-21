#!/usr/bin/env bash
# Bygger APK-en i GitHub Actions. Kjøres fra roten av repoet.
set -euo pipefail
GODOT_VERSION="4.3"
TAG="${GODOT_VERSION}-stable"
BASE="https://github.com/godotengine/godot/releases/download/${TAG}"

echo "== Laster ned Godot ${GODOT_VERSION}"
wget -q "${BASE}/Godot_v${TAG}_linux.x86_64.zip"
wget -q "${BASE}/Godot_v${TAG}_export_templates.tpz"
unzip -q "Godot_v${TAG}_linux.x86_64.zip"
mv "Godot_v${TAG}_linux.x86_64" godot
TEMPLATES="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
mkdir -p "$TEMPLATES"
unzip -q "Godot_v${TAG}_export_templates.tpz"
mv templates/* "$TEMPLATES/"
rm -rf templates *.zip *.tpz

echo "== Editor-innstillinger for Android"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME}}"
KEYSTORE="$(pwd)/android/debug.keystore"
mkdir -p "$HOME/.config/godot"
for f in editor_settings-4.tres editor_settings-4.3.tres; do
  {
    echo '[gd_resource type="EditorSettings" format=3]'
    echo ''
    echo '[resource]'
    echo "export/android/android_sdk_path = \"${SDK}\""
    echo "export/android/java_sdk_path = \"${JAVA_HOME}\""
    echo "export/android/debug_keystore = \"${KEYSTORE}\""
    echo 'export/android/debug_keystore_user = "androiddebugkey"'
    echo 'export/android/debug_keystore_pass = "android"'
  } > "$HOME/.config/godot/$f"
done
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"

APP_VERSION="$(cat version.txt)"
echo "== Versjon ${APP_VERSION}.${BUILD_NUMBER:-1}"
sed -i "s/^version\/code=.*/version\/code=${BUILD_NUMBER:-1}/" export_presets.cfg
sed -i "s/^version\/name=.*/version\/name=\"${APP_VERSION}.${BUILD_NUMBER:-1}\"/" export_presets.cfg

# Samme nøkkel brukes til release-bygget, så nye versjoner kan installeres over gamle
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"

echo "== Importerer prosjektet og sjekker skriptene"
timeout 300 ./godot --headless --editor --quit 2>&1 | tee import.log || true
if grep -E "SCRIPT ERROR|Parse Error" import.log; then
  echo "Skriptfeil – stopper byggingen"
  exit 1
fi

echo "== Kjører testen (spilltest uten skjerm)"
printf '[autoload]\nSmoke="*res://tests/smoke.gd"\n' > override.cfg
set +e
timeout 420 ./godot --headless 2>&1 | tee smoke.log
STATUS=${PIPESTATUS[0]}
set -e
rm -f override.cfg
if [ "$STATUS" -ne 0 ] || ! grep -q "SMOKE OK" smoke.log || grep -E "SCRIPT ERROR" smoke.log; then
  echo "Testen feilet – stopper byggingen"
  exit 1
fi
rm -f import.log smoke.log

echo "== Eksporterer APK (release)"
mkdir -p build
./godot --headless --export-release "Android" build/riket.apk
ls -la build
test -s build/riket.apk
