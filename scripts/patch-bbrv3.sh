#!/usr/bin/env bash
# =============================================================================
# 用 google/bbr 的 v3 分支替换 net/ipv4/tcp_bbr.c
# 用法: patch-bbrv3.sh <kernel_dir>
#
# 注意: google/bbr v3 面向 6.x，5.10 上需要把 5.18+ 的 accessor 还原。
#       本脚本只处理最常见的两类，其余若报错需人工改。
# =============================================================================
set -euo pipefail

K=${1:?用法: patch-bbrv3.sh <kernel_dir>}
DST="$K/net/ipv4/tcp_bbr.c"
[ -f "$DST" ] || { echo "找不到 $DST"; exit 1; }

tmp=$(mktemp -d)
echo ">> 下载 google/bbr v3"
curl -fsSL -o "$tmp/bbr.tar.gz" https://github.com/google/bbr/archive/refs/heads/v3.tar.gz
tar -xzf "$tmp/bbr.tar.gz" -C "$tmp"
SRC=$(find "$tmp" -name tcp_bbr.c | head -1)
[ -n "$SRC" ] || { echo "压缩包里没有 tcp_bbr.c"; exit 1; }

cp "$DST" "$DST.bbr1.bak"
cp "$SRC" "$DST"
echo ">> 已替换（原文件备份为 tcp_bbr.c.bbr1.bak）"

# 5.18+ 的 helper 在 5.10 上不存在，还原成直接访问
sed -i -E 's/tcp_snd_cwnd_set\(([a-z_]+), ?([^)]+)\)/\1->snd_cwnd = \2/g' "$DST" || true
sed -i -E 's/tcp_snd_cwnd\(([a-z_]+)\)/\1->snd_cwnd/g' "$DST" || true

echo ">> 剩余可能的兼容点（若编不过按报错补）:"
grep -nE 'tcp_snd_cwnd_set|tcp_snd_cwnd\(|tcp_snd_pipe|bbr_random|struct bbr_rand' "$DST" || echo "   无"
