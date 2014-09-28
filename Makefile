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
	SHELL := /bin/sh -xv
else
	SHELL := /bin/sh
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

# Relative path to airstack dir; for cache, configs, etc.
AIRSTACK_DIR ?= .airstack

# Name of Docker image to build; ex: airstack/core
# Defaults to current working dir's parent dir name
AIRSTACK_IMAGE_NAME ?= $(notdir $(patsubst %/,%,$(dir $(CURDIR))))

# Current build environment: ex: development, test, production
AIRSTACK_ENV ?= $(AIRSTACK_ENV_DEVELOPMENT)

# Docker image tag; ex: development
AIRSTACK_IMAGE_TAG ?= $(AIRSTACK_ENV)

# Build file templates located in AIRSTACK_BUILD_DIR.
# Concatenated together on build. Useful for customizing dev vs test vs prod builds.
#
# Example:
# AIRSTACK_BUILD_PRODUCTION ?= Dockerfile.base Dockerfile.packages Dockerfile.services
AIRSTACK_BUILD_DEVELOPMENT ?= Dockerfile.development
AIRSTACK_BUILD_PRODUCTION ?= Dockerfile.production
AIRSTACK_BUILD_TEST ?= Dockerfile.test

AIRSTACK_BUILD ?= $(AIRSTACK_BUILD_$(AIRSTACK_ENV))


################################################################################
# CONFIG VARS
################################################################################
AIRSTACK_USERNAME ?= airstack
AIRSTACK_USERDIR ?= $(AIRSTACK_USERNAME)

AIRSTACK_BUILD_DIR ?= $(AIRSTACK_DIR)/build
AIRSTACK_CACHE_DIR ?= $(AIRSTACK_DIR)/cache
AIRSTACK_IGNOREFILE ?= $(AIRSTACK_DIR)/.airstackignore

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
AIRSTACK_CACHE_DIR := $(CURDIR)/$(AIRSTACK_CACHE_DIR)

PLATFORM := $(shell [ $$(uname -s 2>/dev/null) = Darwin ] && echo osx || echo linux)
ifeq ($(PLATFORM),osx)
	OS_SPECIFIC_RUNOPTS := $(DOCKER_OPTS_OSX)
else
	OS_SPECIFIC_RUNOPTS := $(DOCKER_OPTS_LINUX)
endif

# .PHONY should include all commands. Arrange in order that they appear in the Makefile
.PHONY: default all init bootstrap help \
	build build-all build-debug build-dev build-development build-prod build-production build-test \
	build-tarball build-tarball-docker build-docker build-image \
	clean clean-all clean-tag clean-dev clean-development clean-prod clean-production clean-test clean-cache \
	debug \
	console console-debug console-dev console-development console-prod console-production console-test console-single \
	console-single console-single-dev console-single-prod \
	run run-dev run-development run-prod run-production run-test run-base \
	test test-all test-runner test-dev test-development test-prod test-production \
	repair stats ps ssh-vm \


################################################################################
# GENERAL COMMANDS
################################################################################

default: build

all: build-all

bootstrap:
	@printf "\n\
	========================================\n\
	        Already bootstrapped!\n\
	========================================\n\n" $(DEBUG_INFO)
	$(AT)$(MAKE) help

init:
	@# TODO: move all file related tasks to non PHONY tasks; no need to test if files exists since that's what make does by default
	$(AT)$(foreach var,$(AIRSTACK_BUILD),$(shell [ -e $(AIRSTACK_BUILD_DIR)/$(var) ] || touch $(AIRSTACK_BUILD_DIR)/$(var) ]))
	$(AT)[ -d $(AIRSTACK_CACHE_DIR) ] || mkdir -vp $(AIRSTACK_CACHE_DIR)
	@# TODO: add call to ~/.airstack/bootstrap/init to populate .airstackignore ???
	@# TODO: split boot2docker commands into separate init ???
ifeq ($(PLATFORM),osx)
ifneq ($(shell boot2docker status $(DEBUG_STDERR)),running)
	$(AT)boot2docker $(DEBUG_VERBOSE_FLAG) up $(DEBUG_STDOUT) $(DEBUG_STDERR)
endif
$(AT)export DOCKER_HOST=tcp://$(shell boot2docker ip $(DEBUG_STDERR)):2375
endif

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

build-all: build-development build-test build-production

build: build-development

# Rebuild dev image without using the cache
build-debug:
	$(AT)$(MAKE) DOCKER_OPTS_BUILD='--rm --no-cache' build-development

build-dev: build-development
build-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) AIRSTACK_BUILD="$(AIRSTACK_BUILD_DEVELOPMENT)" build-image

build-test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) AIRSTACK_BUILD="$(AIRSTACK_BUILD_TEST)" build-image

build-prod: build-production
build-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) AIRSTACK_BUILD="$(AIRSTACK_BUILD_PRODUCTION)" build-image


