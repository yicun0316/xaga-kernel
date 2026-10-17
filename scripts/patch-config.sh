#!/usr/bin/env bash
# =============================================================================
# 在 CI 中对 gki_defconfig 做批量修改（幂等，重复跑结果一致）
# 用法: patch-config.sh <kernel_dir>
# =============================================================================
set -euo pipefail

K=${1:?用法: patch-config.sh <kernel_dir>}
DEF="$K/arch/arm64/configs/gki_defconfig"
[ -f "$DEF" ] || { echo "找不到 $DEF"; exit 1; }

# 先清掉同名的旧行，避免重复
strip() { sed -i "/^$1=/d; /^# $1 is not set/d" "$DEF"; }
off()   { strip "$1"; printf '# %s is not set\n' "$1" >> "$DEF"; }
on()    { strip "$1"; printf '%s=y\n' "$1" >> "$DEF"; }
str()   { strip "$1"; printf '%s="%s"\n' "$1" "$2" >> "$DEF"; }

echo ">> 1) 去掉调试脚手架"
for s in CONFIG_KASAN CONFIG_KASAN_HW_TAGS CONFIG_PAGE_OWNER \
         CONFIG_DEBUG_INFO CONFIG_DEBUG_INFO_DWARF4 \
         CONFIG_INIT_ON_ALLOC_DEFAULT_ON CONFIG_KALLSYMS_ALL \
         CONFIG_SCHED_DEBUG CONFIG_SCHEDSTATS; do
  off "$s"
done

echo ">> 2) PELT 半衰期 16ms -> 12ms"
strip CONFIG_PELT_UTIL_HALFLIFE_16
strip CONFIG_PELT_UTIL_HALFLIFE_32
strip CONFIG_PELT_UTIL_HALFLIFE_DEFAULT
on CONFIG_PELT_UTIL_HALFLIFE_12

echo ">> 3) BBR"
on CONFIG_TCP_CONG_ADVANCED
on CONFIG_TCP_CONG_BBR
str CONFIG_DEFAULT_TCP_CONG bbr

echo ">> 4) MGLRU（仅在源码已含补丁时启用）"
if grep -q '^config LRU_GEN' "$K/mm/Kconfig" 2>/dev/null; then
  on CONFIG_LRU_GEN
  on CONFIG_LRU_GEN_ENABLED
  echo "   MGLRU 配置已写入"
else
  echo "   mm/Kconfig 中无 LRU_GEN —— 原树没有 MGLRU 代码，跳过"
fi

echo ">> 结果:"
grep -E 'KASAN|PAGE_OWNER|DEBUG_INFO=|INIT_ON_ALLOC|KALLSYMS_ALL|SCHED_DEBUG|SCHEDSTATS|PELT_UTIL|TCP_CONG|LRU_GEN' "$DEF" || true
