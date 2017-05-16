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
# @TODO: Add version of the script in the log.
# @TODO: Refactor main to *only* call functions (and not process).
# @TODO: Function to check used space before doing archive, log size.
# @TODO: Better log, calculate size moved / read / copy.
# @TODO: Use tee to copy echo ouput and add it to log
# @TODO: Add speed stat mo/s ko/s go/s in the log.
# @TODO: Move log to /var/log + package + logrotate
# @TODO: Add support for relative path to getValidateTo/From()
# @TODO: Add a way to get the rsync/tar status.
# @TODO: We need better test over ssh before rm/add.
# @TODO: Count the files on a given period (day/week/month/year).
# @TODO: Add getFileNameNotInPeriod of 2 timestamps.
# @TODO: Improve cleaning mode filter, add param to configure it.
# @TODO: Add new mode agent to parse log and output (mail) important event.
# @TODO: Add mode 2 way SYNC2W to provide 2 way sync, the newer is taken.

# Error Codes {{{1
# 0  Ok
# 1  Error in cmd / options
# 2  Error log file
# 3  The last call is still running
# 4  The getFileNameByDay is called with no filename (first parm).
# 5  The getValidateFrom arg is not readable, check fs perm.
# 6  The getValidateTo arg is not readable/writeable, check fr perm.
# 7  The bwlimit is null.
# 8  Missing dependencies
# 9  Some default param is missing
# 10 Error unknown options
# 11 Error in function exitWrapper
# 12 Error in statusCall
# 13 Disk avail is not enought for the sizeMoved by rsync
# 14 The getFileTypeNotInPeriod filename is missing

# Default variables {{{1
dependencies='date dirname sha1sum cut rev tar rsync'
# Flags :
flagGetOpts=0
# dateNow="$(date +"%Y%m%d-%H:%M:%S")"
dateNow="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
logPath="$(dirname "$0")"
lockHash="$(echo "$@" | sha1sum | cut -d ' ' -f1)"
lockFile="$logPath/${lockHash}.lock"
logFile="$(echo "$0" | rev | cut -d"/" -f1 | rev)"
# This is for the actual run
logFileActual="$logPath/${lockHash}-${logFile%.*}-${dateNow}.log"
logFile="$logPath/${logFile%.*}.log"
# simple timing
# Convert dateNow to %s timestamp
timeStart="$(date -d "$dateNow" "+%s")"

# TAR archive infos
tarParams="-Jcf"
tarExtension=".tar.xz"

# FUNCTION usage() {{{1
# Return the helping message for the use.
function usage()
{
  cat << DOC

  ${0} options

Backup a target in a location path.


OPTIONS:
  -h, --help        Show this message.
  -v, --verbose     Activate verbose mode, show debug messages.
  -f, --from        Location* from.
  -t  --to          Location* to.
  *Locations can be remote or local:
    -Local: (~/foo or /foo/bar/).
    -Remote :
    - ssh_alias:~/foo
    - user@127.0.0.1:~/foo
  -m, --mode [opt]  Define mode, can be:
      "TARB":       Create a tarball. (LOCAL ONLY)
      "SYNC":       Sync 2 directory (default).
                    Note that the sync is 1 way (from -> to).
      "CLEAN":      Clean old tarball, (keep only today).
      "SYNCRM":     Delete the missing (cleaned) files on the reference.
  -l, --limit       Limit the bandwith available:
      0             Is no limit (default).
      By default the value will be in KiB.
      You can specify other suffixes see rsync man page.
  -e, --email       Specify a email to contact if error.

Examples:
  Sync 2 directory
  ${0} -f server:/var/www/foo -t /var/save/bar/ -m SYNC
  Make a tarball of a path, save it in the location.
  ${0} -f server:/var/www/foo -t /var/save/dump/ -m TARB
  Delete old tarball:
  ${0} -f server:/var/www/foo -t /var/save/bar/ -m CLEAN
  SYNCRM 2 directory
  ${0} -f server:/var/www/foo -t /var/save/bar/ -m SYNCRM

DOC
}

