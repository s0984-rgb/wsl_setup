#!/bin/bash
# Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logger
logInternal() {
    local utcTime=`date -u -Iseconds`
    local color=${1}
    local level=${2}
    local message=${3}
    printf "${color}[${utcTime}] [${level}] ${message}${NC}\n"
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
    if [ ${exit_code} -ne 0 ]; then
        logError "Process failed at ${FUNCNAME[1]}. Exit code '${exit_code}'. See error above."
        exit ${exit_code}
    fi
}
