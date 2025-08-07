#!/bin/zsh

set -euo pipefail

echo -n 'What version? '
read VERSION

echo "got version $VERSION"
sed -i '' "s/<string>1\.0<\/string>/<string>$VERSION<\/string>/g" AnkiBirthdays.app/Contents/Info.plist
zig build
cp zig-out/bin/bdays AnkiBirthdays.app/Contents/MacOS/bdays
create-dmg \
    --volname "Anki Birthdays Installer" \
    --window-pos 200 120 \
    --window-size 600 300 \
    --icon-size 100 \
    --icon "AnkiBirthdays.app" 175 120 \
    --hide-extension "AnkiBirthdays.app" \
    --app-drop-link 425 120 \
    "AnkiBirthdays-$VERSION.dmg" \
    "AnkiBirthdays.app"

