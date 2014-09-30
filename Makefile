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

AIRSTACK_ENV_DEVELOPMENT ?= development
AIRSTACK_ENV_TEST ?= test
AIRSTACK_ENV_PRODUCTION ?= production

# Setup output verbosity
ifeq ($(DEBUG_LEVEL),4)
	SHELL := /bin/sh -exv
else
	SHELL := /bin/sh -e
endif
AT := @
DEBUG_STDOUT := 1>/dev/null
DEBUG_STDERR := 2>/dev/null
DEBUG_INFO := 1>/dev/null
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

# User dir for Airstack dependencies, cache, etc.; not project specific
AIRSTACK_HOME ?= ~/.airstack

# Relative path to project specific airstack dir.
# Dir contains build artifacts, project configs, etc.
AIRSTACK_DIR ?= .airstack

# Name of Docker image to build; ex: airstack/core
# Defaults to current working dir's parent dir name
AIRSTACK_IMAGE_NAME ?= $(shell cat $(CURDIR)/env/AIRSTACK_IMAGE_NAME)

# Current build environment: ex: development, test, production
AIRSTACK_ENV ?= $(AIRSTACK_ENV_DEVELOPMENT)

# Docker image tag; ex: development
AIRSTACK_IMAGE_TAG ?= $(AIRSTACK_ENV)

# Build file templates located in AIRSTACK_BUILD_TEMPLATES_DIR.
# Concatenated together on build. Useful for customizing dev vs test vs prod builds.
#
# Example:
# AIRSTACK_BUILD_TEMPLATES_PRODUCTION ?= Dockerfile.base Dockerfile.packages Dockerfile.services
AIRSTACK_BUILD_TEMPLATES_DEVELOPMENT ?= Dockerfile.development
AIRSTACK_BUILD_TEMPLATES_PRODUCTION ?= Dockerfile.production
AIRSTACK_BUILD_TEMPLATES_TEST ?= Dockerfile.test

AIRSTACK_BUILD_TEMPLATES ?= $(AIRSTACK_BUILD_$(AIRSTACK_ENV))


################################################################################
# CONFIG VARS
################################################################################

AIRSTACK_BOOTSTRAP_HOME ?= $(AIRSTACK_HOME)/package/airstack/bootstrap

AIRSTACK_USERNAME ?= airstack
AIRSTACK_USERDIR ?= $(AIRSTACK_USERNAME)

AIRSTACK_BUILD_TEMPLATES_DIR ?= $(CURDIR)/Dockerfiles
AIRSTACK_BUILD_DIR ?= $(AIRSTACK_DIR)/build
AIRSTACK_IGNOREFILE ?= $(CURDIR)/.airstackignore
AIRSTACK_IMAGE_FULLNAME ?= $(AIRSTACK_IMAGE_NAME):$(AIRSTACK_IMAGE_TAG)

AIRSTACK_RUN_MODE ?= multi
AIRSTACK_CMD ?= sh -c '{ /etc/runit/2 $(AIRSTACK_RUN_MODE) &}'
AIRSTACK_SHELL ?= chpst -u $(AIRSTACK_USERNAME) /bin/bash
AIRSTACK_CMD_CONSOLE ?= sh -c '{ /etc/runit/2 $(AIRSTACK_RUN_MODE) &}; $(AIRSTACK_SHELL)'

AIRSTACK_BASE_IMAGE := debian:jessie

