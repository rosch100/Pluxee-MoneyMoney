#!/bin/sh
set -e
# MoneyMoney läuft sandboxed: Hardlinks auf Dateien außerhalb des Containers
# werden oft nicht geladen. Deshalb echte Kopie (wie Givve / übrige Extensions).
EXT_DIR="$HOME/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions"
SRC="$(cd "$(dirname "$0")" && pwd)/Pluxee Benefits.lua"
DST="$EXT_DIR/Pluxee Benefits.lua"
OLD="$EXT_DIR/Pluxee.lua"
ls -li "$DST" "$SRC" "$OLD" 2>/dev/null || true
rm -f "$DST" "$OLD"
cp "$SRC" "$DST"
ls -li "$DST" "$SRC"
