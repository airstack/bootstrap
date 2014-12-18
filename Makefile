#######################################
# VARIABLES
#
# Set these at runtime to override the below defaults.
# e.g.:
# `make AIRSTACK_CMD=/bin/bash console`
# `make AIRSTACK_USERNAME=root AIRSTACK_CMD=/bin/bash run`
# `make AIRSTACK_IMAGE_TAG=1.2-debug build`
# `make AIRSTACK_ENV=development build`
#######################################

# ENV constants

# DEBUG LEVELS
# 0 - no output
# 1 - print info
# 2 - print info, stdout, and stderr
# 3 - verbose
# 4 - very verbose
DEBUG_LEVEL ?= 2

# Setup output verbosity
ifeq ($(DEBUG_LEVEL),4)
SHELL := /bin/sh -exv
else
SHELL := /bin/sh -e
endif

AT := @
DEBUG_STDOUT := 1>/dev/null
DEBUG_STDERR := 2>/dev/null
DEBUG_INFO := >&2

ifeq ($(shell test $(DEBUG_LEVEL) -gt 0 && echo y),y)
DEBUG_INFO :=
endif
ifeq ($(shell test $(DEBUG_LEVEL) -gt 1 && echo y),y)
DEBUG_STDOUT :=
DEBUG_STDERR :=
endif
ifeq ($(shell test $(DEBUG_LEVEL) -gt 2 && echo y),y)
AT :=
DEBUG_VERBOSE_FLAG := -v
endif
ifeq ($(shell test $(DEBUG_LEVEL) -gt 3 && echo y),y)
DEBUG_VERBOSE_FLAG := -vv
endif


################################################################################
# COMMONLY OVERRIDDEN VARS
################################################################################

# Prefix used for commands that enable a terminal
TERM ?= eval

# User dir for Airstack dependencies, cache, etc.; not project specific
AIRSTACK_HOME ?= ~/.airstack

# Relative path to project specific airstack dir.
# Dir contains build artifacts, project configs, etc.
AIRSTACK_DIR ?= .airstack

# Name of Docker image to build; ex: airstack/core
# Defaults to current working dir's parent dir name
AIRSTACK_IMAGE_NAME ?= $(shell cat $(CURDIR)/env/AIRSTACK_IMAGE_NAME)

# Current build environment: ex: development, test, production
AIRSTACK_ENV ?= development

# Docker image tag; ex: development
AIRSTACK_IMAGE_TAG ?= $(AIRSTACK_ENV)

AIRSTACK_BUILD_TEMPLATES_FILES ?= $(AIRSTACK_BUILD_$(AIRSTACK_ENV))


################################################################################
# CONFIG VARS
################################################################################

AIRSTACK_BASE_IMAGE ?= debian:jessie

AIRSTACK_BOOTSTRAP_HOME ?= $(AIRSTACK_HOME)/package/airstack/bootstrap

AIRSTACK_USERNAME ?= airstack
AIRSTACK_USERDIR ?= $(AIRSTACK_USERNAME)

AIRSTACK_BUILD_TEMPLATES_DIR ?= $(CURDIR)/Dockerfiles
AIRSTACK_BUILD_DIR ?= $(AIRSTACK_DIR)/build
AIRSTACK_IGNOREFILE ?= $(CURDIR)/.airstackignore
AIRSTACK_IMAGE_FULLNAME ?= $(AIRSTACK_IMAGE_NAME):$(AIRSTACK_IMAGE_TAG)

AIRSTACK_RUN_MODE ?= multi

AIRSTACK_SHELL ?= chpst -u $(AIRSTACK_USERNAME) /bin/bash
# AIRSTACK_CMD ?= sh -c '{ /etc/runit/2 $(AIRSTACK_RUN_MODE) &}'
AIRSTACK_CMD_CONSOLE ?= sh -c '{ /etc/runit/2 $(AIRSTACK_RUN_MODE) &}; $(AIRSTACK_SHELL)'

DOCKER_OPTS_USER ?=
DOCKER_OPTS_RUN ?= --detach
DOCKER_OPTS_RUN_CONSOLE ?= --rm -it
DOCKER_OPTS_BUILD ?= --rm
DOCKER_OPTS_COMMON ?= --publish-all --workdir /home/$(AIRSTACK_USERDIR) -e HOME=$(AIRSTACK_USERDIR) $(AIRSTACK_IMAGE_FULLNAME)

ifeq ($(AIRSTACK_NO_CACHE),1)
DOCKER_OPTS_BUILD += --no-cache
endif

SUBMAKE := $(MAKE) -f $(firstword $(MAKEFILE_LIST))

# TODO: remove auto mounting of host files; CLI handles mounting
# DOCKER_OPTS_LINUX ?= --volume $(CURR_DIR)/:/files/host/
# DOCKER_OPTS_OSX ?= --volume $(ROOTDIR)/:/files/host/

