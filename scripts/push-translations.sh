#!/bin/bash
set -e

# Push strings to Lokalise.
# By default pushes English only. Pass --all to push all languages.
#
# Extracts values from the xcstrings file as .strings format
# and uploads to Lokalise.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
XCSTRINGS="$PROJECT_DIR/Sources/Resources/Localizable.xcstrings"
CONFIG="$PROJECT_DIR/lokalise.yml"

PUSH_ALL=false
if [ "$1" = "--all" ]; then
    PUSH_ALL=true
fi

if [ ! -f "$CONFIG" ]; then
    echo "Error: $CONFIG not found."
    echo "Copy lokalise.yml.example to lokalise.yml and add your API token."
    exit 1
fi

if [ ! -f "$XCSTRINGS" ]; then
    echo "Error: $XCSTRINGS not found."
    exit 1
fi

TMPDIR=$(mktemp -d /tmp/Localizable_push.XXXXXX)

echo "==> Extracting strings..."
python3 - "$XCSTRINGS" "$TMPDIR" "$PUSH_ALL" << 'PYEOF'
import json
import os
import sys

xcstrings_path = sys.argv[1]
output_dir = sys.argv[2]
push_all = sys.argv[3] == "true"

apple_to_lokalise = {
    "zh-Hans": "zh_CN",
    "zh-Hant": "zh_TW",
    "pt-BR": "pt_BR",
}

with open(xcstrings_path, "r", encoding="utf-8") as f:
    data = json.load(f)

langs_to_push = set()
if push_all:
    for entry in data["strings"].values():
        for lang in entry.get("localizations", {}):
            langs_to_push.add(lang)
else:
    langs_to_push.add("en")

for lang in sorted(langs_to_push):
    lines = []
    for key in sorted(data["strings"].keys()):
        entry = data["strings"][key]
        locs = entry.get("localizations", {})
        loc = locs.get(lang, {})
        value = loc.get("stringUnit", {}).get("value", "")
        if not value:
            continue
        escaped_key = key.replace('\\', '\\\\').replace('"', '\\"')
        escaped_value = value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
        lines.append(f'"{escaped_key}" = "{escaped_value}";')
    if not lines:
        continue
    lokalise_lang = apple_to_lokalise.get(lang, lang)
    output_path = os.path.join(output_dir, f"{lokalise_lang}.strings")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  {lang} -> {lokalise_lang}: {len(lines)} keys")
PYEOF

echo "==> Pushing to Lokalise..."
for STRINGS_FILE in "$TMPDIR"/*.strings; do
    LANG_ISO=$(basename "$STRINGS_FILE" .strings)
    echo "  Uploading $LANG_ISO..."
    lokalise2 --config "$CONFIG" file upload \
        --file "$STRINGS_FILE" \
        --lang-iso "$LANG_ISO" \
        --replace-modified \
        --poll \
        --poll-timeout 120s
done

rm -rf "$TMPDIR"
echo "==> Done."
