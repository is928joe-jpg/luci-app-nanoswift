> GitHub 搜索关键词：`sing-box` `luci` `tun` 就可以找到 NanoSwift。

# NanoSwift：轻量级 OpenWrt Sing-Box LuCI 管理插件

**NanoSwift** 是一款专为 OpenWrt 设计的轻量级 LuCI 插件。它以 **sing-box** 为核心，集成透明代理（TUN）、FakeIP、多协议订阅转换以及 Cloudflare 优选 IP（CFNAT）功能，旨在提供简单直观、高性能、低资源占用的代理管理体验。

## 📦 安装

`察看当前路由器的架构(ARCH)`
```bash
opkg print-architecture
# 或者
cat /etc/openwrt_release
```

### 1. 安装 NanoSwift

安装对应架构的 NanoSwift IPK 包后，即可在 LuCI 后台使用：

https://github.com/is928joe-jpg/luci-app-nanoswift/releases/latest

首次安装:

```bash
opkg install luci-app-nanoswift_*.ipk
```

如果之前已经安装了其它版本,强烈建议先导出数据,便于日后导入恢复:

```bash
opkg remove luci-app-nanoswift
opkg install luci-app-nanoswift_*.ipk
```

### 2. 安装 sing-box

NanoSwift 依赖 sing-box 运行，如果之前没有安装, 请安装与当前 OpenWrt 架构匹配的 sing-box.ipk：

https://github.com/SagerNet/sing-box/releases/latest

安装完成后：

```text
LuCI → 服务 → NanoSwift
```

## 📸 界面预览

<p align="center">
  <img src="https://github.com/is928joe-jpg/luci-app-nanoswift/blob/main/images/1.png?raw=true" width="45%" alt="服务设定" />
  <img src="https://github.com/is928joe-jpg/luci-app-nanoswift/blob/main/images/2.png?raw=true" width="45%" alt="CFNAT 设置" />
</p>

<p align="center">
  <b>📌 左：服务设定与 API 状态、Cloudflare 优选 IP（CFNAT）</b><br>
  <b>📌 右：多协议订阅转换</b>
</p>

<p align="center">
  <img src="https://github.com/is928joe-jpg/luci-app-nanoswift/blob/main/images/3.png?raw=true" width="45%" alt="订阅管理" />
  <img src="https://github.com/is928joe-jpg/luci-app-nanoswift/blob/main/images/4.png?raw=true" width="45%" alt="节点组管理" />
</p>

<p align="center">
  <b>📌 左：扁平化组管理、规则管理、拖拽式分流绑定（支持排序与自动合并）</b><br>
  <b>📌 右：可视化 Clash Yacd 节点管理</b>
</p>

<p align="center">
  <img src="https://github.com/is928joe-jpg/luci-app-nanoswift/blob/main/images/5.png?raw=true" width="80%" alt="规则绑定" />
</p>

<p align="center">
  <b>⚡ 规则绑定界面 —— 极低资源占用</b>
</p>

---

## 🌟 核心特性

* **全协议兼容**

  * 原生支持 Clash（YAML）、V2Ray（Neko / V2rayN URI）以及 Sing-Box（JSON）订阅格式,推荐采用sing-box格式。

* **极致性能**

  * 深度优化 TUN 模式与 FakeIP，大幅降低网络延迟与 CPU 开销。

* **智能规则引擎**

  * 支持远程与本地编译的 SRS 二进制规则集。
  * 支持基于 IP、端口、域名后缀及域名关键词的精准分流。
  * 支持拖拽手柄 `≡` 调整规则优先级，同类规则自动合并，保持配置简洁。

* **内置 CFNAT 增强**

  * 无需手动寻找 Cloudflare 优选 IP。

  * 使用方法：将 VLESS WS-TLS 节点配置中的：

    ```text
    server = 127.0.0.1
    port   = 2345
    ```

  * 集成 Cloudflare 优选 IP 工具，支持多线程扫描。

  * 支持移动、联通、电信运营商分池。

  * 支持百度前置代理（Baidu Proxy）模式。

  * 内置 CFNAT C 版，针对 OpenWrt 与低内存设备优化。

  * 支持 Cloudflare IP 优选、健康检查、单端口 TCP 转发等功能。

  项目地址：

  https://github.com/fscarmen/cfnat

* **Clash 控制面板**

  * 内置 API 密钥与端口配置。
  * 支持一键跳转 Yacd 或 Metacubexd 面板进行实时节点管理。

---

## 🛠 功能模块

### 1. 服务设定

支持开机自启、延迟启动以及 SRS 规则集 Cron 定时自动更新，确保分流规则始终保持最新。

### 2. CFNAT 优选

针对 Cloudflare CDN 节点进行本地延迟测速。支持自定义数据中心（如 NRT、SIN、HKG）、扫描线程数以及目标延迟阈值，为 Warp 或自建节点选择更优的接入点。

### 3. 订阅与节点池

支持一键同步多平台订阅源，并提供直观的节点池预览。可手动移除无效节点，并将节点快速分配至不同策略组。

> 高级用法
>
> 如果您的 VPS 安装脚本支持直接输出 sing-box 配置，可将包含 `outbounds` 的 sing-box JSON 文件放入：
>
> `/etc/nanoswift/static/`
>
> 在执行“保存订阅并更新节点池”时，NanoSwift 会自动导入该文件中的节点作为内置节点。

