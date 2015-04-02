#!/bin/bash
# -*- coding: UTF8 -*-
# ---------------------------------------------
# @author:  Guillaume Seren
# @since:   09/03/2015
# source:   https://github.com/GuillaumeSeren/backup
# file:     backup.sh
# Licence:  GPLv3
# ---------------------------------------------

# TaskList {{{1
#@FIXME: Better clean of the cmdTo path, to avoid // .
#@FIXME: It would be better to expand path like ~
#@TODO: Count the files on a given period (day/week/month/year).
#@TODO: Add the getFileNameNotOn period 2 timestamp
#@TODO: Keep only the last archive, add the other to the clean list.
#@TODO: Count the number and size freed by the cleaning, log it.
#@TODO: Send mail on error, add (e) email option.
#@TODO: Add a function to check free space before doing archive, add a log.
#@TODO: Add time and size to the log.
#@TODO: Add SYNCRM, to sync and also delete.
#@TODO: Add 2 way SYNC2W to provide 2 way sync, the newer is taken.
#@TODO: Add better log, calculate size moved / read.
#@TODO: Move log to /var/log.
#@TODO: Add speed stat mo/s ko/s go/s.

# Error Codes {{{1
# 0 - Ok
# 1 - Error in cmd / options
# 2 - Error log file
# 3 - The last call is still running
# 4 - The getFileNameByDay is called with no filename (first parm).
# 5 - The getValidateFrom arg is not readable, check fs perm.
# 6 - The getValidateTo arg is not readable/writeable, check fr perm.

# Default variables {{{1
# Flags :
flagGetOpts=0
dateNow="$(date +"%Y%m%d-%H:%M:%S")"
logPath="$(dirname "$0")"
lockFile="$logPath/$(echo "$@" | sha1sum | cut -d ' ' -f1).lock"
logFile="$(echo "$0" | rev | cut -d"/" -f1 | rev)"
logFile="$logPath/${logFile%.*}.log"
# simple timing
timeStart="$(date +"%s")"

# FUNCTION usage() {{{1
# Return the helping message for the use.
function usage()
{
cat << DOC

usage: "$0" options

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
    "$0" -f server:/var/www/foo -t /var/save/bar/ -m SYNC
    Make a tarball of a path, save it in the location.
    "$0" -f server:/var/www/foo -t /var/save/dump/ -m TARB

DOC
}

# FUNCION createlogFile() {{{1
function createLogFile() {
    # Touch the file
    if [ ! -f "$logFile" ]; then
        earlyLog="Creation log file: $logFile"
        touch "$logFile"
    fi
    # If the file is still no variable
    if [ ! -w "$logFile" ]; then
        echo "The log file is not writeable, please check permissions."
        exit 2
    fi
    echo "$earlyLog"
}

# FUNCTION log {{{1
function log() {
    dateNow="$(date +"%Y%m%d-%H:%M:%S")"
    # We need to check if the file is available
    if [[ ! -w "$logFile" ]]; then
        earlyLog="$(createLogFile)"
    fi
    # Do we have some early log to catch
    if [[ -n "$earlyLog" && "$earlyLog" != "" ]]; then
        echo "$dateNow $idScriptCall $earlyLog" >> "$logFile" 2>&1
        # Clear earlyLog after displaying it
        unset earlyLog
    fi
    # test if it is writeable
    # Export the create / open / check file outside
    if [[ -n "$1" && "$1" != "" ]]; then
        echo "$dateNow $idScriptCall $1" >> "$logFile" 2>&1
    fi
}

# FUNCTION getUniqueName {{{1
function getUniqueName() {
    dateNow="$(date +"%Y%m%d-%H:%M:%S")"
    if [[ -n "$1" && "$1" != "" ]]; then
        # The name is derivative from the target pathname
        # but you can give other things
        uniqueName="$1"
    else
        uniqueName="$1"
    fi
    echo "${uniqueName}_${dateNow}"
}

# Function getFileNameOnDay() {{{1
# Return the filename if the date pattern is on a given day (default today).
function getFileNameOnDay() {
    # Check the filename
    if [[ -z "$1" && "$1" == "" ]]; then
        echo "Error: You can not call the getFileNameByDay without filename"
        cleanLockFile
        exit 4
    fi
    # Check the date (day)
    if [[ -n $2 && $2 != "" ]]; then
        #@TODO: Add a regex to validate the format
        dateDay="$2"
    else
        # Take today by default
        dateDay="$(date +"%Y%m%d")"
    fi
    # Let's check if the filename contain the chosen date:
    if [[ "${1}" =~ ^$dateDay-.*+$ ]]; then
        # echo "Find result: ${1}"
        echo "${1}"
    fi
}

# Function getFileNotOnDay() {{{1
# Return the filename if the date pattern is not on a given day (default today).
function getFileNameNotOnDay() {
    # Check the filename
    if [[ -z "$1" && "$1" == "" ]]; then
        echo "Error: You can not call the getFileNameNotOnDay without filename"
        cleanLockFile
        exit 4
    fi
    # Check the date (day)
    if [[ -n "$2" && "$2" != "" ]]; then
        #@TODO: Add a regex to validate the format
        dateDay="$2"
    else
        # Take today by default
        dateDay="$(date +"%Y%m%d")"
    fi
    # Let's check if the filename contain the chosen date:
    if [[ ! "${1}" =~ ^$dateDay-.*+$ ]]; then
        # echo "Find result: ${1}"
        echo "${1}"
    fi
}

