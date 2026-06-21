# Timeline & Task Progress

Tracking eksekusi 3 task GLChat infra automation. Status per **2026-06-22**.

Legend: ✅ Done · ⚠️ Scaffold ready (perlu run di env beneran) · 📋 Plan ready (perlu eksekusi) · ⏳ Pending

---

## 📌 Ringkasan status

| Task                                              | Due        | Status keseluruhan |
|---------------------------------------------------|------------|--------------------|
| 1 — Observe `make infra-standalone-scripts`       | 22 Jun     | ⚠️ Scaffold complete, perlu run untuk dapat error log |
| 2 — Exclude GPU as default                        | 24 Jun     | ✅ Done di modul lokal · 📋 Plan ready untuk upstream |
| 3 — Script connect k8s + taint nodes              | 26 Jun     | ✅ Done (script + Makefile + docs) |

---

## Task 1 — Observe script untuk running infra section
**Due: 2026-06-22**

| Sub-task | Status | Date | Deliverable |
|----------|--------|------|-------------|
| a. Provide 5/6 EC2 via terraform module `terraform-aws-modules/ec2-instance/aws` + AWS NLB | ✅ | 2026-06-22 | `modules/glchat-aws/main.tf` (module ec2 + module vpc + sg + aws_lb) |
| b. Running `make infra-standalone-scripts` (upstream command) | ⚠️ | — | Instruksi run via `make handoff` (perlu AWS access untuk eksekusi) |
| c. List error ke docs | ⚠️ | — | Template `docs/errors.md` (isi setelah run beneran) |
| d. Solusi tiap error | ⚠️ | — | Template `docs/errors.md` (field `Solution`) |

**Deliverable utama:** dokumentasi error.

### Eksekusi
- **2026-06-22 00:30** — Scaffold Terraform awal (4 EC2: rancher/master/2 worker) dengan tfvars existing
- **2026-06-22 01:00** — Adjust ke spec README upstream: 5 node (bastion/LB/master/worker/GPU)
- **2026-06-22 01:30** — Restructure jadi single module `modules/glchat-aws/` (VPC + SG + EC2)
- **2026-06-22 01:45** — Hapus customisasi `root_block_device` (gp3/encrypted/volume_size) supaya simpel
- **2026-06-22 02:15** — Refactor arsitektur: drop LB EC2, split worker jadi BE/FE/DB, add **AWS NLB** (3 listener: 6443/443/80, target masters & workers)
- **⏳ Pending** — Run `make infra-provision` di laptop ber-AWS, lalu `make install-cluster`, capture error ke `docs/errors.md`

---

## Task 2 — Exclude GPU as the default
**Due: 2026-06-24**

| Sub-task | Status | Date | Deliverable |
|----------|--------|------|-------------|
| Check script & disable GPU by default (modul lokal) | ✅ | 2026-06-22 | `variable "include_gpu" { default = false }` di `variables.tf` |
| Command Makefile untuk exclude (default) | ✅ | 2026-06-22 | `make infra-provision` → 4 EC2 tanpa GPU |
| Command Makefile untuk include GPU | ✅ | 2026-06-22 | `make infra-provision-gpu` |
| Modif Makefile **upstream** (`infra-standalone-scripts`) | 📋 | — | `docs/gpu-exclusion-plan.md` — PR plan (additive, non-breaking) |

**Deliverable utama:** command makefile untuk exclude.

### Eksekusi
- **2026-06-22 01:00** — Set `include_gpu = false` sebagai default di Terraform
- **2026-06-22 01:00** — Tambah Makefile target `infra-provision` (default no-GPU) + `infra-provision-gpu` (include)
- **2026-06-22 01:30** — Tulis PR plan untuk modif Makefile upstream (`docs/gpu-exclusion-plan.md`)
- **⏳ Pending** — Eksekusi PR ke fork `gl-sre-helm-charts` setelah punya akses repo

---

## Task 3 — Script connect k8s + taint nodes
**Due: 2026-06-26**

