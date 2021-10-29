#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2021 Joyent, Inc.
#

NAME = sdc-manatee

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

NODE_PREBUILT_VERSION   := v0.10.48
NODE_PREBUILT_TAG       := zone
# sdc-minimal-multiarch-lts 15.4.1
NODE_PREBUILT_IMAGE=18b094b0-eb01-11e5-80c1-175dac7ddf02

ENGBLD_USE_BUILDIMAGE	= true
ENGBLD_REQUIRE		:= $(shell git submodule update --init deps/eng)
include ./deps/eng/tools/mk/Makefile.defs
TOP ?= $(error Unable to access eng.git submodule Makefiles.)

include ./deps/eng/tools/mk/Makefile.node_prebuilt.defs
include ./deps/eng/tools/mk/Makefile.agent_prebuilt.defs
include ./deps/eng/tools/mk/Makefile.smf.defs

RELEASE_TARBALL         := $(NAME)-pkg-$(STAMP).tar.gz
ROOT                    := $(shell pwd)
RELSTAGEDIR             := /tmp/$(NAME)-$(STAMP)

BASE_IMAGE_UUID = 04a48d7d-6bb5-4e83-8c3b-e60a99e0f48f
BUILDIMAGE_NAME = sdc-postgres
BUILDIMAGE_DESC	= SDC manatee
BUILDIMAGE_DO_PKGSRC_UPGRADE = true
BUILDIMAGE_PKGSRC = lz4-131nb1
AGENTS		= amon config registrar waferlock

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
	(cd $(RELSTAGEDIR) && $(TAR) -I pigz -cf $(ROOT)/$(RELEASE_TARBALL) root site)
	@rm -rf $(RELSTAGEDIR)

.PHONY: publish
publish: release
	mkdir -p $(ENGBLD_BITS_DIR)/$(NAME)
	cp $(ROOT)/$(RELEASE_TARBALL) $(ENGBLD_BITS_DIR)/$(NAME)/$(RELEASE_TARBALL)

sdc-scripts: deps/sdc-scripts/.git

.PHONY: pg
pg: all deps/postgresql92/.git deps/postgresql96/.git deps/pg_repack/.git
	$(MAKE) -C node_modules/manatee -f Makefile.postgres \
		RELSTAGEDIR="$(RELSTAGEDIR)" \
		DEPSDIR="$(ROOT)/deps"

include ./deps/eng/tools/mk/Makefile.deps
include ./deps/eng/tools/mk/Makefile.node_prebuilt.targ
include ./deps/eng/tools/mk/Makefile.agent_prebuilt.targ
include ./deps/eng/tools/mk/Makefile.smf.targ
include ./deps/eng/tools/mk/Makefile.targ
