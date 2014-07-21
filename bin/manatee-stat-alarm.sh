#!/bin/bash
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
