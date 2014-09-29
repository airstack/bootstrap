# THIS MAKEFILE CAN BE COPIED INTO AN AIRSTACK IMAGE PROJECT

# Set variables here
# AIRSTACK_IMAGE_NAME := airstack/core
# AIRSTACK_BUILD_TEMPLATES_DIR := $(AIRSTACK_DIR)/config
# AIRSTACK_BUILD_TEMPLATES_PRODUCTION := Dockerfile.base Dockerfile.packages Dockerfile.services
# AIRSTACK_BUILD_TEMPLATES_DEVELOPMENT := Dockerfile.base Dockerfile.packages Dockerfile.packages.development Dockerfile.services Dockerfile.services.development Dockerfile.services.tests
# AIRSTACK_BUILD_TEMPLATES_TEST := $(AIRSTACK_BUILD_DEVELOPMENT)


################################################################################
# BOOTSTRAP MAKEFILE: DO NOT EDIT BELOW THIS LINE
AIRSTACK_HOME ?= ~/.airstack
ifeq ($(shell test -d $(AIRSTACK_HOME)/package/airstack/bootstrap && echo y),y)
include $(AIRSTACK_HOME)/package/airstack/bootstrap/Makefile
else
.PHONY: init
init:
  curl -s https://raw.githubusercontent.com/airstack/bootstrap/master/install | sh -e
  @$(MAKE) init
.DEFAULT:
	@echo Please run \'make init\' to initialize Airstack
endif
