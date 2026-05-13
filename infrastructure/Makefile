TF_DIR := $(CURDIR)/terraform

.PHONY: init apply destroy plan output reset

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

# Wipe local state and re-apply from scratch (use after localstack restart)
reset:
	rm -f $(TF_DIR)/terraform.tfstate $(TF_DIR)/terraform.tfstate.backup
	cd $(TF_DIR) && tflocal init -input=false && tflocal apply -auto-approve