# FUNCTION createlogFile() {{{1
function createLogFile() {
  local logFileLocal=''
  if [[ -n "$1" ]]; then
    logFileLocal="$1"
  else
    # If no parm take default log file
    logFileLocal="$logFile"
  fi
  # Touch the file
  if [[ ! -f "$logFileLocal" ]]; then
    earlyLog="Creation log file: $logFileLocal"
    touch "$logFileLocal"
  fi
  # If the file is still no variable
  if [ ! -w "$logFileLocal" ]; then
    echo "The log file is not writeable, please check permissions."
    exitWrapper 2
  fi
  echo "$earlyLog"
}

# FUNCTION log() {{{1
# $1 Message
# $2 Verbose level (VERBOSE, ALERT)
function log() {
  local globalLog=''
  local earlyLog=''
  # We need to check if the file is available
  if [[ ! -w "$logFile" ]]; then
    globalLog="$(createLogFile "${logFile}")"
  fi
  # Do we have some early log to catch
  if [[ -n "${globalLog}" ]]; then
    echo "${dateNow} ${idScriptCall} ${globalLog}" >> "${globalLog}" 2>&1
    # Clear earlyLog after displaying it
    unset globalLog
  fi
  if [[ ! -w "${logFileActual}" ]]; then
    earlyLog="$(createLogFile "${logFileActual}")"
  fi
  # Do we have some early log to catch
  if [[ -n "$earlyLog" ]]; then
    echo "${dateNow} ${idScriptCall} ${earlyLog}" >> "${logFile}" 2>&1
    # Clear earlyLog after displaying it
    unset earlyLog
  fi
  # Ouput message + verbose level if set
  if [[ -n "$1" && -z "$2" ]]; then
    echo "${dateNow} ${idScriptCall} $1" >> "${logFileActual}" 2>&1
  elif [[ -n "$1" && -n "$2" && "$2" == "VERBOSE" ]]; then
    # This is verbose stuff not critical for production
    if [[ -n "${cmdVerbose}" && "${cmdVerbose}" == 1 ]]; then
      echo "${dateNow} ${idScriptCall} $1" >> "${logFileActual}" 2>&1
    fi
  elif [[ -n "$1" && -n "$2" && "$2" == "ALERT" ]]; then
    echo "${dateNow} ${idScriptCall} $1" >> "${logFileActual}" 2>&1
    # Do we have the alert flag
    echo "${dateNow} ${idScriptCall} $1"
  fi
}

# FUNCTION getUniqueName() {{{1
function getUniqueName() {
  # dateNow is already defined at the beginning
  local uniqueName=''
  if [[ -n "$1" ]]; then
    # The name is derivative from the target pathname
    # but you can give other things
    uniqueName="$1"
  fi
  echo "${uniqueName}_${dateNow}"
}

# FUNCTION getFileNameOnDay() {{{1
# Return the filename if the date pattern is on a given day (default today).
function getFileNameOnDay() {
  local dateDay=''
  # Check the filename
  if [[ -z "$1" ]]; then
    echo "Error: You can not call the getFileNameByDay without filename"
    cleanLockFile
    exitWrapper 4
  fi
  # Check the date (day)
  if [[ -n $2 ]]; then
    #@TODO: Add a regex to validate the format
    dateDay="$2"
  else
    dateDay="$(date -d "$dateNow" "+%Y-%m-%d")"
  fi
  # Let's check if the filename contain the chosen date:
  if [[ "${1}" =~ ^$dateDay-.*+$ ]]; then
    echo "${1}"
  fi
}

# FUNCTION getFileNotOnDay() {{{1
# Return the filename if the date pattern is not on a given day (default today).
function getFileNameNotOnDay() {
  # local dateDay=''
  # Check the filename
  if [[ -z "$1" ]]; then
    echo "Error: You can not call the getFileNameNotOnDay without filename"
    cleanLockFile
    exitWrapper 4
  fi
  # Check the date (day)
  if [[ -n "$2" ]]; then
    #@TODO: Add a regex to validate the format
    dateDay="$2"
  else
    dateDay="$(date -d "$dateNow" "+%Y-%m-%d")"
  fi
  # Let's check if the filename contain the chosen date:
  if [[ ! "${1}" =~ ^$dateDay-.*+$ ]]; then
    echo "${1}"
  fi
}

