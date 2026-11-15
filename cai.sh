#!/usr/bin/env bash
# ============================================================================================================
#  G123: LỆNH CÀI DUY NHẤT cho bot Jeistu (LINE / Zalo / Web) trên Ubuntu 24.04 / 26.04 sạch. Chỉ chủ / IT của công ty dùng.
#
#     curl -fsSLO https://raw.githubusercontent.com/dashlinebot/cai-dat/v1/cai.sh     # tải về (repo công khai, không bí mật)
#     sha256sum cai.sh                                                               # so với mã băm trong sổ tay nội bộ
#     sudo bash cai.sh                                                               # KHÔNG pipe thẳng vào bash
#
#  Tuỳ chọn:  --check            chỉ kiểm máy, không đổi gì
#             --kenh line|zalo|web   (không có thì hỏi một câu)
#             --them <tên>       thêm một bản cài nữa trên máy đã có (vd kênh khác)
#             --khoi-phuc <tệp> --khoa <tệp khoá age>   cài máy mới TỪ BẢN SAO LƯU ngoài máy (.tar.age): đúng bản bot ghi trong bản,
#                                router khôi phục trước khi khởi tạo, rồi bot + OpenViking (docs/RESTORE.md). Bản không có router
#                                (hoặc router mã hoá bằng khoá của máy cũ): thêm --router <bản router .tar.gz.age> --khoa-router <khoa.txt>
#                                Bản cài thứ hai (vd Web) từ bản sao lưu của chính nó: --them <tên> --kenh <kênh> --khoi-phuc … --khoa …
#             --phien-ban X.Y.Z  cài đúng bản này (mặc định: bản mới nhất)
#  Hỏi DUY NHẤT (ẩn chữ, từ bàn phím): token đọc mã (GitHub fine-grained, Contents: Read) + token đọc image (classic,
#  read:packages). Cất /etc/jeistu/*-token (root 0600). Mọi lựa chọn khác (model, lịch, cách cập nhật…) ở trang thiết lập.
#  Chạy lại = làm tiếp (mỗi chặng tự biết đã xong chưa; trạng thái /var/lib/jeistu/trang-thai.json). Nhật ký /var/log/jeistu-cai.log.
#  Cuối cùng chỉ in MỘT đường link thiết lập (dùng một lần, 24 giờ).
# ============================================================================================================
# Cả tệp bọc trong main(), gọi ở dòng cuối: tải dở giữa chừng thì bash không chạy nửa script.
main() {
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive
local HERE; HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Lệnh dưới user dịch vụ giữ thư mục hiện tại (thường là /root của người cài): về "/" để không đọc nhầm tệp ở đó.
cd /

# ---------- hằng ----------
ORG="${JEISTU_ORG:-dashlinebot}"
KHO_MAC_DINH="ghcr.io/$ORG"
REPO_BOT="${JEISTU_REPO_BOT:-https://github.com/$ORG/jeistu-bot.git}"
REPO_ADDON="${JEISTU_REPO_ADDON:-https://github.com/$ORG/jeistu-bot-pro.git}"
SVC_USER="${JEISTU_SVC_USER:-jeistu}"
ETC=/etc/jeistu
STATE=/var/lib/jeistu
LIBDIR=/usr/local/lib/jeistu
LOGF=/var/log/jeistu-cai.log
TT="$STATE/trang-thai.json"
CHANG="kiem nen ky ma tro-ly router bot tuong-lua xong"
KP_DIR="$STATE/khoi-phuc-cli"

# Mã băm ghim (dung-cai-dat.sh thay hai chữ giữ chỗ khi dựng repo cai-dat). Còn chữ giữ chỗ = bản chép từ repo mã (máy thử): chỉ
# chạy khi JEISTU_CAI_THU=1.
GHIM_KY_SH="aa05bb00fb0dcd8774d2c04648ab827f427470fd348cf6fbd213690252713c97"
GHIM_COSIGN_PUB="d400003ead61da0f8701221df3cd76c22b3448e42aa3177f235559e0896ec019"
ghim() {   # ghim <tệp> <sha256 ghim> <tên>
  local got; got="$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)"
  case "$2" in @*@) [ "${JEISTU_CAI_THU:-}" = 1 ] || dung "bản cai.sh này chưa ghim mã băm (lấy cai.sh từ repo cai-dat)"; return 0 ;; esac
  [ -n "$got" ] && [ "$got" = "$2" ] || dung "$3 SAI mã băm so với bản ghim trong cai.sh — không chạy (tải lại từ repo cai-dat, so sổ tay)"
}

# ---------- tham số ----------
local CHECK=0 KENH="" THEM="" KHOI_PHUC="" PB="" KP_KHOA="" KP_ROUTER="" KP_KHOA_ROUTER="" KP_BK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --kenh) KENH="${2:?--kenh line|zalo|web}"; shift 2 ;;
    --them) THEM="${2:?--them <tên>}"; shift 2 ;;
    --khoi-phuc) KHOI_PHUC="${2:?--khoi-phuc <tệp>}"; shift 2 ;;
    --khoa) KP_KHOA="${2:?--khoa <tệp khoá age>}"; shift 2 ;;
    --router) KP_ROUTER="${2:?}"; shift 2 ;;
    --khoa-router) KP_KHOA_ROUTER="${2:?}"; shift 2 ;;
    --phien-ban) PB="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,/^# =\{20,\}$/p' "$0" | sed 's/^# \{0,1\}//'; return 0 ;;
    *) echo "tham số lạ: $1 (xem --help)" >&2; return 2 ;;
  esac
done

# ---------- in / log ----------
xanh() { printf '\033[32m[OK]\033[0m %s\n' "$*"; }
vang() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
buoc() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
dung() { printf '\n\033[31m[DỪNG]\033[0m %s\n' "$*" >&2; printf '%s [DỪNG] %s\n' "$(date '+%F %T')" "$*" >> "$LOGF" 2>/dev/null; exit 1; }

[ "$(id -u)" = 0 ] || dung "chạy bằng sudo: sudo bash cai.sh"
install -d -m 750 "$STATE"; install -d -m 755 "$ETC"; touch "$LOGF"; chmod 600 "$LOGF"
exec > >(tee -a "$LOGF") 2>&1
printf '\n===== %s cai.sh %s =====\n' "$(date '+%F %T')" "$*"

