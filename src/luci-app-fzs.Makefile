#
# luci-app-fzs —— 蜂助手面板（MIBOX-668M2 蜂窝运维 LuCI 应用）
#
# 本包用"预编译文件"方式打包：面板的 ipk 内容已解包放入 files/，
# 由本 Makefile 直接安装进固件（等价于把 ipk 内置）。
#
# 来源：fzs1_panel 项目 luci-app-fzs_0.2.8_all.ipk
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-fzs
PKG_VERSION:=0.2.8
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=zzt718

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Fengzhushou FZS Panel (蜂助手面板)
  # ★ 绝不把 i2c-tools 写进本包 DEPENDS（2026-10-11 交付级 bug 修复）
  #   机制：opkg 里包的 'Auto-Installed: yes' 由【是否被别的包依赖】决定，与 Makefile 的
  #        '+' 前缀无关（生成的 ipk control 里两者写法相同）。i2c-tools 唯一依赖者就是本包，
  #        于是用 opkg 升级面板 ipk 时（先卸旧版 → 依赖图瞬间缺它 → 判为孤儿）
  #        i2c-tools 会被当孤儿自动删除 → /usr/sbin/i2ctransfer 消失 →
  #        /etc/init.d/mifi-modem 无法给 I2C@0x39 上电 → 两个模组全哑（4G/短信全废）。
  #   正解：i2c-tools 属固件级必需，由 .config 的 CONFIG_PACKAGE_i2c-tools=y 显式安装，
  #        让它成为【无依赖者的独立手动安装包】，任何 opkg 操作都不会清它。
  #        （面板原始 ipk 的 control 本来也不含 i2c-tools，此处对齐。）
  DEPENDS:=+luci-base +rpcd
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
  蜂助手面板 —— MIBOX-668M2 蜂窝运维 LuCI 应用。
  双模组状态面板 / 锁频段(AT*BAND) / 锁频点·锁小区(AT*CELL) /
  短信中心(收件箱+转发) / IMEI / APN 与数据开关 / 运维工具。
  自包含 AT 引擎，不依赖 mifi-at 内部实现。
endef

define Build/Compile
endef

# 直接安装预置文件（files/ 目录下已是最终目录结构）
define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	# 权限：脚本可执行
	chmod 0755 $(1)/usr/bin/fzs-atio 2>/dev/null || true
	chmod 0755 $(1)/usr/libexec/fzs-at 2>/dev/null || true
	chmod 0755 $(1)/usr/libexec/fzs-fwd 2>/dev/null || true
	chmod 0755 $(1)/usr/libexec/fzs-net 2>/dev/null || true
	chmod 0755 $(1)/usr/libexec/fzs-smsd 2>/dev/null || true
	chmod 0755 $(1)/etc/init.d/fzs-sms 2>/dev/null || true
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
