# Canonical setup, validation and local run entry points.
# Compatible with GNU Make 3.81 (macOS default). Run `make help` for targets.

SHELL := /bin/bash
export PIP_DISABLE_PIP_VERSION_CHECK := 1

PYTHON ?= python3.13
API_DIR := services/api
API_VENV := $(API_DIR)/.venv
API_BIN := $(API_VENV)/bin
WHEEL_VENV := $(API_DIR)/build/wheel-venv
WEB_DIR := apps/mobile

# Local overrides (ignored by Git); see .env.example.
-include .env

API_HOST ?= 127.0.0.1
API_PORT ?= 8000
ALLOWED_ORIGINS ?= http://localhost:3000
WEB_HOST ?= localhost
WEB_PORT ?= 3000
WEB_CONFIG ?= config/development.json

# API_BASE_URL=<url> overrides the API origin from WEB_CONFIG.
ifdef API_BASE_URL
WEB_DEFINES := --dart-define=API_BASE_URL=$(API_BASE_URL)
else
WEB_DEFINES := --dart-define-from-file=$(WEB_CONFIG)
endif

require = @command -v $(1) >/dev/null 2>&1 || { echo "error: required tool '$(1)' not found on PATH" >&2; exit 127; }
require_api_venv = @test -x $(API_BIN)/python || { echo "error: $(API_VENV) missing; run 'make setup-api'" >&2; exit 1; }

.PHONY: help setup setup-api setup-mobile check check-api check-api-wheel check-mobile \
	run-api run-web build-web serve-web lock-api clean

help:
	@echo "setup         Create the API venv from pinned hashes and fetch locked Flutter packages"
	@echo "check         Run every canonical check (mobile and API); fails on any error"
	@echo "check-mobile  Dart format check, analyze, tests, web release build"
	@echo "check-api     Ruff lint/format check, mypy, pytest, wheel build + clean install check"
	@echo "run-api       Start the API with reload on API_HOST:API_PORT (CORS: ALLOWED_ORIGINS)"
	@echo "run-web       Start the Flutter dev server in Chrome on WEB_PORT"
	@echo "build-web     Release web build (WEB_CONFIG or API_BASE_URL)"
	@echo "serve-web     Serve the release build on WEB_HOST:WEB_PORT (local smoke checks only)"
	@echo "lock-api      Regenerate hashed Python pins after editing pyproject.toml"
	@echo "clean         Remove build outputs and virtual environments"

setup: setup-api setup-mobile

setup-api:
	$(call require,$(PYTHON))
	@$(PYTHON) -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 13) else "error: Python 3.13 required, found " + sys.version.split()[0])'
	$(PYTHON) -m venv $(API_VENV)
	$(API_BIN)/python -m pip install --require-hashes -r $(API_DIR)/requirements-dev.txt

setup-mobile:
	$(call require,flutter)
	cd $(WEB_DIR) && flutter pub get --enforce-lockfile

check: check-mobile check-api

check-mobile:
	$(call require,flutter)
	$(call require,dart)
	cd $(WEB_DIR) && flutter pub get --enforce-lockfile
	cd $(WEB_DIR) && dart format --output=none --set-exit-if-changed lib test
	cd $(WEB_DIR) && flutter analyze --fatal-infos
	cd $(WEB_DIR) && flutter test
	cd $(WEB_DIR) && flutter build web --release --dart-define-from-file=config/development.json

check-api:
	$(require_api_venv)
	cd $(API_DIR) && .venv/bin/ruff check .
	cd $(API_DIR) && .venv/bin/ruff format --check .
	cd $(API_DIR) && .venv/bin/mypy
	cd $(API_DIR) && .venv/bin/pytest
	$(MAKE) check-api-wheel

# Builds the wheel, installs it with only the pinned runtime dependencies into a
# fresh venv, and exercises it from outside the repository in isolated mode.
check-api-wheel:
	$(require_api_venv)
	rm -rf $(API_DIR)/dist $(WHEEL_VENV)
	cd $(API_DIR) && .venv/bin/python -m build --wheel --no-isolation --outdir dist .
	$(API_BIN)/python -m venv $(WHEEL_VENV)
	$(WHEEL_VENV)/bin/python -m pip install --quiet --require-hashes -r $(API_DIR)/requirements.txt
	$(WHEEL_VENV)/bin/python -m pip install --quiet --no-deps --no-index $(API_DIR)/dist/*.whl
	$(WHEEL_VENV)/bin/python -m pip check
	cd "$$(mktemp -d)" && $(CURDIR)/$(WHEEL_VENV)/bin/python -I $(CURDIR)/$(API_DIR)/scripts/check_installed_wheel.py

run-api:
	$(require_api_venv)
	cd $(API_DIR) && ALLOWED_ORIGINS='$(ALLOWED_ORIGINS)' .venv/bin/python -m uvicorn app.main:app \
		--app-dir src --host $(API_HOST) --port $(API_PORT) --reload

run-web:
	$(call require,flutter)
	cd $(WEB_DIR) && flutter run -d chrome --web-hostname $(WEB_HOST) --web-port $(WEB_PORT) $(WEB_DEFINES)

build-web:
	$(call require,flutter)
	cd $(WEB_DIR) && flutter build web --release $(WEB_DEFINES)

serve-web:
	$(call require,$(PYTHON))
	@test -f $(WEB_DIR)/build/web/index.html || { echo "error: run 'make build-web' first" >&2; exit 1; }
	$(PYTHON) -m http.server $(WEB_PORT) --bind $(WEB_HOST) --directory $(WEB_DIR)/build/web

lock-api:
	$(call require,$(PYTHON))
	rm -rf $(API_DIR)/build/lock-venv
	$(PYTHON) -m venv $(API_DIR)/build/lock-venv
	$(API_DIR)/build/lock-venv/bin/python -m pip install --quiet pip-tools==7.6.2
	cd $(API_DIR) && build/lock-venv/bin/pip-compile --quiet --strip-extras --generate-hashes \
		--allow-unsafe --output-file requirements.txt pyproject.toml
	cd $(API_DIR) && build/lock-venv/bin/pip-compile --quiet --strip-extras --generate-hashes \
		--allow-unsafe --extra dev --output-file requirements-dev.txt pyproject.toml

clean:
	rm -rf $(API_DIR)/build $(API_DIR)/dist $(API_VENV) $(WEB_DIR)/build
