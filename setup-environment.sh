#!/bin/bash

use_ssh=false
debug=false
verbose=false
quiet=false
dry_run=false
txtgrn='\e[0;32m'
txtblk='\e[0m'
txtred='\e[0;31m'

http_urls=(
    https://github.com/shingoinstitute/shingo-sf-api.git
    https://github.com/shingoinstitute/shingo-auth-api.git
    https://github.com/shingoinstitute/shingo-affiliates-api.git
    https://github.com/shingoinstitute/shingo-events-api.git
    https://github.com/shingoinstitute/shingo-affiliates-frontend.git
    https://github.com/shingoinstitute/shingo-events-frontend.git
)

ssh_urls=(
    git@github.com:shingoinstitute/shingo-events-frontend.git
    git@github.com:shingoinstitute/shingo-affiliates-frontend.git
    git@github.com:shingoinstitute/shingo-affiliates-api.git
    git@github.com:shingoinstitute/shingo-sf-api.git
    git@github.com:shingoinstitute/shingo-auth-api.git
    git@github.com:shingoinstitute/shingo-events-api.git
)

function get_distro {
    local info
    command -v lsb_release >/dev/null 2>&1 && {
    { info="$(lsb_release -a 2>/dev/null)"; } || {
      info="$(cat /etc/*-release)"; }
    }

    [[ "$info" =~ "Ubuntu" ]] && echo true || echo false
    unset info
}

# Loads env variables or prompts the user to create an env file
function load_env {
    write_debug "${FUNCNAME[0]}"
if [[ -f ./env.sh ]]; then
    source ./env.sh
else
    echo "Fill the env.sh file with exported environment variables"
    touch env.sh
    cat <<< "export SF_USER=''
export SF_PASS=''
export SF_ENV=''
export SF_URL=''
export MYSQL_ROOT_PASS=''
export MYSQL_VOL_PREFIX=''
export MYSQL_AUTH_USER=''
export MYSQL_AUTH_PASS=''
export MYSQL_AUTH_DB=''
export MYSQL_URL=''
export EMAIL_PASS=''" > env.sh
    exit 1;
fi
}

# Writes to the console in a verbose format
# PARAM $1: the text to write
function write_detail {
    if [[ -z "$quiet" || "$quiet" = false ]]; then
        printf "${txtgrn}%s${txtblk}\n" "$1"
    fi
}

# Runs the arguments passed to it, outputing to /dev/null if not in debug mode
# PARAM $1: the command to run
function run {
    write_debug "$1"
    if [[ "$dry_run" = true ]]; then
        return 0
    fi

    if [[ "$verbose" = true && "$quiet" = false ]]; then
        eval "$1"
    else
        eval "$1" > /dev/null
    fi
}

# Writes a header
# PARAM $1: the text to write
function write_header {
    write_detail "$1"
    if [[ "$verbose" = true ]]; then
        write_detail "======================="
    fi
}

# Writes to the console in a debug format
# PARAM $1: the text to write
function write_debug {
    if [[ "$debug" = true && "$quiet" = false ]]; then
        printf "${txtred}DEBUG${txtblk} -- %s\n" "$1"
    fi
}

# Reads any variables not filled by parameters
function read_variables {
    write_debug "${FUNCNAME[0]}"
    if [[ "$steps" =~ "create_aff_user" ]]; then
        if [[ -z $extid ]]; then
            echo -n "External ID: "
            read -r extid
        fi
        if [[ -z $user_email ]]; then
            echo -n "Account Email: "
            read -r user_email
        fi
        if [[ -z $user_pass ]]; then
            echo -n "Account Password: "
            read -r user_pass
        fi
    fi
}

# Ensures Docker is installed from docker's ppa
# TODO: Make this platform agnostic (apt vs yum vs pacman)
function ensure_docker {
    write_debug "${FUNCNAME[0]}"
    command -v docker >/dev/null 2>&1 || {
        if [[ "$(get_distro)" = true ]]; then
            printf "Your distro is not supported. Install docker manually\n"
            return 1;
        fi
        write_header "Installing Docker"
        sudo apt install -y linux-image-extra-"$(uname -r)" linux-image-extra-virtual
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt update
        sudo apt install -y docker-ce
        sudo usermod -aG docker "$USER"
        exec su -l "$USER"
    }
    return 0;
}