da_xong() { [ -s "$TT" ] && jq -e --arg c "$1" '.xong | index($c) != null' "$TT" >/dev/null 2>&1; }
danh_dau() {
  local tmp; tmp="$(mktemp "$TT.XXXXXX")"
  if [ -s "$TT" ]; then jq --arg c "$1" '.xong = ((.xong // []) + [$c] | unique) | .luc = (now | todate)' "$TT" > "$tmp"
  else jq -n --arg c "$1" '{xong: [$c], luc: (now | todate)}' > "$tmp"; fi
  mv -f "$tmp" "$TT"
}
tien_do() { local n=0 c; for c in $CHANG; do da_xong "$c" && n=$((n + 1)); done; printf '%s/%s' "$n" "$(wc -w <<< "$CHANG" | tr -d ' ')"; }

# ============================================================================================================
# Chặng 1: kiểm máy (chỉ đọc). Lỗi nào cũng một câu tiếng Việt + cách sửa.
# ============================================================================================================
kiem_may() {
  buoc "Kiểm máy"
  local loi=0 id ver gb free p
  . /etc/os-release 2>/dev/null || true
  id="${ID:-?}"; ver="${VERSION_ID:-?}"
  case "$id:$ver" in ubuntu:24.04|ubuntu:26.04) xanh "Ubuntu $ver" ;; *) vang "máy là ${PRETTY_NAME:-?}: bộ cài chỉ thử trên Ubuntu 24.04 / 26.04"; loi=1 ;; esac
  case "$(uname -m)" in x86_64) xanh "CPU x86_64" ;; *) vang "CPU $(uname -m): image chỉ dựng cho x86_64 (amd64)"; loi=1 ;; esac
  [ "$(ps -p 1 -o comm= 2>/dev/null)" = systemd ] && xanh "systemd đang chạy" || { vang "không có systemd (máy ảo / container đặc biệt?)"; loi=1; }
  gb="$(awk '/^MemTotal:/ {printf "%d", $2 / 1048576 + 0.5}' /proc/meminfo)"
  if [ "$gb" -lt 4 ]; then vang "RAM ${gb} GB: cần ít nhất 4 GB (8 GB nếu chạy từ 2 tài khoản trở lên)"; loi=1; else xanh "RAM ${gb} GB"; fi
  free="$(df -BG --output=avail / | tail -1 | tr -dc 0-9)"
  # Máy mới: 30 GB (router, model nhúng, image ~10 GB + dữ liệu). Thêm bản cài trên máy đã có bot: image dùng chung, 10 GB đủ.
  # BỔ SUNG 2 (thử ngắt giữa chừng): chạy lại sau khi đã qua chặng nền — phần đã cài chiếm sẵn đĩa, chỉ cần 10 GB cho phần còn lại.
  local can=30; { [ -n "$THEM" ] || da_xong nen; } && can=10
  # Chỉ máy thử (bản cai.sh chưa ghim, JEISTU_CAI_THU=1): đĩa chung của máy thử không đủ 30 GB trống.
  [ "${JEISTU_CAI_THU:-}" = 1 ] && [[ "${JEISTU_CAI_DIA_GB:-}" =~ ^[0-9]+$ ]] && can="$JEISTU_CAI_DIA_GB"
  if [ "$free" -lt "$can" ]; then vang "đĩa / còn ${free} GB: cần ít nhất ${can} GB trống"; loi=1; else xanh "đĩa trống ${free} GB"; fi
  if command -v snap >/dev/null && snap list docker >/dev/null 2>&1; then vang "Docker đang cài bằng snap: gỡ trước (sudo snap remove docker) rồi chạy lại"; loi=1; fi
  p=20128
  if ss -ltnH "sport = :$p" 2>/dev/null | grep . >/dev/null && ! docker inspect jeistu-router >/dev/null 2>&1; then vang "cổng $p đang có chương trình khác nghe (router cần cổng này)"; loi=1; fi
  local h
  for h in ghcr.io api.github.com github.com download.docker.com; do
    if curl -fsS -o /dev/null --max-time 10 "https://$h/" 2>/dev/null || [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$h/" 2>/dev/null)" != 000 ]; then xanh "ra được $h:443"
    else vang "không ra được $h:443 — mạng công ty phải cho phép HTTPS tới $h"; loi=1; fi
  done
  for h in line.me chat.zalo.me; do
    [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$h/" 2>/dev/null)" != 000 ] && xanh "ra được $h:443" || vang "không ra được $h:443 (cần nếu dùng kênh $( [ $h = line.me ] && echo LINE || echo Zalo))"
  done
  local dev; dev="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  if [ -n "$dev" ] && ip -4 -o addr show dev "$dev" 2>/dev/null | grep ' dynamic ' >/dev/null; then vang "$dev lấy IP bằng DHCP: khởi động lại có thể đổi IP — nên đặt IP tĩnh"; fi
  case "$(timedatectl show -p Timezone --value 2>/dev/null)" in Etc/UTC|UTC) vang "múi giờ UTC: bộ cài sẽ đặt Asia/Ho_Chi_Minh" ;; esac
  [ "$loi" = 0 ] || { [ "$CHECK" = 1 ] && { vang "máy CHƯA đạt — sửa các dòng [!] ở trên"; exit 1; }; dung "máy chưa đạt yêu cầu (các dòng [!] ở trên)"; }
  xanh "máy đạt yêu cầu"
}

# ============================================================================================================
# Hỏi token (DUY NHẤT): ẩn chữ, đọc từ /dev/tty, cất root 0600. Tự động hoá: JEISTU_TOKEN_MA_FILE / JEISTU_TOKEN_ANH_FILE.
# ============================================================================================================
hoi_token() {
  local f="$1" cau="$2" src="$3" v=""
  [ -s "$f" ] && return 0
  if [ -n "$src" ]; then [ -r "$src" ] || dung "không đọc được $src"; install -m 600 "$src" "$f"; return 0; fi
  [ -r /dev/tty ] || dung "cần bàn phím để dán token (hoặc đặt JEISTU_TOKEN_MA_FILE / JEISTU_TOKEN_ANH_FILE)"
  read -r -s -p "$cau: " v < /dev/tty; echo
  v="$(printf '%s' "$v" | tr -d ' \r\n')"
  [ -n "$v" ] || dung "token trống"
  umask 077; printf '%s' "$v" > "$f"; chmod 600 "$f"; v=""
}

