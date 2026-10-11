# Canonical setup, validation and local run entry points.
# Compatible with GNU Make 3.81 (macOS default). Run `make help` for targets.

SHELL := /bin/bash
export PIP_DISABLE_PIP_VERSION_CHECK := 1
export SUPABASE_TELEMETRY_DISABLED := 1
export DO_NOT_TRACK := 1

PYTHON ?= python3.13
API_DIR := services/api
API_VENV := $(API_DIR)/.venv
API_BIN := $(API_VENV)/bin
WHEEL_VENV := $(API_DIR)/build/wheel-venv
WEB_DIR := apps/mobile
SUPABASE_CLI_DIR := .tools/supabase-cli
SUPABASE := $(CURDIR)/$(SUPABASE_CLI_DIR)/supabase

# Local overrides (ignored by Git); see .env.example.
-include .env

API_HOST ?= 127.0.0.1
API_PORT ?= 8000
ALLOWED_ORIGINS ?= http://localhost:3000
WEB_HOST ?= localhost
WEB_PORT ?= 3000
WEB_CONFIG ?= config/development.json

# Local Supabase stack. These are the stack's fixed, public local values; the
# API never receives a privileged key.
SUPABASE_URL ?= http://127.0.0.1:54321
SUPABASE_PUBLISHABLE_KEY ?= sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH
SUPABASE_JWT_ISSUER ?= http://127.0.0.1:54321/auth/v1
# Supabase URL compiled into the web app (a phone needs the Mac's LAN address).
WEB_SUPABASE_URL ?= $(SUPABASE_URL)

# API_BASE_URL=<url> replaces WEB_CONFIG with explicit public defines (LAN use).
ifdef API_BASE_URL
WEB_DEFINES := --dart-define=API_BASE_URL=$(API_BASE_URL) \
	--dart-define=SUPABASE_URL=$(WEB_SUPABASE_URL) \
	--dart-define=SUPABASE_PUBLISHABLE_KEY=$(SUPABASE_PUBLISHABLE_KEY)
else
WEB_DEFINES := --dart-define-from-file=$(WEB_CONFIG)
endif

require = @command -v $(1) >/dev/null 2>&1 || { echo "error: required tool '$(1)' not found on PATH" >&2; exit 127; }
# Pub only enforces the lower bound of `environment.flutter`, so the exact pin
# in pubspec.yaml is checked against the installed SDK here.
FLUTTER_VERSION := $(shell sed -n 's/^  flutter: *//p' $(WEB_DIR)/pubspec.yaml)
require_flutter = $(call require,flutter)
require_flutter += ; actual="$$(flutter --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')"; \
	test -n "$(FLUTTER_VERSION)" && test "$$actual" = "$(FLUTTER_VERSION)" || \
	{ echo "error: Flutter $(FLUTTER_VERSION) required (pinned in $(WEB_DIR)/pubspec.yaml), found '$$actual'" >&2; exit 1; }
require_api_venv = @test -x $(API_BIN)/python || { echo "error: $(API_VENV) missing; run 'make setup-api'" >&2; exit 1; }
require_supabase = @test -x $(SUPABASE) || { echo "error: Supabase CLI missing; run 'make setup-supabase'" >&2; exit 1; }
require_docker = @docker info >/dev/null 2>&1 || { echo "error: Docker is not running; start Docker Desktop" >&2; exit 1; }
# Exports the running local stack's settings (including privileged keys) as
# SB_* variables for the one command that follows. Fails if the stack is down.
supabase_env = status="$$($(SUPABASE) status -o env --agent no 2>/dev/null)" || \
	{ echo "error: local Supabase is not running; run 'make supabase-start'" >&2; exit 1; }; \
	eval "$$(printf '%s\n' "$$status" | sed 's/^/export SB_/')"

.PHONY: help setup setup-api setup-mobile setup-supabase check check-api check-api-wheel \
	check-mobile check-integration supabase-start supabase-stop supabase-status \
	provision-user list-users run-api run-web build-web serve-web lock-api clean

