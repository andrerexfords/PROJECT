.PHONY: help infra-init infra-plan infra-provision infra-provision-gpu infra-output infra-destroy handoff k8s-label-nodes k8s-label-nodes-dry clean

TERRAFORM_DIR := modules/glchat-aws
SCRIPTS_DIR   := scripts
TF := terraform -chdir=$(TERRAFORM_DIR)

# GPU di-exclude by default. Override: make infra-provision INCLUDE_GPU=true
INCLUDE_GPU ?= false

# Untuk k8s-label-nodes (default cocok dengan naming Terraform di sini)
PROJECT_NAME ?= glchat
ENVIRONMENT  ?= standalone

help:
	@echo "GLChat infra — wrapper untuk Terraform provisioning."
	@echo "Setelah EC2 ready, install RKE2/Rancher pakai repo upstream:"
	@echo "  https://github.com/GDP-ADMIN/gl-sre-helm-charts"
	@echo ""
	@echo "Provisioning (Terraform):"
	@echo "  infra-init           - terraform init"
	@echo "  infra-plan           - terraform plan (default tanpa GPU)"
	@echo "  infra-provision      - provision 4 EC2 (bastion + LB + master + worker, NO GPU)"
	@echo "  infra-provision-gpu  - provision 5 EC2 (+ GPU worker)"
	@echo "  infra-output         - tampilkan IP/ID semua instance"
	@echo "  infra-destroy        - destroy semua resource"
	@echo ""
	@echo "Post-provision:"
	@echo "  handoff              - print instruksi next step (clone repo upstream + isi config.yml)"
	@echo ""
	@echo "Kubernetes (standalone — alternatif kalau tidak via repo upstream):"
	@echo "  k8s-label-nodes      - connect ke cluster + label/taint nodes"
	@echo "  k8s-label-nodes-dry  - dry-run (print perintah tanpa apply)"
	@echo ""
	@echo "Util:"
	@echo "  clean                - hapus .terraform & tfplan lokal"
	@echo ""
	@echo "Override GPU di provision: make infra-provision INCLUDE_GPU=true"

infra-init:
	$(TF) init -upgrade

infra-plan: infra-init
	$(TF) plan -var="include_gpu=$(INCLUDE_GPU)" -out=tfplan

infra-provision: infra-init
	$(TF) apply -var="include_gpu=$(INCLUDE_GPU)" -auto-approve

infra-provision-gpu:
	$(MAKE) infra-provision INCLUDE_GPU=true

infra-output:
	$(TF) output

infra-destroy:
	$(TF) destroy -var="include_gpu=$(INCLUDE_GPU)" -auto-approve

handoff:
	@echo "=== NEXT STEPS (di laptop yang punya AWS access) ==="
	@echo ""
	@echo "1) Catat IP semua instance:"
	@echo "     make infra-output"
	@echo ""
	@echo "2) Clone repo upstream (sibling folder):"
	@echo "     cd .. && git clone https://github.com/GDP-ADMIN/gl-sre-helm-charts"
	@echo "     cd gl-sre-helm-charts"
	@echo ""
	@echo "3) Isi config.yml dengan IP & credentials:"
	@echo "     - infra.bastion.ip      = <bastion public IP>"
	@echo "     - infra.rancher.ip      = <master private IP>"
	@echo "     - infra.rke2.nodes[]    = master + worker (sesuaikan IP)"
	@echo "     - infra.load_balancer.* = LB IP + domain"
	@echo ""
	@echo "4) Letakkan file rahasia di apps/config/:"
	@echo "     - gcp-service-account.json  (minta ke infra@gdplabs.id)"
	@echo "     - kube-config.yaml"
	@echo "     - tls-secret.yaml"
	@echo ""
	@echo "5) SSH ke bastion + run installer:"
	@echo "     ssh -A user@<bastion-ip>"
	@echo "     cd gl-sre-helm-charts"
	@echo "     make infra-standalone-scripts ARGS=\"--exclude gpu-node\"   # tanpa GPU"
	@echo "     # ATAU"
	@echo "     make infra-standalone-scripts                              # dengan GPU"
	@echo ""
	@echo "6) Catat semua error yg muncul ke docs/errors.md (template sudah ada)."

k8s-label-nodes:
	PROJECT_NAME=$(PROJECT_NAME) ENVIRONMENT=$(ENVIRONMENT) $(SCRIPTS_DIR)/label-taint-nodes.sh

k8s-label-nodes-dry:
	PROJECT_NAME=$(PROJECT_NAME) ENVIRONMENT=$(ENVIRONMENT) DRY_RUN=true $(SCRIPTS_DIR)/label-taint-nodes.sh

clean:
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/tfplan
