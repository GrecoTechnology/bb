#!/bin/bash
#########################################################################
# Title:         Bizbox: BB Script                                      #
# Author(s):     GrecoTechnology                                        #
# URL:           https://github.com/GrecoTechnology/bb                  #
# --                                                                    #
#########################################################################
#                   GNU General Public License v3.0                     #
#########################################################################

################################
# Privilege Escalation
################################

# Restart script in SUDO
# https://unix.stackexchange.com/a/28793

if [ $EUID != 0 ]; then
    sudo "$0" "$@"
    exit $?
fi

################################
# Scripts
################################

source /srv/git/bb/yaml.sh
create_variables /srv/git/bizbox/accounts.yml
################################
# Variables
################################

# Ansible
ANSIBLE_PLAYBOOK_BINARY_PATH="/usr/local/bin/ansible-playbook"

# Bizbox
BIZBOX_REPO_PATH="/srv/git/bizbox"
BIZBOX_PLAYBOOK_PATH="$BIZBOX_REPO_PATH/bizbox.yml"

# Sandbox
SANDBOX_REPO_PATH="/opt/sandbox"
SANDBOX_PLAYBOOK_PATH="$SANDBOX_REPO_PATH/sandbox.yml"

# Bizbox_mod
BIZBOXMOD_REPO_PATH="/opt/bizbox_mod"
BIZBOXMOD_PLAYBOOK_PATH="$BIZBOXMOD_REPO_PATH/bizbox_mod.yml"

# BB
BB_REPO_PATH="/srv/git/bb"

################################
# Functions
################################

git_fetch_and_reset () {

    git fetch --quiet >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git checkout --quiet "${BIZBOX_BRANCH:-master}" >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git submodule update --init --recursive
    chmod 664 "${BIZBOX_REPO_PATH}/ansible.cfg"
    # shellcheck disable=SC2154
    chown -R "${user_name}":"${user_name}" "${BIZBOX_REPO_PATH}"
}

git_fetch_and_reset_sandbox () {

    git fetch --quiet >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git checkout --quiet "${SANDBOX_BRANCH:-master}" >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git submodule update --init --recursive

    if [[ ! -f "${SANDBOX_REPO_PATH}/ansible.cfg" ]]
    then
        cp "${SANDBOX_REPO_PATH}/defaults/ansible.cfg.default" "${SANDBOX_REPO_PATH}/ansible.cfg"
    fi

    chmod 664 "${SANDBOX_REPO_PATH}/ansible.cfg"
    chown -R "${user_name}":"${user_name}" "${SANDBOX_REPO_PATH}"
}

git_fetch_and_reset_bb () {

    git fetch --quiet >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git checkout --quiet master >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git submodule update --init --recursive
    chmod 775 "${BB_REPO_PATH}/bb.sh"
}

run_playbook_bb () {

    local arguments=$*

    cd "${BIZBOX_REPO_PATH}" || exit

    # shellcheck disable=SC2086
    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
        "${BIZBOX_PLAYBOOK_PATH}" \
        --become \
        ${arguments}

    cd - >/dev/null || exit

}

run_playbook_sandbox () {

    local arguments=$*

    cd "${SANDBOX_REPO_PATH}" || exit

    # shellcheck disable=SC2086
    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
        "${SANDBOX_PLAYBOOK_PATH}" \
        --become \
        ${arguments}

    cd - >/dev/null || exit

}

run_playbook_bizboxmod () {

    local arguments=$*

    cd "${BIZBOXMOD_REPO_PATH}" || exit

    # shellcheck disable=SC2086
    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
        "${BIZBOXMOD_PLAYBOOK_PATH}" \
        --become \
        ${arguments}

    cd - >/dev/null || exit

}