# FUNCTION cleanLockFile() {{{1
# clean lock file.
function cleanLockFile() {
  # test if lock file has well been made
  if [[ -n "$lockFile" ]]; then
    log "cleaning the lock file: $lockFile" "VERBOSE"
    rmFile "$lockFile"
  fi
}

# FUNCTION getUrlType() {{{1
function getUrlType
{
  # Return the type of the URL.
  # SSH   -> 192.168.0.1:~/mypath/
  # SSH   -> foo@192.168.0.1:~/mypath/
  # SSH   -> ssh_alias:~/mypath/
  # LOCAL -> ~/mypath/
  # Regex :
  local sRegPathLocal='^(/)?([a-zA-Z]+.(/)?)+$'
  local sRegPathSshIp='^([0-9]{1,3}\.){3}[0-9]{1,3}:(~/.+)?(/.+)?$'
  local sRegPathSshIpUser='^([a-zA-Z0-9]+)@([0-9]{1,3}\.){3}[0-9]{1,3}:(~/.+)?(/.+)?$'
  local sRegPathSshAlias='^(.+):(~/.+)?(/.+)?$'
  # Get param
  if [[ -n "$1" ]]; then
    local url=$1
  fi
  local urlType=""
  if [[   $url =~ $sRegPathSshIp ||
          $url =~ $sRegPathSshIpUser ||
          $url =~ $sRegPathSshAlias ]]; then
    # It's SSH
    urlType="ssh"
  elif [[ $url =~ $sRegPathLocal ]]; then
    # It's local
    urlType="local"
  else
    # Sinon c'est une url inconnu.
    urlType="unknown"
  fi
echo $urlType
}

# FUNCTION getValidateFrom() {{{1
function getValidateFrom() {
  local from=""
  local fromReturn=""
  # validate the target
  if [[ -n "$1" ]]; then
    from="$1"
  else
    # Without arg we take the default if set
    from="$cmdFrom"
  fi
  # We need to detect the type of url:
  local urlType=""
  urlType="$(getUrlType "$from")"
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
  if [[ -n "$1" ]]; then
    to="$1"
  else
    # Without arg we take the default if set
    to="$cmdTo"
  fi
  # We need to detect the type of url:
  local urlType=""
  urlType="$(getUrlType "$to")"
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
  if [[ -n "${1}" ]]; then
    returnSize=$(du -b "${1}" | cut -f1)
  fi
  echo "${returnSize}"
}