function ensure_git {
    write_debug "${FUNCNAME[0]}"
    command -v git >/dev/null 2>&1 || {
        if [[ "$(get_distro)" = true ]]; then
            printf "Your distro is not supported. Install git manually\n"
            return 1;
        fi
        write_header "Installing Git"
        sudo apt install -y git
    }
    command -v make >/dev/null 2>&1 || {
        if [[ "$(get_distro)" = true ]]; then
            printf "Your distro is not supported. Install build-essential and make manually\n"
            return 1;
        fi
        sudo apt install -y build-essential make make-doc
    }
    return 0;
}

function ensure_node {
    write_debug "${FUNCNAME[0]}"
    if [ ! -d "$HOME/.nvm" ]; then
        write_header "Installing NodeJS"
        curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

        run "nvm install node"
        run "nvm use node"
    fi
    return 0;
}

# Clones the repositories and puts them in the current
# directory
function clone_repositories {
    write_debug "${FUNCNAME[0]}"
    ensure_git || { exit 1; }
    local urls="${http_urls[*]}"
    write_header "Cloning Repositories"
    write_debug "use_ssh: $use_ssh"
    if [[ "$use_ssh" = true ]]; then
        urls="${ssh_urls[*]}"
    fi

    for u in $urls; do
        file=$(basename "$u")
        if [ ! -d "${file%.*}" ]; then
            run "git clone $u"
        fi
    done
}

# Starts a docker container
# PARAM $1: the text to write
function start_docker {
    write_debug "${FUNCNAME[0]}"
    ensure_docker || { exit 1; }
    write_header "Starting docker container $1"
    run "cd $1" || { echo -e "${txtred}Directory $1 doesn't exist${txtblk}" && exit 1; }
    run ./docker-start.sh
    run "cd .."
}

# Starts all the docker containers
function start_docker_containers {
    write_debug "${FUNCNAME[0]}"
    write_header "Starting Docker Containers"
    local paths="shingo-sf-api shingo-auth-api shingo-affiliates-api shingo-events-api"
    for p in $paths; do
        start_docker "$p"
    done
    # The mysql container needs some time to get started before we can connect
    write_detail "Waiting for MySQL container"
    run "sleep 200"
}

# Creates the shingoauth database and 
# creates a user
function create_database {
    write_debug "${FUNCNAME[0]}"
    ensure_docker || { exit 1; }
    write_header "Creating ShingoAuth Database and ShingoAuth User"
    write_debug "MYSQL_URL: $MYSQL_URL"
    write_debug "MYSQL_AUTH_USER: $MYSQL_AUTH_USER"
    write_debug "MYSQL_AUTH_DB: $MYSQL_AUTH_DB"
    write_debug "MYSQL_AUTH_PASS: $MYSQL_AUTH_PASS"
    write_debug "MYSQL_ROOT_PASS: $MYSQL_ROOT_PASS"
    docker exec -i "$MYSQL_URL" bash -c "mysql -p\"$MYSQL_ROOT_PASS\" <<< \"CREATE DATABASE IF NOT EXISTS $MYSQL_AUTH_DB;
USE $MYSQL_AUTH_DB;
CREATE USER IF NOT EXISTS '$MYSQL_AUTH_USER'@'172.%.%.%' IDENTIFIED BY '$MYSQL_AUTH_PASS';
GRANT ALL PRIVILEGES ON $MYSQL_AUTH_DB.* TO '$MYSQL_AUTH_USER'@'172.%.%.%' WITH GRANT OPTION;\""
    start_docker shingo-auth-api
    start_docker shingo-affiliates-api
}

# Creates a user for the affiliate portal
function create_aff_user {
    write_debug "${FUNCNAME[0]}"
    ensure_node   || { exit 1; }
    ensure_docker || { exit 1; }
    write_header "Creating Affiliate User"
    write_debug "user_email: $user_email"
    write_debug "user_pass: $user_pass"
    run "cd ./shingo-affiliates-api" || { echo -e "${txtred}Directory shingo-affiliates-api doesn't exist${txtblk}" && exit 1; }
    run "npm install"
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' shingo-auth-api)
    write_debug "shingo-auth-api ip: $ip:80"
    node <<< "const grpc = require('grpc')
const auth = grpc.load('./proto/auth_services.proto').authservices
const client = new auth.AuthServices('$ip:80', grpc.credentials.createInsecure())
const cb = good => (e, u) => e && console.error('error: ', e) || u && good(u)
client.createUser({email: '$user_email', password: '$user_pass', services: 'affiliate-portal'},
    cb(u => client.updateUser({id: u.id, extId: '$extid'}, cb(u => u)))
)";
    run "cd .."
}

