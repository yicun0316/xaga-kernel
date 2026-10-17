#!/usr/bin/env bash
# =============================================================================
# 把编译产物 Image 打包成 AnyKernel3 可刷入 zip
# 用法: package-ak3.sh <kernel_dir> [tag]
# 产物: ./out/ak3-<version>-<tag>.zip
# =============================================================================
set -euo pipefail

K=${1:?用法: package-ak3.sh <kernel_dir> [tag]}
TAG=${2:-build}
ROOT=$PWD

IMG=$(ls "$K"/out/*/dist/Image 2>/dev/null | head -1)
[ -n "${IMG:-}" ] && [ -f "$IMG" ] || { echo "找不到 Image"; exit 1; }
echo ">> Image: $IMG ($(du -h "$IMG" | cut -f1))"

work=$(mktemp -d)
cd "$work"
curl -fsSL -o ak3.zip https://github.com/osm0sis/AnyKernel3/archive/refs/heads/master.zip
unzip -q ak3.zip
d=$(find . -maxdepth 1 -type d -name 'AnyKernel3-*' | head -1)
[ -d "$d" ] || { echo "解压失败"; exit 1; }

cp "$IMG" "$d/Image"

sed -i 's|^kernel.string=.*|kernel.string=GKI 5.10 by ztc1997 (CI optimized)|' "$d/anykernel.sh"
sed -i 's|^do.devicecheck=.*|do.devicecheck=0|' "$d/anykernel.sh"
sed -i 's|^do.modules=.*|do.modules=0|' "$d/anykernel.sh"
sed -i 's|^do.systemless=.*|do.systemless=1|' "$d/anykernel.sh"
grep -q '^block=' "$d/anykernel.sh" || echo 'block=boot;' >> "$d/anykernel.sh"
grep -q '^is_slot_device=' "$d/anykernel.sh" || echo 'is_slot_device=1;' >> "$d/anykernel.sh"

ver=$(strings "$IMG" | grep -m1 '^Linux version ' | awk '{print $3}' || echo unknown)
mkdir -p "$ROOT/out"
OUT="$ROOT/out/ak3-${ver}-${TAG}.zip"
( cd "$d" && zip -rq9 "$OUT" . )

echo ">> 打包完成: $OUT ($(du -h "$OUT" | cut -f1))"
sha256sum "$OUT" | tee "$OUT.sha256"
