#!/bin/sh
# ============================================================================
# MIBOX-668M2: RNDIS 数据面【后台激活段】
#             —— 由 /etc/init.d/mifi-modem 在写完 uci 之后用 & 启动，不阻塞开机。
#
# ★ 为什么要拆成两段（2026-09-20，方案 A）：
#   原来「等网卡 + 重命名 + usbnet 检查 + APN 激活 + 配 IP」整段都在
#   /usr/libexec/mifi-rndis.sh 里，由 S18mifi-modem **同步**调用。
#   而 S18 排在 S19*/S20network（WiFi bring-up）之前、且脚本无 USE_PROCD
#   ⇒ 会【同步阻塞】后面所有服务。
#   2026-09-20 实测（RNDIS 版、两张卡都激活失败时）：
#       16:35:43  mifi-modem 解析完成（waited=9s）
#       16:36:43  modem1: WARN 所有 APN 候选都没激活成功   ← 白等 60s
#       16:37:43  modem2: WARN 所有 APN 候选都没激活成功   ← 白等 60s
#       16:37:50  S19mwan3 才开始跑                        ← 被堵了 132 秒
#       16:38:15  radio0 up
#       dmesg:    [185.5] br-lan: port 2(wlan0)            ← WiFi 到内核 185 秒
#   ⇒ 用户感知"开机 3 分钟才有 WiFi"。
#
#   那 60 秒/模组是【可算出来的固定浪费】：卡被拒注册时 4 个 APN 候选
#   （cmiot→cmnet→3gnet→ctnet）每个的 AT 序列固定 14 秒
#   （at_send 里 sleep 1 + wait 2/3）⇒ 4×14 = 56 秒，且必然全失败。
#
# ★ 拆开后的分工：
#   同步段（mifi-rndis.sh）  = 等网卡 + 重命名成稳定名   → 几秒（netifd 要按名字找网卡）
#   后台段（本脚本）         = usbnet 检查 + APN 激活 + 配 IP → 慢，但不挡 WiFi
#   数据面晚通完全没关系 —— 接口会先 up（IP 由 netifd 从 uci 配好），
#   mwan3track 会周期性探测，通了自然转 online。
#
# 用法: mifi-rndis-activate.sh <modem1|modem2>
# ============================================================================

cfg="$1"
case "$cfg" in
modem1) USB=1-1.1 ;;
modem2) USB=1-1.2 ;;
*) echo "usage: $0 <modem1|modem2>"; exit 1 ;;
esac

# 两模块 RNDIS 同网段同 DHCP 地址，必须错开。
# ★ 用厂商原固件里的 .2 / .3：在模组 DHCP 池（通常 .100 起）之外，最稳。
case "$cfg" in
modem1) HOSTIP=192.168.43.2 ;;
modem2) HOSTIP=192.168.43.3 ;;
esac
NETMASK=255.255.255.0
GW=192.168.43.1
NETDEV="rndis-$cfg"          # 稳定名（同步段已重命名好）
ATOUT=/tmp/.mifi-rndis-at-$cfg
LOG="logger -t mifi-rndis-act"

# ---- 读配置 ----------------------------------------------------------------
apn="auto"
[ -f /etc/config/mifi ] && {
	. /lib/functions.sh
	config_load mifi
	config_get apn "$cfg" apn "$apn"
}
AUTO_APNS="cmiot cmnet 3gnet ctnet"
apn_good="/tmp/.mifi-apn-good-$cfg"
apn_idx="/tmp/.mifi-apn-idx-$cfg"

# ---- AT 收发（与 mifi-rndis.sh 保持完全一致）-------------------------------
at_send() {
	_port="$1"; _cmd="$2"; _wait="${3:-2}"
	[ -c "$_port" ] || return 1
	: > "$ATOUT"
	exec 3<>"$_port" 2>/dev/null || return 1
	cat <&3 > "$ATOUT" 2>/dev/null &
	_cp=$!
	sleep 1
	printf '%s\r' "$_cmd" >&3 2>/dev/null
	sleep "$_wait"
	kill $_cp 2>/dev/null
	exec 3<&-
	wait $_cp 2>/dev/null
	return 0
}

# ---- 按 USB 路径找 AT 口（:1.4），不写死 ttyUSB 编号 ------------------------
find_at_port() {
	for _d in /sys/bus/usb-serial/devices/*; do
		[ -e "$_d" ] || continue
		case "$(readlink "$_d" 2>/dev/null)" in
		*"$USB":1.4/*) echo "${_d##*/}"; return 0 ;;
		esac
	done
	return 1
}

# ---- 等 AT 口 --------------------------------------------------------------
_w=0
_at=""
while [ "$_w" -lt 90 ]; do
	_at=$(find_at_port) && [ -n "$_at" ] && break
	sleep 1; _w=$((_w + 1))
done
[ -n "$_at" ] || { $LOG "$cfg: AT port ($USB:1.4) 未出现，放弃"; exit 1; }
APORT="/dev/$_at"

