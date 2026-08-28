SHELL := /bin/bash
CORE_DIR ?= ../reference-atlas-core
LAB ?= sql

.PHONY: validate test-static lab eval test

validate:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate \
		../postgresql-reference-atlas/atlas.yaml \
		../postgresql-reference-atlas/sources.lock.yaml \
		../postgresql-reference-atlas/coverage.yaml \
		../postgresql-reference-atlas/skill.package.yaml
	@if [[ -d evidence ]]; then \
		find evidence -name '*.evidence.yaml' -type f -print0 | while IFS= read -r -d '' file; do \
			(cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate "../postgresql-reference-atlas/$$file") || exit 1; \
		done; \
	fi

test-static:
	bash scripts/static-gates.sh

lab:
	bash scripts/run-lab.sh $(LAB)

eval:
	bash evals/run.sh

test: validate test-static eval
