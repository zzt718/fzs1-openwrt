#!/bin/bash
# ============================================================================
#  fzs1-openwrt —— 一键编译脚本（对外版）
#
#  用途：在 Linux / WSL2（Ubuntu 22.04+）里，从零拉取 OpenWrt 23.05 源码，
#        注入本项目的板级适配与内置面板，编译出可刷固件。
#
#  用法：
#     bash build.sh              # 全流程（clone + 注入 + defconfig + 编译）
#     bash build.sh clone        # 只拉源码
#     bash build.sh inject       # 只注入板级 + 面板
#     bash build.sh config       # 只生成 .config
#     bash build.sh build        # 只编译
#     bash build.sh clean        # 清理产物
#
#  产物：build/openwrt-ramips-mt76x8-mibox_668m2-squashfs-sysupgrade.bin
# ============================================================================
set -e

OPENWRT_VER="v23.05.5"
OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${FZS_WORK:-$HOME/fzs1-openwrt-build}"
SRC="$WORK/openwrt"
OUT="$HERE/build"
JOBS="$(nproc)"

# ---- 内置面板（luci-app-fzs）版本与来源 -------------------------------------
# 面板是独立开源项目 zzt718/fzs1-panel，其 ipk 从该项目 Release 下载。
# 可用环境变量覆盖：
#   FZS_PANEL_IPK=/path/to/luci-app-fzs_x.y.z_all.ipk   （本地文件，开发用）
#   FZS_PANEL_VER=0.2.8                                  （指定版本，默认取下方）
PANEL_VER="${FZS_PANEL_VER:-0.2.8}"
PANEL_REPO="zzt718/fzs1-panel"

log(){ echo -e "\n\033[1;36m>>> $*\033[0m"; }
die(){ echo -e "\n\033[1;31m!! $*\033[0m"; exit 1; }

# 获取面板 ipk（本地优先，否则从 Release 下载）
fetch_panel(){
    if [ -n "${FZS_PANEL_IPK:-}" ] && [ -f "$FZS_PANEL_IPK" ]; then
        echo "$FZS_PANEL_IPK"; return 0
    fi
    local url="https://github.com/${PANEL_REPO}/releases/download/v${PANEL_VER}/luci-app-fzs_${PANEL_VER}_all.ipk"
    local dst="$WORK/luci-app-fzs_${PANEL_VER}_all.ipk"
    mkdir -p "$WORK"
    if [ ! -f "$dst" ]; then
        log "下载面板 ipk：$url"
        wget -q -O "$dst" "$url" || curl -fL -o "$dst" "$url" || die "面板 ipk 下载失败（可设 FZS_PANEL_IPK 指定本地文件）"
    fi
    echo "$dst"
}

# ---------------------------------------------------------------------------
clone(){
    log "拉取 OpenWrt $OPENWRT_VER 源码 → $SRC"
    mkdir -p "$WORK"; cd "$WORK"
    if [ ! -d openwrt/.git ]; then
        git clone --depth 1 -b "$OPENWRT_VER" "$OPENWRT_REPO"
    else
        echo "源码已存在，跳过 clone"
    fi
    cd "$SRC"
    log "更新 feeds"
    ./scripts/feeds update -a
    ./scripts/feeds install -a
}

# ---------------------------------------------------------------------------
inject(){
    log "注入板级适配 + 内置面板"
    cd "$SRC"

    # 1) 设备树
    cp "$HERE/src/mt7628an_mibox_668m2.dts" target/linux/ramips/dts/

    # 2) 设备定义（追加到 mt76x8.mk，幂等）
    if ! grep -q "Device/mibox_668m2" target/linux/ramips/image/mt76x8.mk 2>/dev/null; then
        cat >> target/linux/ramips/image/mt76x8.mk <<'EOF'

define Device/mibox_668m2
  SOC := mt7628an
  DEVICE_VENDOR := MIBOX
  DEVICE_MODEL := 668M2 (FZS S1)
  DEVICE_PACKAGES := kmod-usb2 kmod-usb-ohci kmod-usb-net-rndis \
      kmod-usb-serial-option kmod-i2c-mt7628 i2c-tools \
      kmod-mt76 kmod-mt7603
  SUPPORTED_DEVICES += mibox,668m2
  IMAGE_SIZE := 16128k
endef
TARGET_DEVICES += mibox_668m2
EOF
    fi

    # 3) 板级文件（02_network / 01_leds 等由 board-files 覆盖）
    cp -a "$HERE/src/board-files/." target/linux/ramips/mt76x8/base-files/

    # 4) 内置面板包（luci-app-fzs）
    mkdir -p package/luci-app-fzs
    cp "$HERE/src/luci-app-fzs.Makefile" package/luci-app-fzs/Makefile
    #   面板内容：优先用仓库内 src/luci-app-fzs-files/（若随源码分发）；
    #   否则从面板项目 Release 下载 ipk 解包。
    if [ -d "$HERE/src/luci-app-fzs-files" ]; then
        rm -rf package/luci-app-fzs/files
        mkdir -p package/luci-app-fzs/files
        cp -a "$HERE/src/luci-app-fzs-files/." package/luci-app-fzs/files/
        echo "面板内容：来自 src/luci-app-fzs-files/"
    else
        local ipk; ipk="$(fetch_panel)"
        rm -rf /tmp/fzs_panel && mkdir -p /tmp/fzs_panel
        ( cd /tmp/fzs_panel && tar xzf "$ipk" && mkdir -p data && tar xzf data.tar.gz -C data )
        rm -rf package/luci-app-fzs/files
        mkdir -p package/luci-app-fzs/files
        cp -a /tmp/fzs_panel/data/. package/luci-app-fzs/files/
        echo "面板内容：来自 $(basename "$ipk")（$(find package/luci-app-fzs/files -type f | wc -l) 个文件）"
    fi

    echo "注入完成。src/board-files → target/.../base-files；src/luci-app-fzs.Makefile → package/luci-app-fzs/"
}

# ---------------------------------------------------------------------------
config(){
    log "生成 .config（基于 src/config.seed.v2）"
    cd "$SRC"
    cp "$HERE/src/config.seed.v2" .config
    make defconfig
}

# ---------------------------------------------------------------------------
build(){
    log "编译（首次会下载大量源码，耗时较长）"
    cd "$SRC"
    make -j"$JOBS" download
    make -j"$JOBS"
    mkdir -p "$OUT"
    log "收集产物 → $OUT"
    cp bin/targets/ramips/mt76x8/openwrt-ramips-mt76x8-mibox_668m2-*.bin "$OUT/" 2>/dev/null || true
    cp bin/targets/ramips/mt76x8/sha256sums "$OUT/sha256sums" 2>/dev/null || true
    ls -la "$OUT"
}

# ---------------------------------------------------------------------------
clean(){
    log "清理"
    rm -rf "$OUT"
    [ -d "$SRC" ] && ( cd "$SRC" && make clean ) || true
}

case "${1:-all}" in
    clone)  clone ;;
    inject) inject ;;
    config) config ;;
    build)  build ;;
    clean)  clean ;;
    all)    clone; inject; config; build ;;
    *) echo "用法: $0 {clone|inject|config|build|clean|all}"; exit 1 ;;
esac