# ============================================================================================================
# Chặng 2: nền máy — gói, Docker (kho apt chính thức của Docker), user dịch vụ không sudo, múi giờ.
# ============================================================================================================
# BỔ SUNG 2 (thử ngắt giữa chừng): bị giết lúc dpkg đang cài thì gói nằm dở ("in a mess" / "unpacked but not configured") và apt từ
# chối chạy tiếp. Chữa trước mỗi chặng dùng apt: cấu hình nốt, cài lại gói hỏng (gói tải lại từ kho, không đoán).
chua_apt() {
  [ -n "$(dpkg --audit 2>/dev/null)" ] || return 0
  vang "lần trước bị ngắt giữa lúc cài gói — đang chữa (dpkg --configure -a, cài lại gói hỏng)"
  dpkg --configure -a >/dev/null 2>&1 || true
  local hong; hong="$(dpkg --audit 2>/dev/null | sed -n 's/^ \([a-z0-9][a-z0-9.+:-]*\) .*/\1/p' | sort -u | tr '\n' ' ')"
  # shellcheck disable=SC2086
  [ -z "$hong" ] || apt-get install -y -qq --reinstall $hong >/dev/null 2>&1 || true
  apt-get install -f -y -qq >/dev/null 2>&1 || true
  [ -z "$(dpkg --audit 2>/dev/null)" ] || dung "gói hệ thống vẫn hỏng sau khi chữa: sudo dpkg --configure -a && sudo apt-get install -f, rồi chạy lại lệnh cài"
  xanh "đã chữa gói cài dở"
}

nen_may() {
  buoc "Nền máy: gói hệ thống, Docker, tài khoản dịch vụ"
  chua_apt
  apt-get update -qq
  apt-get install -y -qq git curl ca-certificates gnupg jq openssl ufw acl sqlite3 unzip >/dev/null
  if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
    systemctl enable --now docker >/dev/null
  fi
  docker info >/dev/null 2>&1 || dung "Docker cài xong nhưng chưa chạy (systemctl status docker)"
  xanh "Docker $(docker version --format '{{.Server.Version}}')"
  if ! id "$SVC_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /usr/sbin/nologin --comment "Jeistu bot" "$SVC_USER"
    xanh "tạo tài khoản dịch vụ $SVC_USER (không sudo, không đăng nhập được)"
  fi
  # Hôm nay dashboard còn dùng Docker trực tiếp (trí nhớ, sao lưu) → nhóm docker; GĐ4 thay bằng trợ lý máy.
  id -nG "$SVC_USER" | tr ' ' '\n' | grep -x docker >/dev/null || usermod -aG docker "$SVC_USER"
  # Nhóm của socket trợ lý máy: thêm TRƯỚC linger — phiên systemd của user bot khởi động lúc bật linger và chỉ mang các nhóm có
  # lúc đó (thêm sau thì dashboard không mở được socket cho tới khi user@ khởi động lại).
  getent group jeistu-tro-ly >/dev/null || groupadd --system jeistu-tro-ly
  id -nG "$SVC_USER" | tr ' ' '\n' | grep -x jeistu-tro-ly >/dev/null || usermod -aG jeistu-tro-ly "$SVC_USER"
  loginctl enable-linger "$SVC_USER"
  case "$(timedatectl show -p Timezone --value 2>/dev/null)" in Etc/UTC|UTC) timedatectl set-timezone Asia/Ho_Chi_Minh 2>/dev/null && xanh "múi giờ Asia/Ho_Chi_Minh" ;; esac
}

