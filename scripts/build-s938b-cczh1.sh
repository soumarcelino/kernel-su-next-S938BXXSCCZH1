#!/usr/bin/env bash
set -euo pipefail

TARGET_RELEASE='6.6.98-android15-8-pd6ff1cd-abogkiS938BXXSCCZH1-4k'
DDK_IMAGE='ghcr.io/ylarod/ddk-min:android15-6.6-20260828@sha256:51159bc935c75a282fc65bc87e02f16bd098d1cdf55dc558c4fdd0fcf7a132e2'
ROOT="$(git rev-parse --show-toplevel)"
CACHE="${DDK_CACHE:-$HOME/.cache/ksunext-s938b-cczh1}"
NDK="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/28.2.13676358}"
CRANE="${CRANE:-$HOME/.local/bin/crane}"
DDK_ROOT="$CACHE/rootfs/opt/ddk"
SRC="$DDK_ROOT/src/android15-6.6"
KDIR="$DDK_ROOT/kdir/android15-6.6"
OUT="$ROOT/out/S938BXXSCCZH1"

for tool in go tar make pahole modinfo cargo python3; do
  command -v "$tool" >/dev/null || { echo "missing dependency: $tool" >&2; exit 1; }
done
if [[ ! -x "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang" ]]; then
  echo "Android NDK r28c not found at $NDK (set ANDROID_NDK_HOME)" >&2
  exit 1
fi
mkdir -p "$(dirname "$CRANE")" "$CACHE/rootfs" "$OUT"
if [[ ! -x "$CRANE" ]]; then
  GOBIN="$(dirname "$CRANE")" go install github.com/google/go-containerregistry/cmd/crane@v0.22.1
fi
if [[ ! -f "$CACHE/ddk-min.tar" ]]; then
  "$CRANE" export "$DDK_IMAGE" "$CACHE/ddk-min.tar"
fi
if [[ ! -d "$DDK_ROOT" ]]; then
  tar -xf "$CACHE/ddk-min.tar" -C "$CACHE/rootfs"
fi

python3 - "$SRC/include/linux/sched.h" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = "\tANDROID_OEM_DATA_ARRAY(1, 6);\n\n#ifdef CONFIG_KRETPROBES"
new = "\tANDROID_OEM_DATA_ARRAY(1, 6);\n\tANDROID_VENDOR_DATA(2);\n\n#ifdef CONFIG_KRETPROBES"
if new not in s:
    if old not in s:
        raise SystemExit("Samsung task_struct insertion point not found")
    p.write_text(s.replace(old, new, 1))
PY

# Relocate the prepared DDK so it works directly from an ordinary user shell.
printf '# Relocated DDK wrapper; generated from %s/Makefile\ninclude %s/Makefile\n' "$SRC" "$SRC" > "$KDIR/Makefile"
ln -sfn "$SRC" "$KDIR/source"
printf '#define UTS_RELEASE "%s"\n' "$TARGET_RELEASE" > "$KDIR/include/generated/utsrelease.h"
printf '%s\n' "$TARGET_RELEASE" > "$KDIR/include/config/kernel.release"

export PATH="$DDK_ROOT/clang/clang-r510928/bin:$PATH"
export ARCH=arm64 LLVM=1 LLVM_IAS=1
make -C "$KDIR" M="$ROOT/kernel" clean
make -C "$KDIR" M="$ROOT/kernel" -j"$(nproc)" modules \
  CONFIG_KSU=m \
  CONFIG_KSU_SAMSUNG_KDP=y \
  CONFIG_KSU_SAMSUNG_RKP=y \
  CONFIG_KSU_SAMSUNG_DEFEX=y \
  CONFIG_KSU_SAMSUNG_NO_PATCH_TEXT=y

cp "$ROOT/kernel/kernelsu.ko" "$OUT/android15-6.6_kernelsu.ko"
"$DDK_ROOT/clang/clang-r510928/bin/llvm-strip" --strip-debug "$OUT/android15-6.6_kernelsu.ko"
actual="$(modinfo -F vermagic "$OUT/android15-6.6_kernelsu.ko")"
[[ "$actual" == "$TARGET_RELEASE "* ]] || { echo "vermagic mismatch: $actual" >&2; exit 1; }

embed="$ROOT/userspace/ksud/bin/aarch64/android15-6.6_kernelsu.ko"
mkdir -p "$(dirname "$embed")"
cp "$OUT/android15-6.6_kernelsu.ko" "$embed"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"
export LIBCLANG_PATH="$NDK/toolchains/llvm/prebuilt/linux-x86_64/lib"
cargo build --locked --release --target aarch64-linux-android --manifest-path "$ROOT/userspace/ksud/Cargo.toml"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-all \
  -o "$OUT/ksud-next-v3.4.0-samsung-S938BXXSCCZH1" \
  "$ROOT/userspace/ksud/target/aarch64-linux-android/release/ksud"
chmod 0755 "$OUT/ksud-next-v3.4.0-samsung-S938BXXSCCZH1"
(
  cd "$OUT"
  sha256sum android15-6.6_kernelsu.ko ksud-next-v3.4.0-samsung-S938BXXSCCZH1 > SHA256SUMS
)
printf 'Build complete: %s\n' "$OUT"
cat "$OUT/SHA256SUMS"