DOCKER_OPTS_USER ?=
DOCKER_OPTS_RUN ?= --detach
DOCKER_OPTS_RUN_CONSOLE ?= --rm -it
DOCKER_OPTS_BUILD ?= --rm
DOCKER_OPTS_COMMON ?= --publish-all --workdir /home/$(AIRSTACK_USERDIR) -e HOME=$(AIRSTACK_USERDIR) $(AIRSTACK_IMAGE_FULLNAME)

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
	$(AT)$(foreach var,$(AIRSTACK_BUILD_TEMPLATES),$(shell test -e $(AIRSTACK_BUILD_TEMPLATES_DIR)/$(var) || touch $(AIRSTACK_BUILD_TEMPLATES_DIR)/$(var) ))
	$(AT)test -d $(AIRSTACK_BUILD_DIR) || mkdir -vp $(AIRSTACK_BUILD_DIR)
	$(AT)test -f $(AIRSTACK_IGNOREFILE) || cp $(AIRSTACK_BOOTSTRAP_HOME)/templates/airstackignore $(AIRSTACK_IGNOREFILE) $(DEBUG_STDOUT) $(DEBUG_STDERR)
	@# TODO: add call to ~/.airstack/bootstrap/init to populate .airstackignore ???
	@# TODO: split boot2docker commands into separate init ???
	@# TODO: add items from ~/.airstack/...bootstrap/templates/gitignore to .gitignore as needed
	@# TODO: check if @$ is "init" and run `make help`
ifeq ($(PLATFORM),osx)
ifneq ($(shell boot2docker status $(DEBUG_STDERR)),running)
	@# TODO: add check for boot2docker; output url to boot2docker install page if needed
	$(AT)boot2docker $(DEBUG_VERBOSE_FLAG) up $(DEBUG_STDOUT) $(DEBUG_STDERR)
	$(AT)sleep 1 # sleep to prevent incorrect results from boot2docker ip
endif
	$(eval export DOCKER_HOST ?= tcp://$(shell boot2docker ip 2>/dev/null):2375)
endif

.PHONY: update
update:
	$(AT)test -d $(AIRSTACK_BOOTSTRAP_HOME) || ( echo "missing the bootstrap directory" && exit 1)
	$(AT)cd $(AIRSTACK_BOOTSTRAP_HOME) && git pull origin master

.PHONY: help
help:
	@echo Need to implement help
	@# @echo USAGE:
	@# @echo make build-dev
	@# @echo make build-dev console-dev
	@# @echo make -j5 build-all


################################################################################
# BUILD COMMANDS
#
# Commands for building containers.
################################################################################

.PHONY: build-all
build-all: build-development build-test build-production

.PHONY: build
build: build-development

# Rebuild dev image without using the cache
.PHONY: build-debug
build-debug:
	$(AT)$(MAKE) DOCKER_OPTS_BUILD='--rm --no-cache' build-development

.PHONY: build-dev build-development
build-dev: build-development
build-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) AIRSTACK_BUILD_TEMPLATES="$(AIRSTACK_BUILD_TEMPLATES_DEVELOPMENT)" build-image

.PHONY: build-test
build-test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) AIRSTACK_BUILD_TEMPLATES="$(AIRSTACK_BUILD_TEMPLATES_TEST)" build-image

.PHONY: build-prod build-production
build-prod: build-production
build-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) AIRSTACK_BUILD_TEMPLATES="$(AIRSTACK_BUILD_TEMPLATES_PRODUCTION)" build-image


################################################################################
# BUILD HELPERS
################################################################################

.PHONY: build-tarball
build-tarball:
	$(AT)tar $(DEBUG_VERBOSE_FLAG) -cf $(AIRSTACK_BUILD_DIR)/build.$(IMAGE_TAG_FILENAME).tar -C $(CURDIR) -X $(AIRSTACK_IGNOREFILE) . $(DEBUG_STDERR)

.PHONY: build-tarball-docker
build-tarball-docker: build-tarball
	$(AT)> $(AIRSTACK_BUILD_DIR)/Dockerfile.$(IMAGE_TAG_FILENAME)
	$(AT)$(foreach var,$(AIRSTACK_BUILD_TEMPLATES),cat $(AIRSTACK_BUILD_TEMPLATES_DIR)/$(var) >> $(AIRSTACK_BUILD_DIR)/Dockerfile.$(IMAGE_TAG_FILENAME);)
	$(AT)tar $(DEBUG_VERBOSE_FLAG) -C $(AIRSTACK_BUILD_DIR) --append -s /Dockerfile.$(IMAGE_TAG_FILENAME)/Dockerfile/ --file=$(AIRSTACK_BUILD_DIR)/build.$(IMAGE_TAG_FILENAME).tar Dockerfile.$(IMAGE_TAG_FILENAME) $(DEBUG_STDERR)

