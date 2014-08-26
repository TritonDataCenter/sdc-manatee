#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

set -o errexit
set -o pipefail
export HOME=/root
export PATH=$PATH:/opt/local/bin
source /root/.bashrc

shard=$(cat /opt/smartdc/manatee/etc/sitter.json | json shardPath | cut -d '/' -f3)
topology=$(manatee-stat| json -D / $shard)
primary=
sync=

if [[ -z $topology ]]; then
    echo fail && exit;
fi

primary=$(echo $topology | json primary.repl.sync_state)
sync=$(echo $topology | json sync.repl.sync_state)

if [[ $primary != 'sync' ]]; then
    echo fail && exit;
fi
if [[ $sync != 'async' ]]; then
    echo fail;
fi