| Sub-task | Status | Date | Deliverable |
|----------|--------|------|-------------|
| Pelajari taint node (konsep + 3 effect) | ✅ | 2026-06-22 | `docs/taint-and-label.md` section "Konsep singkat" |
| a. Connect script ke k8s cluster | ✅ | 2026-06-22 | `scripts/label-taint-nodes.sh` — pakai `$KUBECONFIG` + verifikasi `kubectl cluster-info` |
| b. Label/taint per role (contoh App=node-a, DB=node-b) | ✅ | 2026-06-22 | `docs/taint-and-label.md` section "App/Database separation" |
| Script ter-integrate ke Makefile | ✅ | 2026-06-22 | `make k8s-label-nodes`, `make k8s-label-nodes-dry` |

**Deliverable utama:** script reusable + Makefile target.

### Eksekusi
- **2026-06-22 00:50** — Buat `scripts/label-taint-nodes.sh` v1 (pattern matching nama node, dry-run support)
- **2026-06-22 00:50** — Tambah Makefile targets `k8s-label-nodes` + `k8s-label-nodes-dry`
- **2026-06-22 01:10** — Tulis `docs/taint-and-label.md` (konsep + dua approach + skema GLChat)
- **2026-06-22 01:30** — Update label scheme pakai `gen-ai=application/dpo` (selaras upstream config.yml)
- **2026-06-22 02:15** — Switch ke skema `workload=backend/frontend/database` (sesuai split worker BE/FE/DB), taint hanya untuk DB
- **⏳ Pending** — Verifikasi end-to-end di cluster beneran (setelah Task 1 selesai)

---

## Tambahan request (di luar 3 task utama)

| Item | Status | Date | Deliverable |
|------|--------|------|-------------|
| Module Terraform "sesimple" bernama `glchat-aws` | ✅ | 2026-06-22 | `modules/glchat-aws/` (5 .tf + tfvars.example + README) |
| Satu module handle semua (VPC, SG, NLB, EC2) | ✅ | 2026-06-22 | `main.tf` — module vpc + sg + module ec2 + aws_lb |
| Setup script — install prereq tools | ✅ | 2026-06-22 | `scripts/setup.sh` + `make setup` |
| Install script — RKE2 + Rancher | ✅ | 2026-06-22 | `scripts/install-cluster.sh` + `make install-cluster` |
| Drop LB EC2, pakai AWS NLB (split worker BE/FE/DB) | ✅ | 2026-06-22 | NLB DNS auto-injected ke config.yml lewat install-cluster |
| Timeline doc | ✅ | 2026-06-22 | `docs/timeline.md` (file ini) |
| Commit + push ke `andrerexfords/PROJECT` | ✅ | 2026-06-22 | commit terbaru di branch `main` |

---

## 🔜 Action items berikutnya (di laptop ber-AWS)

| # | Task | Estimasi waktu |
|---|------|----------------|
| 1 | `make setup` di laptop target | 5-10 menit |
| 2 | Isi `terraform.tfvars` (key_name, ami_id, allowed_ssh_cidr) | 5 menit |
| 3 | `make infra-provision` → catat IP via `make infra-output` | 5-10 menit (AWS apply) |
| 4 | `make install-cluster-dry` → review `config.generated.yml`, edit field CHANGEME (password, domain) | 5-10 menit |
| 5 | Upload secrets ke bastion `gl-sre-helm-charts/apps/config/` (gcp-sa.json, kube-config, tls) | 5 menit |
| 6 | `make install-cluster` → orchestrate install di bastion → **catat error ke `docs/errors.md`** (Task 1 c-d) | 30-60 menit |
| 7 | (Task 2) Fork upstream, apply patch `docs/gpu-exclusion-plan.md`, push PR | 15 menit |
| 8 | (Task 3) Setelah cluster ready: `make k8s-label-nodes-dry` lalu `make k8s-label-nodes` — verifikasi label/taint terpasang | 10 menit |
| 9 | Cleanup: `make infra-destroy` setelah selesai testing | 5 menit |

---

## Catatan

- **Scope:** infrastructure only. App install hanya untuk "learning app" verifikasi.
- **K8s stack:** EC2 + RKE2 (self-managed), selaras dengan repo upstream `gl-sre-helm-charts`. Bukan EKS.
- **Repo:** https://github.com/andrerexfords/PROJECT