install () {

    local arg=("$@")

    if [ -z "$arg" ]
    then
      echo -e "No install tag was provided.\n"
      usage
      exit 1
    fi

    echo "${arg[*]}"

    # Remove space after comma
    # shellcheck disable=SC2128,SC2001
    local arg_clean
    arg_clean=${arg//, /,}

    # Split tags from extra arguments
    # https://stackoverflow.com/a/10520842
    local re="^(\S+[.].\S+)?\s([^-]+)?\s?(--primary)?(-.*)?$"
    if [[ "$arg_clean" =~ $re ]]; then
        local domain="${BASH_REMATCH[1]}"
        local tags_arg="${BASH_REMATCH[2]}"
        local primary_domain="${BASH_REMATCH[3]}"
        local extra_arg="${BASH_REMATCH[4]}"
    else
        tags_arg="$arg_clean"
    fi

    # Save tags into 'tags' array
    # shellcheck disable=SC2206
    local tags_tmp=(${tags_arg//,/ })

    # Remove duplicate entries from array
    # https://stackoverflow.com/a/31736999
    local tags=()
    readarray -t tags < <(printf '%s\n' "${tags_tmp[@]}" | awk '!x[$0]++')

    # Build BB/Sandbox/Bizbox-mod tag arrays
    local tags_bb
    local tags_sandbox
    local tags_bizboxmod

    for i in "${!tags[@]}"
    do
        if [[ ${tags[i]} == sandbox-* ]]; then
            tags_sandbox="${tags_sandbox}${tags_sandbox:+,}${tags[i]##sandbox-}"

        elif [[ ${tags[i]} == mod-* ]]; then
            tags_bizboxmod="${tags_bizboxmod}${tags_bizboxmod:+,}${tags[i]##mod-}"

        else
            tags_bb="${tags_bb}${tags_bb:+,}${tags[i]}"

        fi
    done
    if [[ $primary_domain == "--primary" && "X${domain}" != "X" ]]; then
	    run_playbook_bb "--tags traefik,portainer -e domain=$domain"
    fi

    # Bizbox Ansible Playbook
    if [[ -n "$tags_bb" ]]; then
        # Build arguments
        local arguments_bb="--tags $tags_bb"

        if [[ "X${domain}" != "X" ]]; then
            extra_arg="${extra_arg} -e domain=$domain"
        fi

        if [[ -n "$extra_arg" ]]; then
            arguments_bb="${arguments_bb} ${extra_arg}"
        fi

        # Run playbook
        echo ""
        echo "Running Bizbox Tags: ${tags_bb//,/,  }"
        echo ""
        run_playbook_bb "$arguments_bb"
        echo ""

    fi

    # Sandbox Ansible Playbook
    if [[ -n "$tags_sandbox" ]]; then
        # Build arguments
        local arguments_sandbox="--tags $tags_sandbox"

        if [[ "X${domain}" != "X" ]]; then
            extra_arg="${extra_arg} -e domain=$domain"

        fi

        if [[ -n "$extra_arg" ]]; then
            arguments_sandbox="${arguments_sandbox} ${extra_arg}"
        fi

        # Run playbook
        echo "========================="
        echo ""
        echo "Running Sandbox Tags: ${tags_sandbox//,/,  }"
        echo ""
        run_playbook_sandbox "$arguments_sandbox"
        echo ""
    fi

    # Bizbox_mod Ansible Playbook
    if [[ -n "$tags_bizboxmod" ]]; then

        # Build arguments
        local arguments_bizboxmod="--tags $tags_bizboxmod"

        if [[ "X${domain}" != "X" ]]; then
            extra_arg="${extra_arg} -e domain=$domain"
        fi

        if [[ -n "$extra_arg" ]]; then
            arguments_bizboxmod="${arguments_bizboxmod} ${extra_arg}"
        fi

        # Run playbook
        echo "========================="
        echo ""
        echo "Running Bizbox_mod Tags: ${tags_bizboxmod//,/,  }"
        echo ""
        run_playbook_bizboxmod "$arguments_bizboxmod"
        echo ""
    fi

}

update_domain_usage (){
  echo "Usage:"
  echo "    bb update domain.tld app                    Update application env file and restart container."
}

update_domain_app (){
  local re="^(\S+[.].\S+){1}\s(\S+){1}$"
  local args=${*}
  if [[ "$args" =~ $re ]]
  then
    local domain="${BASH_REMATCH[1]}"
    local app="${BASH_REMATCH[2]}"
    if [[ "X${app}" == "Xinvoiceninja" ]]; then
      app="invoice"
    fi
  else
    echo "Invalid domain: $args"
    echo ""
    update_domain_usage
    exit 1
  fi
  local container_name="${domain//./-}-${app}"
  local envfile="/opt/${domain}/${app}/env.yml"
  nano envfile

  install "$domain $app"
}

update () {
    if [[ -d "${BIZBOX_REPO_PATH}" ]]
    then
        echo -e "Updating Bizbox...\n"

        cd "${BIZBOX_REPO_PATH}" || exit

        git_fetch_and_reset

        run_playbook_bb "--tags settings" && echo -e '\n'

        echo -e "Update Completed."
    else
        echo -e "Bizbox folder not present."
    fi

}

sandbox-update () {

    if [[ -d "${SANDBOX_REPO_PATH}" ]]
    then
        echo -e "Updating Sandbox...\n"

        cd "${SANDBOX_REPO_PATH}" || exit

        git_fetch_and_reset_sandbox

        run_playbook_sandbox "--tags settings" && echo -e '\n'

        echo -e "Update Completed."
    fi

}

bb-update () {

    echo -e "Updating bb...\n"

    cd "${BB_REPO_PATH}" || exit

    git_fetch_and_reset_bb

    echo -e "Update Completed."

}

bb-list ()  {

    if [[ -d "${BIZBOX_REPO_PATH}" ]]
    then
        echo -e "Bizbox tags:\n"

        cd "${BIZBOX_REPO_PATH}" || exit

        "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
            "${BIZBOX_PLAYBOOK_PATH}" \
            --become \
            --list-tags --skip-tags "always" 2>&1 | grep "TASK TAGS" | cut -d":" -f2 | awk '{sub(/\[/, "")sub(/\]/, "")}1' | cut -c2-

        echo -e "\n"

        cd - >/dev/null || exit
    else
        echo -e "Bizbox folder not present.\n"
    fi

}

sandbox-list () {

    if [[ -d "${SANDBOX_REPO_PATH}" ]]
    then
        echo -e "Sandbox tags (prepend sandbox-):\n"

        cd "${SANDBOX_REPO_PATH}" || exit
        "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
            "${SANDBOX_PLAYBOOK_PATH}" \
            --become \
            --list-tags --skip-tags "always,sanity_check" 2>&1 | grep "TASK TAGS" | cut -d":" -f2 | awk '{sub(/\[/, "")sub(/\]/, "")}1' | cut -c2-

        echo -e "\n"

        cd - >/dev/null || exit
    fi

}

bizboxmod-list () {

    if [[ -d "${BIZBOXMOD_REPO_PATH}" ]]
    then
        echo -e "Bizbox_mod tags (prepend mod-):\n"

        cd "${BIZBOXMOD_REPO_PATH}" || exit
        "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
            "${BIZBOXMOD_PLAYBOOK_PATH}" \
            --become \
            --list-tags --skip-tags "always,sanity_check" 2>&1 | grep "TASK TAGS" | cut -d":" -f2 | awk '{sub(/\[/, "")sub(/\]/, "")}1' | cut -c2-

        echo -e "\n"

        cd - >/dev/null || exit
    fi

}

bizbox-branch () {
    if [[ -d "${BIZBOX_REPO_PATH}" ]]
    then
        echo -e "Changing Bizbox branch to $1...\n"

        cd "${BIZBOX_REPO_PATH}" || exit

        BIZBOX_BRANCH=$1

        git_fetch_and_reset

        run_playbook_bb "--tags settings" && echo -e '\n'

        echo -e "Update Completed."
    else
        echo -e "Bizbox folder not present."
    fi
}

sandbox-branch () {

    if [[ -d "${SANDBOX_REPO_PATH}" ]]
    then
        echo -e "Changing Sandbox branch to $1...\n"

        cd "${SANDBOX_REPO_PATH}" || exit

        SANDBOX_BRANCH=$1

        git_fetch_and_reset_sandbox

        run_playbook_sandbox "--tags settings" && echo -e '\n'

        echo -e "Update Completed."
    fi

}

list () {
    bb-list
    sandbox-list
    bizboxmod-list
}

update-ansible () {
    bash "/srv/git/bizbox/scripts/update.sh"
}

backup (){
  local arg=("$@")

    if [ -z "$arg" ]
    then
      echo -e "No Backup tag was provided.\n"
      usage
      exit 1
    fi

    echo "${arg[*]}"

    # Remove space after comma
    # shellcheck disable=SC2128,SC2001
    local arg_clean
    arg_clean=${arg//, /,}

    # Split tags from extra arguments
    # https://stackoverflow.com/a/10520842
    local re="^(\S+[.].\S+)?\s([^-]+)?\s?(--all)?$"
    if [[ "$arg_clean" =~ $re ]]; then
        local domain="${BASH_REMATCH[1]}"
        local tags_arg="${BASH_REMATCH[2]}"
        local all="${BASH_REMATCH[3]}"
    else
        echo "Invalid arguments"
        usage
        exit 1
    fi

    if [[ "X${domain}" != "X" ]]; then
	    extra_arg="-e domain=$domain"
    fi

    if [[ "$all" == "--all" ]]
    then
	    extra_arg="$extra_arg -e all=true"
	  else
	    extra_arg="$extra_arg -e all=false"
    fi

    if [[ -n $tags_arg ]]; then
	    extra_arg="$extra_arg -e apps=$tags_arg"
    fi

    local arguments_bb="--tags backup"

    if [[ -n "$extra_arg" ]]; then
      arguments_bb="${arguments_bb} ${extra_arg}"
    fi

    # Run playbook
        echo ""
        echo "Running Bizbox Tags: ${tags_arg//,/,  }"
        echo ""
        run_playbook_bb "$arguments_bb"
        echo ""
}

uninstall (){
  local arg=("$@")

    if [ -z "$arg" ]
    then
      echo -e "No Uninstall tag was provided.\n"
      usage
      exit 1
    fi

    echo "${arg[*]}"

    # Remove space after comma
    # shellcheck disable=SC2128,SC2001
    local arg_clean
    arg_clean=${arg//, /,}

    # Split tags from extra arguments
    # https://stackoverflow.com/a/10520842
    local re="^(\S+[.].\S+)?\s([^-]+)?\s?(--all)?$"
    if [[ "$arg_clean" =~ $re ]]; then
        local domain="${BASH_REMATCH[1]}"
        local tags_arg="${BASH_REMATCH[2]}"
        local all="${BASH_REMATCH[3]}"
    else
        echo "Invalid arguments"
        usage
        exit 1
    fi

    if [[ "X${domain}" != "X" ]]; then
	    extra_arg="-e domain=$domain"
    fi

    if [[ "$all" == "--all" ]]
    then
	    extra_arg="$extra_arg -e all=true"
	  else
	    extra_arg="$extra_arg -e all=false"
    fi

    if [[ -n $tags_arg ]]; then
	    extra_arg="$extra_arg -e apps=$tags_arg"
    fi

    local arguments_bb="--tags uninstall"

    if [[ -n "$extra_arg" ]]; then
      arguments_bb="${arguments_bb} ${extra_arg}"
    fi

    # Run playbook
        echo ""
        echo "Running Bizbox Tags: ${tags_arg//,/,  }"
        echo ""
        run_playbook_bb "$arguments_bb"
        echo ""
}

restart (){
  local arg=("$@")

  if [ -z "$arg" ]
    then
      echo -e "No Restart tag was provided.\n"
      usage
      exit 1
    fi
  echo "${arg[*]}"

  local arg_clean
  arg_clean=${arg//, /,}

  # Split tags from extra arguments
  # https://stackoverflow.com/a/10520842
  local re="^(\S+[.].\S+)?\s([^-]+)?$"
  if [[ "$arg_clean" =~ $re ]]; then
      local domain="${BASH_REMATCH[1]}"
      local tags_arg="${BASH_REMATCH[2]}"
  else
      echo "Invalid arguments"
      usage
      exit 1
  fi

  # Save tags into 'tags' array
  # shellcheck disable=SC2206
  local tags_tmp=(${tags_arg//,/ })

  # Remove duplicate entries from array
  # https://stackoverflow.com/a/31736999
  local tags=()
  readarray -t tags < <(printf '%s\n' "${tags_tmp[@]}" | awk '!x[$0]++')

  local apps=""

  for i in "${!tags[@]}"
  do
    apps="${apps} ${domain//./-}-${tags[i]}"
  done

  docker restart ${apps}
}

reinstall (){
  local arg=("$@")

    if [ -z "$arg" ]
    then
      echo -e "No Reinstall tag was provided.\n"
      usage
      exit 1
    fi

    echo "${arg[*]}"

    # Remove space after comma
    # shellcheck disable=SC2128,SC2001
    local arg_clean
    arg_clean=${arg//, /,}

    # Split tags from extra arguments
    # https://stackoverflow.com/a/10520842
    local re="^(\S+[.].\S+)?\s([^-]+)?\s?((--all|--force)?\s?(--all|--force)?)?$"
    if [[ "$arg_clean" =~ $re ]]; then
        local domain="${BASH_REMATCH[1]}"
        local tags_arg="${BASH_REMATCH[2]}"
        local flags="${BASH_REMATCH[3]}"
    else
        echo "Invalid arguments"
        usage
        exit 1
    fi

    if [[ "X${domain}" != "X" ]]; then
	    extra_arg="-e domain=$domain"
    fi

    if [[ "$flags" == *--all* ]]
    then
	    extra_arg="$extra_arg -e all=true"
	  else
	    extra_arg="$extra_arg -e all=false"
    fi

    if [[ "$flags" == *--force* ]]
    then
	    extra_arg="$extra_arg -e force=true"
	  else
	    extra_arg="$extra_arg -e force=false"
    fi

    if [[ -n $tags_arg ]]; then
	    extra_arg="$extra_arg -e apps=$tags_arg"
    fi

    local arguments_bb="--tags reinstall"

    if [[ -n "$extra_arg" ]]; then
      arguments_bb="${arguments_bb} ${extra_arg}"
    fi

    # Run playbook
        echo ""
        echo "Running Bizbox Tags: ${tags_arg//,/,  }"
        echo ""
        run_playbook_bb "$arguments_bb"
        echo ""
}

clone (){
  local arg=("$@")

    if [ -z "$arg" ]
    then
      echo -e "No Clone tag was provided.\n"
      usage
      exit 1
    fi

    echo "${arg[*]}"

    # Remove space after comma
    # shellcheck disable=SC2128,SC2001
    local arg_clean
    arg_clean=${arg//, /,}

    # Split tags from extra arguments
    # https://stackoverflow.com/a/10520842
    local re="^(\S+[.].\S+){1}\s(\S+[.].\S+){1}\s([^-]+)?\s?(--all)?$"
    if [[ "$arg_clean" =~ $re ]]; then
        local src_domain="${BASH_REMATCH[1]}"
        local dst_domain="${BASH_REMATCH[2]}"
        local tags_arg="${BASH_REMATCH[3]}"
        local all="${BASH_REMATCH[4]}"
    else
        echo "Invalid arguments"
        usage
        exit 1
    fi

    if [[ "X${src_domain}" != "X" ]]; then
	    extra_arg="-e src_domain=$src_domain"
    fi

    if [[ "X${dst_domain}" != "X" ]]; then
	    extra_arg="$extra_arg -e domain=$dst_domain"
    fi

    if [[ "$all" == "--all" ]]
    then
	    extra_arg="$extra_arg -e all=true"
	  else
	    extra_arg="$extra_arg -e all=false"
    fi

    if [[ -n $tags_arg ]]; then
	    extra_arg="$extra_arg -e apps=$tags_arg"
    fi

    local arguments_bb="--tags clone"

    if [[ -n "$extra_arg" ]]; then
      arguments_bb="${arguments_bb} ${extra_arg}"
    fi

    # Run playbook
        echo ""
        echo "Running Bizbox Tags: ${tags_arg//,/,  }"
        echo ""
        run_playbook_bb "$arguments_bb"
        echo ""

}

usage () {
    echo "Usage:"
    echo -e "    bb update-bb                                                              Update bb Cli.\n"
    echo -e "    bb update                                                                 Update Bizbox.\n"
    echo -e "    bb list                                                                   List Bizbox tags.\n"
    echo -e "    bb install <domain name> <tags> [--primary]                               Install <tags> using <domain name>."
    echo -e "        example: bb install domain.tld wordpress,invoiceninja --primary\n"
    echo -e "    bb clone <source domain name> <destination domain name> [tags] [--all]    Clone [tags] using <source domain name> to <destination domain name>."
    echo -e "        example: bb clone src-domain.tld dst-domain.tld wordpress,invoiceninja\n"
    echo -e "    bb uninstall <domain name> [tags] [--all]                                 Uninstall [tags] using <domain name>."
    echo -e "        example: bb uninstall domain.tld wordpress,invoiceninja\n"
    echo -e "    bb reinstall <domain name> [tags] [--all] [--force]                       Reinstall [tags] using <domain name>."
    echo -e "        example: bb reinstall domain.tld wordpress,invoiceninja\n"
    echo -e "    bb restart <domain name> <tags>                                           Restart   <tags> using <domain name>."
    echo -e "        example: bb restart domain.tld wordpress,invoiceninja\n"
    echo -e "    bb update-ansible                                                         Re-install Ansible.\n"
}


################################
# Update check
################################

################################
# Argument Parser
################################

# https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/

roles=""  # Default to empty role

# Parse options
while getopts ":h" opt; do
  case ${opt} in
    h)
        usage
        exit 0
        ;;
   \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        echo ""
        usage
        exit 1
        ;;
  esac
done
shift $((OPTIND -1))

# Parse commands
subcommand=$1; shift  # Remove 'bb' from the argument list
case "$subcommand" in

  # Parse options to the various sub commands
    list)
        list
        ;;
    update)
        update
        sandbox-update
        ;;
    update-bb)
        bb-update
        ;;
    install)
        parameters=${*}
        install "${parameters}"
        ;;
    branch)
        bizbox-branch "${*}"
        ;;
    sandbox-branch)
        sandbox-branch "${*}"
        ;;
    update-ansible)
        update-ansible
        ;;
    backup)
        backup "${*}"
        ;;
    uninstall)
        uninstall "${*}"
        ;;
    clone)
        clone "${*}"
        ;;
    reinstall)
        reinstall "${*}"
        ;;
    restart)
        restart "${*}"
        ;;
    "") echo "A command is required."
        echo ""
        usage
        exit 1
        ;;
    *)
        echo "Invalid Command: $subcommand"
        echo ""
        usage
        exit 1
        ;;
esac