# fuction cleanLockFile() {{{1
# clean lock file.
function cleanLockFile() {
    # test if lock file has well been made
    if [[ -n "$lockFile" && "$lockFile" != "" ]]; then
        log "cleaning the lock file: $lockFile"
        rm "$lockFile"
    fi
}

# FUNCTION getValidateFrom {{{1
function getValidateFrom() {
    local from=""
    local fromReturn=""
    # validate the target
    if [[ -n "$1" && "$1" != "" ]]; then
        from="$1"
    else
        # Without arg we take the default if set
        from="$cmdFrom"
    fi
    # Now test if the target is available
    if [[ -r "$from" ]]; then
        # target is valid
        fromReturn="$from"
    else
        # target is not
        fromReturn=""
    fi
    echo "$fromReturn"
}

# FUNCTION getValidateTo {{{1
function getValidateTo() {
    local to=""
    local toReturn=""
    # validate the target
    if [[ -n "$1" && "$1" != "" ]]; then
        to="$1"
    else
        # Without arg we take the default if set
        to="$cmdTo"
    fi
    # Now test if the target is available
    if [[ -r "$to" && -w "$to" ]]; then
        # target is valid
        toReturn="$to"
    else
        # target is not
        toReturn=""
    fi
    echo "$toReturn"
}

# GETOPTS {{{1
# Get the param of the script.
while getopts "f:t:m:h" OPTION
do
    flagGetOpts=1
    case $OPTION in
    h)
        usage
        exit 1
        ;;
    f)
        cmdFrom="$(getValidateFrom "$OPTARG")"
        if [[ "$cmdFrom" == "" ]]; then
            echo "The from target is invalid: $OPTARG"
            echo "Please check reading permissions of you file system"
            exit 5
        fi
        ;;
    t)
        cmdTo="$(getValidateTo "$OPTARG")"
        if [[ "$cmdTo" == "" ]]; then
            echo "The to target is invalid: $OPTARG"
            echo "Please check reading permissions of you file system"
            exit 6
        fi
        ;;
    m)
        cmdMode="$OPTARG"
        ;;
    ?)
        echo "commande $1 inconnue"
        usage
        exit
        ;;
    esac
done
# We check if getopts did not find no any param
if [ "$flagGetOpts" == 0 ]; then
    echo 'This script cannot be launched without options.'
    usage
    exit 1
fi

# FUNCTION main() {{{1
function main() {
    # Encode the timestamp of the start in hex to make a id.
    idScriptCall="$(printf "%x\n" "$timeStart")"
    log "Save $cmdFrom to $cmdTo Start"
    # Check the lock
    if [ -f "$lockFile" ]; then
        # The last call is still running
        echo "The last call is still running"
        lockFileContent="$(cat "$lockFile")"
        echo "Running since $(date -d @"$lockFileContent")"
        exit 3
    fi
    log "creating the lock file: $lockFile"
    touch "$lockFile"
    echo "$timeStart" > "$lockFile"
    if [[ -n "$cmdMode" && "$cmdMode" == "SYNC" ]]; then
        log "MODE SYNC"
        log "$(rsync -az --rsync-path="sudo rsync" "$cmdFrom" "$cmdTo")"
    elif [[ -n $cmdMode && $cmdMode == "TARB" ]]; then
        log "MODE TARBALL"
        # Delete the last / if any
        cmdFrom="${cmdFrom%/}"
        pathName="$(basename "$cmdFrom")"
        tarName="$(getUniqueName "$pathName").tar.gz"
        log "Archive name: $tarName"
        log  "$(tar -zcf "${cmdTo}/${tarName}" -C "${cmdFrom%$pathName}" "${pathName}/")"
    elif [[ -n $cmdMode && $cmdMode == "CLEAN" ]]; then
        log "MODE CLEAN"
        # echo "We are going to need the name without date"
        pathName="$(basename "$cmdFrom")"
        # List all files by name
        fileList=("$(\find "$cmdTo"/ -maxdepth 1 -type f -name "${pathName}*.tar.gz")")
        declare -a aTest
        for (( i=0; i<"${#fileList[@]}"; i++ ))
        do
            # Check file not today for the clean
            fileMatch="$(getFileNameNotOnDay "$(basename "${fileList[$i]}")" "${pathName}_$(date +"%Y%m%d")" "1")"
            if [[ -n "$fileMatch" && "$fileMatch" != "" ]]; then
                # There was a match
                aTest+=("${fileList[$i]}")
            fi
        done
        log "Clean list done: ${#aTest[@]} item(s)"
        # Cleaning loop
        for (( i=0; i<"${#aTest[@]}"; i++ ))
        do
            log "rm ${aTest[$i]}"
            rm "${aTest[$i]}"
        done
    else
        log "MODE SYNC"
        log "Default mode"
        log "$(rsync -avz --rsync-path="sudo rsync" "$cmdfrom" "$cmdTo")"
    fi
    timeEnd="$(date +"%s")"
    cleanLockFile
    log "duration (sec): $((timeEnd - timeStart))"
    log "Save $cmdFrom to $cmdTo End"
}

main
