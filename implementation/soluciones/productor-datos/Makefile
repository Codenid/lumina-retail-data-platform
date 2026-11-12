PYTHON ?= python3
HOST ?= 127.0.0.1
PORT ?= 8081
APP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
IMPL_DIR := $(abspath $(APP_DIR)/../..)

.PHONY: start install auth run

start: install run

install:
	$(PYTHON) -m pip install -r "$(APP_DIR)/requirements.txt"

auth:
	gcloud auth application-default login

run:
	cd "$(APP_DIR)" && set -a && . "$(IMPL_DIR)/config.env" && set +a && $(PYTHON) -m uvicorn app:app --host "$(HOST)" --port "$(PORT)"
