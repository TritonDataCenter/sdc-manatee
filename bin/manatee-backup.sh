#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# manatee-backup: backup the current manatee instnace
#

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail

function usage() {
cat << HERE
usage: $0

Backup this manatee instance

OPTIONS:
-h Show this message
-v Verbose

EXAMPLE:
$0 sdc
HERE
}

while getopts "h:v" OPTION
do
    case $OPTION in
        h)
            usage
            exit 1
            ;;
        v)
            verbose=true
            set -o xtrace
            ;;
        ?)
            usage
            exit
            ;;
    esac
done

if [[ -z $verbose ]]
then
    BACKUP_FILE=$1
else
    BACKUP_FILE=$2
fi

if [[ -z $BACKUP_FILE ]]
then
    echo 'no backup file specified'
    exit 1
fi

# get the latest zfs snapshot
SNAPSHOT=$(zfs list -o name -t snapshot | grep manatee | tail -1)
if [[ -z $SNAPSHOT ]]
then
    echo 'no manatee snapshots found'
    exit 1
fi

zfs send $SNAPSHOT > $BACKUP_FILE
