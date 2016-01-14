#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2016 Joyent, Inc.
#

set -o errexit
set -o pipefail
export HOME=/root
export PATH=$PATH:/opt/local/bin
source /root/.bashrc

if ! manatee-adm verify; then
    echo fail
    exit 1
fi
