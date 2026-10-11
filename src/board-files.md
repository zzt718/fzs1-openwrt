# ============================================================
#  MIBOX-668M2 板级文件（要放进 OpenWrt 源码树的片段）
#  这些是"照抄社区固件"的部分，与内核版本无关。
# ============================================================

# ------------------------------------------------------------
# 【1】target/linux/ramips/dts/mt7628an_mibox_668m2.dts
#      → 见 ../../src/mt7628an_mibox_668m2.dts（本仓库已备好）
# ------------------------------------------------------------


# ------------------------------------------------------------
# 【2】target/linux/ramips/image/mt76x8.mk  追加设备定义
# ------------------------------------------------------------
### 追加到文件末尾：
#
# define Device/mibox_668m2
#   SOC := mt7628an
#   DEVICE_VENDOR := MIBOX
#   DEVICE_MODEL := 668M2 (蜂助手 S1)
#   DEVICE_PACKAGES := kmod-usb2 kmod-usb-ohci kmod-usb-net-rndis \
#       kmod-usb-serial-option kmod-i2c-mt7628 i2c-tools \
#       kmod-mt76 kmod-mt7603
#   SUPPORTED_DEVICES += mibox,668m2
#   IMAGE_SIZE := 16128k
# endef
# TARGET_DEVICES += mibox_668m2
#
# 说明：
#   IMAGE_SIZE = 0xFB0000(16,646,144) ≈ 16128k（firmware 分区大小，留点余量）
#   DEVICE_PACKAGES 是"随固件一起编进去"的包，24.10 里包名要核对（见 docs 风险节）


# ------------------------------------------------------------
# 【3】target/linux/ramips/base-files/etc/board.d/02_network
#      在 ramips_setup_interfaces() 的 case 里加：
# ------------------------------------------------------------
### 加在 case "$board" in 分支内：
#
# 	mibox,668m2)
# 		ucidef_add_switch "switch0" \
# 			"2:lan" "4:lan" "1:wan" "6@eth0"
# 		;;
#
### 并在 ramips_setup_macs() 的 case 里加：
#
# 	mibox,668m2|\
# 	skylab,skw92a|\
# 	totolink,lr1200)
# 		wan_mac=$(mtd_get_mac_binary factory 0x2e)
# 		;;
#
# 注意：社区固件用的是 "2:lan" "4:lan" "1:wan" "6@eth0"，与 portmap=0x07 对应。
#       MAC 偏移需与 DTS 里的 macaddr@28 一致（0x28）；此处 0x2e 是 WAN 口 MAC
#       （= 基础 MAC + 偏移），需真机核对后再定。


# ------------------------------------------------------------
# 【4】target/linux/ramips/base-files/etc/board.d/01_leds
#      在 case "$board" in 里加：
# ------------------------------------------------------------
### 加在 case "$board" in 分支内：
#
# 	mibox,668m2)
# 		ucidef_set_led_netdev "wan" "wan" "blue:wan" "eth0.2"
# 		ucidef_set_led_netdev "wifi_led" "wifi" "blue:wifi" "wlan0"
# 		;;
#
# （run 灯已由 DTS 的 led-running 别名接管，无需在此声明）


# ------------------------------------------------------------
# 【5】内核 DTS 挂载（mt76x8 的 image Makefile 会自动按 DTS 名找文件）
#      DTS 文件名 mt7628an_mibox_668m2.dts → 设备名 mibox_668m2，
#      需确保 DEVICE 定义里的 DTS 名与文件名匹配。
# ------------------------------------------------------------
