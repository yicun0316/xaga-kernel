#!/usr/bin/env bash
# =============================================================================
# 把编译产物 Image 打包成可刷入的 AnyKernel3 zip
#   用法: package-ak3.sh <kernel_dir> [tag]
#   产物: ./out/ak3-<version>-<tag>.zip
#
# 说明: AK3 v3 的 anykernel.sh 用 BLOCK= / IS_SLOT_DEVICE= 变量，
#       不再用旧版的 block=boot 属性。这里直接生成整份脚本，不 sed 模板。
# =============================================================================
set -euo pipefail

K=${1:?用法: package-ak3.sh <kernel_dir> [tag]}
TAG=${2:-build}
ROOT=$PWD

# 兼容两种产物路径：build.sh 的 out/*/dist/Image，和手工 make 的 out/arch/arm64/boot/Image
# 注意：不要用 `ls ... | head`。glob 不匹配时 ls 返回 2，配合 pipefail 会让赋值语句失败，
# 加上 set -e 就直接退出，而 stderr 已被丢弃，日志里只会看到 "exit code 2" 一片空白。
IMG=""
for p in "$K"/out/*/dist/Image "$K"/out/arch/arm64/boot/Image; do
  if [ -f "$p" ]; then IMG=$p; break; fi
done
[ -n "$IMG" ] || { echo "找不到 Image（已找过 out/*/dist/Image 与 out/arch/arm64/boot/Image）"; exit 1; }
echo ">> Image: $IMG ($(du -h "$IMG" | cut -f1))"

work=$(mktemp -d)
cd "$work"
echo ">> 下载 AnyKernel3 模板"
curl -fsSL -o ak3.zip https://github.com/osm0sis/AnyKernel3/archive/refs/heads/master.zip
unzip -q ak3.zip
d=$(find . -maxdepth 1 -type d -name 'AnyKernel3-*' | head -1)
[ -d "$d" ] || { echo "解压失败"; exit 1; }

cp "$IMG" "$d/Image"

# ---- 生成 anykernel.sh（v3 格式） ----
cat > "$d/anykernel.sh" <<'AK3EOF'
### AnyKernel3 Ramdisk Mod Script
## 由 CI 生成 — GKI 5.10 kernel-only 替换

properties() { '
kernel.string=GKI 5.10 by ztc1997 (CI optimized)
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=
'; }

# ---- 分区识别 ----
# 槽位: auto = 从 ro.boot.slot_suffix / /proc/cmdline 自动取 _a/_b
#       A/B 机器上 BLOCK=boot + SLOT=_a 会解析成 /dev/block/by-name/boot_a
# 分区: 默认 boot；只有 boot 完全不存在（A13+ 新布局）才退到 init_boot
#       注意用通配符判断：A/B 机器没有不带后缀的 boot 节点
BLOCK=boot;
IS_SLOT_DEVICE=auto;
has_part() {
  ls /dev/block/by-name/$1* /dev/block/bootdevice/by-name/$1* >/dev/null 2>&1;
}
if ! has_part boot && has_part init_boot; then
  BLOCK=init_boot;
fi
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# GKI 只换 kernel，不碰 ramdisk：split 出 boot.img 后只写回 kernel
split_boot;
flash_boot;
AK3EOF

ver=$(strings "$IMG" | grep -m1 '^Linux version ' | awk '{print $3}' || echo unknown)
mkdir -p "$ROOT/out"
OUT="$ROOT/out/ak3-${ver}-${TAG}.zip"
( cd "$d" && zip -rq9 "$OUT" . )

echo ">> 打包完成: $OUT ($(du -h "$OUT" | cut -f1))"
sha256sum "$OUT" | tee "$OUT.sha256"
