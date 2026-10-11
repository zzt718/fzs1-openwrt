#!/bin/sh
# ============================================================================
# MIBOX-668M2: RNDIS 通路【同步段】—— 只做「等网卡 + 重命名成稳定名」。
#
# ★★ 为什么只做这两件事（2026-09-20 拆分，方案 A）：
#   本脚本由 /etc/init.d/mifi-modem（START=18）**同步**调用，而 S18 排在
#   S19*/S20network（WiFi bring-up）之前、且脚本无 USE_PROCD
#   ⇒ **本脚本跑多久，WiFi 就晚多久**。
#
#   而 netifd 起 rndis-modemN 接口【只要求两件事】：
#     [1] 网卡存在且名字正好是 rndis-modemN（它按名字找）
#     [2] uci 里有 device/ipaddr/gateway（由 mifi-modem 写好）
#   ⇒ 「APN 激活」【完全不必须同步】！接口可以先 up（IP 由 netifd 配好），
#     数据面晚通一点完全没关系 —— mwan3track 会周期性探测，通了自然转 online。
#
#   ⇒ 所以把最慢的 APN 激活挪到 /usr/libexec/mifi-rndis-activate.sh（后台跑）。
#     实测那一段在两个模组都激活失败时要白等 132 秒（每个模组 4 个 APN 候选
#     × 14 秒 = 56 秒），是"开机 3 分钟才有 WiFi"的元凶。
#
# 用法: mifi-rndis.sh <modem1|modem2>        # 同步，正常几秒内返回
# ============================================================================

cfg="$1"
case "$cfg" in
modem1) USB=1-1.1 ;;
modem2) USB=1-1.2 ;;
*) echo "usage: $0 <modem1|modem2>"; exit 1 ;;
esac

NETDEV="rndis-$cfg"          # 稳定名（≤15 字符），替代会漂移的 usb0/usb1
LOG="logger -t mifi-rndis"

# ---- 按 USB 路径找 RNDIS 网卡（:1.0）---------------------------------------
find_netdev() {
	for _n in /sys/class/net/*; do
		[ -e "$_n" ] || continue
		_nn="${_n##*/}"
		case "$_nn" in lo|br-lan|eth0*|wlan*|ppp*|rndis-*) continue ;; esac
		case "$(readlink -f "$_n/device" 2>/dev/null)" in
		*"$USB":1.0*) echo "$_nn"; return 0 ;;
		esac
	done
	return 1
}

# ---- ★ 若稳定名已存在，直接返回，别白等 ------------------------------------
# find_netdev() 会【排除】rndis-* 前缀（避免把自己重命名后的网卡再认一遍），
# 所以如果网卡已经是 rndis-modemN（手工重跑本脚本、或 mifi-modem restart），
# 下面的等待循环会一直找不到、白等满 60 秒。这里先短路掉。
if [ -e "/sys/class/net/$NETDEV" ]; then
	ip link set "$NETDEV" up 2>/dev/null
	$LOG "$cfg: $NETDEV 已存在，无需重命名"
	exit 0
fi

# ---- 等网卡 -----------------------------------------------------------------
_nd=""
_w=0
while [ "$_w" -lt 60 ]; do
	_nd=$(find_netdev) && [ -n "$_nd" ] && break
	sleep 1; _w=$((_w + 1))
done

# ---- ★ 兜底：RNDIS probe 失败时手动重新 bind（2026-09-18 实测加的）----------
# 现象：模组上电抖动（两个模组同时重枚举）时，`$USB:1.0` 会 probe 失败：
#     dmesg: rndis_host 1-1.2:1.0: RNDIS init failed, -145   (-145 = ETIMEDOUT)
#            rndis_host: probe of 1-1.2:1.0 failed with error -145
# 此时 USB 接口【存在但没有 driver】（/sys/bus/usb/devices/X:1.0/driver 不存在），
# 而且内核【不会自动重试】⇒ 网卡永远不出现 ⇒ 该口彻底起不来（单点故障）。
# 实测 `echo -n "1-1.2:1.0" > /sys/bus/usb/drivers/rndis_host/bind` 能救活：
#     dmesg: rndis_host 1-1.2:1.0 usb0: register 'rndis_host' ... RNDIS device
if [ -z "$_nd" ]; then
	_b=0
	while [ "$_b" -lt 2 ]; do
		_b=$((_b + 1))
		if [ ! -d "/sys/bus/usb/devices/$USB:1.0" ]; then
			$LOG "$cfg: $USB:1.0 接口不存在，无法 bind"
			break
		fi
		[ -e "/sys/bus/usb/devices/$USB:1.0/driver" ] && break
		$LOG "$cfg: $USB:1.0 无驱动（RNDIS probe 失败），重新 bind 第 $_b 次"
		echo -n "$USB:1.0" > /sys/bus/usb/drivers/rndis_host/bind 2>/dev/null
		_w=0
		while [ "$_w" -lt 20 ]; do
			_nd=$(find_netdev) && [ -n "$_nd" ] && break
			sleep 1; _w=$((_w + 1))
		done
		[ -n "$_nd" ] && break
		sleep 3
	done
fi

[ -n "$_nd" ] || { $LOG "$cfg: RNDIS 网卡 ($USB:1.0) 未出现，放弃"; exit 1; }

# ---- 重命名成稳定名（★ netifd 要按这个名字找网卡，必须同步做完）-----------
if [ "$_nd" != "$NETDEV" ]; then
	ip link set "$_nd" down 2>/dev/null
	if ip link set "$_nd" name "$NETDEV" 2>/dev/null; then
		$LOG "$cfg: 网卡重命名 $_nd -> $NETDEV"
	else
		$LOG "$cfg: WARN 重命名 $_nd -> $NETDEV 失败，沿用 $_nd"
	fi
fi
ip link set "$NETDEV" up 2>/dev/null

# ---- 交给后台段做数据面激活（不阻塞本脚本返回）-----------------------------
# ★ 这里【不等待】。启动命令写在 /etc/init.d/mifi-modem 里（uci 写完 + netifd
#   reload 之后），因为后台段要用到 network.modemN 的配置。
exit 0
