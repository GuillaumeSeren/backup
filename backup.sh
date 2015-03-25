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
#@TODO: Add a lock file.
#@TODO: Add cleanup mode, keep last x data.
#@TODO: Send mail on error, add (e) email option.
#@TODO: Add a function to check free space before doing archive, add a log.
#@TODO: Add time and size to the log.
#@TODO: Add SYNCRM, to sync and also delete.
#@TODO: Move log to /var/log.
#@TODO: Add 2 way SYNC2W to provide 2 way sync, the newer is taken.
#@TODO: Add better log, calculate size moved / read.
#@TODO: Add speed stat mo/s ko/s go/s.


# Error Codes {{{1
# 0 - Ok
# 1 - Error in cmd / options
# 2 - Error log file
# 3 - The last call is still running

# Default variables {{{1
# Flags :
flag_getopts=0
datenow=$(date +"%Y%m%d-%H:%M:%S")
logpath=$(dirname $0)
lockFile="$logpath/"$(echo "$@" | sha1sum | cut -d ' ' -f1)".lock"
logfile=$(echo "$0" | rev | cut -d"/" -f1 | rev)
logfile="$logpath/${logfile%.*}.log"

# FUNCTION usage() {{{1
# Return the helping message for the use.
function usage()
{
cat << DOC

usage: $0 options

This script backup a target in a location path.


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
    -m  Define mode, can be:
        "TARB": Create a tarball. (LOCAL ONLY)
        "SYNC": Sync 2 directory (default).
                Note that the sync is 1 way (from -> to).

Sample:
    Sync 2 directory
    $0 -f server:/var/www/foo -t /var/save/bar/ -m SYNC
    Make a tarball of a path, save it in the location.
    $0 -f server:/var/www/foo -t /var/save/dump/ -m TARB

DOC
}

# FUNCION createLogFile() {{{1
function createLogFile() {
    # Touch the file
    if [ ! -f $logfile ]; then
        earlyLog="Creation log file: $logfile"
        touch $logfile
    fi
    # If the file is still no variable
    if [ ! -w $logfile ]; then
        echo "The log file is not writeable, please check permissions."
        exit 2
    fi
    echo $earlyLog
}

# FUNCTION log {{{1
function log() {
    datenow=$(date +"%Y%m%d-%H:%M:%S")
    # We need to check if the file is available
    if [[ ! -w $logfile ]]; then
        earlyLog=$(createLogFile)
    fi
    # Do we have some early log to catch
    if [[ -n $earlyLog && $earlyLog != "" ]]; then
        echo "$datenow $idScriptCall $earlyLog" >> $logfile 2>&1
        # Clear earlyLog after displaying it
        unset earlyLog
    fi
    # test if it is writeable
    # Export the create / open / check file outside
    if [[ -n "$1" && "$1" != "" ]]; then
        echo "$datenow $idScriptCall $1" >> $logfile 2>&1
    fi
}

# GETOPTS {{{1
# Get the param of the script.
while getopts "f:t:m:h" OPTION
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
    m)
        cmdMode=$OPTARG
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

# Function getUniqueName {{{1
function getUniqueName() {
    datenow=$(date +"%Y%m%d-%H:%M:%S")
    if [[ -n $1 && $1 != "" ]]; then
        # The name is derivative from the target pathname
        # but you can give other things
        uniqueName="$1"
    else
        uniqueName="$1"
    fi
    echo "$1_$datenow"
}

# FUNCTION main() {{{1
function main() {
    # simple timing
    timeStart=$(date +"%s")
    # Encode the timestamp of the start in hex to make a id.
    idScriptCall=$(printf "%x\n" $timeStart)
    log "Save $cmdFrom to $cmdTo Start"
    # Check the lock
    if [ -f $lockFile ]; then
        # The last call is still running
        echo "The last call is still running"
        lockFileContent=$(cat $lockFile)
        echo "Running since $(date -d @$lockFileContent)"
        exit 3
    fi
    log "creating the lock file: $lockFile"
    touch $lockFile
    echo $timeStart > $lockFile
    if [[ -n $cmdMode && $cmdMode == "SYNC" ]]; then
        log "MODE SYNC"
        log "$(rsync -az --rsync-path="sudo rsync" "$cmdFrom" "$cmdTo")"
    elif [[ -n $cmdMode && $cmdMode == "TARB" ]]; then
        log "MODE TARBALL"
        #@FIXME: It would be better to expand path like ~
        pathName=$(basename "$cmdFrom")
        tarName=$(getUniqueName $pathName)
        log  "$(tar -zcf $cmdTo/$tarName.tar.gz -C ${cmdFrom%$pathName} $pathName/)"
    else
        log "MODE SYNC"
        log "Default mode"
        log "$(rsync -avz --rsync-path="sudo rsync" "$cmdFrom" "$cmdTo")"
    fi
    timeEnd=$(date +"%s")
    log "cleaning the lock file: $lockFile"
    rm $lockFile
    log "duration (sec): $(($timeEnd - $timeStart))"
    log "Save $cmdFrom to $cmdTo End"
}

main
