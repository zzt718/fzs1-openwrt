#!/bin/sh
cfg="$1"
[ -n "$cfg" ] || exit 1

apn="cmiot"
dial="*99#"
retry="20"
simfix="1"
[ -f /etc/config/mifi ] && {
	. /lib/functions.sh
	config_load mifi
	config_get apn "$cfg" apn "$apn"
	config_get dial "$cfg" dial "$dial"
	config_get retry "$cfg" retry_delay "$retry"
	config_get simfix "$cfg" simfix "$simfix"
}

# ---- APN 自动兜底 -----------------------------------------------------------
# option apn 'auto' 时，依次尝试 AUTO_APNS 里的候选：成功就记住并固定用它；
# 失败就换下一个（轮转）。option apn 写成显式值（如 'cmnet'）时，这一整段
# 完全跳过，行为与没有本功能时逐字一致 —— 所以显式 APN 不会被这段逻辑影响。
AUTO_APNS="cmiot cmnet 3gnet ctnet"
apn_good="/tmp/.mifi-apn-good-$cfg"
apn_idx="/tmp/.mifi-apn-idx-$cfg"
apn_auto=""
case "$apn" in
auto|AUTO|Auto|'') apn_auto=1 ;;
esac
if [ -n "$apn_auto" ]; then
	if [ -s "$apn_good" ]; then
		apn=$(cat "$apn_good")
	else
		i=$(cat "$apn_idx" 2>/dev/null)
		case "$i" in ''|*[!0-9]*) i=0 ;; esac
		apn=$(echo $AUTO_APNS | cut -d' ' -f$((i + 1)))
		[ -n "$apn" ] || apn=$(echo $AUTO_APNS | cut -d' ' -f1)
	fi
fi

# ---- SIM 自愈 ---------------------------------------------------------------
# 背景（2026-09-18 实测）：模组会把 SIM 状态机锁死在"未插入"——
# AT+CPIN? 返回 +CME ERROR: 10（SIM not inserted），但卡其实好好在里面。
# 触发点是上电/USB 枚举抖动（dmesg 里那个口会多一次 disconnect + 重新枚举）。
# 因为 AT+QSIMDET 是关的（0,0），模组之后**不会主动重读卡**，就一直锁着。
#
# 这个故障特别容易误判：AT 通路是好的，所以 chat 照样能拿到 CONNECT，
# pppd 于是进入 LCP，然后被网络踢掉 —— 日志表现为
#   "Serial connection established" → "Connect: ppp-xxx" → 2 秒后 "Modem hangup"
# 每 retry_delay 秒无限重拨。光看日志只会觉得"固件坏了 / 卡欠费 / 信号差"。
#
# 对策：拨号前在**同一模组的 AT 口**查一次 AT+CPIN?；不是 READY 就做
# AT+CFUN=0 → 等 3s → AT+CFUN=1 强制重读卡，再轮询 CPIN 直到 READY。
# 实测 CFUN 循环后 AT+CPIN: READY / CREG 0,1 / CGATT 1，下一个周期自己就拨通了。
#
# AT 口由 PPP 口的 USB 路径推导（同一条路径，interface :1.3 → :1.4），
# **不写死 ttyUSB 编号** —— 编号每次开机都可能变（见交接文档 §33/§35）。
#
# 节流：同一 cfg 每 SIMFIX_GAP 秒最多自愈一次，避免"故意不插卡"时反复折腾模组。
# 开关：/etc/config/mifi 里 config modem '<cfg>' / option simfix '0' 可整段关闭。
SIMFIX_GAP=300
ATOUT=/tmp/.mifi-at-last

# 在 AT 口发一条命令，原始回显写到 $ATOUT（不污染 stdout —— 那是 pppd 的管道）
at_send() {
	_port="$1"; _cmd="$2"
	[ -c "$_port" ] || return 1
	: > "$ATOUT"
	exec 3<>"$_port" 2>/dev/null || return 1
	cat <&3 > "$ATOUT" 2>/dev/null &
	_cp=$!
	sleep 1
	printf '%s\r' "$_cmd" >&3 2>/dev/null
	sleep 2
	kill $_cp 2>/dev/null
	exec 3<&-
	wait $_cp 2>/dev/null
	return 0
}

# 由 PPP 口推出同一模组的 AT 口：同一条 USB 路径，interface :1.3 → :1.4
at_port_for() {
	_ppp="${1##*/}"
	for _d in /sys/bus/usb-serial/devices/*; do
		[ "${_d##*/}" = "$_ppp" ] || continue
		_b=$(readlink "$_d" 2>/dev/null)
		_b=${_b%/*}
		_b=${_b%:*}
		[ -n "$_b" ] || continue
		for _e in /sys/bus/usb-serial/devices/*; do
			case "$(readlink "$_e" 2>/dev/null)" in
			"$_b":1.4/*) echo "${_e##*/}"; return 0 ;;
			esac
		done
	done
	return 1
}