# Grants affiliate manager privileges to the
# affiliate user
function grant_affiliate_manager {
    write_debug "${FUNCNAME[0]}"
    ensure_docker || { exit 1; }
    write_header "Granting Affiliate Manager Privileges"
    docker exec -i "$MYSQL_URL" bash -c "mysql -p\"$MYSQL_ROOT_PASS\" <<< \"USE $MYSQL_AUTH_DB;
INSERT INTO role_users_user (roleId, userId) VALUES (2, 1);\""
    start_docker shingo-auth-api
}

# Cleans the created directories and removes
# all docker containers
# BE CAREFUL: if you have any additional containers,
# those will also be deleted
function run_clean {
    write_debug "${FUNCNAME[0]}"
    ensure_docker || { exit 1; }
    docker stop $(docker ps -a -q) && docker container prune
    sudo rm -rf "$MYSQL_VOL_PREFIX"
    for u in ${http_urls[*]}; do
        file=$(basename "$u")
        if [ -d "${file%.*}" ]; then
            sudo rm -rf "${file%.*}"
        fi
    done
}

function print_help {
    echo -n "Usage: $PROG_NAME [options] [directory]...
Creates a development environment in specified directories.

If no directory was specified, create an environment in the current directory

Options:
  -v                            Enable verbosity
  -d                            Enable debug mode
  -q                            Quiet - don't output
  -s, --ssh                     Use ssh keys for git clone
  -e ID, --extid=ID             Use ID for the salesforce external id
  -u EMAIL, --email=EMAIL       Use EMAIL for the affiliate manager account email
  -p PASS, --password=PASS      Use PASS for the affiliate manager password
  --steps=STEPS	                Run the specified STEPS instead of defaults
                                Available steps are:
                                load_env                    Loads the environment file
                                clone_repositories          Clones the git repositories
                                start_docker_containers     Starts the docker containers
                                create_database             Creates the mysql auth database
                                create_aff_user             Creates the affiliate portal user in the database
                                grant_affiliate_manager     Grants affiliate manager permissions to the user
  --clean                       Cleans the specified directory and removes all docker containers (WARNING DESTRUCTIVE)
  --dry-run                     Don't actually run anything
  --start                       Starts the development environment. Alias for --steps='load_env start_docker_containers'"
}

PROG_NAME=$(basename "$0")

# The default steps (functions) to run
steps="load_env clone_repositories start_docker_containers create_database create_aff_user grant_affiliate_manager"

# Uses gnu getopt to parse command-line parameters
options=$(getopt -n "$PROG_NAME"  -o 'vdqhse:u:p:' -l ssh,extid:,email:,password:,steps:,start,clean,help,dry-run -- "$@")
if [ "$?" != "0" ]; then
    print_help
    exit 1;
fi
eval set -- "$options"

while true; do
    case "$1" in
        -v)
            verbose=true
            ;;
        -d)
            debug=true
            ;;
        -q)
            quiet=true
            ;;
        -s | --ssh)
            use_ssh=true
            ;;
        -e | --extid)
            shift;
            extid=$1
            ;;
        -u | --email)
            shift;
            user_email=$1
            ;;
        -p | --password)
            shift;
            user_pass=$1
            ;;
        --steps)
            shift;
            steps=$1
            ;;
        --start)
            steps="load_env start_docker_containers"
            ;;
        --clean)
            clean=true
            ;;
        --dry-run)
            dry_run=true
            ;;
        -h|--help)
            print_help
            exit 0;
            ;;
        --) shift; break;;
	*) break;;
    esac
    shift
done

# Main
if (( $# == 0 )); then
    DIRS='.'
else
    DIRS="$*"
fi

for d in $DIRS; do
    if [[ ! -d $d ]]; then
        write_detail "creating directory $d"
        run "mkdir $d"
    fi
    pushd "$d" >/dev/null
    # Cleans if necessary
    if [[ "$clean" == true ]]; then
        load_env
        run_clean
        exit;
    fi
    read_variables
    write_debug "Steps: $steps"
    for s in $steps; do
        eval "$s"
    done
    popd >/dev/null
done