### 4. 节点组（策略组）

支持：

* `urltest`：自动择优
* `selector`：手动选择

通过简单勾选即可完成节点的动态分配。

### 5. 分流规则绑定

将规则（如 Google、Netflix、Telegram）与目标出站（策略组或直连）进行绑定。支持拖拽调整匹配顺序，使分流逻辑更加直观。

---

## 🚀 快速上手

1. 在“服务设定”中确认 `sing-box` 执行文件及工作目录路径。
2. 在“订阅源设置”中添加订阅链接，点击 **保存订阅并更新节点池**。
3. 在“节点组管理”中新建策略组（例如 `Proxy`），并选择节点。
4. 在“分流规则绑定”中配置规则（例如将 `geosite-youtube` 绑定至 `Proxy` 组）。
5. 点击 **生成配置** 写入并快速重载配置，或直接点击 **重启服务**。

---

## 📝 项目初衷

NanoSwift 旨在降低 Sing-Box 的使用门槛。

通过扁平化配置界面、节点组管理以及可视化分流规则绑定，用户无需手动编写复杂 JSON 配置即可完成日常代理管理。同时兼顾性能、灵活性与低资源占用，适用于 OpenWrt 路由器、ARM 小板机、小内存 VPS 等资源受限环境。
LuCI 的核心框架（MVC）在 23.05 → 25.1 完全没变,理论上可以通用,建议使用环境是:Argon主题下。

## 附录,你该下载哪一个ipk?

---

# ⭐ **OpenWrt 23.05 — CPU 架构 → Target 映射表**

> **左边是最终生成的 IPK 架构（33 个）**  
> **右边是属于该架构的所有 target（80 个 target 映射到 33 个架构）**

---

## 🟣 **AArch64 系列**

| CPU 架构 | Target 列表 |
|---------|-------------|
| **aarch64_cortex-a53** | mediatek-filogic, mvebu-cortexa53, sunxi-cortexa53 |
| **aarch64_cortex-a72** | mvebu-cortexa72 |
| **aarch64_generic** | armsr-armv8, ipq807x-generic, rockchip-armv8, layerscape-armv8_64b |

---

## 🔵 **ARM 系列**

| CPU 架构 | Target 列表 |
|---------|-------------|
| **arm_arm1176jzf-s_vfp** | bcm27xx-bcm2708 |
| **arm_arm926ej-s** | at91-sam9x, mxs-generic |
| **arm_cortex-a5_vfpv4** | mediatek-mt7629 |
| **arm_cortex-a7** | ipq40xx-generic, ipq40xx-mikrotik, sunxi-cortexa7 |
| **arm_cortex-a7_neon-vfpv4** | imx-cortexa7 |
| **arm_cortex-a7_vfpv4** | mediatek-mt7623 |
| **arm_cortex-a8_vfpv3** | sunxi-cortexa8 |
| **arm_cortex-a9** | mvebu-cortexa9 |
| **arm_cortex-a9_neon** | ipq806x-generic, ipq806x-chromium |
| **arm_cortex-a9_vfpv3-d16** | imx-cortexa9 |
| **arm_cortex-a15_neon-vfpv4** | mediatek-mt7622 |
| **arm_fa526** | gemini-generic |
| **arm_mpcore** | at91-sama5 |
| **arm_xscale** | kirkwood-generic |

---

## 🟢 **x86 系列**

| CPU 架构 | Target 列表 |
|---------|-------------|
| **i386_pentium-mmx** | x86-geode |
| **i386_pentium4** | x86-generic, x86-legacy |
| **x86_64** | x86-64 |

---

## 🟤 **MIPS 系列（大头）**

| CPU 架构 | Target 列表 |
|---------|-------------|
| **mips_24kc** | ath79-generic, ath79-mikrotik, ath79-nand, ath79-tiny, ramips-rt288x, ramips-rt305x, ramips-rt3883 |
| **mips_4kec** | lantiq-xway, lantiq-xway_legacy |
| **mips_mips32** | pistachio-generic, oxnas-ox820 |
| **mipsel_24kc** | ramips-mt7620, ramips-mt7621, ramips-mt76x8 |
| **mipsel_24kc_24kf** | lantiq-ase |
| **mipsel_74kc** | bcm47xx-mips74k |
| **mipsel_mips32** | bcm47xx-generic, bcm47xx-legacy |
| **mips64_octeonplus** | octeon-generic |

---

## 🟤 **PowerPC 系列**

| CPU 架构 | Target 列表 |
|---------|-------------|
| **powerpc_464fp** | apm821xx-nand, apm821xx-sata |
| **powerpc_8548** | mpc85xx-p1010, mpc85xx-p1020, mpc85xx-p2020 |

---

## 🟢 **RISC-V 系列**

| CPU 架构 | Target 列表 |
|---------|-------------|
| **riscv64_riscv64** | sifiveu-generic |

---

## 🟤 **Realtek 系列（归类到 MIPS/MIPS64）**

| CPU 架构 | Target 列表 |
|---------|-------------|
| **mipsel（Realtek）** | realtek-rtl838x, realtek-rtl839x |
| **mips64（Realtek）** | realtek-rtl930x, realtek-rtl931x |

---


