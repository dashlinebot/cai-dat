# Lệnh cài bot Jeistu (Ubuntu 24.04 / 26.04)

```bash
curl -fsSLO https://raw.githubusercontent.com/dashlinebot/cai-dat/v1/cai.sh
curl -fsSL --create-dirs -o lib/ky.sh https://raw.githubusercontent.com/dashlinebot/cai-dat/v1/lib/ky.sh
curl -fsSLO https://raw.githubusercontent.com/dashlinebot/cai-dat/v1/cosign.pub
curl -fsSLO https://raw.githubusercontent.com/dashlinebot/cai-dat/v1/SHA256SUMS
sha256sum -c SHA256SUMS          # và so mã băm cai.sh với sổ tay nội bộ
sudo bash cai.sh --kenh line     # zalo | web
```

Repo này không chứa bí mật. Lệnh chỉ chạy được với token của máy do chủ cấp; mọi thứ tải về sau đều kiểm chữ ký bằng `cosign.pub`.
