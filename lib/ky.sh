# shellcheck shell=bash
# ============================================================================================================
#  G123: kiểm chữ ký của image và tệp phát hành bằng cosign (khoá công khai của chủ, KHÔNG dùng sổ công khai Sigstore).
#  Dùng chung cho router-cai.sh, cap-nhat.sh (bộ cập nhật), cai.sh (lệnh cài). Chạy bằng root.
#
#  - cosign ghim ĐÚNG bản + SHA256 (như uv trong install.sh); cài vào /usr/local/lib/jeistu/cosign-<bản>, không đụng cosign khác.
#  - Kiểm offline: --insecure-ignore-tlog=true CHỈ ở đây, đi cùng khoá công khai ghim (deploy/ubuntu/cosign.pub). Không có mốc
#    thời gian tin cậy, nên bộ cập nhật phải tự chặn hạ cấp (so số bản trong danh sách phát hành, cap-nhat.sh).
#  - Image luôn gọi theo DIGEST (ghcr.io/…@sha256:<64 hex>); tên theo tag bị từ chối.
# ============================================================================================================

KY_COSIGN_VERSION="v3.1.4"
KY_COSIGN_SHA256_AMD64="424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa"
KY_COSIGN_SHA256_ARM64="ade83b7aac62e131cacfe96d958948b2150cc9efec46a570a2649b8e27dedad2"
KY_DIR="${JEISTU_KY_DIR:-/usr/local/lib/jeistu}"
# Khoá công khai: bản trong /etc/jeistu (bộ cài chép một lần) thắng bản trong mã — mã tải về sau không tự đổi được khoá tin cậy.
KY_PUB_DEFAULT="/etc/jeistu/cosign.pub"
# Kho image của tổ chức. Đổi kho (GHCR đổi chính sách giá) chỉ cần đổi dòng này trong /etc/jeistu/kho-image.
KY_REGISTRY_DEFAULT="ghcr.io/dashlinebot"
# Docker / cosign đọc đăng nhập kho image từ đây (root 700), không ghi vào ~/.docker của ai.
KY_DOCKER_CONFIG="${JEISTU_DOCKER_CONFIG:-/etc/jeistu/docker}"
# CHỈ cho máy thử (kho image cục bộ http://127.0.0.1:…): cosign đi http. Không đổi khoá / cách kiểm chữ ký.
KY_INSECURE=(); { [ "${JEISTU_KY_KHO_THU:-}" = 1 ] || [ -f /etc/jeistu/kho-thu-http ]; } && KY_INSECURE=(--allow-insecure-registry)

ky_loi() { printf '\033[31m[LỖI]\033[0m %s\n' "$*" >&2; return 1; }

ky_kho() {
  local f=/etc/jeistu/kho-image k=""
  [ -r "$f" ] && k="$(tr -d ' \n' < "$f")"
  printf '%s' "${JEISTU_KHO_IMAGE:-${k:-$KY_REGISTRY_DEFAULT}}"
}

ky_pub() { printf '%s' "${JEISTU_COSIGN_PUB:-$KY_PUB_DEFAULT}"; }

