#!/usr/bin/env bash
# Package the Sapphire/Sapphiren kernel image as a flashable AnyKernel3 ZIP.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist-ci}"
TEMP_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
SOURCE_SHA="${GITHUB_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
readonly ANYKERNEL3_REF="41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1"
readonly AK3_REPO="https://github.com/osm0sis/AnyKernel3.git"
AK3_SOURCE="$TEMP_ROOT/anykernel3-source"
STAGE_DIR="$TEMP_ROOT/anykernel3-sapphire-stage"
ZIP_PATH="$DIST_DIR/AnyKernel3-sapphire-sapphiren-$SOURCE_SHA.zip"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -s "$DIST_DIR/Image.gz" ]] || die "Missing kernel image: $DIST_DIR/Image.gz"
command -v git >/dev/null 2>&1 || die "git is required."
command -v zip >/dev/null 2>&1 || die "zip is required."

mkdir -p "$DIST_DIR" "$TEMP_ROOT"
rm -rf "$AK3_SOURCE" "$STAGE_DIR"
mkdir -p "$AK3_SOURCE" "$STAGE_DIR"

git -C "$AK3_SOURCE" init --quiet
git -C "$AK3_SOURCE" fetch --quiet --depth=1 "$AK3_REPO" "$ANYKERNEL3_REF"
git -C "$AK3_SOURCE" checkout --quiet --detach FETCH_HEAD

[[ -f "$AK3_SOURCE/LICENSE" ]] || die "AnyKernel3 source is incomplete."
[[ -d "$AK3_SOURCE/META-INF" && -d "$AK3_SOURCE/tools" ]] || die "AnyKernel3 files are missing."

cp -a "$AK3_SOURCE/LICENSE" "$AK3_SOURCE/META-INF" "$AK3_SOURCE/tools" "$STAGE_DIR/"
install -m 0644 "$ROOT_DIR/anykernel/anykernel.sh" "$STAGE_DIR/anykernel.sh"
install -m 0644 "$DIST_DIR/Image.gz" "$STAGE_DIR/Image.gz"

rm -f "$ZIP_PATH"
(
    cd "$STAGE_DIR"
    zip -qr9 "$ZIP_PATH" .
)

printf 'AnyKernel3 package created: %s\n' "$ZIP_PATH"
