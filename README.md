backup
======
Simple backup script for everyday use, focus on efficiency and portability.
```
 ___________________________.
|;;|                     |;;||
|[]|---------------------|[]||
|;;|                     |;;||
|;;|                     |;;||
|;;|                     |;;||
|;;|                     |;;||
|;;|                     |;;||
|;;|                     |;;||
|;;|_____________________|;;||
|;;;;;;;;;;;;;;;;;;;;;;;;;;;||
|;;;;;;_______________ ;;;;;||
|;;;;;|  ___          |;;;;;||
|;;;;;| |;;;|         |;;;;;||
|;;;;;| |;;;|         |;;;;;||
|;;;;;| |;;;|         |;;;;;||
|;;;;;| |;;;|         |;;;;;||
|;;;;;| |___|         |;;;;;||
\_____|_______________|_____||
```

## Why ?
*Backup things is really important* !

Try to keep things simple as in `KISS` mantra (*Keep It Simple, Stupid*),
and I try to get this **cross-platform**, everywhere bash can run.
I wanted to share my backup script, and also complete it to fit most,
of common need.

## Features
* Auto generate a unique name for the archive (based on the time).
* Compress as a small tarball the target (LZMA).
* Output a clean log to track events, time and duration.
* Add a running log to be sent to user or just kept if error.
* Add a lock file to track already running task.
* Check if free space is enough before SYNC.
* Clean old archive other that today.
* Sync a remote storage (add).
* Control the date for syncrm (delete).

## Modes
The idea behind the modes, is to setup needed feature smallest possible,
like that we can combine several call with different mode.

This are the modes (-m) you can use with the script.

MODE     | DESCRIPTION
---------|------------
`SYNC`   | **Sync** 2 directory content.
`TARB`   | **Tarball** a directory or file.
`CLEAN`  | **Clean** other archives than today.
`SYNCRM` | **Delete** the missing (cleaned) files in the reference.

## Options
Options are compatible with several modes, and define small param to setup.

CODE | OPTION    | DESCRIPTION
-----|-----------|------------
`-v` | `verbose` | Add verbose mode.
`-h` | `help`    | Show help.
`-f` | `from`    | Location **from**.
`-t` | `to`      | Location **to**.
`-l` | `limit`   | Limit the bandwith allocated to rsync operation.
`-e` | `email`   | Email to use in case of error.


## Usage & Installation
You can clone this repos in your home directory, like:
```
$ git clone https://github.com/GuillaumeSeren/backup.git ~/backup
# Open your crontab:
$ crontab -e
# Add a line like that to save your important directory to your usb drive:
$ ~/backup/backup.sh -f ~/important -t /mnt/usb -m SYNC
# You can also make a tarball, with the time in the name to be unique:
$ ~/backup/backup.sh -f ~/important -t /mnt/usb -m TARB
# Clean old tarball
$ ~/backup/backup.sh -f ~/important -t /mnt/usb -m CLEAN
# Delete cleaned files
$ ~/backup/backup.sh -f ~/important -t /mnt/usb -m SYNCRM
# Bring some help with the -h option:
$ ~/backup/backup.sh -h
```

## Who ?
*Everyone should take backup _seriously_*,
I suggest to have, at least 3 copy on different computer and places (if able to).

A great read on this subject, by jwz: http://www.jwz.org/doc/backups.html

This script try to help you setting up you crontab, and your one-shot archives,
I also use it to keep some website saved and sync between different server.

## Participate !
If you find it useful, and would like to add your tips and tricks in it,
feel free to fork this project and fill a __Pull Request__.

## Licence
The project is GPLv3.