# ---- 等同步段把网卡重命名好（正常早已就绪，这里只是兜底）------------------
_w=0
while [ "$_w" -lt 30 ]; do
	[ -e "/sys/class/net/$NETDEV" ] && break
	sleep 1; _w=$((_w + 1))
done
[ -e "/sys/class/net/$NETDEV" ] || { $LOG "$cfg: 网卡 $NETDEV 未出现，放弃"; exit 1; }

# ---- 确保 usbnet 模式 = RNDIS(3) -------------------------------------------
at_send "$APORT" 'AT+QCFG="usbnet"' 2
if grep -q '+QCFG: "usbnet",3' "$ATOUT" 2>/dev/null; then
	:
else
	$LOG "$cfg: usbnet 不是 3，尝试写入（写入后需模组复位才生效）"
	at_send "$APORT" 'AT+QCFG="usbnet",3' 2
fi

# ---- 确定 APN 候选序列 -----------------------------------------------------
if [ "$apn" = "auto" ] || [ -z "$apn" ]; then
	if [ -s "$apn_good" ]; then
		CAND=$(cat "$apn_good")
	else
		CAND=$(echo $AUTO_APNS | cut -d' ' -f1)
	fi
	# 候选顺序：优先上次成功的，其后按轮转起点排其余
	_i=$(cat "$apn_idx" 2>/dev/null)
	case "$_i" in ''|*[!0-9]*) _i=0 ;; esac
	CAND="$CAND $(echo $AUTO_APNS | cut -d' ' -f$((_i + 1)))"
	CAND="$CAND $AUTO_APNS"
	AUTO=1
else
	CAND="$apn"
	AUTO=0
fi

# ---- 逐个 APN 试激活 -------------------------------------------------------
_ok=""
for _a in $CAND; do
	[ -n "$_a" ] || continue
	# 去重（同一个 APN 不重复试）
	case " $_TRIED " in *" $_a "*) continue ;; esac
	_TRIED="$_TRIED $_a"

	at_send "$APORT" "AT+CGDCONT=1,\"IP\",\"$_a\"" 2
	# 先停再起，确保 PDP 重建（只改 CGDCONT 而不重建，切不过去 —— 见交接文档 §38.5）
	# op=0 停止；不同固件对 op 的取值容忍度不同，报错不影响后续，忽略即可。
	at_send "$APORT" 'AT+QNETDEVCTL=0,1,0' 2
	sleep 1
	at_send "$APORT" 'AT+QNETDEVCTL=2,1,1' 3
	# 判成功：CGCONTRDP 里出现一个合法 IPv4
	# ★ 注意正则不能写成 '"1,...' —— 实际回显是 "+CGCONTRDP: 1,5,"apn",..."，
	#   数字 1 前面没有引号。2026-09-18 踩过：写成 '"1,' 会永远匹配不上，
	#   脚本误判"所有 APN 都失败"并 exit 1（但模组其实已经激活成功）。
	at_send "$APORT" 'AT+CGCONTRDP' 2
	if grep -qE 'CGCONTRDP: 1,[0-9]+,"[^"]+","[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$ATOUT" 2>/dev/null; then
		_ok="$_a"
		break
	fi
done

if [ -z "$_ok" ]; then
	$LOG "$cfg: WARN 所有 APN 候选都没激活成功（试过:$_TRIED）"
	if [ "$AUTO" = 1 ]; then
		_n=$(echo $AUTO_APNS | wc -w)
		[ "$_n" -gt 0 ] && echo $(( (_i + 1) % _n )) > "$apn_idx"
	fi
	exit 1
fi

if [ "$AUTO" = 1 ]; then
	echo "$_ok" > "$apn_good"
fi
$LOG "$cfg: RNDIS 已激活 APN=$_ok 网卡=$NETDEV 主机地址=$HOSTIP"

# ---- 配地址 -----------------------------------------------------------------
# ★ 与拆分前不同：这里【不再 flush】。因为 netifd 可能已经从 uci 配好了地址，
#   flush 会把接口地址抹掉、造成一次短暂中断。只在地址确实缺失时才补。
if ! ip -4 addr show dev "$NETDEV" 2>/dev/null | grep -qF "$HOSTIP"; then
	ip addr add "$HOSTIP/$NETMASK" dev "$NETDEV" 2>/dev/null
	$LOG "$cfg: 补配地址 $HOSTIP/$NETMASK（netifd 尚未配）"
fi
ip link set "$NETDEV" up 2>/dev/null

# 网关可达性（仅用于日志，失败不致命 —— 有些固件网关不响应 ICMP）
if ping -c 1 -W 2 -I "$NETDEV" "$GW" >/dev/null 2>&1; then
	$LOG "$cfg: 网关 $GW 可达"
else
	$LOG "$cfg: 网关 $GW 不响应 ICMP（可能正常，继续）"
fi

exit 0
