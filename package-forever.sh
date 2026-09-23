#!/usr/bin/env bash

# Packages the WoW Forever / modern-client build.
#
# Unlike package.sh and package-era.sh, the file list is not hardcoded here -
# it is read out of Rustcore.toc. Those two scripts have already drifted (both
# predate Verification/ and the RustcoreCompat* files), and this build is the
# one that cannot afford to: the whole point of it is that all three compat
# files ship together so RustcoreCompat can pick a backend at runtime. A
# hardcoded list that silently omits RustcoreCompatModern.lua would produce a
# package that loads and then misbehaves on a modern client.

set -euo pipefail

addon_name="Rustcore"
version="${1:-$(date +%Y%m%d-%H%M%S)}"
source_dir="release/Rustcore"
dist_dir="dist/Forever"
stage_dir="${dist_dir}/${addon_name}"
zip_path="${dist_dir}/${addon_name}-forever-${version}.zip"

toc="${source_dir}/Rustcore.toc"

if [[ ! -s "${toc}" ]]; then
  echo "TOC is missing or empty: ${toc}" >&2
  exit 1
fi

# This build target exists for Forever and retail; a TOC that does not declare
# the Forever interface number would install as out-of-date there.
if ! grep -qE '^## Interface:.*\b16001\b' "${toc}"; then
  echo "TOC does not declare interface 16001 (WoW Forever): ${toc}" >&2
  echo "Current: $(grep -E '^## Interface:' "${toc}")" >&2
  exit 1
fi

for required in RustcoreCompat.lua RustcoreCompatClassic.lua RustcoreCompatModern.lua; do
  if ! grep -qF "${required}" "${toc}"; then
    echo "TOC does not load ${required} - both backends must ship in this build." >&2
    exit 1
  fi
done

mkdir -p "${dist_dir}"
rm -rf "${stage_dir}"
mkdir -p "${stage_dir}"

cp "${toc}" "${stage_dir}/Rustcore.toc"

# TOC entries use Windows separators (Verification\Core.lua) and may carry CRLF.
# Take only source-file lines: skip ## directives, # comments and blanks.
mapfile -t toc_files < <(
  tr -d '\r' < "${toc}" \
    | grep -vE '^\s*(#|$)' \
    | grep -iE '\.(lua|xml)\s*$' \
    | tr '\\' '/' \
    | sed -e 's/[[:space:]]*$//'
)

if [[ ${#toc_files[@]} -eq 0 ]]; then
  echo "No source files parsed out of ${toc}" >&2
  exit 1
fi

for file in "${toc_files[@]}"; do
  if [[ ! -s "${source_dir}/${file}" ]]; then
    echo "File listed in TOC is missing or empty: ${source_dir}/${file}" >&2
    exit 1
  fi
  mkdir -p "${stage_dir}/$(dirname "${file}")"
  cp "${source_dir}/${file}" "${stage_dir}/${file}"
done

if [[ ! -s "${source_dir}/RCicon.png" ]]; then
  echo "Required file is missing or empty: ${source_dir}/RCicon.png" >&2
  exit 1
fi
cp "${source_dir}/RCicon.png" "${stage_dir}/"

for asset in UI Font Audio; do
  if [[ ! -d "${source_dir}/${asset}" ]]; then
    echo "Required asset directory is missing: ${source_dir}/${asset}" >&2
    exit 1
  fi
  cp -r "${source_dir}/${asset}" "${stage_dir}/"
done

rm -f "${zip_path}"

if command -v zip >/dev/null 2>&1; then
  (
    cd "${dist_dir}"
    zip -rq "$(basename "${zip_path}")" "${addon_name}"
  )
elif command -v python3 >/dev/null 2>&1; then
  python3 -c '
import os
import sys
import zipfile

source_dir = sys.argv[1]
zip_path = sys.argv[2]

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(source_dir):
        for name in files:
            full_path = os.path.join(root, name)
            arcname = os.path.relpath(full_path, os.path.dirname(source_dir))
            zf.write(full_path, arcname)
' "${stage_dir}" "${zip_path}"
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command \
    "Compress-Archive -Path '${stage_dir}' -DestinationPath '${zip_path}' -Force" \
    >/dev/null
else
  echo "No supported archive tool found. Install 'zip' or run from Windows with PowerShell available." >&2
  exit 1
fi

echo "Staged  ${stage_dir} (${#toc_files[@]} source files)"
echo "Created ${zip_path}"
