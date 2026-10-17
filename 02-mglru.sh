#!/usr/bin/env bash
# =============================================================================
# 从 AOSP android13-5.10 回移 MGLRU 到 android12-5.10 树
#   前置: 在 ztc1997 仓库的源码根目录，工作区干净（git status 无改动）
#   用法: ./02-mglru.sh
#   失败点: mm/vmscan.c 冲突。解决后 git add -A && git cherry-pick --continue
# =============================================================================
set -uo pipefail

TAG=refs/tags/android13-5.10-2023-04_r2
AOSP=https://android.googlesource.com/kernel/common

die() { echo "错误: $*" >&2; exit 1; }

[ -d .git ] || die "请在 kernel 源码根目录运行"
[ -z "$(git status --porcelain)" ] || die "工作区不干净，先 git stash 或 commit"

# 1. 拉 AOSP 分支（约 1-2GB，耐心等）
if ! git remote get-url aosp >/dev/null 2>&1; then
  git remote add aosp "$AOSP"
fi
echo ">> 拉取 $TAG ..."
git fetch aosp "$TAG" || die "fetch 失败（网络/磁盘）"

# 2. 按时间正序列出 MGLRU 相关提交
git log --reverse --format='%h %s' FETCH_HEAD --grep='Multi-gen LRU' -i \
  > /tmp/mglru-list.txt
echo ">> 找到 $(wc -l < /tmp/mglru-list.txt) 个 MGLRU 提交:"
cat /tmp/mglru-list.txt

[ -s /tmp/mglru-list.txt ] || die "没找到 MGLRU 提交，检查 TAG"

# 3. 逐个 cherry-pick（保留原始出处）
echo ">> 开始 cherry-pick（冲突时中断）"
while read -r sha _; do
  if ! git cherry-pick -x "$sha"; then
    echo
    echo "!! 冲突于 $sha"
    echo "   1) 解决冲突（重点看 mm/vmscan.c mm/Kconfig include/linux/mmzone.h）"
    echo "   2) git add -A && git cherry-pick --continue"
    echo "   3) 重跑本脚本会从头再来，建议手抄剩余提交继续："
    echo "      git cherry-pick -x \$(sed -n '/^$sha/,\$p' /tmp/mglru-list.txt | awk '{print \$1}')"
    exit 1
  fi
done < /tmp/mglru-list.txt

# 4. 验证符号已存在
if grep -q 'config LRU_GEN' mm/Kconfig; then
  echo ">> 源码已包含 MGLRU"
  ./optimize.sh config
else
  die "cherry-pick 完成但 mm/Kconfig 仍无 LRU_GEN，检查补丁是否被 --skip"
fi

echo
echo ">> 编译: BUILD_CONFIG=build.config.gki.aarch64 build/build.sh -j\$(nproc)"
echo ">> 开机验证: cat /sys/kernel/mm/lru_gen/enabled   # 期望 0x0007"
