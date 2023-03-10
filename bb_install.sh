#!/bin/bash
#shellcheck disable=SC2220
#########################################################################
# Title:         Bizbox Install Script                                  #
# Author(s):     GrecoTechnology                                        #
# URL:           https://github.com/GrecoTechnology/bb                  #
# --                                                                    #
#########################################################################
#                   GNU General Public License v3.0                     #
#########################################################################

################################
# Variables
################################

VERBOSE=false
VERBOSE_OPT=""
SUPPORT=true
BB_REPO="https://github.com/GrecoTechnology/bb.git"
BB_PATH="/srv/git/bb"
BB_INSTALL_SCRIPT="$BB_PATH/bb_install.sh"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

################################
# Functions
################################

run_cmd () {
    if $VERBOSE; then
        printf '%s\n' "+ $*" >&2;
        "$@"
    else
        "$@" > /dev/null 2>&1
    fi
}

################################
# Argument Parser
################################

while getopts 'v-:' f; do
    case "${f}" in
    v)  VERBOSE=true
        VERBOSE_OPT="-v"
        ;;
    -)
        case "${OPTARG}" in
            no-support)
                SUPPORT=false
                ;;
        esac;;
    esac
done

################################
# Main
################################

# Check if Cloudbox is installed
# develop
if [ -d "/srv/git/cloudbox" ]; then
    echo "==== Cloudbox Install Detected ===="
    echo "Cloudbox installed. Exiting..."
    echo "==== Cloudbox Install Detected ===="
    exit 1
fi

# master
for directory in /home/*/*/ ; do
    base=$(basename "$directory")
    if [ "$base" == "cloudbox" ]; then
        echo "==== Cloudbox Install Detected ===="
        echo "Cloudbox installed. Exiting..."
        echo "==== Cloudbox Install Detected ===="
        exit 1
    fi
done

# Check for supported Ubuntu Releases
release=$(lsb_release -cs)

# Add more releases like (focal|jammy)$
if [[ $release =~ (focal|jammy)$ ]]; then
    echo "$release is currently supported."
elif [[ $release =~ (placeholder)$ ]]; then
    echo "$release is currently in testing."
else
    echo "==== UNSUPPORTED OS ===="
    if $SUPPORT; then
        echo "Install cancelled: $release is not supported."
        echo "Supported OS: 20.04 (focal) and 22.04 (jammy)"
        echo "==== UNSUPPORTED OS ===="
        exit 1
    else
        echo "Forcing install on $release."
        echo "You have chosen to ignore support."
        echo "Do not ask for support on our discord."
        echo "==== UNSUPPORTED OS ===="
        sleep 10
  fi
fi

# Check if using valid arch
arch=$(uname -m)

if [[ $arch =~ (x86_64)$ ]]; then
    echo "$arch is currently supported."
else
    echo "==== UNSUPPORTED CPU Architecture ===="
    echo "Install cancelled: $arch is not supported."
    echo "Supported CPU Architecture(s): x86_64"
    echo "==== UNSUPPORTED CPU Architecture ===="
    exit 1
fi

echo "Installing Bizbox Dependencies."

$VERBOSE || exec &>/dev/null

$VERBOSE && echo "Script Path: $SCRIPT_PATH"

# Update apt cache
run_cmd apt-get update

# Install git
run_cmd apt-get install -y git

# Remove existing repo folder
if [ -d "$BB_PATH" ]; then
    run_cmd rm -rf $BB_PATH;
fi

# Clone BB repo
run_cmd mkdir -p /srv/git
run_cmd git clone --branch master "${BB_REPO}" "$BB_PATH"

# Set chmod +x on script files
run_cmd chmod +x $BB_PATH/*.sh

$VERBOSE && echo "Script Path: $SCRIPT_PATH"
$VERBOSE && echo "BB Install Path: "$BB_INSTALL_SCRIPT

## Create script symlinks in /usr/local/bin
for i in "$BB_PATH"/*.sh; do
    if [ ! -f "/usr/local/bin/$(basename "${i%.*}")" ]; then
        run_cmd ln -s "${i}" "/usr/local/bin/$(basename "${i%.*}")"
    fi
done

# Install Bizbox Dependencies
run_cmd bash -H $BB_PATH/bb_dep.sh $VERBOSE_OPT

# Clone Bizbox Repo
run_cmd bash -H $BB_PATH/bb_repo.sh -b master $VERBOSE_OPT