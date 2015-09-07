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
#@TODO: Add check on required program.
#@TODO: Add new mode agent to parse log and output (mail) important event.
#@TODO: Add a way to calculate the speed for bwlimit, based on time & size.
#@TODO: We need better test over ssh before rm/add.
#@TODO: Add a way to get the rsync/tar status.
#@TODO: Better clean behavior keep 1/4w then 1/m archive.
#@TODO: Add the getFileNameNotOn period 2 timestamp
#@TODO: Count the files on a given period (day/week/month/year).
#@TODO: Add better log, calculate size moved / read.
#@TODO: Add speed stat mo/s ko/s go/s in the log.
#@TODO: It would be better to expand path like ~
#@TODO: Send mail on error, add (e) email option.
#@TODO: Add a function to check free space before doing archive, add a log.
#@TODO: Add mode 2 way SYNC2W to provide 2 way sync, the newer is taken.
#@TODO: Move log to /var/log & Add logrotate + upgrade doc.

# Error Codes {{{1
# 0 - Ok
# 1 - Error in cmd / options
# 2 - Error log file
# 3 - The last call is still running
# 4 - The getFileNameByDay is called with no filename (first parm).
# 5 - The getValidateFrom arg is not readable, check fs perm.
# 6 - The getValidateTo arg is not readable/writeable, check fr perm.
# 7 - The bwlimit is null.

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
# TAR archive infos
tarParams="-Jcf"
tarExtension=".tar.xz"

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
        "TARB":   Create a tarball. (LOCAL ONLY)
        "SYNC":   Sync 2 directory (default).
                  Note that the sync is 1 way (from -> to).
        "CLEAN":  Clean old tarball, (keep only today).
        "SYNCRM": Delete the missing (cleaned) files on the reference.
    -l  OPTION TV: Fill the bwlimit param to rsync:
        By default the value will be in KiB.
        You can specify other suffixes see rsync man page.

Sample:
    Sync 2 directory
    "$0" -f server:/var/www/foo -t /var/save/bar/ -m SYNC
    Make a tarball of a path, save it in the location.
    "$0" -f server:/var/www/foo -t /var/save/dump/ -m TARB
    Delete old tarball:
    "$0" -f server:/var/www/foo -t /var/save/bar/ -m CLEAN
    SYNCRM 2 directory
    "$0" -f server:/var/www/foo -t /var/save/bar/ -m SYNCRM

DOC
}

# FUNCTION createlogFile() {{{1
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

# FUNCTION log() {{{1
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
    # Do we have the alert flag
    if [[ -n "$2" && "$2" == "ALERT" ]]; then
        echo "$dateNow $idScriptCall $1"
    fi

}

# FUNCTION getUniqueName() {{{1
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

# FUNCTION getFileNameOnDay() {{{1
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

# FUNCTION getFileNotOnDay() {{{1
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

# FUNCTION cleanLockFile() {{{1
# clean lock file.
function cleanLockFile() {
    # test if lock file has well been made
    if [[ -n "$lockFile" && "$lockFile" != "" ]]; then
        log "cleaning the lock file: $lockFile"
        rmFile "$lockFile"
    fi
}

# FUNCTION getUrlType() {{{1
function getUrlType
{
    # Return the type of the URL.
    #----------------------------------------------
    # SSH   - 192.168.0.1:~/mypath/
    # SSH   - foo@192.168.0.1:~/mypath/
    # SSH   - ssh_alias:~/mypath/
    # LOCAL - ~/mypath/
    #--------------------------------------------
    # Regex :
    local sRegPathLocal='^(/)?([a-zA-Z]+.(/)?)+$'
    local sRegPathSshIp='^([0-9]{1,3}\.){3}[0-9]{1,3}:(~/.+)?(/.+)?$'
    local sRegPathSshIpUser='^([a-zA-Z0-9]+)@([0-9]{1,3}\.){3}[0-9]{1,3}:(~/.+)?(/.+)?$'
    local sRegPathSshAlias='^(.+):(~/.+)?(/.+)?$'
    #--------------------------------------------
    # Get param
    if [[ -n "$1" && "$1" != "" ]]; then
        local url=$1
    fi
    local urlType=""
    if [[ $url =~ $sRegPathSshIp ||
          $url =~ $sRegPathSshIpUser ||
          $url =~ $sRegPathSshAlias
    ]]; then
        # It's SSH
        urlType="ssh"
    elif [[ $url =~ $sRegPathLocal ]]; then
        # It's local
        urlType="local"
    else
        # Sinon c'est une url inconnu.
        urlType="unknown"
        # echo "Error URL : $url"
        # exit $flag
    fi
    echo $urlType
}