help:
	@echo "setup             API venv (hashed pins), locked Flutter packages, pinned Supabase CLI"
	@echo "check             Every canonical check (mobile, API, integration); fails on any error"
	@echo "check-mobile      Dart format check, analyze, tests, web release build"
	@echo "check-api         Ruff lint/format check, mypy, unit tests, wheel build + clean install"
	@echo "check-integration Start local Supabase and run the real auth/data/storage tests"
	@echo "supabase-start    Start the local Supabase stack (Docker required); -stop / -status"
	@echo "provision-user    Optional test account (USERNAME=... PASSWORD=...); users normally sign up in the app"
	@echo "list-users        List local accounts"
	@echo "run-api           API with reload on API_HOST:API_PORT, using the local Supabase stack"
	@echo "run-web           Start the Flutter dev server in Chrome on WEB_PORT"
	@echo "build-web         Release web build (WEB_CONFIG or API_BASE_URL)"
	@echo "serve-web         Serve the release build on WEB_HOST:WEB_PORT (local smoke checks only)"
	@echo "lock-api          Regenerate hashed Python pins after editing pyproject.toml"
	@echo "clean             Remove build outputs, virtual environments and the local Supabase CLI"

setup: setup-api setup-mobile setup-supabase

setup-api:
	$(call require,$(PYTHON))
	@$(PYTHON) -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 13) else "error: Python 3.13 required, found " + sys.version.split()[0])'
	$(PYTHON) -m venv $(API_VENV)
	$(API_BIN)/python -m pip install --require-hashes -r $(API_DIR)/requirements-dev.txt

setup-mobile:
	$(require_flutter)
	cd $(WEB_DIR) && flutter pub get --enforce-lockfile

setup-supabase:
	scripts/install-supabase-cli.sh $(SUPABASE_CLI_DIR)

check: check-mobile check-api check-integration

check-mobile:
	$(require_flutter)
	$(call require,dart)
	cd $(WEB_DIR) && flutter pub get --enforce-lockfile
	cd $(WEB_DIR) && dart format --output=none --set-exit-if-changed lib test
	cd $(WEB_DIR) && flutter analyze --fatal-infos
	cd $(WEB_DIR) && flutter test
	cd $(WEB_DIR) && flutter build web --release --dart-define-from-file=config/development.json \
		--output $(CURDIR)/$(WEB_DIR)/build/check-web

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

# Real auth/data/storage tests against disposable fixtures on the local stack.
check-integration:
	$(require_api_venv)
	$(require_supabase)
	$(require_docker)
	$(SUPABASE) start --agent no
	$(supabase_env); export SUPABASE_BIN=$(SUPABASE); \
		cd $(API_DIR) && .venv/bin/pytest -m integration -p no:cacheprovider

supabase-start:
	$(require_supabase)
	$(require_docker)
	$(SUPABASE) start --agent no

supabase-stop:
	$(require_supabase)
	$(SUPABASE) stop --agent no

supabase-status:
	$(require_supabase)
	$(SUPABASE) status --agent no

provision-user:
	$(require_api_venv)
	$(require_supabase)
	@test -n "$(USERNAME)" || { echo "usage: make provision-user USERNAME=alice PASSWORD=..." >&2; exit 2; }
	@$(supabase_env); PROVISION_PASSWORD='$(PASSWORD)' $(API_BIN)/python $(API_DIR)/scripts/provision_local_user.py '$(USERNAME)'

list-users:
	$(require_api_venv)
	$(require_supabase)
	@$(supabase_env); $(API_BIN)/python $(API_DIR)/scripts/provision_local_user.py --list

run-api:
	$(require_api_venv)
	cd $(API_DIR) && ALLOWED_ORIGINS='$(ALLOWED_ORIGINS)' SUPABASE_URL='$(SUPABASE_URL)' \
		SUPABASE_PUBLISHABLE_KEY='$(SUPABASE_PUBLISHABLE_KEY)' SUPABASE_JWT_ISSUER='$(SUPABASE_JWT_ISSUER)' \
		.venv/bin/python -m uvicorn app.main:app --app-dir src --host $(API_HOST) --port $(API_PORT) --reload

run-web:
	$(require_flutter)
	cd $(WEB_DIR) && flutter run -d chrome --web-hostname $(WEB_HOST) --web-port $(WEB_PORT) $(WEB_DEFINES)

build-web:
	$(require_flutter)
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
	rm -rf $(API_DIR)/build $(API_DIR)/dist $(API_VENV) $(WEB_DIR)/build $(SUPABASE_CLI_DIR)
