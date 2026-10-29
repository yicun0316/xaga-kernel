#!/usr/bin/env bash
# =============================================================================
# 在 CI 中对 gki_defconfig 做批量修改（幂等，重复跑结果一致）
# 用法: patch-config.sh <kernel_dir>
#
# 原则：只做「体积裁剪」，不做「行为修改」。
#       任何会影响 ABI、struct 布局、或驱动隐含假设的选项，一律保持上游默认。
# =============================================================================
set -euo pipefail

K=${1:?用法: patch-config.sh <kernel_dir>}
DEF="$K/arch/arm64/configs/gki_defconfig"
[ -f "$DEF" ] || { echo "找不到 $DEF"; exit 1; }

# 先清掉同名的旧行，避免重复
strip() { sed -i "/^$1=/d; /^# $1 is not set/d" "$DEF"; }
off()   { strip "$1"; printf '# %s is not set\n' "$1" >> "$DEF"; }

echo ">> 1) 关掉纯调试脚手架（不改变运行时行为）"
# KASAN 虽然编进去了，但 CMDLINE 里已有 kasan=off，运行时本就是关的，
# 关掉它只省 Image 体积和一点内联开销。
for s in CONFIG_KASAN CONFIG_KASAN_HW_TAGS CONFIG_PAGE_OWNER \
         CONFIG_DEBUG_INFO CONFIG_DEBUG_INFO_DWARF4; do
  off "$s"
done

# Ubuntu 的 clang 不带 libPolly。CONFIG_LLVM_POLLY=y 时 Makefile 会追加
# 一整组 -mllvm -polly-*，而 LLVM option parsing 遇到不认识的参数是硬失败
# （不像 cc-option 那样能跳过）。关掉它，由 Makefile 的 ifdef 自然跳过。
off CONFIG_LLVM_POLLY

echo ">> 2) 以下选项刻意保持上游默认，不再改动"
cat <<'NOTE'
     CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y   vendor 驱动依赖 kmalloc 清零语义
     CONFIG_KALLSYMS_ALL=y               oops backtrace 需要函数名，否则全是地址
     CONFIG_SCHEDSTATS=y                 影响 task_struct 布局，动了会波及 vendor 模块
     CONFIG_PELT_UTIL_HALFLIFE_16=y      改半衰期等于改调度器行为
     CONFIG_DEFAULT_TCP_CONG             不设 bbr，保持原样
     CONFIG_LOCALVERSION="-ztc1997"       必须与原包一致
NOTE

echo ">> 3) 校验：下面这些必须是原值"
for s in CONFIG_INIT_ON_ALLOC_DEFAULT_ON CONFIG_KALLSYMS_ALL CONFIG_SCHEDSTATS \
         CONFIG_PELT_UTIL_HALFLIFE_16 CONFIG_LOCALVERSION CONFIG_MODVERSIONS; do
  line=$(grep -m1 "^$s=" "$DEF" || true)
  if [ -n "$line" ]; then
    printf '  OK   %s\n' "$line"
  else
    printf '  !!   缺少 %s（上游默认应有，请检查）\n' "$s"
  fi
done

echo ">> 4) MGLRU（仅在源码已含补丁时启用）"
if grep -q '^config LRU_GEN' "$K/mm/Kconfig" 2>/dev/null; then
  strip CONFIG_LRU_GEN
  strip CONFIG_LRU_GEN_ENABLED
  printf 'CONFIG_LRU_GEN=y\nCONFIG_LRU_GEN_ENABLED=y\n' >> "$DEF"
  echo "   mm/Kconfig 有 LRU_GEN，配置已写入"
else
  echo "   mm/Kconfig 中无 LRU_GEN —— 源码没有 MGLRU 代码，本次不启用（这是预期结果）"
fi

echo ">> 结果:"
grep -E 'KASAN|PAGE_OWNER|DEBUG_INFO=|INIT_ON_ALLOC|KALLSYMS_ALL|SCHEDSTATS|PELT_UTIL|TCP_CONG|LOCALVERSION|LRU_GEN' "$DEF" || true
