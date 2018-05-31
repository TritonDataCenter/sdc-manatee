#!/bin/bash
# -*- mode: shell-script; fill-column: 80; -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

SOURCE="${BASH_SOURCE[0]}"
if [[ -h $SOURCE ]]; then
    SOURCE="$(readlink "$SOURCE")"
fi
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
PROFILE=/root/.bashrc
SVC_ROOT=/opt/smartdc/manatee
role=manatee
REGISTRAR_CFG=/opt/smartdc/registrar/etc/config.json

export PATH=$SVC_ROOT/build/node/bin:/opt/local/bin:/usr/sbin/:/usr/bin:$PATH

# Install zookeeper package, need to touch this file to disable the license prompt
touch /opt/local/.dli_license_accepted


function sdc_manatee_setup {
    # vars used by manatee-* tools
    ZONE_UUID=$(json -f /var/tmp/metadata.json ZONE_UUID)
    DATASET=zones/$ZONE_UUID/data/manatee
    PARENT_DATASET=zones/$ZONE_UUID/data
    DATASET_MOUNT_DIR=/manatee/pg
    PG_DIR=/manatee/pg/data
    PG_LOG_DIR=/var/pg
    BINDER_ADMIN_IPS=$(json -f /var/tmp/metadata.json binder_admin_ips)

    # Cookie to identify this as a SmartDC zone and its role
    mkdir -p /var/smartdc/$role
    mkdir -p /opt/smartdc/$role/ssl

    #echo "Installing local node.js"
    mkdir -p /opt/smartdc/$role/etc
    /usr/bin/chown -R root:root /opt/smartdc

    #cron
    mkdir -p /var/log/manatee/
    local crontab=/tmp/.sdc_manatee_cron
    crontab -l > $crontab

    echo "0 0 * * * /opt/smartdc/manatee/pg_dump/pg_dump.sh >> /var/log/manatee/pgdump.log 2>&1" >> $crontab
    [[ $? -eq 0 ]] || fatal "Unable to write to $crontab"
    crontab $crontab
    [[ $? -eq 0 ]] || fatal "Unable import crons"

    # rotate pgdump logs
    sdc_log_rotation_add pgdump /var/log/manatee/pgdump.log 1g

    common_manatee_setup

    common_enable_services
}

function common_enable_services {
    # import services
    echo "Starting snapshotter"
    svccfg import /opt/smartdc/manatee/smf/manifests/snapshotter.xml
    svcadm enable manatee-snapshotter

    echo "Starting backupserver"
    svccfg import /opt/smartdc/manatee/smf/manifests/backupserver.xml
    svcadm enable manatee-backupserver

    svccfg import /opt/smartdc/manatee/smf/manifests/sitter.xml
    # For SDC we'll let configure decide if it wants to enable sitter or not.
}

function common_manatee_setup {
    #
    # Enable LZ4 compression and set the recordsize to 8KB on the top-level
    # delegated dataset.  The Manatee dataset is a child dataset, and will
    # inherit these properties -- even if it is subsequently recreated by a
    # rebuild operation.
    #
    echo "enabling LZ4 compression on manatee dataset"
    zfs set compress=lz4 "$PARENT_DATASET"

    echo "setting recordsize to 8K on manatee dataset"
    zfs set recordsize=8k "$PARENT_DATASET"

    # create manatee dataset
    echo "creating manatee dataset"
    zfs create -o canmount=noauto $DATASET

    echo "make snapdir property match the ancestor's"
    zfs inherit -r snapdir $DATASET

    # create postgres group
    echo "creating postgres group (gid=907)"
    groupadd -g 907 postgres

    # create postgres user
    echo "creating postgres user (uid=907)"
    useradd -u 907 -g postgres postgres

    # grant postgres user chmod chown privileges with sudo
    echo "postgres    ALL=(ALL) NOPASSWD: /usr/bin/chown, /usr/bin/chmod, /opt/local/bin/chown, /opt/local/bin/chmod" >> /opt/local/etc/sudoers

    # give postgres user zfs permmissions.
    echo "grant postgres user zfs perms"
    zfs allow -ld postgres create,destroy,diff,hold,release,rename,setuid,rollback,share,snapshot,mount,promote,send,receive,clone,mountpoint,canmount $PARENT_DATASET

    # change dataset perms such that manatee can access the dataset and mount/unmount
    mkdir -p $DATASET_MOUNT_DIR
    chown -R postgres $DATASET_MOUNT_DIR
    chmod 700 -R $DATASET_MOUNT_DIR

    # set mountpoint
    zfs set mountpoint=$DATASET_MOUNT_DIR $DATASET

    # mount the dataset
    zfs mount $DATASET

    # make the pg data dir
    echo "creating $PG_DIR"
    mkdir -p $PG_DIR
    chown postgres $PG_DIR
    chmod 700 $PG_DIR

    # add pg log dir
    mkdir -p $PG_LOG_DIR
    chown -R postgres $PG_LOG_DIR
    chmod 700 $PG_LOG_DIR
}