# FUNCTION getValidateFrom() {{{1
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
    # We need to detect the type of url:
    local urlType="$(getUrlType "$from")"
    if [[ "$urlType" == "local" ]]; then
        # Now test if the target is available
        if [[ -r "$from" ]]; then
            # target is valid
            fromReturn="$from"
        else
            # target is not
            fromReturn=""
        fi
    else
        # The URL is not local so we don't test it
        fromReturn="$from"
    fi
    echo "$fromReturn"
}

# FUNCTION getValidateTo() {{{1
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
    # We need to detect the type of url:
    local urlType="$(getUrlType "$to")"
    if [[ "$urlType" == "local" ]]; then
        # Now test if the target is available
        if [[ -r "$to" && -w "$to" ]]; then
            # target is valid
            toReturn="$to"
        else
            # target is not
            toReturn=""
        fi
    else
        # The URL is not local so we don't test it
        toReturn="$toReturn"
    fi
    echo "$toReturn"
}

# FUNCTION getFileSize {{{1
function getFileSize() {
    # Default size
    local returnSize="0"
    # get the file size
    if [[ -n "${1}" && "${1}" != "" ]]; then
        returnSize=$(du -b "${1}" | cut -f1)
    fi
    echo "${returnSize}"
}

# FUNCTION rmFile() {{{1
function rmFile() {
    # Before deleting the file we check that exist and type and perm
    if [[ -n "${1}" && "${1}" != "" ]]; then
        if [[ ! -e "${1}" ]]; then
            # if file not exist
            log "File ${1} not exist"
        elif [[ ! -f "${1}" ]]; then
            # file is not a regular file
            log "File ${1} is not a regular file"
        elif [[ ! -r "${1}" && ! -w "${1}" ]]; then
            log "File ${1} permissions problem (r/w)"
        else
            # I hope we can delete it now
            rm "${1}"
        fi
    fi
}

# FUNCTION rmDir() {{{1
function rmDir() {
    # Before deleting the directory we check that exist and type and perm
    if [[ -n "${1}" && "${1}" != "" ]]; then
        if [[ ! -e "${1}" ]]; then
            # if file not exist
            log "Directory ${1} not exist"
        elif [[ ! -d "${1}" ]]; then
            # file is not a regular file
            log "Directory ${1} is not a directory"
        elif [[ ! -r "${1}" && ! -w "${1}" ]]; then
            log "Directory ${1} permissions problem (r/w)"
        else
            # I hope we can delete it now
            rm -r "${1}"
        fi
    fi
}

