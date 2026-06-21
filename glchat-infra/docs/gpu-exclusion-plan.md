# Task 2 — Exclude GPU as Default

**Due:** 2026-06-24
**Scope:** modifikasi Makefile di repo upstream `gl-sre-helm-charts`.

## Konteks

Saat ini di repo upstream:
```bash
make infra-standalone-scripts                                # include GPU node
make infra-standalone-scripts ARGS="--exclude gpu-node"      # exclude GPU (opt-out)
```

Target: GPU **default-nya excluded**, dan tersedia command untuk include kembali.

## Pendekatan

**Additive — tambah target baru, jangan flip default existing.**

Rasional:
- **Non-breaking** untuk user/CI yang sudah pakai `infra-standalone-scripts` dengan ekspektasi GPU included.
- Mudah di-review/merge upstream (PR additive).
- Reversible kalau policy berubah.
- Tetap penuhi permintaan task: command Makefile yang default-nya tanpa GPU.

## Proposed change

Tambah 2 target baru di Makefile repo upstream:

```makefile
# Default: exclude GPU. Pakai ini untuk client tanpa GPU node.
infra-standalone:
	$(MAKE) infra-standalone-scripts ARGS="--exclude gpu-node $(ARGS)"

# Eksplisit include GPU (alias untuk infra-standalone-scripts apa adanya).
infra-standalone-with-gpu:
	$(MAKE) infra-standalone-scripts $(ARGS)
```

Hasil command yang tersedia:
| Command                            | GPU? | Catatan |
|------------------------------------|------|---------|
| `make infra-standalone`            | NO   | **Baru**, default no-GPU |
| `make infra-standalone-with-gpu`   | YES  | **Baru**, eksplisit include GPU |
| `make infra-standalone-scripts`    | YES  | Existing, tidak diubah |

User tetap bisa pass `ARGS=...` tambahan:
```bash
make infra-standalone ARGS="--exclude label-taints"   # no-GPU + skip label-taints
```

## Verifikasi sebelum PR

1. Clone repo & buat branch:
   ```bash
   git clone https://github.com/GDP-ADMIN/gl-sre-helm-charts
   cd gl-sre-helm-charts
   git checkout -b feat/default-no-gpu
   ```

2. Cek struktur Makefile saat ini:
   ```bash
   grep -n "infra-standalone" Makefile
   ```
   Pastikan target `infra-standalone` belum ada (kalau ada, kita pakai nama lain misal `infra-standalone-no-gpu`).

3. Apply patch di atas, commit:
   ```bash
   git add Makefile
   git commit -m "feat(makefile): add infra-standalone target with GPU excluded by default"
   ```

4. Dry-run test (di env yang sudah punya config.yml + EC2 ready):
   ```bash
   make -n infra-standalone | head -5    # cek perintah yang akan dijalankan
   ```
   Output harus include `--exclude gpu-node`.

5. Push & buka PR ke upstream (atau bawa ke tim internal dulu).

## Update dokumentasi

Setelah patch diterima, update README upstream:

```markdown
## 🚀 Quick Start Deployment

# Default: tanpa GPU
make infra-standalone

# Dengan GPU
make infra-standalone-with-gpu

# Advanced (pakai flag manual):
make infra-standalone-scripts ARGS="..."
```

## Alternatif kalau breaking change diizinkan

Kalau tim setuju breaking change (flip default existing), patch-nya jauh lebih kecil — ubah `infra-standalone-scripts` supaya inject `--exclude gpu-node` by default. Tapi:
- Perlu sign-off explicit dari tim
- Semua user/CI existing harus diberitahu
- Tidak direkomendasikan kecuali ada alasan kuat

## Open question untuk tim upstream

1. Apakah nama `infra-standalone` sudah dipakai untuk hal lain?
2. Apakah ada use case lain di mana default include-GPU lebih masuk akal (mis. internal staging)?
3. Penamaan `infra-standalone-with-gpu` vs `infra-standalone-gpu` — preferensi?