sim_ensure() {
	[ "$simfix" = "0" ] && return 0

	# 防御：这些变量若被外部弄丢，节流会**静默失效**（实测踩过），
	# 所以在这里再兜一次默认值。
	case "$SIMFIX_GAP" in ''|*[!0-9]*) SIMFIX_GAP=300 ;; esac
	[ -n "$ATOUT" ] || ATOUT=/tmp/.mifi-at-last

	_uci=$(command -v uci 2>/dev/null)
	[ -n "$_uci" ] || _uci=/sbin/uci
	_dev=$($_uci -q get "network.$cfg.device" 2>/dev/null)
	[ -n "$_dev" ] || return 0
	_at=$(at_port_for "$_dev") || return 0
	_port="/dev/$_at"

	at_send "$_port" 'AT+CPIN?' || return 0
	grep -q '+CPIN: READY' "$ATOUT" 2>/dev/null && return 0

	_stamp="/tmp/.mifi-simfix-$cfg"
	_now=$(cut -d. -f1 /proc/uptime 2>/dev/null)
	case "$_now" in ''|*[!0-9]*) _now=0 ;; esac
	_last=$(cat "$_stamp" 2>/dev/null)
	case "$_last" in ''|*[!0-9]*) _last=0 ;; esac
	_el=$((_now - _last))
	[ "$_el" -lt 0 ] && _el=0
	if [ "$_el" -lt "$SIMFIX_GAP" ]; then
		logger -t mifi-dial "SIM not ready on $cfg (recovered ${_el}s ago, throttled)"
		return 0
	fi
	echo "$_now" > "$_stamp"

	logger -t mifi-dial "SIM not ready on $cfg -> CFUN 0/1 recovery (AT port $_at)"
	at_send "$_port" 'AT+CFUN=0'
	sleep 3
	at_send "$_port" 'AT+CFUN=1'
	_i=0
	while [ "$_i" -lt 12 ]; do
		sleep 2
		at_send "$_port" 'AT+CPIN?'
		if grep -q '+CPIN: READY' "$ATOUT" 2>/dev/null; then
			logger -t mifi-dial "SIM recovery OK on $cfg (~$((_i * 2 + 6))s)"
			return 0
		fi
		_i=$((_i + 1))
	done
	logger -t mifi-dial "WARN: SIM recovery failed on $cfg, dialing anyway"
	return 0
}

sim_ensure

# ---- 重试节流 ---------------------------------------------------------------
# 硬件未就绪（例如没插 SIM）时避免 pppd 高频重拨刷屏。
# 间隔由 /etc/config/mifi 的 option retry_delay 控制；设 0 关闭节流（恢复原速）。
STAMP="/tmp/.mifi-last-dial-$cfg"
case "$retry" in ''|*[!0-9]*) retry=20 ;; esac
now=$(cut -d. -f1 /proc/uptime 2>/dev/null)
last=$(cat "$STAMP" 2>/dev/null)
case "$last" in ''|*[!0-9]*) last=0 ;; esac
if [ "$retry" -gt 0 ]; then
	el=$((now - last))
	[ "$el" -lt 0 ] && el=0
	[ "$el" -lt "$retry" ] && sleep $((retry - el))
fi
now=$(cut -d. -f1 /proc/uptime 2>/dev/null)
echo "$now" > "$STAMP"

sed -e "s|@APN@|$apn|g" -e "s|@DIAL@|$dial|g" /etc/chatscripts/mifi-connect > "/tmp/mifi-chat-$cfg"

# 这里刻意不用 exec：需要在 chat 返回后记录 APN 尝试结果。
# 退出码照样传给 pppd（0 = CONNECT 成功），对外行为与 exec 一致。
/usr/sbin/chat -t 45 -s -f "/tmp/mifi-chat-$cfg"
rc=$?

if [ -n "$apn_auto" ]; then
	if [ "$rc" -eq 0 ]; then
		echo "$apn" > "$apn_good"
	else
		n=$(echo $AUTO_APNS | wc -w)
		i=$(cat "$apn_idx" 2>/dev/null)
		case "$i" in ''|*[!0-9]*) i=0 ;; esac
		[ "$n" -gt 0 ] && i=$(((i + 1) % n))
		echo "$i" > "$apn_idx"
	fi
fi

exit $rc
