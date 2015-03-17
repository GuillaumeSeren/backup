#!/bin/bash
# -*- coding: UTF8 -*-
# ---------------------------------------------
# @author:  Guillaume Seren
# @since:   09/03/2015
# source:   https://github.com/GuillaumeSeren/backup
# file:     backup.sh
# Licence:  GPLv3
# ---------------------------------------------
# TaskList:
#@TODO: Send mail on error.
#@TODO: Move log to /var/log.
#@TODO: Add time and size to the log.

# Default variables {{{1
# Flags :
flag_getopts=0
datenow=$(date +"%Y%m%d-%H:%M:%S")
logpath=$(pwd $0)
logfile="$logpath/${0%.*}.log"

# FUNCTION usage() {{{1
# Return the helping message for the use.
function usage()
{
cat << DOC

usage: $0 options

This script backup a folder as an archive in a location path.


OPTIONS:
    -h  Show this message.
    -v  Activate verbose mode.
    -f  Path from.
    -t  Location to.
    Path can be remote or local:
        -Local: (~/foo or /foo/bar/).
        -Remote :
            - ssh_alias:~/foo
            - user@127.0.0.1:~/foo

Sample:
    $0 -f server:/var/www/foo -t /var/save/foo/

DOC
}

# FUNCTION log {{{1
function log() {
    datenow=$(date +"%Y%m%d-%H:%M:%S")
    if [[ -n "$1" && "$1" != "" ]]; then
        echo "$datenow $1" >> $logfile 2>&1
    fi
}

# GETOPTS {{{1
# Get the param of the script.
while getopts "f:t:h" OPTION
do
    flag_getopts=1
    case $OPTION in
    h)
        usage
        exit 1
        ;;
    f)
        cmdFrom=$OPTARG
        ;;
    t)
        cmdTo=$OPTARG
        ;;
    ?)
        echo "commande $1 inconnue"
        usage
        exit
        ;;
    esac
done
# We check if getopts did not find no any param
if [ $flag_getopts == 0 ]; then
    echo 'This script cannot be launched without options.'
    usage
    exit 1
fi

# FUNCTION main() {{{1
function main() {
    # simple timing
    timeStart=$(date +"%s")
    log "Save $cmdFrom Start"
    log "$(rsync -avz --rsync-path="sudo rsync" "$cmdFrom" "$cmdTo")"
    timeEnd=$(date +"%s")
    log "duration (sec): $(($timeEnd - $timeStart))"
    log "Save $cmdFrom End."
}

main
