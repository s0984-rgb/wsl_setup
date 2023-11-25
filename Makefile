SHELL:=/bin/bash
PROJECT_NAME:=$${PWD\#\#*/}
PROJECT_MOUNT_POINT:="/mnt/wsl/${WSL_DISTRO_NAME}/${PROJECT_NAME}"
DEV_K8S_NAMESPACE=${PROJECT_NAME}-dev

help: ## Show this help
	@echo "----------------------------------------------------------------------"
	@echo "Descriptions of Make commands and what they do."
	@echo "Usage: $(MAKE) <cmd1> <cmd2> <cmdN>"
	@echo "e.g.: $(MAKE) help"
	@echo "----------------------------------------------------------------------"
	@sed -ne 's/^\([^[:space:]]*\):.*##/\1:\t/p' $(MAKEFILE_LIST) | column -t -s $$'\t'

##########################
# Rancher Desktop        #
##########################

_check_wsl:
ifndef WSL_DISTRO_NAME
	$(error Run this command in WSL)
endif

_check_dockerfile:
ifndef DOCKERFILE
	$(error DOCKERFILE not specified)
endif

_check_context:
ifndef CONTEXT
	$(error CONTEXT not specified)
endif

# Ubuntu 20.04 WSL2 does not expose the root filesystem on /mnt/wsl/
# Other WSL distros, particularly Rancher Desktop's WSL distro does this
# This allows easy sharing of folders across all WSL2 Linux distros and any docker containers running in them
# https://superuser.com/questions/1659218/is-there-a-way-to-access-files-from-one-wsl-2-distro-image-in-another-one
# This command must be run from your Ubuntu WSL
expose_wsl_project: _check_wsl ## Expose present working directory to /mnt/wsl/${WSL_DISTRO_NAME} ! RUN THIS OUTSIDE DEVCONTAINER !
	@$(eval EXPRESSION := $(shell printf "${PWD} ${PROJECT_MOUNT_POINT} none defaults,bind,X-mount.mkdir 0 0"))
	@grep -xq "${EXPRESSION}" /etc/fstab; \
		if [ $$? != 0 ]; then \
			echo "${EXPRESSION}" | sudo tee -a /etc/fstab; \
		else \
			echo "The directory \"${PWD}\" is mounted at \"${PROJECT_MOUNT_POINT}\""; \
		fi
	@sudo mount ${PWD}

remove_wsl_project: _check_wsl ## Removes PWD from WSL mount point
	@$(eval EXPRESSION := $(shell printf "${PWD} ${PROJECT_MOUNT_POINT} none defaults,bind,X-mount.mkdir 0 0"))
	@sudo umount ${PROJECT_MOUNT_POINT}
	@grep -v "${EXPRESSION}" /etc/fstab | sudo tee /etc/fstab

_rd_hydra_context: ## Use Rancher Desktop Kubernetes context
	@kubectl config use-context rancher-desktop

rd_create_docker_context: ## Configure Rancher Desktop docker context
	@docker context create rancher-desktop --default-stack-orchestrator=swarm --docker host=unix:///mnt/wsl/rancher-desktop/run/docker.sock

rd_switch_docker_context: ## Use Rancher Desktop docker context
	@docker context use rancher-desktop

rd_revert_docker_context: ## Use default docker context
	@docker context use default

rd_setup: _check_wsl ## Setup Rancher Desktop WSL
	@$(eval LOCAL_DOCKER_GROUP_ID:=$(shell grep 'docker' /etc/group | cut -d : -f 3))
	@cp ${PWD}/build/rancher_desktop_setup.sh ${PWD}/build/templated_rancher_desktop_setup.sh
	@sed -i "s@{LOCAL_DOCKER_GROUP_ID}@${LOCAL_DOCKER_GROUP_ID}@" ${PWD}/build/templated_rancher_desktop_setup.sh
	@rdctl.exe shell sh ${PROJECT_MOUNT_POINT}/build/templated_rancher_desktop_setup.sh
	@rm ${PROJECT_MOUNT_POINT}/build/templated_rancher_desktop_setup.sh

rd_clean: _rd_hydra_context ## Destroy dev namespace
	@kubectl delete ns ${DEV_K8S_NAMESPACE}
	@$(MAKE) rd_init

rd_init: _rd_hydra_context ## Initialize Rancher Desktop environment
	@kubectl create ns ${DEV_K8S_NAMESPACE}
	@$(MAKE) rd_setup

rd_build: rd_switch_docker_context _check_dockerfile _check_context ## Build container in Rancher Desktop context
	@docker buildx build -f ${DOCKERFILE} ${CONTEXT}
	@$(MAKE) rd_revert_docker_context

rd_deploy: _rd_hydra_context ## Deploy Helm chart on Rancher Desktop
	@helm upgrade --install \
		--values ./config/${ENV}.yaml \
		nginx ./nginx