################################################################################
# BUILD HELPERS
################################################################################

build-tarball:
	$(AT)tar $(DEBUG_VERBOSE_FLAG) -cf $(AIRSTACK_CACHE_DIR)/build.$(IMAGE_TAG_FILENAME).tar -C $(CURDIR) -X $(AIRSTACK_IGNOREFILE) . $(DEBUG_STDERR)

build-tarball-docker: build-tarball
	$(AT)> $(AIRSTACK_CACHE_DIR)/Dockerfile.$(IMAGE_TAG_FILENAME)
	$(AT)$(foreach var,$(AIRSTACK_BUILD),cat $(AIRSTACK_BUILD_DIR)/$(var) >> $(AIRSTACK_CACHE_DIR)/Dockerfile.$(IMAGE_TAG_FILENAME);)
	$(AT)tar $(DEBUG_VERBOSE_FLAG) -C $(AIRSTACK_CACHE_DIR) --append -s /Dockerfile.$(IMAGE_TAG_FILENAME)/Dockerfile/ --file=$(AIRSTACK_CACHE_DIR)/build.$(IMAGE_TAG_FILENAME).tar Dockerfile.$(IMAGE_TAG_FILENAME) $(DEBUG_STDERR)

build-docker: init build-tarball-docker
	$(AT)docker build $(DOCKER_OPTS_BUILD) --tag $(AIRSTACK_IMAGE_FULLNAME) - < $(AIRSTACK_CACHE_DIR)/build.$(IMAGE_TAG_FILENAME).tar $(DEBUG_STDOUT) $(DEBUG_STDERR)
	@printf "\
	[DONE] $(AIRSTACK_IMAGE_FULLNAME)\n\
	" $(DEBUG_INFO)

build-image: build-docker


################################################################################
# CLEAN COMMANDS
#
# Commands for cleaning up leftover container build artifacts.
################################################################################

clean: clean-all
clean-all: clean-development clean-test clean-production clean-cache

clean-tag: init
	@echo "Removing Docker image: $(AIRSTACK_IMAGE_FULLNAME)" $(DEBUG_INFO)
	$(AT)! docker rmi -f $(AIRSTACK_IMAGE_FULLNAME) $(DEBUG_STDERR)

clean-dev: clean-development
clean-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) clean-tag

clean-test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) clean-tag

clean-prod: clean-production
clean-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) clean-tag

clean-cache:
	@echo "Cleaning cache dir: $(AIRSTACK_CACHE_DIR)" $(DEBUG_INFO)
ifeq ($(CURDIR),$(findstring $(CURDIR),$(AIRSTACK_CACHE_DIR)))
	$(AT)rm $(DEBUG_VERBOSE_FLAG) -rf $(AIRSTACK_CACHE_DIR) $(DEBUG_STDERR)
else
	@printf "\n[WARNING] Not deleting cache directory\n\n"
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

console:
	$(AT)$(MAKE) DOCKER_OPTS_RUN="$(DOCKER_OPTS_RUN_CONSOLE)" AIRSTACK_CMD="$(AIRSTACK_CMD_CONSOLE)" run

# Run console without starting any services
debug: console-debug
console-debug:
	$(AT)$(MAKE) AIRSTACK_CMD_CONSOLE="$(AIRSTACK_SHELL)" console

console-dev: console-development
console-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) console

console-test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) console

console-prod: console-production
console-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) console

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

run: init
	$(AT)docker run $(DOCKER_OPTS_RUN) $(OS_SPECIFIC_RUNOPTS) $(DOCKER_OPTS_USER) $(DOCKER_OPTS_COMMON) $(AIRSTACK_CMD) $(DEBUG_STDERR)

run-dev: run-development
run-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) run

run-test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) run

run-dev: run-production
run-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) run

run-base: init
	$(AT)docker run --rm -it $(AIRSTACK_BASE_IMAGE) /bin/bash $(DEBUG_STDERR)


################################################################################
# TEST COMMANDS
################################################################################

test-all: test test-development test-production

test-runner:
	$(AT)$(MAKE) AIRSTACK_CMD_CONSOLE="core-test-runner -f /package/airstack/test/*_spec.lua" console

test:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) test-runner

test-dev: test-development
test-development:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) test-runner

test-prod: test-production
test-production:
	$(AT)$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) test-runner


################################################################################
# DOCKER COMMANDS
#
# Convenience helper commands for managing docker
################################################################################

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

stats: init
	$(AT)docker images | grep $(AIRSTACK_IMAGE_NAME) $(DEBUG_STDERR)

ps: init
	$(AT)docker ps $(DEBUG_STDERR)

ssh-vm: init
ifeq ($(PLATFORM),osx)
	$(AT)boot2docker $(DEBUG_VERBOSE_FLAG) ssh $(DEBUG_STDERR)
endif
