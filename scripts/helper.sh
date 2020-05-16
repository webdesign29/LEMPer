#!/usr/bin/env bash

# Helper Functions
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 17/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Export environment variables.
if [ -f ".env" ]; then
    # Clean environemnt first.
    # shellcheck source=.env.dist
    # shellcheck disable=SC2046
    unset $(grep -v '^#' .env | grep -v '^\[' | sed -E 's/(.*)=.*/\1/' | xargs)

    # shellcheck source=.env.dist
    # shellcheck disable=SC1094
    source <(grep -v '^#' .env | grep -v '^\[' | sed -E 's|^(.+)=(.*)$|: ${\1=\2}; export \1|g')
else
    echo "Environment variables required, but the dotenv file doesn't exist. Copy .env.dist to .env first!"
    exit 1
fi

# Direct access? make as dryrun mode.
DRYRUN=${DRYRUN:-true}

# Init timezone, set default to UTC.
TIMEZONE=${TIMEZONE:-"UTC"}

# Set default color decorator.
RED=31
GREEN=32
YELLOW=33

function begin_color() {
    color="$1"
    echo -e -n "\e[${color}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    color="$1"
    shift
    begin_color "$color"
    echo "$@"
    end_color
}

function error() {
    echo_color "$RED" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"

    # Normally I'd use $0 in "usage" here, but since most people will be running
    # this via curl, that wouldn't actually give something useful.
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function status() {
    echo_color "$GREEN" "$@"
}

function warning() {
    echo_color "$YELLOW" "$@"
}

# If we set -e or -u then users of this script will see it silently exit on
# failure.  Instead we need to check the exit status of each command manually.
# The run function handles exit-status checking for system-changing commands.
# Additionally, this allows us to easily have a dryrun mode where we don't
# actually make any changes.
function run() {
    if "$DRYRUN"; then
        echo_color "$YELLOW" -n "would run "
        echo "$@"
    else
        if ! "$@"; then
            local CMDSTR="$*"
            error "Failure running '${CMDSTR}', exiting."
            exit 1
        fi
    fi
}

function redhat_is_installed() {
    local package_name="$1"
    rpm -qa "$package_name" | grep -q .
}

function debian_is_installed() {
    local package_name="$1"
    dpkg -l "$package_name" | grep ^ii | grep -q .
}

# Usage:
# install_dependencies install_pkg_cmd is_pkg_installed_cmd dep1 dep2 ...
#
# install_pkg_cmd is a command to install a dependency
# is_pkg_installed_cmd is a command that returns true if the dependency is
# already installed
# each dependency is a package name
function install_dependencies() {
    local install_pkg_cmd="$1"
    local is_pkg_installed_cmd="$2"
    shift 2

    local missing_dependencies=""

    for package_name in "$@"; do
        if ! "$is_pkg_installed_cmd" "$package_name"; then
            missing_dependencies+="$package_name "
        fi
    done
    if [ -n "$missing_dependencies" ]; then
        status "Detected that we're missing the following depencencies:"
        echo " $missing_dependencies"
        status "Installing them:"
        run sudo "$install_pkg_cmd" "$missing_dependencies"
    fi
}

function gcc_too_old() {
    # We need gcc >= 4.8
    local gcc_major_version && \
    gcc_major_version=$(gcc -dumpversion | awk -F. '{print $1}')
    if [ "$gcc_major_version" -lt 4 ]; then
        return 0 # too old
    elif [ "$gcc_major_version" -gt 4 ]; then
        return 1 # plenty new
    fi
    # It's gcc 4.x, check if x >= 8:
    local gcc_minor_version && \
    gcc_minor_version=$(gcc -dumpversion | awk -F. '{print $2}')
    test "$gcc_minor_version" -lt 8
}

function continue_or_exit() {
    local prompt="$1"
    echo_color "$YELLOW" -n "$prompt"
    read -rp " [y/n] " yn
    if [[ "$yn" == N* || "$yn" == n* ]]; then
        echo "Cancelled."
        exit 0
    fi
}

# If a string is very simple we don't need to quote it.    But we should quote
# everything else to be safe.
function needs_quoting() {
    echo "$@" | grep -q '[^a-zA-Z0-9./_=-]'
}

function escape_for_quotes() {
    echo "$@" | sed -e 's~\\~\\\\~g' -e "s~'~\\\\'~g"
}

function quote_arguments() {
    local argument_str=""
    for argument in "$@"; do
        if [ -n "$argument_str" ]; then
            argument_str+=" "
        fi
        if needs_quoting "$argument"; then
            argument="'$(escape_for_quotes "$argument")'"
        fi
        argument_str+="$argument"
    done
    echo "$argument_str"
}

function version_sort() {
    # We'd rather use sort -V, but that's not available on Centos 5.    This works
    # for versions in the form A.B.C.D or shorter, which is enough for our use.
    sort -t '.' -k 1,1 -k 2,2 -k 3,3 -k 4,4 -g
}

# Compare two numeric versions in the form "A.B.C".    Works with version numbers
# having up to four components, since that's enough to handle both nginx (3) and
# ngx_pagespeed (4).
function version_older_than() {
    local test_version && \
    test_version=$(echo "$@" | tr ' ' '\n' | version_sort | head -n 1)
    local compare_to="$2"
    local older_version="${test_version}"

    test "$older_version" != "$compare_to"
}

function nginx_download_report_error() {
    fail "Couldn't automatically determine the latest nginx version: failed to $* Nginx's download page"
}

function get_nginx_versions_available() {
    # Scrape nginx's download page to try to find the all available nginx versions.
    nginx_download_url="https://nginx.org/en/download.html"

    local nginx_download_page
    nginx_download_page=$(curl -sS --fail "$nginx_download_url") || \
        nginx_download_report_error "download"

    local download_refs
    download_refs=$(echo "$nginx_download_page" | \
        grep -owE '"/download/nginx-[0-9.]*\.tar\.gz"') || \
        nginx_download_report_error "parse"

    versions_available=$(echo "$download_refs" | \
        sed -e 's~^"/download/nginx-~~' -e 's~\.tar\.gz"$~~') || \
        nginx_download_report_error "extract versions from"

    echo "$versions_available"
}

# Try to find the most recent nginx version (mainline).
function determine_latest_nginx_version() {
    local versions_available
    local latest_version

    versions_available=$(get_nginx_versions_available)
    latest_version=$(echo "$versions_available" | version_sort | tail -n 1) || \
        report_error "determine latest (mainline) version from"

    if version_older_than "$latest_version" "1.14.2"; then
        fail "Expected the latest version of nginx to be at least 1.14.2 but found
$latest_version on $nginx_download_url"
    fi

    echo "$latest_version"
}

# Try to find the stable nginx version (mainline).
function determine_stable_nginx_version() {
    local versions_available
    local stable_version

    versions_available=$(get_nginx_versions_available)
    stable_version=$(echo "$versions_available" | version_sort | tail -n 2 | sort -r | tail -n 1) || \
        report_error "determine stable (LTS) version from"

    if version_older_than "1.14.2" "$latest_version"; then
        fail "Expected the latest version of nginx to be at least 1.14.2 but found
$latest_version on $nginx_download_url"
    fi

    echo "$stable_version"
}

# Validate Nginx configuration.
function validate_nginx_config() {
    if nginx -t 2>/dev/null > /dev/null; then
        echo "true" # success
    else
        echo "false" # error
    fi
}

# Validate FQDN domain.
function validate_fqdn() {
    local FQDN=${1}

    if grep -qP '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)' <<< "${FQDN}"; then
        echo true # success
    else
        echo false # error
    fi
}

##
# Make sure only root can run LEMPer script.
#
function requires_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This command can only be used by root."
        exit 1
    fi
}

