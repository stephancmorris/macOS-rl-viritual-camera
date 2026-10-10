#!/bin/bash
# App/extension version match, Mach service prefix, Debug-only flags, and
# entitlement diffs. No credentials. Entitlement diffs are allowed when the
# pull request carries the label allow-entitlement-change.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
project="CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj"

setting() {
  local target="$1" key="$2"
  xcodebuild -project "$project" -target "$target" -configuration Release -showBuildSettings \
    | awk -F ' = ' -v key="$key" '$1 ~ key { print $2; exit }'
}

app_version="$(setting CinematicCoreMacOS MARKETING_VERSION)"
app_build="$(setting CinematicCoreMacOS CURRENT_PROJECT_VERSION)"
ext_version="$(setting CinematicCoreExtension MARKETING_VERSION)"
ext_build="$(setting CinematicCoreExtension CURRENT_PROJECT_VERSION)"

if [[ -z "$app_version" || -z "$app_build" || "$app_version" != "$ext_version" || "$app_build" != "$ext_build" ]]; then
  echo "version mismatch: app ${app_version} (${app_build}) extension ${ext_version} (${ext_build})" >&2
  exit 1
fi
echo "versions match: ${app_version} (${app_build})"

mach="CinematicCoreMacOS/CinematicCoreExtension/Info.plist"
if ! grep -q 'EPZDEPSV69.Morris.CinematicCoreMacOS.extension' "$mach"; then
  echo "CMIOExtensionMachServiceName is not team-prefixed" >&2
  exit 1
fi
echo "Mach service prefix ok"

flags="CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift"
for name in allowRehearsalOutput allowInjectedQualification allowStageBelowShowRate; do
  if ! awk -v name="$name" '
    $0 ~ "#else" { in_else = 1 }
    $0 ~ "#endif" { in_else = 0 }
    in_else && $0 ~ ("static let " name " = false") { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$flags"; then
    echo "Release flag ${name} is not forced false" >&2
    exit 1
  fi
done
echo "Debug-only flags stay false in Release"

if [[ "${ALLOW_ENTITLEMENT_CHANGE:-}" == "1" ]]; then
  echo "entitlement diff allowed by label"
  exit 0
fi

base="${BASE_SHA:-}"
if [[ -z "$base" || "$base" == "0000000000000000000000000000000000000000" ]]; then
  echo "no base commit; entitlement diff skipped"
  exit 0
fi

if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  echo "base ${base} is not in this checkout; entitlement diff skipped" >&2
  exit 0
fi

diff="$(git diff --name-only "$base" -- '*.entitlements' || true)"
if [[ -n "$diff" ]]; then
  echo "entitlements changed without the allow-entitlement-change label:" >&2
  echo "$diff" >&2
  exit 1
fi
echo "entitlements unchanged"