# ref hợp lệ: <kho của tổ chức>/<tên>@sha256:<64 hex>. In lỗi + trả 1 nếu sai.
ky_ref_hop_le() {
  local ref="$1" kho; kho="$(ky_kho)"
  [[ "$ref" =~ ^[a-z0-9.:-]+(/[a-z0-9._-]+)+@sha256:[0-9a-f]{64}$ ]] || { ky_loi "image phải gọi theo digest (…@sha256:<64 ký tự>): $ref"; return 1; }
  case "$ref" in "$kho"/*) ;; *) ky_loi "image ngoài kho của tổ chức ($kho): $ref"; return 1 ;; esac
}

# Đường tới cosign đã kiểm SHA256 (cài nếu chưa có). In đường dẫn ra stdout.
ky_cosign() {
  local arch sha bin url tmp
  case "$(uname -m)" in x86_64|amd64) arch=amd64; sha="$KY_COSIGN_SHA256_AMD64" ;; aarch64|arm64) arch=arm64; sha="$KY_COSIGN_SHA256_ARM64" ;;
    *) ky_loi "cosign: máy $(uname -m) chưa hỗ trợ"; return 1 ;; esac
  bin="$KY_DIR/cosign-$KY_COSIGN_VERSION"
  if [ -x "$bin" ] && echo "$sha  $bin" | sha256sum -c --status 2>/dev/null; then printf '%s' "$bin"; return 0; fi
  install -d -m 755 "$KY_DIR"
  tmp="$(mktemp "$KY_DIR/.cosign.XXXXXX")"
  url="https://github.com/sigstore/cosign/releases/download/$KY_COSIGN_VERSION/cosign-linux-$arch"
  if ! curl -fsSL --retry 3 --max-time 120 -o "$tmp" "$url"; then rm -f "$tmp"; ky_loi "không tải được cosign ($url): kiểm kết nối 443 tới github.com"; return 1; fi
  if ! echo "$sha  $tmp" | sha256sum -c --status; then rm -f "$tmp"; ky_loi "cosign tải về SAI mã băm SHA256 — dừng, không dùng"; return 1; fi
  chmod 755 "$tmp"; mv -f "$tmp" "$bin"
  printf '%s' "$bin"
}

# ky_kiem_image <ref@sha256> : 0 = chữ ký đúng khoá của chủ. Image phải đã kéo được (cosign đọc chữ ký từ kho).
ky_kiem_image() {
  local ref="$1" pub cos
  ky_ref_hop_le "$ref" || return 1
  pub="$(ky_pub)"; [ -s "$pub" ] || { ky_loi "thiếu khoá công khai $pub"; return 1; }
  cos="$(ky_cosign)" || return 1
  if DOCKER_CONFIG="$KY_DOCKER_CONFIG" "$cos" verify ${KY_INSECURE[@]+"${KY_INSECURE[@]}"} --key "$pub" --insecure-ignore-tlog=true "$ref" >/dev/null 2>&1; then return 0; fi
  ky_loi "CHỮ KÝ SAI hoặc thiếu cho $ref — không chạy image này"
  return 1
}

# ky_kiem_tep <tệp> <bundle> : 0 = tệp đúng chữ ký của chủ.
ky_kiem_tep() {
  local f="$1" b="$2" pub cos
  pub="$(ky_pub)"; [ -s "$pub" ] || { ky_loi "thiếu khoá công khai $pub"; return 1; }
  [ -s "$f" ] && [ -s "$b" ] || { ky_loi "thiếu tệp hoặc chữ ký: $f"; return 1; }
  cos="$(ky_cosign)" || return 1
  if "$cos" verify-blob --key "$pub" --insecure-ignore-tlog=true --bundle "$b" "$f" >/dev/null 2>&1; then return 0; fi
  ky_loi "CHỮ KÝ SAI cho $(basename "$f") — không dùng"
  return 1
}

# ---------- G123 BỔ SUNG 2: image NẠP TAY từ Mac (scripts/nap-image.sh) cho máy không kéo được kho image ----------
# Máy không tới được ghcr.io thì cosign cũng không đọc được chữ ký của image. Thay vào đó kiểm CHUỖI DIGEST từ danh sách phát hành
# ĐÃ KÝ (ky_kiem_tep) xuống tới image đang có trên máy:
#   digest trong danh sách = sha256(index.json) → mục linux/<chip> của index = sha256(manifest.json) → manifest.config.digest
#   = ID image đã nạp (Docker tự kiểm từng lớp khớp config khi docker load).
# index.json + manifest.json là bản gốc từng byte do Mac lấy từ kho (docker buildx imagetools inspect --raw), chép vào
# ~/.cache/jeistu-nap/<64 hex của digest>/ của user bot. Ai sửa tệp thì mã băm lệch → từ chối; không cần tin người chép.
KY_NAP_DA_KIEM="${JEISTU_STATE_DIR:-/var/lib/jeistu}/nap-da-kiem"
ky_nap_thu_muc() {   # các thư mục bằng chứng ứng viên (user của mọi bản cài đã đăng ký, cộng JEISTU_NAP_DIR cho test)
  local f u h
  [ -n "${JEISTU_NAP_DIR:-}" ] && printf '%s\n' "$JEISTU_NAP_DIR"
  for f in "${JEISTU_ETC:-/etc/jeistu}"/ban-cai.d/*.env; do
    [ -f "$f" ] || continue
    u="$(sed -n 's/^USER=//p' "$f" | tail -n 1)"; h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
    [ -n "$h" ] && printf '%s\n' "$h/.cache/jeistu-nap"
  done
}
ky_sha() { sha256sum | cut -d' ' -f1; }
ky_chip() { case "$(uname -m)" in x86_64|amd64) echo amd64 ;; aarch64|arm64) echo arm64 ;; *) uname -m ;; esac; }

# ky_nap_kiem <ref@sha256> : 0 = image đang có trên máy đúng là image danh sách ký chỉ tới. Ghi tên chạy được vào KY_NAP_DA_KIEM.
ky_nap_kiem() {
  local ref="$1" hex repo tag d idx man mt mdig cfg id ten=""
  ky_ref_hop_le "$ref" || return 1
  hex="${ref##*@sha256:}"; repo="${ref%@*}"; tag="$repo:nap-${hex:0:12}"
  while IFS= read -r d; do
    [ -f "$d/$hex/index.json" ] || continue
    # Đọc có giới hạn (1 MiB), không đi theo symlink.
    [ ! -L "$d/$hex/index.json" ] && [ ! -L "$d/$hex/manifest.json" ] || continue
    idx="$(head -c 1048576 "$d/$hex/index.json")"; man="$(head -c 1048576 "$d/$hex/manifest.json" 2>/dev/null || true)"
    # Băm THẲNG từ tệp (không qua biến: $(…) cắt dòng trống cuối, lệch digest với bản gốc của kho).
    [ "$(head -c 1048576 "$d/$hex/index.json" | ky_sha)" = "$hex" ] || { ky_loi "bằng chứng nạp tay của $ref: index.json không khớp digest trong danh sách ký"; return 1; }
    mt="$(printf '%s' "$idx" | jq -r '.mediaType // ""' 2>/dev/null)"
    if printf '%s' "$idx" | jq -e '.manifests' >/dev/null 2>&1; then
      mdig="$(printf '%s' "$idx" | jq -r --arg a "$(ky_chip)" '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == $a)][0].digest // ""')"
      [ -n "$mdig" ] && [ "sha256:$(head -c 1048576 "$d/$hex/manifest.json" 2>/dev/null | ky_sha)" = "$mdig" ] \
        || { ky_loi "bằng chứng nạp tay của $ref: manifest.json không phải bản linux/$(ky_chip) của index ($mt)"; return 1; }
    else
      man="$idx"   # image một nền tảng: digest trỏ thẳng manifest
    fi
    cfg="$(printf '%s' "$man" | jq -r '.config.digest // ""')"
    [[ "$cfg" =~ ^sha256:[0-9a-f]{64}$ ]] || { ky_loi "bằng chứng nạp tay của $ref: manifest không có config"; return 1; }
    # Kho containerd giữ được tên theo digest (ID = digest của index / manifest); kho cũ chỉ còn thẻ nap-<12 hex> (ID = config).
    for ten in "$ref" "$tag"; do
      id="$(docker image inspect --format '{{.Id}}' "$ten" 2>/dev/null)" || continue
      case "$id" in "$cfg"|"sha256:$hex"|"$mdig") ;; *) ky_loi "image $ten trên máy KHÁC image danh sách ký chỉ tới ($id) — không chạy"; return 1 ;; esac
      install -d -m 750 "$KY_NAP_DA_KIEM"; printf '%s\n' "$ten" > "$KY_NAP_DA_KIEM/$hex"
      return 0
    done
    ky_loi "đã có bằng chứng nạp tay cho $ref nhưng máy chưa có image (chạy lại Nap-image trên Mac)"; return 1
  done < <(ky_nap_thu_muc)
  return 1
}

# ky_anh_chay <ref@sha256> : tên để docker / compose chạy. Bình thường là chính ref; image nạp tay trên kho Docker cũ (không giữ tên
# theo digest) thì là thẻ nap-<12 hex> ĐÃ qua ky_nap_kiem.
ky_anh_chay() {
  local ref="$1" hex t
  hex="${ref##*@sha256:}"
  if ! docker image inspect "$ref" >/dev/null 2>&1 && [ -s "$KY_NAP_DA_KIEM/$hex" ]; then
    t="$(head -n 1 "$KY_NAP_DA_KIEM/$hex")"
    case "$t" in "${ref%@*}:nap-${hex:0:12}") printf '%s' "$t"; return 0 ;; esac
  fi
  printf '%s' "$ref"
}

# ky_keo <ref@sha256> : kéo đúng digest (đăng nhập kho trong KY_DOCKER_CONFIG) rồi kiểm chữ ký; sai thì xoá image vừa kéo.
# Không kéo được / không đọc được chữ ký trên kho MÀ máy đã có image nạp tay kèm bằng chứng → kiểm chuỗi digest (ky_nap_kiem).
# Image VỪA kéo từ kho mà chữ ký sai thì KHÔNG có đường lùi này.
ky_keo() {
  local ref="$1" had=0
  ky_ref_hop_le "$ref" || return 1
  rm -f "$KY_NAP_DA_KIEM/${ref##*@sha256:}" 2>/dev/null || true
  docker image inspect "$ref" >/dev/null 2>&1 && had=1
  if [ "$had" = 0 ] && ! DOCKER_CONFIG="$KY_DOCKER_CONFIG" docker pull -q "$ref" >/dev/null 2>&1; then
    if ky_nap_kiem "$ref"; then echo "[ky] $ref: image nạp tay, khớp danh sách phát hành đã ký (chuỗi digest)" >&2; return 0; fi
    ky_loi "không kéo được $ref (token đọc image hết hạn / bị thu hồi, hoặc mạng chặn ghcr.io:443; máy không tải được image: Nap-image trên Mac)"; return 1
  fi
  if ! ky_kiem_image "$ref"; then
    if [ "$had" = 1 ] && ky_nap_kiem "$ref"; then echo "[ky] $ref: image nạp tay, khớp danh sách phát hành đã ký (chuỗi digest)" >&2; return 0; fi
    [ "$had" = 1 ] || docker image rm -f "$ref" >/dev/null 2>&1 || true
    return 1
  fi
}

# ky_dang_nhap <tệp token> : đăng nhập kho image bằng token đọc (classic read:packages), token qua stdin.
ky_dang_nhap() {
  local tf="$1" kho host
  [ -r "$tf" ] || { ky_loi "không đọc được $tf"; return 1; }
  kho="$(ky_kho)"; host="${kho%%/*}"
  # Tên đăng nhập: tên GitHub của chủ token (/etc/jeistu/ghcr-user); thiếu thì một tên bất kỳ (GHCR xét token).
  local u="jeistu-may"; [ -r /etc/jeistu/ghcr-user ] && u="$(tr -d ' \n' < /etc/jeistu/ghcr-user)"
  install -d -m 700 "$KY_DOCKER_CONFIG"
  DOCKER_CONFIG="$KY_DOCKER_CONFIG" docker login "$host" -u "${u:-jeistu-may}" --password-stdin < "$tf" >/dev/null 2>&1 \
    || { ky_loi "đăng nhập $host bằng token đọc image không được (token sai, hết hạn hoặc thiếu quyền read:packages)"; return 1; }
}