##
# Make sure only supported distribution can run this installer script.
#
function system_check() {
    export DISTRIB_NAME && DISTRIB_NAME=$(get_distrib_name)
    export RELEASE_NAME && RELEASE_NAME=$(get_release_name)

    if [[ "${RELEASE_NAME}" == "unsupported" ]]; then
        fail "This Linux distribution isn't supported yet. If you'd like it to be, let us know at https://github.com/joglomedia/LEMPer/issues"
    else
        # Set system architecture.
        export ARCH && \
        ARCH=$(uname -p)

        # Set default timezone.
        export TIMEZONE
        if [[ -z "${TIMEZONE}" || "${TIMEZONE}" = "none" ]]; then
            [ -f /etc/timezone ] && TIMEZONE=$(cat /etc/timezone) || TIMEZONE="UTC"
        fi

        # Set ethernet interface.
        export IFACE && \
        IFACE=$(find /sys/class/net -type l | grep -e "enp\|eth0" | cut -d'/' -f5)

        # Set server IP.
        export SERVER_IP && \
        SERVER_IP=${SERVER_IP:-$(get_ip_addr)}

        # Set server hostname.
        if [ -z "${HOSTNAME}" ]; then
            export HOSTNAME && \
            HOSTNAME=$(hostname)
        fi

        # Validate server's hostname for production stack.
        if [[ "${ENVIRONMENT}" = "production" ]]; then
            # Check if the hostname is valid.
            if [[ $(validate_fqdn "${HOSTNAME}") != true ]]; then
                error "Your server's hostname is not fully qualified domain name (FQDN)."
                echo -e "Please update your hostname to qualify the FQDN format and\nthen points your hostname to this server ip ${SERVER_IP} !"
                exit 1
            fi

            # Check if the hostname is pointed to server IP address.
            if [[ $(dig "${HOSTNAME}" +short) != "${SERVER_IP}" ]]; then
                error "It seems that your server's hostname is not yet pointed to your server's IP address."
                echo -e "Please update your DNS record by adding an A record and point it to your server IP ${SERVER_IP} !"
                exit 1
            fi
        fi
    fi
}

