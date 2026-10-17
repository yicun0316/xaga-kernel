# ztc1997 GKI 5.10 内核 — CI 优化构建

在 GitHub Actions 上编译 <https://github.com/ztc1997/android_gki_kernel_5.10_common>，
并叠加一组针对「天玑 8100 / 8G / HyperOS」的优化。

---

## 先说清楚：原包有什么、没有什么

我解包并分析了你现在的内核
（`kernel-5.10.240-ztc1997-20260127_noksu.zip`，内嵌 config 6758 行），结论：

| 能力 | 原包状态 |
|---|---|
| zram 异步压缩 kcompressd | **有**（Image 里有 `vmscan: Failed to start kcompressd on node %d`） |
| zstd 作为 zram 默认算法 | **有** |
| TEO cpuidle / SSG I/O 调度 / lazy RCU / LTO Full / O3 / HZ 250 | **有** |
| **MGLRU** | **完全没有代码**（config 里连 `LRU_GEN` 符号都不存在） |
| **BBRv3** | **没有**，且 BBR 的 v1 也没编（`TCP_CONG_ADVANCED` 未开，只有 cubic） |
| KASAN / PAGE_OWNER / DEBUG_INFO / KALLSYMS_ALL | 全开（43MB Image 的来源，纯调试脚手架） |

所以本仓库做三件事：

1. **删掉调试脚手架 + 调 PELT/BBR**（纯配置，稳定可跑）
2. **可选：替换 BBRv3**（代码级，默认关）
3. **可选：MGLRU 补丁**（代码级，需要你本地先解决一次冲突）

---

## 目录

```
.github/workflows/build.yml   # CI 流程
scripts/patch-config.sh       # 配置层改动（幂等）
scripts/patch-bbrv3.sh        # BBRv3 替换（可选）
scripts/package-ak3.sh        # 打包 AnyKernel3
patches/mglru/                # 放你的 MGLRU 补丁（默认空）
optimize.sh                   # 本地：配置 / 运行期参数 / 验证
02-mglru.sh                   # 本地：从 AOSP android13-5.10 抽 MGLRU
```

---

## 用法

### 1. 建仓库并上传

把本目录整个推到一个新仓库（public 或 private 都行，private 也会消耗 Actions 额度）。

### 2. 跑 workflow

Actions → `build-kernel` → Run workflow：

| 输入 | 说明 |
|---|---|
| `branch` | 内核分支，默认 `android12-5.10-2025-12` |
| `apply_mglru` | 应用 `patches/mglru/*.patch`，**默认关**（见下） |
| `apply_bbr3` | 换成 BBRv3，**默认关**（面向 6.x，5.10 上有兼容工作） |

### 3. 下载产物

Artifacts 里有：

- `ak3-<version>-<branch>.zip` — 可直接刷的 AnyKernel3 包
- `Image`、`System.map` — 原始产物

### 4. 刷机

```bash
fastboot boot Image          # 先临时启动验证，不写分区
fastboot flash boot ak3-*.zip
```

刷之前把原包留好，出事 `fastboot flash boot 原包.zip` 一分钟回来。

---

## 为什么 MGLRU 默认关

原树里**没有 MGLRU 代码**，只能从 AOSP `android13-5.10`（Google 自己回移过）cherry-pick。
那串提交有 50+ 个，**几乎一定会和 `android12-5.10` 的 mm 代码冲突**，CI 无法交互解决。

正确流程：

```bash
# 本地（WSL2/Linux），在 kernel 源码根目录
bash 02-mglru.sh            # 逐个 cherry-pick，冲突时停下
# 解决冲突 → git add -A && git cherry-pick --continue
# 全部完成后导出补丁：
git format-patch -o ../patches/mglru <起点>..HEAD
```

把 `patches/mglru/*.patch` 提交进仓库，CI 里勾上 `apply_mglru` 即可稳定复现。

---

## 验证清单（刷完必查）

```bash
uname -a                                    # 版本对不对
cat /sys/kernel/mm/lru_gen/enabled          # 开了 MGLRU 才有，期望 0x0007
cat /sys/block/zram0/comp_algorithm         # 仍是 [zstd]
grep -E 'allocstall|pgsteal_anon' /proc/vmstat
cat /proc/pressure/memory
dmesg | grep -iE 'vermagic|module.*(fail|error)'   # 最关键：vendor 模块有没有起来
```

最后一条最关键：vendor 模块加载失败 = 指纹/相机/触屏坏，必须回退。

---

## 已知风险

1. **BBRv3 可能编不过**——它面向 6.x，`tcp_snd_cwnd()` 之类的 accessor 在 5.10 上不存在，
   `patch-bbrv3.sh` 只自动处理了最常见的两类，其余要按报错手改。
2. **MGLRU 冲突**——见上，必须本地解一次。
3. **版本后缀**——编出来的 `LOCALVERSION` 必须与官方 GKI 对齐（`-android12-9-`），
   否则 vendor_dlkm 的模块 vermagic 不匹配。
4. **boot 分区大小**——关掉 `DEBUG_INFO` 后 Image 约 15MB，一般没问题；保留全量调试信息会到 43MB，部分机型塞不下。

---

## 参考

- AOSP MGLRU 的 5.10 回移：`android13-5.10-2023-04_r2` 里的 `BACKPORT: FROMGIT: Multi-gen LRU` 系列
- BBRv3 源码：<https://github.com/google/bbr>（`v3` 分支）
- MGLRU 改动背景：MTK 的 kcompressd RFC <https://lkml.org/lkml/2025/3/7/867>（原包已合入）
