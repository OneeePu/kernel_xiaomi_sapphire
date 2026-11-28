#!/usr/bin/env bash
# Build the Redmi Note 13 (sapphire) arm64 GKI kernel and device trees.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out-ci}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist-ci}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
LTO_MODE="${LTO_MODE:-thin}"
ARCH=arm64
LLVM="${LLVM:-1}"
LLVM_TOOLS=(LLVM="$LLVM" LD=ld.lld AR=llvm-ar NM=llvm-nm)

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] || die "BUILD_JOBS must be a positive integer."
case "$LTO_MODE" in
    thin|full|none) ;;
    *) die "LTO_MODE must be thin, full, or none." ;;
esac
for tool in clang ld.lld llvm-ar llvm-nm; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required; install the matching LLVM toolchain."
done
[[ -f "$ROOT_DIR/arch/arm64/configs/vendor/bengal_GKI.config" ]] || die "Missing Bengal GKI config fragment."
[[ -f "$ROOT_DIR/arch/arm64/configs/vendor/sapphire_GKI.config" ]] || die "Missing Sapphire GKI config fragment."

mkdir -p "$OUT_DIR" "$DIST_DIR"

printf 'Configuring arm64 GKI with Bengal and Sapphire fragments...\n'
make -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" "${LLVM_TOOLS[@]}" gki_defconfig
"$ROOT_DIR/scripts/kconfig/merge_config.sh" -m -O "$OUT_DIR" "$OUT_DIR/.config" \
    "$ROOT_DIR/arch/arm64/configs/vendor/bengal_GKI.config" \
    "$ROOT_DIR/arch/arm64/configs/vendor/sapphire_GKI.config"

printf 'Selecting %s LTO...\n' "$LTO_MODE"
LTO_CONFIG="$OUT_DIR/lto.config"
case "$LTO_MODE" in
    thin)
        cat > "$LTO_CONFIG" <<'EOF'
# CONFIG_LTO_CLANG_FULL is not set
CONFIG_LTO_CLANG_THIN=y
# CONFIG_LTO_NONE is not set
EOF
        ;;
    full)
        cat > "$LTO_CONFIG" <<'EOF'
CONFIG_LTO_CLANG_FULL=y
# CONFIG_LTO_CLANG_THIN is not set
# CONFIG_LTO_NONE is not set
EOF
        ;;
    none)
        cat > "$LTO_CONFIG" <<'EOF'
# CONFIG_LTO_CLANG_FULL is not set
# CONFIG_LTO_CLANG_THIN is not set
CONFIG_LTO_NONE=y
EOF
        ;;
esac
"$ROOT_DIR/scripts/kconfig/merge_config.sh" -m -O "$OUT_DIR" "$OUT_DIR/.config" "$LTO_CONFIG"
make -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" "${LLVM_TOOLS[@]}" olddefconfig

case "$LTO_MODE" in
    thin)
        LTO_CONFIG_LINE='CONFIG_LTO_CLANG_THIN=y'
        ;;
    full)
        LTO_CONFIG_LINE='CONFIG_LTO_CLANG_FULL=y'
        ;;
    none)
        LTO_CONFIG_LINE='CONFIG_LTO_NONE=y'
        ;;
esac
if ! grep -qx "$LTO_CONFIG_LINE" "$OUT_DIR/.config"; then
    grep -E '^(CONFIG_(LTO|HAS_LTO_CLANG|CC_IS_CLANG|LD_IS_LLD|AS_IS_LLVM|ARCH_SUPPORTS_LTO_CLANG|KASAN|GCOV_KERNEL|FTRACE_MCOUNT_USE_RECORDMCOUNT)|# CONFIG_LTO_)' "$OUT_DIR/.config" >&2 || true
    die "Requested LTO_MODE=$LTO_MODE was not enabled by Kconfig."
fi

printf 'Building %s LTO Image.gz, device trees, and modules with %s jobs...\n' "$LTO_MODE" "$BUILD_JOBS"
make -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" "${LLVM_TOOLS[@]}" -j"$BUILD_JOBS" Image.gz dtbs modules

KERNEL_RELEASE="$(make -s -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" "${LLVM_TOOLS[@]}" kernelrelease)"
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

make -C "$ROOT_DIR" O="$OUT_DIR" ARCH="$ARCH" "${LLVM_TOOLS[@]}" \
    INSTALL_MOD_PATH="$DIST_DIR/modules" modules_install

{
    printf 'kernel_release=%s\n' "$KERNEL_RELEASE"
    printf 'source_commit=%s\n' "$(git -C "$ROOT_DIR" rev-parse HEAD)"
    printf 'arch=%s\n' "$ARCH"
    printf 'lto_mode=%s\n' "$LTO_MODE"
    printf 'build_jobs=%s\n' "$BUILD_JOBS"
    printf 'config_fragments=bengal_GKI.config,sapphire_GKI.config\n'
} > "$DIST_DIR/build-info.txt"

printf '%s LTO build complete. Artifacts are in %s\n' "$LTO_MODE" "$DIST_DIR"