# FUNCTION rmFile() {{{1
function rmFile() {
  # Before deleting the file we check that exist and type and perm
  if [[ -n "${1}" ]]; then
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
  if [[ -n "${1}" ]]; then
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

# FUNCTION checkDependencies() {{{1
# Test if needed dependencies are available.
function checkDependencies()
{
  local deps_ok=''
  for dep in $1
  do
    if  ! which "$dep" &>/dev/null;  then
      echo "This script requires $dep to run but it is not installed"
      deps_ok='NO'
    fi
  done
  if [[ "$deps_ok" == "NO" ]]; then
    echo "This script need : $1"
    echo "Please install them, before using this script !"
    exitWrapper 8
  else
    return 0
  fi
}

# FUNCTION exitWrapper() {{{1
function exitWrapper()
{
  # Embed the needed process to do while exiting
  if [[ -n "$1" && "$1" != 0 ]]; then
    if [[ -e "${logFileActual}" && -e "${logFile}" ]]; then
      cat "${logFileActual}" >> "${logFile}"
    fi
    if [[ -n "${cmdMail}" ]]; then
      cat "${logFileActual}" | mail -s "Backup has failed: ${logFileActual}" "${cmdMail}"
    else
      echo "The backup script failed with error ${1}"
    fi
    exit "${1}"
  elif [[ -n "$1" && "$1" == 0 ]]; then
    # it is a non error exit (help)
    exit "${1}"
  else
    echo "The backup script failed with error 11"
    if [[ -e "${logFileActual}" && -e "${logFile}" ]]; then
      cat "${logFileActual}" >> "${logFile}"
    fi
    if [[ -n "${cmdMail}" ]]; then
      cat "${logFileActual}" | mail -s "Backup has failed: ${logFileActual}" "${cmdMail}"
    fi
    exit "11"
  fi
}

# FUNCTION getStatusCall() {{{1
function getStatusCall() {
  local output=''
  if [[ -n "${1}" && -n "${2}" ]]; then
    output="MODE ${1} ${2}"
  else
    echo "Bad getStatusCall() parm1: ${1} param2: ${2}"
    exit 12
  fi
  echo "${output}"
}

# FUNCTION getMode() {{{1
function getMode() {
  # local cmdMode=''
  # check valid mode
  if [[   "$cmdMode" == "SYNC" ]]; then
    cmdMode="SYNC"
  elif [[ "$cmdMode" == "SYNCRM" ]]; then
    cmdMode="SYNCRM"
  elif [[ "$cmdMode" == "TARB" ]]; then
    cmdMode="TARB"
  elif [[ "$cmdMode" == "CLEAN" ]]; then
    cmdMode="CLEAN"
  else
    # Default mode
    cmdMode="SYNC"
  fi
  echo "${cmdMode}"
}

# FUNCTION getBwLimit() {{{1
function getRsyncBwLimit() {
  local rsyncBwLimit=''
  if [[ -n "${1}" ]]; then
    rsyncBwLimit="${1}"
  else
    rsyncBwLimit="--bwlimit=0"
  fi
  echo "${rsyncBwLimit}"
}

# GETOPTS {{{1
# Get the param of the script.
optspec=":f:t:m:l:-:evh"
while getopts "$optspec" optchar; do
  flagGetOpts=1
  # Short options
  case "${optchar}" in
    h)
      usage
      exitWrapper 0
      ;;
    f)
      cmdFrom="$(getValidateFrom "$OPTARG")"
      if [[ "$cmdFrom" == "" ]]; then
        echo "The from target is invalid: $OPTARG"
        echo "Please check reading permissions of your file system"
        exitWrapper 5
      fi
      ;;
    t)
      cmdTo="$(getValidateTo "$OPTARG")"
      if [[ "$cmdTo" == "" ]]; then
        echo "The to target is invalid: $OPTARG"
        echo "Please check reading permissions of your file system"
        exitWrapper 6
      fi
      ;;
    l)
      rsyncBwLimit="$OPTARG"
      if [[ -z "$rsyncBwLimit" ]]; then
        echo "Your rsync bwlimit can not be null"
        usage
        exitWrapper 7
      fi
      rsyncBwLimit="--bwlimit=${rsyncBwLimit}"
      ;;
    m)
      cmdMode="$OPTARG"
      ;;
    e)
      cmdMail="$OPTARG"
      checkDependencies "mail"
      ;;
    v)
      cmdVerbose=1
      ;;
    -)
      case "${OPTARG}" in
        # Long options
        # https://stackoverflow.com/questions/402377/using-getopts-in-bash-shell-script-to-get-long-and-short-command-line-options
        help)
          usage
          exitWrapper 0
          ;;
        from)
          val="${!OPTIND}"; OPTIND=$(( OPTIND + 1 ))
          cmdFrom="$(getValidateFrom "$val")"
          if [[ -z "$cmdFrom" ]]; then
            echo "The from target is invalid: $OPTARG"
            echo "Please check reading permissions of your file system"
            exitWrapper 5
          fi
          ;;
        to)
          val="${!OPTIND}"; OPTIND=$(( OPTIND + 1 ))
          cmdTo="$(getValidateTo "$val")"
          if [[ -z "$cmdTo" ]]; then
            echo "The to target is invalid: $OPTARG"
            echo "Please check reading permissions of your file system"
            exitWrapper 6
          fi
          ;;
        limit)
          val="${!OPTIND}"; OPTIND=$(( OPTIND + 1 ))
          rsyncBwLimit="$val"
          if [[ -z "$rsyncBwLimit" ]]; then
            echo "Your rsync bwlimit can not be null"
            usage
            exitWrapper 7
          fi
          rsyncBwLimit="--bwlimit=${rsyncBwLimit}"
          ;;
        mode)
          val="${!OPTIND}"; OPTIND=$(( OPTIND + 1 ))
          cmdMode="$val"
          ;;
        verbose)
          cmdVerbose=1
          ;;
        email)
          val="${!OPTIND}"; OPTIND=$(( OPTIND + 1 ))
          cmdMail="$val"
          checkDependencies "mail"
          ;;
        *)
          echo "Unknown long option --${OPTARG}" >&2
          usage >&2;
          exitWrapper 1
          ;;
      esac;;
    *)
      echo "Unknown short option -${OPTARG}" >&2
      usage >&2;
      exitWrapper 10
      ;;
  esac