function delete_if_already_exists() {
     if "$DRYRUN"; then return; fi

    local directory="$1"
    if [ -d "$directory" ]; then
        if [ ${#directory} -lt 8 ]; then
            fail "Not deleting $directory; name is suspiciously short. Something is wrong."
        fi

        continue_or_exit "OK to delete $directory?"
        run rm -rf "$directory"
    fi
}

# Get general distribution name.
function get_distrib_name() {
    if [ -f "/etc/os-release" ]; then
        # Export os-release vars.
        . /etc/os-release

        # Export lsb-release vars.
        [ -f /etc/lsb-release ] && . /etc/lsb-release

        # Get distribution name.
        [[ "${ID_LIKE}" == "ubuntu" ]] && DISTRIB_NAME="ubuntu" || DISTRIB_NAME=${ID:-"unsupported"}
    elif [ -e /etc/system-release ]; then
    	DISTRIB_NAME="unsupported"
    else
        # Red Hat /etc/redhat-release
    	DISTRIB_NAME="unsupported"
    fi

    echo "${DISTRIB_NAME}"
}

# Get general release name.
function get_release_name() {
    if [ -f "/etc/os-release" ]; then
        # Export os-release vars.
        . /etc/os-release

        # Export lsb-release vars.
        [ -f /etc/lsb-release ] && . /etc/lsb-release

        # Get distribution name.
        [[ "${ID_LIKE}" == "ubuntu" ]] && DISTRIB_NAME="ubuntu" || DISTRIB_NAME=${ID:-"unsupported"}

        case ${DISTRIB_NAME} in
            debian)
                #RELEASE_NAME=${VERSION_CODENAME:-"unsupported"}
                RELEASE_NAME="unsupported"

                # TODO for Debian install
            ;;
            ubuntu)
                # Hack for Linux Mint release number.
                DISTRO_VERSION=${VERSION_ID:-"${DISTRIB_RELEASE}"}
                MAJOR_RELEASE_VERSION=$(echo ${DISTRO_VERSION} | awk -F. '{print $1}')
                [[ "${DISTRIB_ID}" == "LinuxMint" || "${ID}" == "linuxmint" ]] && \
                    DISTRIB_RELEASE="LM${MAJOR_RELEASE_VERSION}"

                case ${DISTRIB_RELEASE} in
                    "16.04"|"LM18")
                        # Ubuntu release 16.04, LinuxMint 18
                        RELEASE_NAME=${UBUNTU_CODENAME:-"xenial"}
                    ;;
                    "18.04"|"LM19")
                        # Ubuntu release 18.04, LinuxMint 19
                        RELEASE_NAME=${UBUNTU_CODENAME:-"bionic"}
                    ;;
                    "19.04")
                        # Ubuntu release 19.04
                        RELEASE_NAME=${UBUNTU_CODENAME:-"disco"}
                    ;;
                    "20.04")
                        # Ubuntu release 20.04
                        RELEASE_NAME=${UBUNTU_CODENAME:-"focal"}
                    ;;
                    *)
                        RELEASE_NAME="unsupported"
                    ;;
                esac
            ;;
            amzn)
                # Amazon based on RHEL/CentOS
                RELEASE_NAME="unsupported"

                # TODO for Amzn install
            ;;
            centos)
                # CentOS
                RELEASE_NAME="unsupported"

                # TODO for CentOS install
            ;;
            *)
                RELEASE_NAME="unsupported"
            ;;
        esac
    elif [ -e /etc/system-release ]; then
    	RELEASE_NAME="unsupported"
    else
        # Red Hat /etc/redhat-release
    	RELEASE_NAME="unsupported"
    fi

    echo "${RELEASE_NAME}"
}