# Replace / and \ and spaces with underscores
IMAGE_TAG_FILENAME := $(shell echo $(AIRSTACK_IMAGE_TAG) | sed -e 's/[\/ \\]/_/g')

# TODO: only expand var if first char is not a '/'
AIRSTACK_BUILD_DIR := $(CURDIR)/$(AIRSTACK_BUILD_DIR)

PLATFORM := $(shell [ $$(uname -s 2>/dev/null) = Darwin ] && echo osx || echo linux)
ifeq ($(PLATFORM),osx)
OS_SPECIFIC_RUNOPTS := $(DOCKER_OPTS_OSX)
else
OS_SPECIFIC_RUNOPTS := $(DOCKER_OPTS_LINUX)
endif


################################################################################
# GENERAL COMMANDS
################################################################################

default: build

.PHONY: all
all: build-all

.PHONY: init
init:
	@# TODO: move all file related tasks to non PHONY tasks; no need to test if files exists since that's what make does by default
	$(AT)test -d $(AIRSTACK_BUILD_TEMPLATES_DIR) || mkdir -vp $(AIRSTACK_BUILD_TEMPLATES_DIR)
	$(AT)$(foreach var,$(AIRSTACK_BUILD_TEMPLATES_FILES),$(shell test -e $(AIRSTACK_BUILD_TEMPLATES_DIR)/$(var) || touch $(AIRSTACK_BUILD_TEMPLATES_DIR)/$(var) ))
	$(AT)test -d $(AIRSTACK_BUILD_DIR) || mkdir -vp $(AIRSTACK_BUILD_DIR)
	$(AT)test -f $(AIRSTACK_IGNOREFILE) || cp $(AIRSTACK_BOOTSTRAP_HOME)/templates/airstackignore $(AIRSTACK_IGNOREFILE) $(DEBUG_STDOUT) $(DEBUG_STDERR)
	@# TODO: add call to ~/.airstack/bootstrap/init to populate .airstackignore ???
	@# TODO: split boot2docker commands into separate init ???
	@# TODO: add items from ~/.airstack/...bootstrap/templates/gitignore to .gitignore as needed
ifeq ($(PLATFORM),osx)
ifneq ($(shell boot2docker status $(DEBUG_STDERR)),running)
	@# TODO: add check for boot2docker; output url to boot2docker install page if needed
	$(AT)boot2docker $(DEBUG_VERBOSE_FLAG) up $(DEBUG_STDOUT) $(DEBUG_STDERR)
	$(AT)sleep 1 # sleep to prevent incorrect results from boot2docker ip
