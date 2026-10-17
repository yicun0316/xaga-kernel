#!/usr/bin/env bash
# =============================================================================
# ztc1997 android_gki_kernel_5.10_common 一键优化脚本
#   用法:
#     ./optimize.sh config    # 改 arch/arm64/configs/gki_defconfig（可逆，自动备份）
#     ./optimize.sh runtime   # 手机端运行期参数（需 root）
#     ./optimize.sh check     # 采集验证数据
#   在 kernel 源码根目录执行 config；在手机上执行 runtime/check。
# =============================================================================
set -euo pipefail

DEF=arch/arm64/configs/gki_defconfig
SC=scripts/config

die() { echo "错误: $*" >&2; exit 1; }

do_config() {
  [ -f "$DEF" ] || die "请在 kernel 源码根目录运行（找不到 $DEF）"
  [ -x "$SC" ]  || die "找不到 scripts/config"

  BAK="$DEF.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$DEF" "$BAK"
  echo "备份: $BAK"

  # ---- 1. 去掉调试脚手架（纯减法，不改行为） ----
  $SC --file "$DEF" -d KASAN
  $SC --file "$DEF" -d KASAN_HW_TAGS
  $SC --file "$DEF" -d PAGE_OWNER
  $SC --file "$DEF" -d DEBUG_INFO
  $SC --file "$DEF" -d DEBUG_INFO_DWARF4
  $SC --file "$DEF" -d INIT_ON_ALLOC_DEFAULT_ON
  $SC --file "$DEF" -d KALLSYMS_ALL
  $SC --file "$DEF" -d SCHED_DEBUG
  $SC --file "$DEF" -d SCHEDSTATS

  # ---- 2. PELT 半衰期 16ms -> 12ms（更跟手；觉得费电改回 16） ----
  $SC --file "$DEF" -d PELT_UTIL_HALFLIFE_16
  $SC --file "$DEF" -e PELT_UTIL_HALFLIFE_12

  # ---- 3. BBR ----
  $SC --file "$DEF" -e TCP_CONG_ADVANCED
  $SC --file "$DEF" -e TCP_CONG_BBR
  $SC --file "$DEF" --set-str DEFAULT_TCP_CONG bbr

  # ---- 4. MGLRU（只有打了 cherry-pick 之后符号才存在） ----
  if grep -q 'config LRU_GEN' mm/Kconfig 2>/dev/null; then
    $SC --file "$DEF" -e LRU_GEN
    $SC --file "$DEF" -e LRU_GEN_ENABLED
    echo "MGLRU: 已写入配置"
  else
    echo "MGLRU: mm/Kconfig 中没有 LRU_GEN，补丁未打，跳过（先跑 02-mglru.sh）"
  fi

  echo "--- 配置差异 ---"
  diff -u "$BAK" "$DEF" || true
  echo
  echo "下一步: BUILD_CONFIG=build.config.gki.aarch64 build/build.sh -j\$(nproc)"
}

do_runtime() {
  [ "$(id -u)" -eq 0 ] || die "需要 root"
  echo 100    > /proc/sys/vm/watermark_scale_factor
  echo 131072 > /proc/sys/vm/min_free_kbytes
  echo 100    > /proc/sys/vm/swappiness
  echo 0      > /proc/sys/kernel/printk
  echo "已生效:"
  for f in watermark_scale_factor min_free_kbytes swappiness; do
    printf '  vm.%-24s = %s\n' "$f" "$(cat /proc/sys/vm/$f)"
  done
}

do_check() {
  echo "== 版本 =="
  uname -a
  echo "== 回收 =="
  grep -E 'allocstall|pgsteal_anon|pswpin|pswpout|nr_free_pages' /proc/vmstat || true
  echo "== PSI =="
  cat /proc/pressure/memory 2>/dev/null || echo "(无 PSI)"
  echo "== zram =="
  cat /sys/block/zram0/mm_stat 2>/dev/null || echo "(无 zram0)"
  cat /sys/block/zram0/comp_algorithm 2>/dev/null || true
  echo "== MGLRU =="
  cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo "(MGLRU 未启用)"
}

case "${1:-}" in
  config)  do_config  ;;
  runtime) do_runtime ;;
  check)   do_check   ;;
  *) echo "用法: $0 {config|runtime|check}"; exit 1 ;;
esac
