TF_DIR    := $(CURDIR)/terraform
SCRIPTS   := $(CURDIR)/scripts
REPO_ROOT := $(CURDIR)/..

.PHONY: init plan apply destroy output reset nuke pod-save pod-load pod-list start-order-service deploy-frontend

init:
	cd $(TF_DIR) && tflocal init -input=false

plan:
	cd $(TF_DIR) && tflocal plan

apply:
	cd $(TF_DIR) && tflocal apply -auto-approve

destroy:
	cd $(TF_DIR) && tflocal destroy -auto-approve

output:
	cd $(TF_DIR) && tflocal output

# Delete every bookstore resource from LocalStack (idempotent, safe to re-run)
nuke:
	bash $(SCRIPTS)/nuke.sh

# Build the React app and sync dist/ to the LocalStack S3/CloudFront bucket
deploy-frontend:
	bash $(SCRIPTS)/deploy-frontend.sh

# Start the Flask order service locally on port 5001 (reads env vars from Terraform outputs)
start-order-service:
	bash $(SCRIPTS)/start-order-service.sh

# Snapshot the current LocalStack state (infrastructure + data) into a Cloud Pod
pod-save:
	localstack pod save bookstore-dev

# Load a saved Cloud Pod and refresh local config files
pod-load:
	localstack pod load bookstore-dev --strategy overwrite
	bash $(SCRIPTS)/update-mcp-config.sh
	bash $(SCRIPTS)/deploy-frontend.sh

# List all available Cloud Pods
pod-list:
	localstack pod list

# Full reset after a LocalStack restart:
#   1. nuke  — wipe all persisted resources from LocalStack
#   2. clear — delete stale local state so Terraform starts from scratch
#   3. init  — reinitialise providers
#   4. build — reinstall Lambda npm deps (needed for archive_file)
#   5. apply — create everything fresh
reset: nuke
	rm -f $(TF_DIR)/terraform.tfstate $(TF_DIR)/terraform.tfstate.backup
	cd $(TF_DIR) && tflocal init -input=false
	cd $(REPO_ROOT)/services/catalog-api && npm install --production --silent
	cd $(TF_DIR) && tflocal apply -auto-approve
	bash $(SCRIPTS)/update-mcp-config.sh
	bash $(SCRIPTS)/seed-data.sh