# Get physical RAM size.
function get_ram_size() {
    local RAM_SIZE

    # RAM size in MB
    RAM_SIZE=$(dmidecode -t 17 | awk '( /Size/ && $2 ~ /^[0-9]+$/ ) { x+=$2 } END{ print x}')

    echo "${RAM_SIZE}"
}

# Create custom Swap.
function create_swap() {
    local SWAP_FILE="/swapfile"
    local RAM_SIZE && \
    RAM_SIZE=$(get_ram_size)

    if [[ ${RAM_SIZE} -le 2048 ]]; then
        # If machine RAM less than / equal 2GiB, set swap to 2x of RAM size.
        local SWAP_SIZE=$((RAM_SIZE * 2))
    elif [[ ${RAM_SIZE} -gt 2048 && ${RAM_SIZE} -le 8192 ]]; then
        # If machine RAM less than / equal 8GiB and greater than 2GiB, set swap equal to RAM size.
        local SWAP_SIZE="${RAM_SIZE}"
    else
        # Otherwise, set swap to max of 8GiB.
        local SWAP_SIZE=8192
    fi

    echo "Creating ${SWAP_SIZE}MiB swap..."

    # Create swap.
    run fallocate -l "${SWAP_SIZE}M" ${SWAP_FILE} && \
    run chmod 600 ${SWAP_FILE} && \
    run chown root:root ${SWAP_FILE} && \
    run mkswap ${SWAP_FILE} && \
    run swapon ${SWAP_FILE}

    # Make the change permanent.
    if "${DRYRUN}"; then
        echo "Add persistent swap to fstab in dryrun mode."
    else
        if grep -qwE "#${SWAP_FILE}" /etc/fstab; then
            run sed -i "s|#${SWAP_FILE}|${SWAP_FILE}|g" /etc/fstab
        else
            run echo "${SWAP_FILE} swap swap defaults 0 0" >> /etc/fstab
        fi
    fi

    # Adjust swappiness, default Ubuntu set to 60
    # meaning that the swap file will be used fairly often if the memory usage is
    # around half RAM, for production servers you may need to set a lower value.
    if [[ $(cat /proc/sys/vm/swappiness) -gt 10 ]]; then
        if "${DRYRUN}"; then
            echo "Update swappiness value in dryrun mode."
        else
            run sysctl vm.swappiness=10
            run echo "vm.swappiness=10" >> /etc/sysctl.conf
        fi
    fi
}

# Remove created Swap.
function remove_swap() {
    local SWAP_FILE="/swapfile"

    if [ -f ${SWAP_FILE} ]; then
        run swapoff ${SWAP_FILE} && \
        run sed -i "s|${SWAP_FILE}|#\ ${SWAP_FILE}|g" /etc/fstab && \
        run rm -f ${SWAP_FILE}

        echo "Swap file removed."
    else
        warning "Unable to remove swap."
    fi
}

# Enable swap.
function enable_swap() {
    echo "Checking swap..."

    if free | awk '/^Swap:/ {exit !$2}'; then
        local SWAP_SIZE && \
        SWAP_SIZE=$(free -m | awk '/^Swap:/ { print $2 }')
        status "Swap size ${SWAP_SIZE}MiB."
    else
        warning "No swap detected."
        create_swap
        status "Swap created and enabled."
    fi
}

