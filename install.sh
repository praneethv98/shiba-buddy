#!/bin/zsh
# One-click install: builds Shiba Buddy, installs it to Applications and launches it.
# On first launch the app turns on Open at Login.
set -e
cd "$(dirname "$0")"
./build.sh

pkill -x ShibaBuddy 2>/dev/null || true
sleep 0.5

DEST=/Applications
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/Shiba Buddy.app"
ditto ShibaBuddy.app "$DEST/Shiba Buddy.app"
open "$DEST/Shiba Buddy.app"
echo "Installed $DEST/Shiba Buddy.app and launched it."
