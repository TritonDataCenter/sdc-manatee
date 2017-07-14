#!/bin/bash
# -*- mode: shell-script; fill-column: 80; -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2017, Joyent, Inc.
#

PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export PS4
set -o xtrace

#
# Disable the protection against RST reflection denial-of-service attacks.
# In order for system liveliness when PostgreSQL is not running, we need to
# be able to send a RST for every inbound connection to a closed port.  This
# is only safe because we run Manatee on an isolated network.
#
# The long-term stability of this interface is not completely clear, so we
# ignore the exit status of ndd(1M).  To do otherwise may unintentionally
# create a flag day with future platform versions.
#
/usr/sbin/ndd -set /dev/tcp tcp_rst_sent_rate_enabled 0

# set shared_buffers to 1/4 provisoned RSS
set -o errexit
set -o pipefail

shared_buffers="$(( $(prtconf -m) / 4 ))MB"
# maintenance_work_mem should be 1/128th of the zone's dram.
maintenance_work_mem="$(( $(prtconf -m) / 128 ))MB"

function expandPgConfig() {
    ETC_DIR=$1

    # Make a backup if one doesn't already exist.
    if [[ ! -f $ETC_DIR/postgresql.sdc.conf.in ]]; then
        cp $ETC_DIR/postgresql.sdc.conf $ETC_DIR/postgresql.sdc.conf.in
    fi

    sed -e "s#@@SHARED_BUFFERS@@#$shared_buffers#g" \
        -e "s#@@MAINTENANCE_WORK_MEM@@#$maintenance_work_mem#g" \
        $ETC_DIR/postgresql.sdc.conf.in > $ETC_DIR/postgresql.sdc.conf
}

expandPgConfig /opt/smartdc/manatee/etc/9.2
expandPgConfig /opt/smartdc/manatee/etc/9.6

set +o errexit
set +o pipefail

# For SDC we want to check if we should enable or disable the sitter on each boot.
svccfg import /opt/smartdc/manatee/smf/manifests/sitter.xml
disableSitter=$(json disableSitter < /opt/smartdc/manatee/etc/sitter.json)
if [[ -n ${disableSitter} && ${disableSitter} == "true" ]]; then
    # HEAD-1327 we want to be able to disable the sitter on the 2nd manatee we
    # create as part of the dance required to go from 1 -> 2+ nodes. This should
    # only ever be set for the 2nd manatee.
    echo "Disabing sitter per /opt/smartdc/manatee/etc/sitter.json"
    svcadm disable manatee-sitter
else
    echo "Starting sitter"
    svcadm enable manatee-sitter
fi

exit 0
