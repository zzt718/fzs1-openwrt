# 蜂助手 S1 OpenWrt 固件 · fzs1-openwrt

> **给「蜂助手 S1」（MIBOX-668M2）自编译的 OpenWrt 固件 —— 双模组 4G 上网 + 中文蜂窝运维面板，刷一次机全都有。**  
> 基于 OpenWrt 23.05（内核 5.15），已实测：双 EC200 模组 RNDIS 上网、mwan3 负载均衡、中文面板开箱可用。

**语言 / Language：** 简体中文 · [English](README.en.md)

**适用范围与关键词**（方便检索）：  
`蜂助手 S1` / `MIBOX-668M2` / `MT7628DAN` 4G CPE、`Quectel EC200T` / `EC200N`、  
OpenWrt 23.05（ramips/mt76x8）、双模组 RNDIS、`mwan3`、LuCI、中文面板、短信转发。

> ⚠️ **刷机有风险，请先阅读 [免责声明](#免责声明)。** 本项目**不修改 IMEI**，也不含任何云控/后门。

> 📦 **下载固件**：[Releases 页面](../../releases/latest) → 选最新版 → 下载 `*squashfs-sysupgrade.bin`。

> 💚 **本项目完全免费、开源，无任何收费内容。** 如果你在花钱买它，请立即停止并到仓库 Issue 反馈。

---

## 界面预览

**OpenWrt 状态页**（固件信息 / 内存 / 存储）：

![OpenWrt 状态页](images/status.jpg)

**蜂助手面板 · 概览**（双模组状态 + 功能入口，内置 LuCI 面板）：

![蜂助手面板 · 概览](images/panel-overview.jpg)

> 双模组的信号 / 运营商 / 驻网频段 / 小区一屏可见；上网设置、锁频段、锁小区、IMEI、APN、短信中心等入口齐全。

---

## 这是什么

**一整套可直接刷入的 OpenWrt 固件**，针对「蜂助手 S1」这台双卡 4G CPE 定制：

- **底座**：OpenWrt 23.05.5（内核 5.15.167），官方 `ramips/mt76x8` target，opkg 可装软件包；
- **硬件适配**：本板专属设备树（DTS）+ 板级脚本，把双 EC200 模组、I2C 上电、网口映射、LED 全部接好；
- **双模组上网**：两个模组走 RNDIS，`mwan3` 负载均衡，任一在线即可上网；
- **内置中文面板**：`luci-app-fzs`（蜂助手面板）已集成进固件，**刷完打开网页即用**，无需再装 ipk。

一句话：**刷一次机 = 新底座 + 现成面板。**

## 硬件

| 项   | 规格                                                           |
| --- | ------------------------------------------------------------ |
| SoC | MediaTek **MT7628DAN**（ramips / mt76x8）                      |
| 存储  | **16MB** SPI-NOR flash / **64MB** DDR2                       |
| 模组  | Quectel **EC200T**（CAT4）+ **EC200N**（CAT1），经 I2C 芯片 @0x39 上电 |
| 无线  | 仅 **2.4GHz**                                                 |
| 网口  | **3× RJ45**（**2× LAN + 1× WAN**，MT7628 内置交换机）              |

## 为什么自编译

- **22.03 太旧**：官方安全更新已停止；
- **24.10（内核 6.6）在本板实测不可用**：启动慢、USB 重枚举容错差（详见仓库外部的内部记录），已封存；
- **23.05（内核 5.15）** 是本板"既有官方 target、又稳定"的最佳落点；
- **自编译 = 每一行可控**，解决"用别人二进制"的信任链问题。

## 固件特性

| 能力           | 说明                                                  |
| ------------ | --------------------------------------------------- |
| 双模组 RNDIS 上网 | `rndis-modem1` / `rndis-modem2`，稳定命名，双网关同址路由已处理     |
| 负载均衡         | `mwan3` 策略 `balanced`，50/50 分流，自动判在线                |
| 中文面板         | 概览 / 上网设置 / 锁频段 / 锁频点·锁小区 / IMEI / APN 与数据开关 / 短信中心 |
| 短信转发         | 支持企业微信 / 钉钉 / 飞书 / Telegram / webhook 等渠道           |
| Web 后台       | LuCI（Argon 主题，中文），`http://192.168.1.1/`             |
| 精简体积         | 砍掉 ttyd / OpenSSL / dbus 等非必需件，overlay 可用 ≈ 8MB     |

## 安装（刷机）

1. 先确保设备**已能进** OpenWrt（社区版或本固件旧版皆可）；
2. 到 [Releases](../../releases/latest) 下载 `openwrt-ramips-mt76x8-mibox_668m2-squashfs-sysupgrade.bin`；
3. **网页刷**：LuCI → 系统 → 备份/刷写固件 → 选该文件 → 刷写；  
   **命令行刷**：`sysupgrade -F -n /tmp/<固件>.bin`（`-n` 清配置，跨版本建议）；
4. 等待重启（约 1.5~2 分钟），浏览器打开 `http://192.168.1.1/`。

> 默认 root 密码见下方"首次登录"。

### 首次登录

| 项           | 值                     |
| ----------- | --------------------- |
| 后台地址        | `http://192.168.1.1/` |
| 用户名         | `root`                |
| **密码**      | **`admin`**           |
| **WiFi 名称** | **`FZS-S1`**          |
| **WiFi 密码** | **`1234567890`**      |

> ⚠️ **安全提示**：以上均为默认值，**强烈建议首次登录后立刻修改**后台密码与 WiFi 密码（LuCI → 系统 → 管理权 / 网络 → 无线）。

## 一键救砖包

救砖包是一个 Windows 小工具：解压后双击 `一键救砖.bat`，它会在电脑上架设一个 TFTP 服务器，
配合设备内置的恢复通道完成固件刷写，让设备恢复成可用状态——**无需拆机，无需串口线**。

**这是应急手段，不是常规刷机方式**：设备能正常进入后台时，请直接使用网页刷机（见上一节）。

原理是设备引导程序（u-boot）内置了工厂级的 TFTP 恢复通道：通电时按住 reset 键，它会自动从
`192.168.1.3` 下载固件并写入闪存；本工具负责在电脑端把这个 TFTP 服务器架起来。

### 操作步骤（约 5 分钟）

1. 从 [Releases](../../releases) 下载 **`FZS-S1-Rescue-v1.zip`**，解压到任意目录；
2. 用网线连接电脑与设备（设备的**任意 LAN 口**），运行 **`一键救砖.bat`**
   （建议：右键 → **以管理员身份运行**）；
3. 按屏幕提示操作设备：**设备断电 → 用取卡针/回形针捅住 reset 小孔 → 插上电源，继续捅住约 3 秒后松开**。

此后全自动：下载固件 → 写入闪存 → 自动重启。**过程中请勿断电、勿拔网线。**
约 5 分钟后访问 `http://192.168.1.1`，出现登录页即为恢复成功。

### 常见问题

| 问题 | 说明 |
|---|---|
| **首次启动很慢** | 正常。设备需要重建配置区（约 2~3 分钟），期间可能自动重启一次 |
| **工具没有任何反应** | 依次检查：① 网线是否插在设备 **LAN 口**（非 WAN 口）② 工具窗口是否显示 TFTP 服务已启动 ③ 是否以**管理员**身份运行 ④ reset 是否确实被捅住（取卡针插进小孔里按住） |
| **会不会刷坏设备** | 不会。引导程序不参与刷写，只要它完好，随时可以再次进入恢复流程 |
| **恢复后是什么系统** | 本项目的 OpenWrt 固件。之后可在网页后台刷写其它固件 |

> ⚠️ 仅限在**你合法拥有**的设备上使用。本工具只操作电脑的**有线网卡**，不影响无线网络。

---

## 从源码构建

本项目**不要求你改 OpenWrt 主仓库**，用脚本把定制内容注入官方源码树即可。

```bash
# 1) 准备（WSL2 / Linux，Ubuntu 22.04+）
sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib \
  g++-multilib gettext git libncurses5-dev libssl-dev python3-setuptools rsync \
  swig unzip zlib1g-dev file wget time libelf-dev

# 2) 一键编译（拉源码 → 注入板级+面板 → defconfig → 编译）
bash build.sh

# 产物：build/openwrt-ramips-mt76x8-mibox_668m2-squashfs-sysupgrade.bin
```

> 分步：`bash build.sh clone|inject|config|build`。  
> 面板（luci-app-fzs）默认从姊妹项目 [fzs1-panel](../../../fzs1-panel) 的 Release 下载 ipk 内置；  
> 也可用 `FZS_PANEL_IPK=/path/to/*.ipk bash build.sh inject` 指定本地文件。

> 也支持 **GitHub Actions 在线编译**（见 `.github/workflows/build.yml`）——手动触发或推 tag 自动出固件到 Release。

## 目录结构

```
fzs1-openwrt/
├── README.md / README.en.md   # 本文件（中/英）
├── LICENSE                    # GPL-3.0
├── build.sh                   # ★ 一键编译（clone → inject → config → build）
├── src/                       # ★ 定制源：DTS + 板级文件 + 配置
│   ├── mt7628an_mibox_668m2.dts        # 本板设备树
│   ├── config.seed.v2                  # OpenWrt 配置种子
│   ├── board-files/                    # 板级文件（init.d / uci-defaults / hotplug）
│   └── luci-app-fzs.Makefile           # 内置面板的打包 Makefile
├── patches/                   # 板级补丁（如有）
├── .github/workflows/         # 在线编译（GitHub Actions）
└── build/                     # 编译产物（git 忽略；正式固件走 Releases）
```

> 内置面板的**源码**在姊妹项目 [fzs1-panel](../../../fzs1-panel)；本仓编译时按其 Release 下载 ipk 内置。

## 已知限制

- **NET 指示灯不亮**：本机 GPIO37 那颗蓝灯，经全手段实测**软件不可控**（社区固件同样不亮），  
  判定与厂商私有板级初始化有关，**本项目不修**（不影响任何功能）。
- **仅 2.4GHz 无线**：硬件本身只支持 2.4G。
- **16MB flash**：overlay 空间有限，装大型插件前请注意。

## 常见问题

**Q：刷了会变砖吗？能刷回原厂吗？**  
A：sysupgrade 刷写失败一般仍可进 uboot/救援模式；恢复原厂的路径见项目内说明文档（若提供）。

**Q：能装别的插件吗？**  
A：可以。本固件是标准 OpenWrt 23.05，`opkg update && opkg install <包>` 即可（依赖 opkg 源可达）。

**Q：为什么要 `-n` 清配置刷？**  
A：跨版本/大改版时，旧配置可能与新固件不兼容；`-n` 最稳。同版本小升级可用保留配置。

## 致谢

- **OpenWrt** 项目与 `ramips/mt76x8` 社区；
- **社区固件作者** —— 本项目的板级适配（双模组 RNDIS、mwan3、I2C 上电）建立在其先行工作之上；
- **蜂助手面板**（姊妹项目 `fzs1-panel`）作者 —— 中文运维面板。

## 免责声明

- 本固件**按"现状"提供，不作任何担保**。刷机可能导致设备无法使用，风险自负。
- 本项目**不修改 IMEI、不含云控、不收集任何用户数据**。
- 请仅对你**本人合法拥有**的设备使用。
- 在适用法律允许的最大范围内，作者不对任何直接或间接损失负责。

## 许可证

[GPL-3.0-or-later](LICENSE)。本项目基于 OpenWrt 及其开源组件，遵循相应开源许可。
