#!/bin/bash

CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )" # Returns full path of the directory of the script 'build'.
source ${CUR_DIR}/commons.sh

# Run as user that you need to config WSL for

# Add user to sudoers file with no passwd
sudo grep ${USER} /etc/sudoers > /dev/null
if [ $? -ne 0 ]; then
    printf "${USER} ALL=(ALL:ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
else
    logInfo "sudo configured for user '${USER}'"
fi

# update everything
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoclean -y 

# Install docker-ce from repo
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    net-tools \
    socat \
    git

# Add Docker GPG key
if [ ! -d /etc/apt/keyrings ]; then
    sudo mkdir -m 0755 -p /etc/apt/keyrings
fi

if [ -f /etc/apt/keyrings/docker.gpg ]; then
    logInfo "Docker GPG key detected"
else
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

# Docker Setup Repo
if [ -f /etc/apt/sources.list.d/docker.list ]; then
    logInfo "Docker repo setup"
else
    printf \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
fi

# Install Docker engine
sudo apt-get update
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Add user to docker group
grep ${USER} /etc/group | grep docker > /dev/null
if [ $? -ne 0 ]; then
    sudo usermod -aG docker ${USER}
else
    logInfo "User configured for Docker user"
fi

# Configure Docker daemon
grep '"buildkit": true' /etc/docker/daemon.json > /dev/null
if [ $? -ne 0 ]; then
printf \
'{
    "hosts": ["unix:///var/run/docker.sock"],
    "features": {
        "buildkit": true
    }
}' | sudo tee /etc/docker/daemon.json > /dev/null
else
    logInfo "Docker daemon configured"
fi

# Docker on start-up
grep 'sudo /usr/sbin/service docker start > /dev/null' ${HOME}/.profile > /dev/null
if [ $? -ne 0 ]; then
    printf << EOF >> ${HOME}/.profile
if ! sudo /usr/sbin/service docker status > /dev/null; then
    sudo /usr/sbin/service docker start > /dev/null
fi
EOF
else
    logInfo "Docker configured for startup"
fi

# Ensure SSH on startup
grep "check-ssh-agent" ${HOME}/.profile > /dev/null
if [ $? -ne 0 ]; then
    printf << EOF >> ${HOME}/.profile
check-ssh-agent() {
    [ -S "$SSH_AUTH_SOCK" ] && { ssh-add -l >& /dev/null || [ $? -ne 2 ]; }
}
check-ssh-agent || export SSH_AUTH_SOCK=~/.ssh/agent.sock
check-ssh-agent || { rm -f $SSH_AUTH_SOCK; eval "$(ssh-agent -s -a $SSH_AUTH_SOCK)" > /dev/null; }
EOF
else
    logInfo "SSH agent configured"
fi

# Custom Bash prompt and commands
grep "parse_git_branch()" ${HOME}/.bashrc > /dev/null
if [ $? -ne 0 ]; then
    printf << EOF >> ${HOME}/.bashrc
# some more ls aliases
alias lsa='ls -alFh'
alias cls='clear'
alias vi='vim'
alias k='kubectl'
alias k8s='kubectl config set-context --current --namespace '

# Parse git branch for 
parse_git_branch() {
    git branch 2> /dev/null | grep \* | awk '{ print " git:(" \$2 ")" }'
}

export PS1="[\[\033[36m\]\u\[\033[00m\]@\[\033[33m\]\h\[\033[00m\]:\[\033[31m\]\W\[\033[32m\]\$(parse_git_branch)\[\033[00m\]] $ "
EOF
else
    logInfo "Bash shell configured"
fi

# Install FZF
if [ ! -d ${HOME}/.fzf ]; then
    git clone --depth 1 https://github.com/junegunn/fzf.git ${HOME}/.fzf
    ${HOME}/.fzf/install
fi

#################
##### GPG #######
#################

# Download & install https://www.gpg4win.org/
PINENTRY_LOCATION=/mnt/c/Program\ Files\ \(x86\)/Gpg4win/bin/pinentry.exe
ls "${PINENTRY_LOCATION}" > /dev/null
if [ $? -eq 0 ]; then
    grep "pinentry-program ${PINENTRY_LOCATION}" ${HOME}/.gnupg/gpg-agent.conf > /dev/null
    if [ $? -ne 0 ]; then
        mkdir -p ~/.gnupg
        echo "pinentry-program ${PINENTRY_LOCATION}" > ${HOME}/.gnupg/gpg-agent.conf
        chmod -R go-rwx ~/.gnupg
        logSuccess "GPG configured on host"
        logWarning "Manual intervention required! Follow instructions on https://docs.gitlab.com/ee/user/project/repository/gpg_signed_commits/#generating-a-gpg-key to generate GPG key."
    else
        logInfo "GPG agent configured"
    fi
else
    logError "Cannot find '${PINENTRY_LOCATION}'. Download 'https://www.gpg4win.org/'."
    exit 1
fi


grep 'gpg-agent --homedir ~/.gnupg --daemon' ${HOME}/.profile > /dev/null
if [ $? -ne 0 ]; then
    printf "if ! pidof gpg-agent >& /dev/null; then gpg-agent --homedir ~/.gnupg --daemon;fi" >> ${HOME}/.profile
else
    logInfo "GPG agent startup configured"
fi

#################
#### Kubectl ####
#################
if [ ! -f /etc/apt/keyrings/kubernetes-archive-keyring.gpg ]; then
    sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
fi

grep 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' /etc/apt/sources.list.d/kubernetes.list > /dev/null
if [ $? -ne 0 ]; then
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
fi

sudo apt update
sudo apt install -y --allow-downgrades kubectl=1.21.8-00

# Kubectx + Kubens
if [ ! -d ${HOME}/kubectx ]; then
    sudo git clone https://github.com/ahmetb/kubectx ${HOME}/kubectx
fi
if [ ! -f /usr/local/bin/kubectx ]; then
    sudo ln -s ${HOME}/kubectx/kubectx /usr/local/bin/kubectx
fi
if [ ! -f /usr/local/bin/kubens ]; then
    sudo ln -s ${HOME}/kubectx/kubens /usr/local/bin/kubens
fi