# Create default system account.
function create_account() {
    export USERNAME=${1:-"lemper"}
    export PASSWORD && \
    PASSWORD=${LEMPER_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

    echo "Creating default LEMPer account..."

    if [[ -z $(getent passwd "${USERNAME}") ]]; then
        if "${DRYRUN}"; then
            echo "Create ${USERNAME} account in dryrun mode."
        else
            run useradd -d "/home/${USERNAME}" -m -s /bin/bash "${USERNAME}"
            run echo "${USERNAME}:${PASSWORD}" | chpasswd
            run usermod -aG sudo "${USERNAME}"

            # Create default directories.
            run mkdir -p "/home/${USERNAME}/webapps"
            run mkdir -p "/home/${USERNAME}/.lemper"
            run chown -hR "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

            # Add account credentials to /srv/.htpasswd.
            if [ ! -f "/srv/.htpasswd" ]; then
                run touch /srv/.htpasswd
            fi

            # Protect .htpasswd file.
            run chmod 0600 /srv/.htpasswd
            run chown www-data:www-data /srv/.htpasswd

            # Generate passhword hash.
            if [[ -n $(command -v mkpasswd) ]]; then
                PASSWORD_HASH=$(mkpasswd --method=sha-256 "${PASSWORD}")
                run sed -i "/^${USERNAME}:/d" /srv/.htpasswd
                run echo "${USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
            elif [[ -n $(command -v htpasswd) ]]; then
                run htpasswd -b /srv/.htpasswd "${USERNAME}" "${PASSWORD}"
            else
                PASSWORD_HASH=$(openssl passwd -1 "${PASSWORD}")
                run sed -i "/^${USERNAME}:/d" /srv/.htpasswd
                run echo "${USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
            fi

            # Save config.
            save_config -e "LEMPER_USERNAME=${USERNAME}\nLEMPER_PASSWORD=${PASSWORD}\nLEMPER_ADMIN_EMAIL=${ADMIN_EMAIL}"

            # Save data to log file.
            save_log -e "Your default system account information:\nUsername: ${USERNAME}\nPassword: ${PASSWORD}"

            status "Username ${USERNAME} created."
        fi
    else
        warning "Unable to create account, username ${USERNAME} already exists."
    fi
}

# Delete default system account.
function delete_account() {
    local USERNAME=${1:-"lemper"}

    if [[ -n $(getent passwd "${USERNAME}") ]]; then
        if pgrep -u "${USERNAME}" > /dev/null; then
            error "User lemper is currently used by running processes."
        else
            run userdel -r "${USERNAME}"

            if [ -f "/srv/.htpasswd" ]; then
                run sed -i "/^${USERNAME}:/d" /srv/.htpasswd
            fi

            status "Account ${USERNAME} deleted."
        fi
    else
        warning "Account ${USERNAME} not found."
    fi
}

# Get server IP Address.
function get_ip_addr() {
    local IP_INTERNAL && \
    IP_INTERNAL=$(ip addr | grep 'inet' | grep -v inet6 | \
        grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    local IP_EXTERNAL && \
    IP_EXTERNAL=$(curl -s http://ipecho.net/plain)

    # Ugly hack to detect aws-lightsail public IP address.
    if [[ "${IP_INTERNAL}" == "${IP_EXTERNAL}" ]]; then
        echo "${IP_INTERNAL}"
    else
        echo "${IP_EXTERNAL}"
    fi
}

# Init logging.
function init_log() {
    [ ! -f lemper.log ] && run touch lemper.log
    save_log "Initialize LEMPer installation log..."
}

# Save log.
function save_log() {
    if ! ${DRYRUN}; then
        {
            date '+%d-%m-%Y %T %Z'
            echo "$@"
            echo ""
        } >> lemper.log
    fi
}

# Make config file if not exist.
function init_config() {
    if [ ! -f /etc/lemper/lemper.conf ]; then
        run mkdir -p /etc/lemper/
        run touch /etc/lemper/lemper.conf
    fi

    save_log -e "# LEMPer configuration.\n# Edit here if you change your password manually, but do NOT delete!"
}

# Save configuration.
function save_config() {
    if ! ${DRYRUN}; then
        [ -f /etc/lemper/lemper.conf ] && \
        echo "$@" >> /etc/lemper/lemper.conf
    fi
}

# Header message.
function header_msg() {
    clear
#    cat <<- _EOF_
#==========================================================================#
#      Welcome to LEMPer for Ubuntu-based server, Written by ESLabs.ID     #
#==========================================================================#
#      Bash scripts to install Nginx + MariaDB (MySQL) + PHP on Linux      #
#                                                                          #
#        For more information please visit https://eslabs.id/lemper        #
#==========================================================================#
#_EOF_
    status "
         _     _____ __  __ ____               _     
        | |   | ____|  \/  |  _ \ _welcome_to_| |__  
        | |   |  _| | |\/| | |_) / _ \ '__/ __| '_ \ 
        | |___| |___| |  | |  __/  __/ | _\__ \ | | |
        |_____|_____|_|  |_|_|   \___|_|(_)___/_| |_|
    "
}

# Footer credit message.
function footer_msg() {
    cat <<- _EOF_

#==========================================================================#
#         Thank's for installing LEMP stack using LEMPer Installer         #
#        Found any bugs/errors, or suggestions? please let me know         #
#       If useful, don't forget to buy me a cup of coffee or milk :D       #
#   My PayPal is always open for donation, here https://paypal.me/masedi   #
#                                                                          #
#           (c) 2014-2019 / ESLabs.ID / https://eslabs.id/lemper           #
#==========================================================================#
_EOF_
}

# Define build directory.
BUILD_DIR=${BUILD_DIR:-"/usr/local/src/lemper"}
if [ ! -d "${BUILD_DIR}" ]; then
    run mkdir -p "${BUILD_DIR}"
fi