# GETOPTS {{{1
# Get the param of the script.
while getopts "f:t:m:l:h" OPTION
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
            echo "Please check reading permissions of your file system"
            exit 5
        fi
        ;;
    t)
        cmdTo="$(getValidateTo "$OPTARG")"
        if [[ "$cmdTo" == "" ]]; then
            echo "The to target is invalid: $OPTARG"
            echo "Please check reading permissions of your file system"
            exit 6
        fi
        ;;
    l)
        rsyncBwLimit="$OPTARG"
        if [[ -z "$rsyncBwLimit" && "$rsyncBwLimit" == '' ]]; then
            echo "Your rsync bwlimit can not be null"
            usage
            exit 7
        fi
        rsyncBwLimit="--bwlimit=${rsyncBwLimit}"
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
    # Use the PID:
    idScriptCall="$$"
    log "Save $cmdFrom to $cmdTo Start"
    # Check the lock
    if [ -f "$lockFile" ]; then
        # The last call is still running
        log "The last call is still running" "ALERT"
        lockFileContent="$(cat "$lockFile")"
        log "Running since $(date -d @"$lockFileContent")" "ALERT"
    fi
    log "creating the lock file: $lockFile"
    touch "$lockFile"
    echo "$timeStart" > "$lockFile"
    if [[ -n "$cmdMode" && "$cmdMode" == "SYNC" ]]; then
        log "MODE SYNC"
        if [[ -n "$rsyncBwLimit" && "$rsyncBwLimit" != '' ]]; then
            log "OPTION TV: $rsyncBwLimit"
        else
            rsyncBwLimit="--bwlimit=0"
        fi
        log "$(rsync -az "$rsyncBwLimit" "$cmdFrom" "$cmdTo")"
    elif [[ -n $cmdMode && $cmdMode == "SYNCRM" ]]; then
        log "MODE SYNCRM"
        if [[ -n "$rsyncBwLimit" && "$rsyncBwLimit" != '' ]]; then
            log "OPTION TV: $rsyncBwLimit"
        else
            rsyncBwLimit="--bwlimit=0"
        fi
        # Calculate files that are in the cmdTo but deleted on from.
        IFS=$'\n'
        fileList=($(rsync -avz "$rsyncBwLimit" --delete --dry-run "$cmdFrom" "$cmdTo" | grep 'delet' | sed s/'deleting '//))
        unset IFS
        log "SYNCRM Nb fichier détectés: ${#fileList[@]}"
        sizeFileDeleted=0
        declare -a aSyncRm
        for (( i=0; i<"${#fileList[@]}"; i++ ))
        do
            if [[ "${fileList[$i]}" == "" || "${fileList[$i]}" =~ ^[[:space:]]++$ ]]; then
                log "SYNCRM error on the file: ${fileList[$i]}"
            else
                # Remove the last / if any in the cmdTo name
                targetRm="${cmdTo%/}/${fileList[$i]}"
                log "Delete: ${targetRm}"
                if [[ -d "${targetRm}" ]]; then
                    rmDir "${targetRm}"
                else
                    sizeFileDeleted=$(( sizeFileDeleted + $(getFileSize "${targetRm}") ))
                    rmFile "${targetRm}"
                fi
                aSyncRm+=("${fileList[$i]}")
            fi
        done
        log "SYNCRM list done: ${#aSyncRm[@]} deleted item(s)"
        log "SYNCRM size freed: ${sizeFileDeleted}"
    elif [[ -n $cmdMode && $cmdMode == "TARB" ]]; then
        log "MODE TARBALL"
        # Delete the last / if any
        cmdFrom="${cmdFrom%/}"
        pathName="$(basename "$cmdFrom")"
        tarName="$(getUniqueName "$pathName")${tarExtension}"
        sizeFileDeleted=0
        log "Archive name: $tarName"
        log "$(tar "${tarParams}" "${cmdTo}/${tarName}" -C "${cmdFrom%$pathName}" "${pathName}/")"
        sizeFileDeleted="$(getFileSize "${cmdTo}/${tarName}")"
        log "TARB file size: ${sizeFileDeleted}"
    elif [[ -n $cmdMode && $cmdMode == "CLEAN" ]]; then
        log "MODE CLEAN"
        pathName="$(basename "$cmdFrom")"
        sizeFileDeleted=0
        # List all files by name
        IFS=$'\n'
        fileList=($(find "$cmdTo"/ -maxdepth 1 -type f -name "${pathName}*${tarExtension}"))
        unset IFS
        declare -a aFileToClean
        for (( i=0; i<"${#fileList[@]}"; i++ ))
        do
            # Check file not today for the clean
            fileMatch="$(getFileNameNotOnDay "$(basename "${fileList[$i]}")" "${pathName}_$(date +"%Y%m%d")" "1")"
            if [[ -n "$fileMatch" && "$fileMatch" != "" ]]; then
                # There was a match
                aFileToClean+=("${fileList[$i]}")
            fi
        done
        # Cleaning loop
        for (( i=0; i<"${#aFileToClean[@]}"; i++ ))
        do
            log "rm ${aFileToClean[$i]}"
            sizeFileDeleted=$(( sizeFileDeleted + $(getFileSize "${aFileToClean[$i]}") ))
            rmFile "${aFileToClean[$i]}"
        done
        log "CLEAN done: ${#aFileToClean[@]} deleted item(s)"
        log "CLEAN size freed: ${sizeFileDeleted}"
    else
        #@FIXME: We should better set cmdMode a default value and use this case for error.
        log "MODE SYNC"
        log "Default mode"
        if [[ -n "$rsyncBwLimit" && "$rsyncBwLimit" != '' ]]; then
            log "OPTION TV: $rsyncBwLimit"
        else
            rsyncBwLimit="--bwlimit=0"
        fi
        log "$(rsync -avz "$rsyncBwLimit" "$cmdfrom" "$cmdTo")"
    fi
    timeEnd="$(date +"%s")"
    cleanLockFile
    log "duration (sec): $(( timeEnd - timeStart ))"
    log "Save $cmdFrom to $cmdTo End"
}

main
