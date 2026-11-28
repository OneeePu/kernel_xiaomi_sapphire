#!/usr/bin/env bash
# Build the Redmi Note 13 (sapphire) arm64 GKI kernel and device trees.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out-ci}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist-ci}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
ARCH=arm64
LLVM="${LLVM:-1}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] || die "BUILD_JOBS must be a positive integer."
command -v ld.lld >/dev/null 2>&1 || die "ld.lld is required; install the LLVM linker."
[[ -f "$ROOT_DIR/arch/arm64/configs/vendor/bengal_GKI.config" ]] || die "Missing Bengal GKI config fragment."
[[ -f "$ROOT_DIR/arch/arm64/configs/vendor/sapphire_GKI.config" ]] || die "Missing Sapphire GKI config fragment."

mkdir -p "$OUT_DIR" "$DIST_DIR"

printf 'Configuring arm64 GKI with Bengal and Sapphire fragments...\n'
make -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" LLVM="$LLVM" gki_defconfig
"$ROOT_DIR/scripts/kconfig/merge_config.sh" -m -O "$OUT_DIR" "$OUT_DIR/.config" \
    "$ROOT_DIR/arch/arm64/configs/vendor/bengal_GKI.config" \
    "$ROOT_DIR/arch/arm64/configs/vendor/sapphire_GKI.config"

printf 'Selecting ThinLTO...\n'
"$ROOT_DIR/scripts/config" --file "$OUT_DIR/.config" \
    --disable LTO_CLANG_FULL \
    --enable LTO_CLANG_THIN

make -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" LLVM="$LLVM" olddefconfig
grep -qx 'CONFIG_LTO_CLANG_THIN=y' "$OUT_DIR/.config" || die "ThinLTO was not enabled by Kconfig."
grep -qx '# CONFIG_LTO_CLANG_FULL is not set' "$OUT_DIR/.config" || die "Full LTO is still enabled."

printf 'Building ThinLTO Image.gz, device trees, and modules with %s jobs...\n' "$BUILD_JOBS"
make -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" LLVM="$LLVM" -j"$BUILD_JOBS" Image.gz dtbs modules

KERNEL_RELEASE="$(make -s -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" LLVM="$LLVM" kernelrelease)"
mkdir -p "$DIST_DIR/dtbs"

install -D "$OUT_DIR/arch/arm64/boot/Image" "$DIST_DIR/Image"
install -D "$OUT_DIR/arch/arm64/boot/Image.gz" "$DIST_DIR/Image.gz"
install -D "$OUT_DIR/.config" "$DIST_DIR/kernel.config"

mapfile -d '' DTB_FILES < <(find "$OUT_DIR/arch/arm64/boot/dts" -type f \( -name '*.dtb' -o -name '*.dtbo' \) -print0)
(("${#DTB_FILES[@]}" > 0)) || die "No DTB or DTBO files were produced."
for dtb in "${DTB_FILES[@]}"; do
    relative_path="${dtb#"$OUT_DIR/arch/arm64/boot/dts/"}"
    install -D "$dtb" "$DIST_DIR/dtbs/$relative_path"
done

make -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" LLVM="$LLVM" \
    INSTALL_MOD_PATH="$DIST_DIR/modules" modules_install

{
    printf 'kernel_release=%s\n' "$KERNEL_RELEASE"
    printf 'source_commit=%s\n' "$(git -C "$ROOT_DIR" rev-parse HEAD)"
    printf 'arch=%s\n' "$ARCH"
    printf 'lto=thin\n'
    printf 'config_fragments=bengal_GKI.config,sapphire_GKI.config\n'
} > "$DIST_DIR/build-info.txt"

printf 'ThinLTO build complete. Artifacts are in %s\n' "$DIST_DIR"