.PHONY: build-docker
build-docker: init build-tarball-docker
	$(AT)docker build $(DOCKER_OPTS_BUILD) --tag $(AIRSTACK_IMAGE_FULLNAME) - < $(AIRSTACK_BUILD_DIR)/build.$(IMAGE_TAG_FILENAME).tar $(DEBUG_STDOUT) $(DEBUG_STDERR)
	@printf "\
	[BUILT] $(AIRSTACK_IMAGE_FULLNAME)\n\
	" $(DEBUG_INFO)

.PHONY: build-image
build-image: build-docker


################################################################################
# CLEAN COMMANDS
#
# Commands for cleaning up leftover container build artifacts.
################################################################################

.PHONY: clean-all
clean: clean-all
clean-all: clean-development clean-test clean-production clean-tarballs

.PHONY: clean-tag
clean-tag: init
	@echo "Removing Docker image: $(AIRSTACK_IMAGE_FULLNAME)" $(DEBUG_INFO)
	$(AT)! docker rmi -f $(AIRSTACK_IMAGE_FULLNAME) $(DEBUG_STDERR)

.PHONY: clean-dev clean-development
clean-dev: clean-development
clean-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) clean-tag

.PHONY: clean-test
clean-test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) clean-tag

.PHONY: clean-prod clean-production
clean-prod: clean-production
clean-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) clean-tag

.PHONY: clean-build-dir
clean-tarballs:
	@echo "Removing tarballs: $(AIRSTACK_BUILD_DIR)/*.tar" $(DEBUG_INFO)
ifeq ($(CURDIR),$(findstring $(CURDIR),$(AIRSTACK_BUILD_DIR)))
	$(AT)rm $(DEBUG_VERBOSE_FLAG) -f $(AIRSTACK_BUILD_DIR)/*.tar $(DEBUG_STDERR)
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
	$(AT)$(MAKE) DOCKER_OPTS_RUN="$(DOCKER_OPTS_RUN_CONSOLE)" AIRSTACK_CMD="$(AIRSTACK_CMD_CONSOLE)" run

# Run console without starting any services
.PHONY: debug console-debug
debug: console-debug
console-debug:
	$(AT)$(MAKE) AIRSTACK_CMD_CONSOLE="$(AIRSTACK_SHELL)" console

.PHONY: console-dev console-development
console-dev: console-development
console-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) console

.PHONY: console-test
console-test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) console

.PHONY: console-prod console-production
console-prod: console-production
console-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) console

.PHONY: console-single
console-single:
	$(AT)$(MAKE) AIRSTACK_RUN_MODE=single console


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
	$(AT)docker run $(DOCKER_OPTS_RUN) $(OS_SPECIFIC_RUNOPTS) $(DOCKER_OPTS_USER) $(DOCKER_OPTS_COMMON) $(AIRSTACK_CMD) $(DEBUG_STDERR)

.PHONY: run-dev run-development
run-dev: run-development
run-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) run

.PHONY: run-test
run-test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) run

.PHONY: run-prod run-production
run-prod: run-production
run-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) run

.PHONY: run-base
run-base: init
	$(AT)docker run --rm -it $(AIRSTACK_BASE_IMAGE) /bin/bash $(DEBUG_STDERR)


################################################################################
# TEST COMMANDS
################################################################################

# .PHONY: test-runner
# test-runner:
# 	$(AT)$(MAKE) AIRSTACK_CMD_CONSOLE="/command/core-test-runner -f /package/airstack/test/*_spec.lua" console

.PHONY: test
test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) AIRSTACK_CMD_CONSOLE="/command/core-test-runner -f /package/airstack/test/*_spec.lua" console

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