done
# We check if getopts did not find no any param
if [[ "$flagGetOpts" == 0 ]]; then
  echo 'This script cannot be launched without options.'
  usage
  exitWrapper 1
elif [[ -z "${cmdFrom}" || -z "${cmdTo}" || -z "${cmdMode}" ]]; then
  echo 'You need to setup at least 3 params: from, to, mode'
  exitWrapper 9

fi

# FUNCTION main() {{{1
function main() {
  local idScriptCall=''
  # Use the PID of the current shell
  idScriptCall="$$"
  log "Save $cmdFrom to $cmdTo"
  log "Check dependencies: ${dependencies}" "VERBOSE"
  checkDependencies "$dependencies"
  # local cmdMode=''
  cmdMode=$(getMode "${cmdMode}")
  # local rsyncBwLimit=''
  rsyncBwLimit=$(getRsyncBwLimit "${rsyncBwLimit}")
  local statusCall=''
  statusCall=$(getStatusCall "${cmdMode}" "${rsyncBwLimit}")
  log "${statusCall}"
  # Check the lockfile (defined in default var)
  if [ -f "$lockFile" ]; then
    log "The last call is still running" "ALERT"
    local lockFileContent=''
    lockFileContent="$(cat "$lockFile")"
    log "Running since $(date -d @"$lockFileContent") ABORTING !!" "ALERT"
    exitWrapper 3
  else
    # Only display it if verbose is set
    log "creating the lock file: $lockFile" "VERBOSE"
    touch "$lockFile"
    echo "$timeStart" > "$lockFile"
  fi
  case "${cmdMode}" in
    'SYNC')
      # To check if available disk is > than needed by copy
      local sizeMoved=''
      sizeMoved=$(rsync -a --stats --dry-run "$rsyncBwLimit" "$cmdFrom" "$cmdTo" | grep -i 'Total transferred file size: ' | cut -d':' -f2 | cut -d' ' -f2)
      sizeMoved=${sizeMoved//,/}
      local diskAvail=''
      diskAvail=$(\df --output=avail -B1 "$cmdTo" | grep -v 'Avail')
      if [[ $diskAvail -lt $sizeMoved ]]; then
        log "Disk space avail ($diskAvail) is not enought for ($sizeMoved) !!" "ALERT"
        exitWrapper 13
      fi
      log "$(rsync -az "$rsyncBwLimit" "$cmdFrom" "$cmdTo")"
      ;;
    'SYNCRM')
      # Calculate files that are in the cmdTo but deleted on from.
      IFS=$'\n'
      fileList=($(rsync -avz "$rsyncBwLimit" --delete --dry-run "$cmdFrom" "$cmdTo" | grep 'delet' | sed s/'deleting '//))
      # fileList=($(rsync -avz --delete --dry-run "$cmdFrom" "$cmdTo" | grep 'delet' | sed s/'deleting '//))
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
      ;;
    'TARB')
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
      ;;
    'CLEAN')
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
        fileMatch="$(getFileNameNotOnDay "$(basename "${fileList[$i]}")" "${pathName}_$(date -d "$dateNow" "+%Y-%m-%d")")"
        if [[ -n "$fileMatch" ]]; then
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
      ;;
  esac
  timeEnd="$(date +"%s")"
  cleanLockFile
  log "duration (sec): $(( timeEnd - timeStart ))"
  if [[ -e "${logFileActual}" ]]; then
    # if we go here we can add local log to global
    cat "${logFileActual}" >> "${logFile}"
    # Then clean logFileActual
    rm "${logFileActual}"
  fi
}
main
# }}}

# vim: set ft=sh ts=2 sw=2 tw=80 foldmethod=marker et :
