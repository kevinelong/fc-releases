#!/usr/bin/env bash
# verify-release.sh — does this repository's release actually hand a stranger the bytes we claim?
#
# This repo exists to hand out two binaries, and its whole contract is the numbers it publishes:
# the download page (README.md) names a size and a sha256, SHA256SUMS.txt in the release names the
# same, and those are what comes back over the wire to an unknown person on an unknown machine.
# That contract was checked by hand once (2026-10-12, when it was written) and by nothing since.
#
#   bash verify-release.sh                 verify the newest published release (network)
#   bash verify-release.sh v1.0.3-4        verify a named tag
#   bash verify-release.sh --dir <dir>     verify already-downloaded files (offline)
#
# What it asserts, in order, and it stops at nothing less:
#   1. README.md carries a release table: every asset, its size and its sha256.
#   2. SHA256SUMS.txt in the release lists exactly those assets, with the same digests.
#   3. the served (or local) bytes hash to those digests and are that many bytes long.
# A network failure is a failure, not a skip: a verification that could not run verified nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="${SCRIPT_DIR}/README.md"
REPO_SLUG="kevinelong/fc-releases"
ASSET_BASE="https://github.com/${REPO_SLUG}/releases/latest/download"

FAILED=0
ok()   { printf 'ok     : %s\n' "$*"; }
fail() { printf 'FAIL   : %s\n' "$*"; FAILED=$((FAILED + 1)); }
info() { printf '       : %s\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

hash_file() {   # prints the sha256 of a file
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
size_of() { wc -c < "$1" | tr -d ' \r'; }

# ---------------------------------------------------------------- what the README claims
# | `app-release.apk` | 49,526,430 | `0880…` |
CLAIM="$TMP/claim.txt"
awk -F'|' '
  /^\|/ {
    a=$2; b=$3; c=$4
    gsub(/[` ]/, "", a); gsub(/[, ]/, "", b); gsub(/[` ]/, "", c)
    if (a ~ /\.(apk|aab)$/ && b ~ /^[0-9]+$/ && c ~ /^[0-9a-f]{64}$/) print a" "b" "c
  }' "$README" > "$CLAIM"
if [ ! -s "$CLAIM" ]; then
  fail "README.md has no release table (an asset name, a byte count and a 64-hex sha256 per line)"
  printf 'verify-release: %d checks failed\n' "$FAILED"
  exit 1
fi
CLAIMS="$(wc -l < "$CLAIM" | tr -d ' ')"
ok "README.md claims ${CLAIMS} release asset(s): $(awk '{print $1}' "$CLAIM" | tr '\n' ' ')"

# ---------------------------------------------------------------- where the bytes come from
MODE="network"
TAG=""
DIR=""
case "${1:-}" in
  "") ;;
  --dir)
    MODE="dir"
    DIR="${2:?usage: verify-release.sh --dir <dir>}"
    [ -d "$DIR" ] || { fail "no such directory: $DIR"; exit 2; }
    ;;
  -*) fail "unknown option: $1"; exit 2 ;;
  *)  TAG="$1" ;;
esac

fetch_asset() {   # <name> <output path>
  local name="$1" out="$2" url
  if [ -n "$TAG" ]; then
    url="https://github.com/${REPO_SLUG}/releases/download/${TAG}/${name}"
  else
    # /releases/latest/download/ goes through a CDN that can serve a stale response for a few
    # minutes after a release is replaced (it did, on 2026-10-12, with a cached 5xx). The explicit
    # tag URL never does, so resolve the tag from the public API as the fallback — the same order
    # tools/deploy-fc-apk.sh uses in the fc repository.
    url="${ASSET_BASE}/${name}"
  fi
  if curl -fsSL -o "$out" "$url"; then return 0; fi
  info "fetch: ${url} failed — resolving the tag from the API"
  TAG="$(curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/releases/latest" 2>/dev/null \
        | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"tag_name": *"//; s/"$//')"
  [ -n "$TAG" ] || return 1
  info "fetch: retrying with tag ${TAG}"
  curl -fsSL -o "$out" "https://github.com/${REPO_SLUG}/releases/download/${TAG}/${name}"
}

if [ "$MODE" = dir ]; then
  ok "verifying files already in ${DIR}"
else
  if [ -n "$TAG" ]; then info "release: ${TAG}"; else info "release: newest published"; fi
  if fetch_asset SHA256SUMS.txt "$TMP/SHA256SUMS.txt"; then
    ok "fetched SHA256SUMS.txt from the release"
  else
    fail "could not fetch SHA256SUMS.txt — nothing can be verified without it"
    printf 'verify-release: %d checks failed\n' "$FAILED"
    exit 1
  fi
fi

SUMS="$TMP/SHA256SUMS.txt"
[ "$MODE" = dir ] && SUMS="${DIR}/SHA256SUMS.txt"
if [ ! -f "$SUMS" ]; then
  fail "no SHA256SUMS.txt alongside the assets — the release's own claim is missing"
  printf 'verify-release: %d checks failed\n' "$FAILED"
  exit 1
fi

# ---------------------------------------------------------------- SHA256SUMS.txt vs the README
# sha256  name
SUMSET="$TMP/sumset.txt"
awk 'NF==2 && $1 ~ /^[0-9a-f]{64}$/ {print $2" "$1}' "$SUMS" > "$SUMSET"
SUMS_N="$(wc -l < "$SUMSET" | tr -d ' ')"
if [ "${SUMS_N:-0}" = 0 ]; then
  fail "SHA256SUMS.txt has no usable 'sha256  name' lines"
else
  ok "SHA256SUMS.txt lists ${SUMS_N} entry(ies)"
fi

while read -r name size digest; do
  got="$(awk -v n="$name" '$1 == n {print $2}' "$SUMSET")"
  if [ -z "$got" ]; then
    fail "SHA256SUMS.txt does not list ${name}, which the README claims"
  elif [ "$got" != "$digest" ]; then
    fail "${name}: README says sha256 ${digest}, SHA256SUMS.txt says ${got}"
  else
    ok "${name}: SHA256SUMS.txt matches the README digest"
  fi

  # ------------------------------------------------------------ the bytes themselves
  FILE="$TMP/$name"
  if [ "$MODE" = dir ]; then
    FILE="${DIR}/${name}"
    if [ ! -f "$FILE" ]; then
      fail "${name}: not present in ${DIR}"
      continue
    fi
  elif ! fetch_asset "$name" "$FILE"; then
    fail "${name}: could not be downloaded from the release"
    continue
  fi
  actual_size="$(size_of "$FILE")"
  actual_hash="$(hash_file "$FILE")"
  if [ "$actual_hash" = "$digest" ]; then
    ok "${name}: the served bytes hash to ${digest}"
  else
    fail "${name}: served bytes hash to ${actual_hash}, the claim is ${digest}"
  fi
  if [ "$actual_size" = "$size" ]; then
    ok "${name}: ${actual_size} bytes, as claimed"
  else
    fail "${name}: ${actual_size} bytes, the README claims ${size}"
  fi
done < "$CLAIM"

# ---------------------------------------------------------------- nothing extra in the release
while read -r name _sum; do
  case "$name" in
    SHA256SUMS.txt) continue ;;
  esac
  if ! grep -q "^${name} " "$CLAIM"; then
    fail "the release carries ${name}, which README.md does not document"
  fi
done < "$SUMSET"

printf '\nverify-release: %d checks failed\n' "$FAILED"
[ "$FAILED" = 0 ] || exit 1
printf 'The release delivers exactly the bytes this repository claims.\n'
