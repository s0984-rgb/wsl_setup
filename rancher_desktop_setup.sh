#!/bin/sh
# Rancher Desktop WSL is configured withj a different 'docker' group by default as compared Ubuntu WSL
# the 'docker' group in Ubuntu is 999 by default; whereas rancher-desktop's is 100 by default
# Because of this difference, we must modify the GID of the docker group on one of the WSL instances

# This can be achieved with a provisioning script:
# https://docs.rancherdesktop.io/how-to-guides/provisioning-scripts#windows

# Docker group of the remote WSL that will be worked from
REMOTE_DOCKER_GROUP_ID={LOCAL_DOCKER_GROUP_ID}
# Docker daemon socket on rancher-desktop WSL
DOCKER_DAEMON_SOCKET=/mnt/wsl/rancher-desktop/run/docker.sock
# Name of the docker group with permissions on the docker daemon in rancher-desktop WSL
DOCKER_DAEMON_GROUP_NAME=$(stat ${DOCKER_DAEMON_SOCKET} -c %G)
# Group ID that has permissions on the docker daemon
DOCKER_DAEMON_GROUP_ID=$(stat ${DOCKER_DAEMON_SOCKET} -c %g)
# Group ID of the 'docker' group
DOCKER_GROUP_ID=$(grep 'docker' /etc/group | cut -d : -f 3)

# Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
DEFAULT='\033[1;39m'
NC='\033[0m' # No Color

# Logger
logInternal() {
    # shellcheck disable=SC2155 # the command does not benefit from being split in multiple commands
    local utcTime=$(date -u -Iseconds)
    local color=${1}
    local level=${2}
    local message=${3}
    printf "%b[%s] [%s] %s%b\n" "${color}" "${utcTime}" "${level}" "${message}" "${NC}"
}

logDebug() {
    logInternal "${DEFAULT}" "DEBUG" "${1}"
}

logSuccess() {
    logInternal "${GREEN}" "SUCCESS" "${1}"
}

logInfo() {
    logInternal "${WHITE}" "INFO" "${1}"
}

logWarning() {
    logInternal "${YELLOW}" "WARN" "${1}"
}

logError() {
    logInternal "${RED}" "ERROR" "${1}"
}

# Check exit code
check_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        logError "Process failed at ${FUNCNAME[1]}. Exit code '${exit_code}'. See error above."
        exit "${exit_code}"
    fi
}

# Check if executable is installed
get_exec() {
    EXEC_PATH=$(which ${1}) >/dev/null 2>&1 && printf 0 || printf 1
}

# Install groupmod
if [ $(get_exec groupmod) -ne 0 ]; then
    # Add groupmod tool
    apk add --update --no-cache shadow
    check_exit
    logSuccess "groupmod installed successfully"
else
    logInfo "groupmod already installled"
fi

# Sanity check to make sure the GID for docker group doesn't conflict with an exist group.
# Check docker group ID
if [ -z ${DOCKER_GROUP_ID} ]; then
    logError "Docker is not installed"
    exit 1
elif [ ${DOCKER_GROUP_ID} -ne ${REMOTE_DOCKER_GROUP_ID} ]; then
    groupmod -g ${REMOTE_DOCKER_GROUP_ID} docker
    check_exit
    logSuccess "Docker group configured successfully"
else
    logInfo "Docker group already configured"
fi

# Check group id on docker daemon
if [ ${DOCKER_DAEMON_GROUP_ID} -ne ${REMOTE_DOCKER_GROUP_ID} ]; then
    chown :${REMOTE_DOCKER_GROUP_ID} ${DOCKER_DAEMON_SOCKET}
    check_exit
    logSuccess "Docker daemon configured successfully"
else
    logInfo "Docker daemon already configured"
fi

SYSCTL_CMD="sysctl -w vm.max_map_count=262144"

# Add configuration for ELK
if grep -Fx "command=\"${SYSCTL_CMD}\"" /etc/wsl.conf > /dev/null; then
    logInfo "System configured for ELK"
else
echo "
[boot]
command=\"${SYSCTL_CMD}\"" | tee -a /etc/wsl.conf
fi

${SYSCTL_CMD}
