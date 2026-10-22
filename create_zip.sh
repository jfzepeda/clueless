#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

archives_dir="$HOME/Library/Developer/Xcode/Archives"
latest_app=""
latest_date=0

while IFS= read -r -d '' log; do
    app="$(dirname "$log")/clueless.app"
    [[ -d "$app" ]] || continue
    status=$(/usr/bin/plutil -extract status raw -o - "$log" 2>/dev/null) || continue
    [[ "$status" == "Accepted" ]] || continue
    date=$(/usr/bin/stat -f %m "$log")
    if (( date > latest_date )); then
        latest_date=$date
        latest_app="$app"
    fi
done < <(/usr/bin/find "$archives_dir" -type f -path '*/Submissions/*/notarization-log.json' -print0)

if [[ -z "$latest_app" ]]; then
    echo "No se encontró una exportación notarizada de clueless en $archives_dir." >&2
    exit 1
fi

echo "App seleccionada: $latest_app"
/usr/bin/codesign --verify --deep --strict "$latest_app"
/usr/bin/xcrun stapler validate "$latest_app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$latest_app"

mkdir -p dist
staging_dir=$(mktemp -d "$PWD/dist/.package.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
ditto "$latest_app" "$staging_dir/clueless.app"
rm -rf dist/clueless.app
mv "$staging_dir/clueless.app" dist/clueless.app

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/clueless.app/Contents/Info.plist)
zip_path="dist/clueless-${version}-macOS.zip"

ditto -c -k --sequesterRsrc --keepParent dist/clueless.app "$zip_path"
unzip -t "$zip_path"
