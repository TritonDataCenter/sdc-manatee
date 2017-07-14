#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2017, Joyent, Inc.
#

#
# Tools
#
TAR = tar
UNAME := $(shell uname)
ifeq ($(UNAME), SunOS)
	TAR = gtar
endif

#
# Files
#
SMF_MANIFESTS_IN = smf/manifests/backupserver.xml.in \
		smf/manifests/sitter.xml.in \
		smf/manifests/snapshotter.xml.in

#
# Variables
#

NODE_PREBUILT_VERSION   := v0.10.26
NODE_PREBUILT_TAG       := zone
# Allow building on a SmartOS image other than sdc-multiarch/13.3.1.
NODE_PREBUILT_IMAGE=b4bdc598-8939-11e3-bea4-8341f6861379


include ./tools/mk/Makefile.defs
include ./tools/mk/Makefile.node_prebuilt.defs
include ./tools/mk/Makefile.smf.defs

RELEASE_TARBALL         := sdc-manatee-pkg-$(STAMP).tar.bz2
ROOT                    := $(shell pwd)
RELSTAGEDIR             := /tmp/$(STAMP)

#
# Env variables
#
PATH            := $(NODE_INSTALL)/bin:${PATH}

#
# Repo-specific targets
#
.PHONY: all
all: $(SMF_MANIFESTS) | $(NPM_EXEC) $(REPO_DEPS) sdc-scripts
	$(NPM) install

DISTCLEAN_FILES = ./node_modules

.PHONY: release
release: all deps docs pg $(SMF_MANIFESTS)
	@echo "Building $(RELEASE_TARBALL)"
	@mkdir -p $(RELSTAGEDIR)/root/opt/smartdc/manatee/deps
	@mkdir -p $(RELSTAGEDIR)/root/opt/smartdc/boot
	@mkdir -p $(RELSTAGEDIR)/site
	@touch $(RELSTAGEDIR)/site/.do-not-delete-me
	@mkdir -p $(RELSTAGEDIR)/root
	cp -r   $(ROOT)/build \
		$(ROOT)/bin \
		$(ROOT)/etc \
		$(ROOT)/node_modules \
		$(ROOT)/package.json \
		$(ROOT)/pg_dump \
		$(ROOT)/sapi_manifests \
		$(ROOT)/smf \
		$(RELSTAGEDIR)/root/opt/smartdc/manatee/
	cp -r $(ROOT)/deps/sdc-scripts \
	    $(RELSTAGEDIR)/root/opt/smartdc/manatee/deps
	mkdir -p $(RELSTAGEDIR)/root/opt/smartdc/boot/scripts
	cp -R $(ROOT)/boot/* \
	    $(RELSTAGEDIR)/root/opt/smartdc/boot/
	cp -R $(ROOT)/deps/sdc-scripts/* \
	    $(RELSTAGEDIR)/root/opt/smartdc/boot/
	(cd $(RELSTAGEDIR) && $(TAR) -jcf $(ROOT)/$(RELEASE_TARBALL) root site)
	@rm -rf $(RELSTAGEDIR)

.PHONY: publish
publish: release
	@if [[ -z "$(BITS_DIR)" ]]; then \
		echo "error: 'BITS_DIR' must be set for 'publish' target"; \
		exit 1; \
	fi
	mkdir -p $(BITS_DIR)/sdc-manatee
	cp $(ROOT)/$(RELEASE_TARBALL) $(BITS_DIR)/sdc-manatee/$(RELEASE_TARBALL)

sdc-scripts: deps/sdc-scripts/.git

.PHONY: pg
pg: all deps/postgresql92/.git deps/postgresql96/.git deps/pg_repack/.git
	$(MAKE) -C node_modules/manatee -f Makefile.postgres \
		RELSTAGEDIR="$(RELSTAGEDIR)" \
		DEPSDIR="$(ROOT)/deps"

include ./tools/mk/Makefile.deps
include ./tools/mk/Makefile.node_prebuilt.targ
include ./tools/mk/Makefile.smf.targ
include ./tools/mk/Makefile.targ