function add_manatee_profile_functions {
    ZK_IPS=${BINDER_ADMIN_IPS}

    # .bashrc
    #
    # - An external promise to sdcadm (e.g. `sdcadm post-setup ha-binder`) is
    #   that the following works:
    #       zlogin $manateeUuid 'source ~/.bashrc; manatee-adm state'
    #   this requires having both "manatee-adm" and ".../build/node/bin/node"
    #   on the PATH.
    #
    echo "export PATH=\$PATH:/opt/smartdc/manatee/bin/:/opt/smartdc/manatee/pg_dump/:/opt/smartdc/manatee/build/node/bin:/opt/smartdc/manatee/node_modules/manatee/bin:/opt/postgresql/current/bin" >> /root/.bashrc
    echo "export MANPATH=\$MANPATH:/opt/smartdc/manatee/node_modules/manatee/man" >> /root/.bashrc

    # get correct ZK_IPS
    echo "source /opt/smartdc/etc/zk_ips.sh" >> $PROFILE
    echo "export ZK_IPS=\"\$(echo \$ZK_IPS | cut -d' ' -f1)\"" >> $PROFILE

    # export shard
    local shard=$(cat /opt/smartdc/manatee/etc/sitter.json | json shardPath | \
        cut -d '/' -f3)
    echo "export SHARD=$shard" >> $PROFILE

    # export sitter config
    echo "export MANATEE_SITTER_CONFIG=/opt/smartdc/manatee/etc/sitter.json" \
        >> $PROFILE

    #functions
    echo "zbunyan() { bunyan -c \"this.component !== 'ZKPlus'\"; }" >> $PROFILE
    echo "mbunyan() { bunyan -c \"this.component !== 'ZKPlus'\"  -c 'level >= 30'; }" >> $PROFILE
    echo "msitter(){ tail -f \`svcs -L manatee-sitter\` | mbunyan; }" >> $PROFILE
    echo "mbackupserver(){ tail -f \`svcs -L manatee-backupserver\` | mbunyan; }" >> $PROFILE
    echo "msnapshotter(){ tail -f \`svcs -L manatee-snapshotter\` | mbunyan; }" >> $PROFILE
    echo "manatee-stat(){ manatee-adm status; }" >> $PROFILE
}


# Local manifests
CONFIG_AGENT_LOCAL_MANIFESTS_DIRS=/opt/smartdc/$role

# Include common utility functions (then run the boilerplate)
source /opt/smartdc/boot/lib/util.sh
sdc_common_setup

# Do the SDC-specific manatee stuff.
sdc_manatee_setup
add_manatee_profile_functions

# add log rotation
sdc_log_rotation_add manatee-sitter /var/svc/log/*manatee-sitter*.log 1g
sdc_log_rotation_add manatee-snapshotter /var/svc/log/*manatee-snapshotter*.log 1g
sdc_log_rotation_add manatee-backupserver /var/svc/log/*manatee-backupserver*.log 1g
sdc_log_rotation_add manatee-postgres /var/pg/postgresql.log 1g
sdc_log_rotation_setup_end

# All done, run boilerplate end-of-setup
sdc_setup_complete

exit 0
