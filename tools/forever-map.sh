#!/usr/bin/env bash
# Regenerates the Rustcore symbol map.
# Run from anywhere:  bash tools/forever-map.sh
#
# Writes one small index per Lua file into map/, plus a short FOREVER-MAP.md
# table of contents. Grep map/*.md to locate a symbol, then read a narrow
# window of the real file. Never read a whole source file.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/dist/forever/Rustcore"
out="$root/map"

rm -rf "$out"
mkdir -p "$out"

index="$root/FOREVER-MAP.md"
{
  echo "# Rustcore \`dist/forever\` symbol map"
  echo
  echo "Per-file function indexes live in \`map/\`. Grep those, then read a narrow"
  echo "window of the real file. Regenerate: \`bash tools/forever-map.sh\`."
  echo
  echo "| File | Lines | Index |"
  echo "| --- | --- | --- |"
} > "$index"

for f in "$src"/*.lua; do
  name="$(basename "$f")"
  stem="${name%.lua}"
  lines="$(wc -l < "$f" | tr -d ' ')"
  {
    echo "# $name — $lines lines"
    echo
    echo "Top-level definitions in \`dist/forever/Rustcore/$name\`."
    echo
    echo '```'
    grep -nE "^(function|local function) " "$f" || true
    echo '```'
  } > "$out/$stem.md"
  echo "| $name | $lines | [map/$stem.md](map/$stem.md) |" >> "$index"
done

echo "index: $(wc -l < "$index" | tr -d ' ') lines"
echo "shards: $(ls -1 "$out" | wc -l | tr -d ' ')"
echo "largest shard: $(wc -l "$out"/*.md | sort -rn | sed -n '2p')"
