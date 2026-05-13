TF_DIR    := $(CURDIR)/terraform
SCRIPTS   := $(CURDIR)/scripts
REPO_ROOT := $(CURDIR)/..

.PHONY: init plan apply destroy output reset nuke

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