endif
	$(eval export DOCKER_HOST ?= tcp://$(shell boot2docker ip 2>/dev/null):2376)
	$(eval export DOCKER_CERT_PATH ?= $(shell echo $$HOME)/.boot2docker/certs/boot2docker-vm)
	$(eval export DOCKER_TLS_VERIFY ?= 1)
endif

.PHONY: update
update:
	$(AT)test -d $(AIRSTACK_BOOTSTRAP_HOME) || ( echo "missing the bootstrap directory" && exit 1)
	$(AT)cd $(AIRSTACK_BOOTSTRAP_HOME) && git pull origin master


################################################################################
# BUILD COMMANDS
#
# Commands for building containers.
################################################################################


.PHONY: build
build: build-docker

# Rebuild dev image without using the cache
.PHONY: build-debug
build-debug:
	$(SUBMAKE) AIRSTACK_NO_CACHE=1 build

.PHONY: build-tarball
build-tarball:
	$(AT)tar $(DEBUG_VERBOSE_FLAG) -cf $(AIRSTACK_BUILD_DIR)/build.$(IMAGE_TAG_FILENAME).tar -C $(CURDIR) -X $(AIRSTACK_IGNOREFILE) . $(DEBUG_STDERR)

.PHONY: build-tarball-docker
build-tarball-docker: build-tarball
	$(AT)> $(AIRSTACK_BUILD_DIR)/Dockerfile.$(IMAGE_TAG_FILENAME)
	$(AT)$(foreach var,$(AIRSTACK_BUILD_TEMPLATES_FILES),cat $(AIRSTACK_BUILD_TEMPLATES_DIR)/$(var) >> $(AIRSTACK_BUILD_DIR)/Dockerfile.$(IMAGE_TAG_FILENAME);)
	# -s /search/replace/ is specific to bsdtar, use --transform for GNU tar
	$(AT)tar $(DEBUG_VERBOSE_FLAG) -C $(AIRSTACK_BUILD_DIR) --append -s /Dockerfile.$(IMAGE_TAG_FILENAME)/Dockerfile/ --file=$(AIRSTACK_BUILD_DIR)/build.$(IMAGE_TAG_FILENAME).tar Dockerfile.$(IMAGE_TAG_FILENAME) $(DEBUG_STDERR)

.PHONY: build-docker
build-docker: init build-tarball-docker
	$(AT)docker build $(DOCKER_OPTS_BUILD) --tag $(AIRSTACK_IMAGE_FULLNAME) - < $(AIRSTACK_BUILD_DIR)/build.$(IMAGE_TAG_FILENAME).tar $(DEBUG_STDOUT) $(DEBUG_STDERR)
	@printf "\
	[BUILT] $(AIRSTACK_IMAGE_FULLNAME)\n\
	" $(DEBUG_INFO)


################################################################################
# CLEAN COMMANDS
#
# Commands for cleaning up leftover container build artifacts.
################################################################################

.PHONY: clean
clean: clean-image clean-tarball

.PHONY: clean-image
clean-image: init
	@echo "Removing Docker image: $(AIRSTACK_IMAGE_FULLNAME)" $(DEBUG_INFO)
	-$(AT)docker rmi -f $(AIRSTACK_IMAGE_FULLNAME) $(DEBUG_STDERR)

.PHONY: clean-tarball
clean-tarball:
	@echo "Removing tarballs: $(AIRSTACK_BUILD_DIR)/*.$(AIRSTACK_ENV).tar" $(DEBUG_INFO)
ifeq ($(CURDIR),$(findstring $(CURDIR),$(AIRSTACK_BUILD_DIR)))
	$(AT)rm $(DEBUG_VERBOSE_FLAG) -f $(AIRSTACK_BUILD_DIR)/*.$(AIRSTACK_ENV).tar $(DEBUG_STDERR)
else
	@printf "\n[WARNING] Not deleting tarballs. Build dir must be a child of current dir.\n\n"
endif


################################################################################
# CONSOLE COMMANDS
#
# Commands for running containers in a console window in foreground.
#
# The commands named console-single* will launch containers with
# only the remote /dev/log forwarder running on start
# Commands without *single* will run containers in multi mode, with
# all 'up' services running.
#
# CTRL-C Exits and does auto-cleanup.
################################################################################

.PHONY: console
console:
	$(SUBMAKE) DOCKER_OPTS_RUN="$(DOCKER_OPTS_RUN_CONSOLE)" AIRSTACK_CMD="$(AIRSTACK_CMD_CONSOLE)" run

# Run console in single mode
.PHONY: console-single
console-single:
	$(SUBMAKE) AIRSTACK_RUN_MODE=single console

# Run console without starting any services
.PHONY: shell
shell:
	$(SUBMAKE) AIRSTACK_CMD_CONSOLE="$(AIRSTACK_SHELL)" console


################################################################################
# RUN COMMANDS
#
# Commands for running containers in background.
#
# Outputs id of daemonized container
# To cleanup, run `docker rm <imageid>` after stopping container.
################################################################################

.PHONY: run
run: init
	$(AT)$(TERM) "docker run $(DOCKER_OPTS_RUN) $(OS_SPECIFIC_RUNOPTS) $(DOCKER_OPTS_USER) $(DOCKER_OPTS_COMMON) $(AIRSTACK_CMD) $(DEBUG_STDERR)"

.PHONY: run-base
run-base: init
	$(AT)docker run --rm -it $(AIRSTACK_BASE_IMAGE) /bin/bash $(DEBUG_STDERR)



################################################################################
# DOCKER COMMANDS
#
# Convenience helper commands for managing docker
################################################################################

.PHONY: repair
repair:
ifeq ($(PLATFORM),osx)
	@printf "\n\
	=====================\n\
	Repairing boot2docker\n\
	=====================\n\
	" $(DEBUG_INFO)

	@printf "\nTurning off existing boot2docker VMs..." $(DEBUG_INFO)
	$(AT)boot2docker $(DEBUG_VERBOSE_FLAG) poweroff $(DEBUG_STDOUT) $(DEBUG_STDERR)
	@printf "DONE\n" $(DEBUG_INFO)

	@printf "\nRemoving existing boot2docker setup..." $(DEBUG_INFO)
	$(AT)boot2docker $(DEBUG_VERBOSE_FLAG) destroy $(DEBUG_STDOUT) $(DEBUG_STDERR)
	@printf "DONE\n" $(DEBUG_INFO)

	@printf "\nInitializing new boot2docker setup..." $(DEBUG_INFO)
	$(AT)boot2docker $(DEBUG_VERBOSE_FLAG) init $(DEBUG_STDOUT) $(DEBUG_STDERR)
	@printf "DONE\n" $(DEBUG_INFO)
endif

.PHONY: stats
stats: init
	$(AT)docker images | grep $(AIRSTACK_IMAGE_NAME) $(DEBUG_STDERR)

.PHONY: ps
ps: init
	$(AT)docker ps $(DEBUG_STDERR)

.PHONY: ssh-vm
ssh-vm: init
ifeq ($(PLATFORM),osx)
	$(AT)boot2docker $(DEBUG_VERBOSE_FLAG) ssh $(DEBUG_STDERR)
endif