# ============================================================================================================
# Chặng 3: khoá ký + kho image + danh sách phát hành (kiểm chữ ký).
# ============================================================================================================
ky_va_danh_sach() {
  buoc "Kiểm chữ ký bản phát hành"
  # Gốc tin cậy: mã băm của lib/ky.sh (root nạp) và cosign.pub GHIM TRONG chính tệp này (scripts/mac/dung-cai-dat.sh điền khi dựng
  # repo cai-dat; người cài so mã băm cai.sh với sổ tay nội bộ) — kẻ chiếm repo công khai không thay riêng hai tệp kia được.
  ghim "$HERE/lib/ky.sh" "$GHIM_KY_SH" "lib/ky.sh"
  if [ ! -s "$ETC/cosign.pub" ]; then
    ghim "$HERE/cosign.pub" "$GHIM_COSIGN_PUB" "cosign.pub"
    install -m 644 "$HERE/cosign.pub" "$ETC/cosign.pub" 2>/dev/null || dung "thiếu khoá công khai cosign.pub cạnh cai.sh"
  fi
  [ -s "$ETC/kho-image" ] || printf '%s\n' "${JEISTU_KHO_IMAGE:-$KHO_MAC_DINH}" > "$ETC/kho-image"
  # shellcheck source=lib/ky.sh
  . "$HERE/lib/ky.sh"
  ky_dang_nhap "$ETC/ghcr-token" || dung "token đọc image không dùng được"
  install -d -m 750 "$STATE/danh-sach"
  local ref cid d="$STATE/danh-sach"
  ref="$(ky_kho)/jeistu-phat-hanh:${PB:-moi-nhat}"
  DOCKER_CONFIG="$KY_DOCKER_CONFIG" docker pull -q "$ref" >/dev/null 2>&1 || dung "không tải được danh sách phát hành ${PB:-mới nhất} ($ref)"
  cid="$(docker create "$ref" /khong-chay)"
  docker cp "$cid:/release.json" "$d/release.json" >/dev/null; docker cp "$cid:/release.json.sigstore.json" "$d/release.json.sigstore.json" >/dev/null
  docker rm -f "$cid" >/dev/null
  ky_kiem_tep "$d/release.json" "$d/release.json.sigstore.json" || dung "danh sách phát hành SAI CHỮ KÝ — dừng"
  REL="$d/release.json"
  # Chạy lại trên máy đã cài: KHÔNG lùi về danh sách cũ hơn bản đang chạy (chống hạ cấp như cap-nhat.sh; về bản trước = Quay lại).
  if [ -s "$STATE/dang-chay.json" ]; then
    local cu moi; cu="$(jq -r .version "$STATE/dang-chay.json" 2>/dev/null)" moi="$(jq -r .version "$REL")"
    [[ "$cu" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || dung "không đọc được bản đang chạy ($STATE/dang-chay.json) — dừng để không mất chống hạ cấp"
    [ "$(printf '%s\n%s\n' "$cu" "$moi" | sort -V | head -n 1)" = "$cu" ] || dung "bản $moi CŨ HƠN bản đang chạy $cu — không cài lùi (về bản trước: Bảo trì › Quay về bản trước)"
  fi
  if [ -n "$KHOI_PHUC" ]; then
    local bk="$KP_BK" moi2; moi2="$(jq -r .version "$REL")"
    [[ "$bk" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$(printf '%s\n%s\n' "$bk" "$moi2" | sort -V | tail -n 1)" != "$moi2" ] \
      && dung "bản sao lưu từ bot $bk MỚI HƠN bản cài $moi2 — dữ liệu không chuyển xuống được (bỏ --phien-ban hoặc chọn ≥ $bk)"
  fi
  xanh "bản phát hành $(jq -r .version "$REL") (router $(jq -r .router.version "$REL")) — chữ ký đúng"
}

# ============================================================================================================
# BỔ SUNG 2 — khôi phục: mở + kiểm bản sao lưu (máy chưa có node: chỉ age + jq + tar), chọn bản bot ghi trong bản.
# ============================================================================================================
mo_ban_sao_luu() {
  buoc "Mở bản sao lưu"
  command -v age >/dev/null || apt-get install -y -qq age >/dev/null || dung "không cài được age (apt)"
  # Giải + mở ngay (cần biết bản bot TRƯỚC khi chọn danh sách phát hành); kiểm mã băm từng phần + router ở khoi-phuc.sh mo sau khi
  # có bản chép root của mã (cai-dat chỉ mang cai.sh + lib/ky.sh + cosign.pub).
  if [ ! -s "$KP_DIR/OFFSITE.json" ]; then
    rm -rf "$KP_DIR"; install -d -m 700 "$KP_DIR"
    age -d -i "$KP_KHOA" -o "$KP_DIR/.goi.tar" "$KHOI_PHUC" || { rm -rf "$KP_DIR"; dung "không giải được bản sao lưu: sai tệp khoá hoặc tệp hỏng"; }
    # Chỉ tệp thường + thư mục (không symlink / liên kết) — như khoi-phuc.sh giai_an_toan.
    [[ "$(tar -tvf "$KP_DIR/.goi.tar" | cut -c1 | sort -u | tr -d '\n')" =~ ^[-d]*$ ]] || { rm -rf "$KP_DIR"; dung "bản sao lưu có symlink / liên kết — từ chối"; }
    tar -xf "$KP_DIR/.goi.tar" -C "$KP_DIR" --no-same-owner --no-same-permissions || { rm -rf "$KP_DIR"; dung "bản sao lưu hỏng"; }
    rm -f "$KP_DIR/.goi.tar"
    [ -s "$KP_DIR/OFFSITE.json" ] || { rm -rf "$KP_DIR"; dung "tệp không phải bản sao lưu ngoài máy (thiếu OFFSITE.json)"; }
  fi
  local b; b="$(jq -r '[.parts[].path | select(test("^bot/[A-Za-z0-9._-]+$"))][0] // ""' "$KP_DIR/OFFSITE.json")"
  [ -n "$b" ] && [ -f "$KP_DIR/$b" ] || dung "bản sao lưu không có phần bot"
  KP_BK="$( { tar -xzOf "$KP_DIR/$b" ./MANIFEST.json 2>/dev/null || tar -xzOf "$KP_DIR/$b" MANIFEST.json; } | jq -r '.bot // ""')"
  xanh "bản sao lưu tạo $(jq -r '.createdAt // "?"' "$KP_DIR/OFFSITE.json") (bot ${KP_BK:-?})"
  # Bản bot: đúng bản ghi trong bản sao lưu nếu có danh sách ký cho bản đó (≥ 3.8.0); cũ hơn → bản mới nhất (dữ liệu chuyển lên).
  # --them: máy đã chạy một bản (router, bản chép root dùng chung) — không chọn bản theo bản sao lưu (chống hạ cấp vẫn kiểm bên dưới).
  if [ -z "$THEM" ] && [ -z "$PB" ] && [[ "$KP_BK" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$(printf '%s\n3.8.0\n' "$KP_BK" | sort -V | head -n 1)" = 3.8.0 ]; then
    PB="$KP_BK"; xanh "cài đúng bản bot của bản sao lưu: $PB (muốn bản mới hơn: --phien-ban X.Y.Z)"
  fi
}
kiem_ban_sao_luu() {   # sau khi có bản chép root: mã băm từng phần (OFFSITE.json) + giải phần router
  [ -s "$KP_DIR/tom-tat.json" ] && return 0
  local a=(mo --da-giai --ra "$KP_DIR")
  [ -z "$KP_ROUTER" ] || a+=(--router "$KP_ROUTER"); [ -z "$KP_KHOA_ROUTER" ] || a+=(--khoa-router "$KP_KHOA_ROUTER")
  bash "$LIBDIR/khoi-phuc.sh" "${a[@]}" || dung "bản sao lưu không qua được bước kiểm (xem /var/log/jeistu-khoi-phuc.log)"
  xanh "mã băm từng phần khớp OFFSITE.json"
  if [ -n "$THEM" ]; then xanh "bản cài thêm: router chung GIỮ NGUYÊN, bản này nhận khoá router mới"; return 0; fi
  [ "$(jq -r .router "$KP_DIR/tom-tat.json")" = true ] && xanh "có dữ liệu router (khôi phục TRƯỚC khi khởi tạo)" \
    || vang "bản KHÔNG có router (hoặc thiếu --khoa-router): router cài mới tinh, thêm lại nhà cung cấp trên trang router"
}

# ============================================================================================================
# Chặng 4: mã — bản root (cho trợ lý máy / bộ cập nhật) + bản của user dịch vụ (bot chạy), đúng commit trong danh sách.
# ============================================================================================================
clone_dung() {   # clone_dung <repo> <tag> <commit> <đích> <tệp token> [user]
  local repo="$1" tag="$2" commit="$3" dest="$4" tok="$5" u="${6:-}" ask head
  ask="$(mktemp)"; printf '#!/bin/sh\ncase "$1" in Username*) echo x-access-token ;; *) cat %q ;; esac\n' "$tok" > "$ask"; chmod 755 "$ask"
  if [ -n "$u" ]; then chmod 644 "$ask"; chmod 755 "$ask"; fi
  # Đã có thư mục mà khác commit của danh sách (danh sách mới hơn giữa hai lần chạy): bản root thì lấy lại; bản của user chỉ lấy
  # lại khi bot CHƯA cài xong (dời bản cũ sang .cu-<giờ>, không xoá) — máy đang chạy thì cập nhật bằng cap-nhat.sh.
  if [ -d "$dest/.git" ]; then
    if [ -n "$u" ]; then head="$(sudo -H -u "$u" git -C "$dest" rev-parse HEAD 2>/dev/null || true)"; else head="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"; fi
    if [ "$head" != "$commit" ]; then
      if [ -z "$u" ]; then rm -rf "$dest"
      elif ! da_xong bot; then mv "$dest" "$dest.cu-$(date +%Y%m%d%H%M%S)"
      fi
    fi
  fi
  if [ ! -d "$dest/.git" ]; then
    if [ -n "$u" ]; then sudo -H -u "$u" env GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 git -c advice.detachedHead=false clone -q --branch "$tag" "$repo" "$dest"
    else env GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 git -c advice.detachedHead=false clone -q --branch "$tag" "$repo" "$dest"; fi || { rm -f "$ask"; return 1; }
  fi
  rm -f "$ask"
  if [ -n "$u" ]; then head="$(sudo -H -u "$u" git -C "$dest" rev-parse HEAD)"; else head="$(git -C "$dest" rev-parse HEAD)"; fi
  [ "$head" = "$commit" ] || { vang "$dest ở $head, danh sách ghi $commit"; return 1; }
}

lay_ma() {
  buoc "Lấy mã bot đúng bản phát hành"
  local tag commit v uh
  tag="$(jq -r .bot.tag "$REL")"; commit="$(jq -r .bot.commit "$REL")"; v="$(jq -r .version "$REL")"
  ROOT_MA="$LIBDIR/ma-$v"
  install -d -m 755 "$LIBDIR"
  printf '%s\n' "$REPO_BOT" > "$ETC/repo-bot"; chmod 644 "$ETC/repo-bot"
  clone_dung "$REPO_BOT" "$tag" "$commit" "$ROOT_MA" "$ETC/github-token" || dung "không lấy được mã bot $tag (token đọc mã sai / hết hạn / thiếu quyền repo)"
  chown -R root:root "$ROOT_MA"; chmod -R go-w "$ROOT_MA"
  uh="$(getent passwd "$SVC_USER" | cut -d: -f6)"
  BOT_DIR="$uh/jeistu-bot${THEM:+-$THEM}"
  # Token đọc mã cho nút Cập nhật bot (git-auth.js đọc qua GIT_ASKPASS từ tệp 600; không vào dòng lệnh / .git/config).
  install -d -m 700 -o "$SVC_USER" -g "$SVC_USER" "$uh/.config" "$uh/.config/jeistu"
  install -m 600 -o "$SVC_USER" -g "$SVC_USER" "$ETC/github-token" "$uh/.config/jeistu/github-token"
  clone_dung "$REPO_BOT" "$tag" "$commit" "$BOT_DIR" "$uh/.config/jeistu/github-token" "$SVC_USER" || dung "không lấy được mã bot cho $SVC_USER"
  ADDON_DIR="" ROOT_ADDON=""
  if [ "$(jq -r '.addon != null' "$REL")" = true ] && [ "$REPO_ADDON" != khong ]; then
    ADDON_DIR="$uh/jeistu-bot-pro${THEM:+-$THEM}"
    if clone_dung "$REPO_ADDON" "$(jq -r .addon.tag "$REL")" "$(jq -r .addon.commit "$REL")" "$ADDON_DIR" "$uh/.config/jeistu/github-token" "$SVC_USER"; then
      # Bản root của add-on: phần chạy bằng root (addon-system.sh, studio-system.sh) lấy từ đây, KHÔNG từ thư mục của user bot.
      ROOT_ADDON="$LIBDIR/addon-$v"
      clone_dung "$REPO_ADDON" "$(jq -r .addon.tag "$REL")" "$(jq -r .addon.commit "$REL")" "$ROOT_ADDON" "$ETC/github-token" \
        && chown -R root:root "$ROOT_ADDON" && chmod -R go-w "$ROOT_ADDON" || ROOT_ADDON=""
      xanh "add-on $(jq -r .addon.tag "$REL")"
    else vang "không lấy được add-on (token không có quyền repo add-on?) — cài lõi trước, thêm add-on sau"; ADDON_DIR=""; fi
  fi
  xanh "mã bot $tag ($commit) — khớp danh sách"
}

# ============================================================================================================
# Chặng 6: router từ image có ký; khoá router cho bot giao thẳng vào tệp của user dịch vụ.
# ============================================================================================================
router() {
  buoc "JeistuRouter (image dựng sẵn, có ký)"
  printf 'THU_MUC=/opt/jeistu/router\n' > "$ETC/router.env"
  if [ -n "$THEM" ]; then
    # Tên khoá RIÊNG cho từng bản cài thêm (BỔ SUNG 2, thử máy: bản Web thứ hai cùng kênh → "hermes-web" đã có → cap-khoa hỏng).
    # Chạy lại: khoá đã cấp mà tệp giao đã được install.sh nạp + xoá thì bỏ qua (khoá đã nằm trong config.yaml của bản cài).
    local k uh; uh="$(getent passwd "$SVC_USER" | cut -d: -f6)"
    for k in "hermes-$KENH-$THEM" "openviking-$KENH-$THEM"; do
      [ -s "$uh/.config/jeistu/khoa-router/$k" ] || da_xong "khoa-$k" && continue
      bash "$LIBDIR/router-cai.sh" cap-khoa --ten "$k" --nguoi-dung "$SVC_USER" || { [ "${k%%-*}" = openviking ] && continue; dung "router không cấp được khoá $k cho bản cài thêm"; }
      danh_dau "khoa-$k"
    done
  else
    local kp=(); [ -n "$KHOI_PHUC" ] && [ -d "$KP_DIR/router-giai" ] && kp=(--khoi-phuc-tu "$KP_DIR/router-giai")
    bash "$LIBDIR/router-cai.sh" cai --anh "$(jq -r .router.image "$REL")" --nguoi-dung "$SVC_USER" --khoa "hermes-$KENH,openviking-$KENH" ${kp[@]+"${kp[@]}"} \
      || dung "cài router không được"
  fi
}

# ============================================================================================================
# Chặng 7: bot — install.sh của bản ROOT, cài vào thư mục mã của user dịch vụ, câu trả lời sinh tự động (không nano).
# ============================================================================================================
cai_bot() {
  buoc "Bot Jeistu kênh $KENH"
  local conf ip uh
  uh="$(getent passwd "$SVC_USER" | cut -d: -f6)"
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1)"
  conf="$ETC/install-${THEM:-chinh}.conf"
  umask 077
  {
    echo "INSTALL_USER=$SVC_USER"
    echo "BOT_DIR=$BOT_DIR"
    echo "DASHBOARD_IP=${ip:-127.0.0.1}"
    echo "ENABLE_UFW=0"
    echo "ENABLE_OPENVIKING=1"
    echo "UPDATE_TOKEN_FILE=$uh/.config/jeistu/github-token"
    # Add-on qua HTTPS + token đọc mã (scripts/addon-lib.js: dạng owner/tên bị coi là SSH và đòi deploy key).
    [ -z "${ADDON_DIR:-}" ] || { echo "ADDON_REPO=$REPO_ADDON"; echo "ADDON_TOKEN_FILE=$uh/.config/jeistu/github-token"; }
    echo "ROUTER_URL=http://127.0.0.1:20128/v1"
    # Bản cài thêm: tệp khoá router tên riêng (install.sh mặc định tìm hermes-<kênh> / openviking-<kênh>).
    if [ -n "$THEM" ]; then
      [ ! -s "$uh/.config/jeistu/khoa-router/hermes-$KENH-$THEM" ] || echo "ROUTER_KEY_FILE=$uh/.config/jeistu/khoa-router/hermes-$KENH-$THEM"
      [ ! -s "$uh/.config/jeistu/khoa-router/openviking-$KENH-$THEM" ] || echo "OV_VLM_API_KEY_FILE=$uh/.config/jeistu/khoa-router/openviking-$KENH-$THEM"
    fi
    echo "TZ=Asia/Ho_Chi_Minh"
  } > "$conf"
  # umask 077 chỉ cho tệp câu trả lời; bộ cài chạy với umask thường (khoá apt, thư mục hệ thống phải đọc được).
  umask 022
  chua_apt
  bash "$ROOT_MA/deploy/ubuntu/install.sh" --yes --kenh "$KENH" --config "$conf" --skip ufw || dung "bộ cài bot báo lỗi (xem $LOGF)"
  # Phần cần root của add-on trong cùng lượt sudo (bubblewrap / AppArmor / Chromium / LibreOffice).
  if [ -n "${ROOT_ADDON:-}" ]; then
    # Bản root của add-on là nguồn gộp (không có kenh.env cạnh script): --kenh. addon-system.sh chạy bằng root chỉ làm phần hệ thống
    # (bubblewrap, AppArmor) rồi dừng; phần còn lại (Chromium vào HOME, ghi .env của Hermes) chạy DƯỚI user bot từ bản của user.
    [ ! -f "$ROOT_ADDON/deploy/ubuntu/addon-system.sh" ] || bash "$ROOT_ADDON/deploy/ubuntu/addon-system.sh" --kenh "$KENH" || vang "addon-system.sh (phần hệ thống) báo lỗi"
    [ ! -f "$ROOT_ADDON/deploy/ubuntu/studio-system.sh" ] || bash "$ROOT_ADDON/deploy/ubuntu/studio-system.sh" || vang "studio-system.sh báo lỗi"
    if [ -f "$ADDON_DIR/deploy/ubuntu/addon-system.sh" ]; then
      sudo -H -u "$SVC_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$SVC_USER")" PATH="$uh/.local/bin:/usr/local/bin:/usr/bin:/bin" \
        bash -c 'cd "$1" && bash deploy/ubuntu/addon-system.sh --kenh "$2"' _ "$ADDON_DIR" "$KENH" || vang "addon-system.sh (phần của user bot) báo lỗi"
    fi
  fi
  # Sổ bản cài cho trợ lý máy / bộ cập nhật.
  local ten="${THEM:-chinh}" pre home_k
  pre="$(sed -n "s/^KENH_ENV_PREFIX=['\"]\{0,1\}\([A-Z_]*\)['\"]\{0,1\}$/\1/p" "$ROOT_MA/kenh/$KENH/kenh.env" | head -1)"
  home_k="$(sed -n "s/^KENH_HOME_DIR=['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/\1/p" "$ROOT_MA/kenh/$KENH/kenh.env" | head -1)"
  install -d -m 755 "$ETC/ban-cai.d"
  {
    echo "USER=$SVC_USER"; echo "BOT_DIR=$BOT_DIR"; echo "KENH=$KENH"; echo "ENV_PREFIX=$pre"
    echo "SVC_ENV=$uh/$home_k/services/compose.env"; echo "COMPOSE_FILE=$BOT_DIR/kenh/$KENH/docker-compose.yml"
    # Cổng ra ngoài của bản cài (đọc MỘT lần ngay sau khi bộ cài của root vừa ghi .env), chỉ nhận số.
    sed -n "s/^${pre}\(DASHBOARD_PORT\|ROUTER_FORWARD_PORT\)=\([0-9]\{4,5\}\)\$/\1=\2/p" "$BOT_DIR/.env" | sort -u
    # Cổng chuyển tiếp router: .env không ghi thì là mặc định của kênh (kenh.env của bản root).
    grep -q "^${pre}ROUTER_FORWARD_PORT=" "$BOT_DIR/.env" \
      || sed -n "s/^KENH_PORT_ROUTER_FORWARD=['\"]\{0,1\}\([0-9]\{4,5\}\)['\"]\{0,1\}$/ROUTER_FORWARD_PORT=\1/p" "$ROOT_MA/kenh/$KENH/kenh.env"
  } > "$ETC/ban-cai.d/$ten.env"
  chmod 644 "$ETC/ban-cai.d/$ten.env"
}

# ============================================================================================================
# Chặng 8: tường lửa — tự nhận cổng SSH (sshd -T + phiên đang nối), mở trước rồi mới bật; hẹn giờ tự tắt 10 phút, trang
# thiết lập mở được = mạng còn vào được → hẹn giờ huỷ (không cần cửa sổ SSH thứ hai).
# ============================================================================================================
tuong_lua() {
  buoc "Tường lửa"
  local ports p from=""
  ports="$( { sshd -T 2>/dev/null | awk '$1=="port"{print $2}'; ss -tnpH state established 2>/dev/null | awk '/sshd/ {split($3,a,":"); print a[length(a)]}'; } | sort -un)"
  [ -n "$ports" ] || ports=22
  [ -r "$ETC/ufw-from" ] && from="$(tr -d ' \n' < "$ETC/ufw-from")"
  # Chỉ đặt lại tường lửa lần đầu (ufw đang tắt); máy đang bật ufw thì GIỮ luật của quản trị, chỉ thêm luật của bot.
  if ! ufw status 2>/dev/null | grep '^Status: active' >/dev/null; then
    ufw --force reset >/dev/null 2>&1 || true
    ufw default deny incoming >/dev/null; ufw default allow outgoing >/dev/null
  fi
  for p in $ports; do ufw allow "$p/tcp" comment "SSH" >/dev/null; done
  # Cổng lấy từ sổ bản cài của ROOT (ban-cai.d, ghi lúc cài), không từ .env của user bot; kiểm dạng số + khoảng.
  local f
  for f in "$ETC"/ban-cai.d/*.env; do
    [ -f "$f" ] || continue
    for p in $(sed -n 's/^\(DASHBOARD_PORT\|ROUTER_FORWARD_PORT\)=\([0-9]\{4,5\}\)$/\2/p' "$f"); do
      [ "$p" -ge 1024 ] && [ "$p" -le 65535 ] && [ "$p" != 20128 ] || continue
      if [ -n "$from" ]; then ufw allow from "$from" to any port "$p" proto tcp comment "jeistu" >/dev/null; else ufw allow "$p/tcp" comment "jeistu" >/dev/null; fi
    done
  done
  ufw --force enable >/dev/null
  systemd-run --quiet --unit jeistu-ufw-hen-gio --on-active=10min /usr/sbin/ufw --force disable 2>/dev/null || true
  xanh "ufw bật: SSH $(echo $ports | tr ' ' ','), dashboard; tự TẮT sau 10 phút nếu chưa mở trang thiết lập (phòng khoá ngoài)"
}

# ============================================================================================================
main_flow() {
  if [ -n "$KENH" ]; then case "$KENH" in line|zalo|web) ;; *) dung "--kenh chỉ nhận line, zalo, web" ;; esac; fi
  [ -z "$THEM" ] || [[ "$THEM" =~ ^[a-z0-9][a-z0-9-]{0,20}$ ]] || dung "--them: tên chỉ gồm a-z 0-9 -"
  if [ -s "$TT" ] && da_xong xong && [ -z "$THEM" ] && [ -z "$KHOI_PHUC" ] && [ "$CHECK" = 0 ]; then
    buoc "Máy đã có bot ($(ls "$ETC/ban-cai.d" 2>/dev/null | sed 's/\.env$//' | tr '\n' ' '))"
    local c=""
    [ -r /dev/tty ] && read -r -p "Chọn: 1 = cập nhật, 2 = thêm tài khoản, 3 = sửa lỗi cài (chạy lại các chặng), Enter = thoát: " c < /dev/tty
    case "$c" in
      1) exec bash "$LIBDIR/cap-nhat.sh" chay ;;
      2) read -r -p "Tên bản cài thêm (a-z 0-9 -): " THEM < /dev/tty; [ -n "$KENH" ] || read -r -p "Kênh (line / zalo / web): " KENH < /dev/tty
         [[ "$THEM" =~ ^[a-z0-9][a-z0-9-]{0,20}$ ]] || dung "tên chỉ gồm a-z 0-9 -"
         case "$KENH" in line|zalo|web) ;; *) dung "kênh chỉ nhận line, zalo, web" ;; esac ;;
      3) jq '.xong = ["kiem"]' "$TT" > "$TT.moi" && mv "$TT.moi" "$TT" ;;
      *) return 0 ;;
    esac
  fi
  [ -s "$TT" ] && ! da_xong xong && buoc "Làm tiếp lần cài trước: đã xong $(tien_do) chặng"

  # BỔ SUNG 2: khôi phục — kiểm tham số TRƯỚC khi đổi gì trên máy (khoá đọc được, không --them, máy chưa có bot).
  if [ -n "$KHOI_PHUC" ]; then
    [ -f "$KHOI_PHUC" ] && [ -r "$KP_KHOA" ] || dung "--khoi-phuc <bản .tar.age> cần --khoa <tệp khoá age của chủ> (cả hai phải đọc được)"
    # --them <tên> --khoi-phuc: bản cài THỨ HAI từ bản sao lưu của chính bản đó (vd bản Web) — router dùng chung KHÔNG bị ghi đè, bản cài
    # nhận khoá router mới (cap-khoa); thư mục mở gói + dấu chặng riêng theo tên bản cài.
    KP_DIR="$STATE/khoi-phuc-cli${THEM:+-$THEM}"
    [ -z "$THEM" ] || { [ -z "$KP_ROUTER" ] && [ -z "$KP_KHOA_ROUTER" ]; } || dung "--them dùng router chung của máy: không nhận --router / --khoa-router"
    { [ -z "$KP_ROUTER" ] || [ -f "$KP_ROUTER" ]; } && { [ -z "$KP_KHOA_ROUTER" ] || [ -r "$KP_KHOA_ROUTER" ]; } || dung "--router / --khoa-router: tệp không đọc được"
    [ -n "$THEM" ] || { { [ -s "$TT" ] && da_xong bot; } && ! [ -d "$KP_DIR" ] && dung "máy đã cài bot: khôi phục trên máy mới, thêm bản cài bằng --them <tên> --khoi-phuc, hoặc dùng trang thiết lập › Khôi phục"; } || true
  fi
  kiem_may
  [ "$CHECK" = 1 ] && { xanh "chỉ kiểm (--check): không đổi gì"; return 0; }
  # Ubuntu cài mới không có jq: tệp trạng thái (làm tiếp khi chạy lại) cần nó ngay từ đây.
  command -v jq >/dev/null || { apt-get update -qq && apt-get install -y -qq jq >/dev/null; } || dung "không cài được jq (apt)"
  danh_dau kiem
  if [ -z "$KENH" ]; then
    KENH="$(jq -r '.kenh // ""' "$TT")"
    if [ -z "$KENH" ]; then
      [ -r /dev/tty ] || dung "thiếu --kenh line|zalo|web"
      read -r -p "Kênh của bot (line / zalo / web) [line]: " KENH < /dev/tty; KENH="${KENH:-line}"
      case "$KENH" in line|zalo|web) ;; *) dung "kênh chỉ nhận line, zalo, web" ;; esac
    fi
  fi
  # --them chỉ cho KÊNH KHÁC: hai bản cài cùng kênh trùng cổng / thư mục Hermes mặc định (thử máy BỔ SUNG 2: web1 rồi web2 → cổng
  # 4280 đã có). Thêm tài khoản cùng kênh: dashboard › Tài khoản › Thêm tài khoản (scripts/instance.js, cổng / thư mục riêng).
  if [ -n "$THEM" ] && [ ! -f "$ETC/ban-cai.d/$THEM.env" ]; then
    local fk
    for fk in "$ETC"/ban-cai.d/*.env; do
      [ -f "$fk" ] && grep -qx "KENH=$KENH" "$fk" && dung "máy đã có bản cài kênh $KENH ($(basename "$fk" .env)): thêm tài khoản cùng kênh ở dashboard › Tài khoản › Thêm tài khoản; --them dùng cho kênh khác"
    done
  fi
  jq --arg k "$KENH" '.kenh = $k' "$TT" > "$TT.moi" && mv "$TT.moi" "$TT"
  install -d -m 700 "$ETC"; chmod 755 "$ETC"
  hoi_token "$ETC/github-token" "Dán token ĐỌC MÃ (GitHub fine-grained, Contents: Read) rồi Enter" "${JEISTU_TOKEN_MA_FILE:-}"
  hoi_token "$ETC/ghcr-token" "Dán token ĐỌC IMAGE (GitHub classic, read:packages) rồi Enter" "${JEISTU_TOKEN_ANH_FILE:-}"

  da_xong nen || { nen_may; danh_dau nen; }
  [ -z "$KHOI_PHUC" ] || mo_ban_sao_luu
  ky_va_danh_sach; danh_dau ky
  lay_ma; danh_dau ma
  bash "$ROOT_MA/deploy/ubuntu/tro-ly-cai.sh" --tu "$ROOT_MA" --nguoi-dung "$SVC_USER" >/dev/null || dung "cài trợ lý máy không được"
  # Dashboard (nhóm jeistu-tro-ly) đọc trạng thái cập nhật / bản đang chạy ở đây; không có bí mật trong thư mục này.
  chgrp jeistu-tro-ly "$STATE" && chmod 750 "$STATE"
  install -m 640 -g jeistu-tro-ly "$REL" "$STATE/dang-chay.json"; danh_dau tro-ly
  [ -z "$KHOI_PHUC" ] || kiem_ban_sao_luu
  if [ -n "$THEM" ] || ! da_xong router; then router; danh_dau router; fi
  cai_bot; danh_dau bot
  if [ -n "$KHOI_PHUC" ] && ! da_xong "khoi-phuc${THEM:+-$THEM}"; then
    buoc "Đổ dữ liệu từ bản sao lưu (bot, bộ nhớ, Việc, lịch, add-on, trí nhớ dài hạn)"
    local giu=(); [ -z "$THEM" ] || giu=(--giu-khoa-router-moi)
    bash "$LIBDIR/khoi-phuc.sh" bot --tu "$KP_DIR" --ban "${THEM:-chinh}" ${giu[@]+"${giu[@]}"} || dung "đổ dữ liệu bot hỏng (xem /var/log/jeistu-khoi-phuc.log); chạy lại lệnh để làm tiếp"
    danh_dau "khoi-phuc${THEM:+-$THEM}"; rm -rf "$KP_DIR"; xanh "đã khôi phục dữ liệu bot"
  fi
  tuong_lua; danh_dau tuong-lua
  danh_dau xong
  if [ -n "$KHOI_PHUC" ]; then
    printf '\n\033[32m✔ Đã cài và khôi phục từ bản sao lưu.\033[0m Mở dashboard (cổng như máy cũ) và đăng nhập bằng TÀI KHOẢN DASHBOARD CŨ;\n'
    printf '  kênh cần đăng nhập lại thì trang hiện mã QR. Mật khẩu trang router: mật khẩu cũ. Tắt hẳn máy cũ (không để hai máy chạy một phiên).\n'
    return 0
  fi
  local link
  link="$(sudo -H -u "$SVC_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$SVC_USER")" bash -c 'cd "$1" && npm run -s dashboard:setup-link' _ "$BOT_DIR" 2>/dev/null | tail -n 1)"
  printf '\n\033[32m✔ Cài xong. Mở đường link này trên trình duyệt (dùng một lần, trong 24 giờ):\033[0m\n\n    %s\n\n' "${link:-(chưa tạo được link: sudo -u $SVC_USER bash -c 'cd $BOT_DIR && npm run dashboard:setup-link')}"
}
main_flow
}
main "$@"
