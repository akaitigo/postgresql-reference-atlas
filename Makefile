SHELL := /bin/bash
CORE_DIR ?= ../reference-atlas-core
LAB ?= sql
ATLAS_ROOT := $(CURDIR)

.PHONY: validate audit claims provenance certificate-verify test-static evidence-freshness lab eval refresh-evidence test

validate:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate \
		$(ATLAS_ROOT)/atlas.yaml \
		$(ATLAS_ROOT)/mastery.yaml \
		$(ATLAS_ROOT)/sources.lock.yaml \
		$(ATLAS_ROOT)/coverage.yaml \
		$(ATLAS_ROOT)/skill.package.yaml \
		$(ATLAS_ROOT)/provenance.yaml \
		$(ATLAS_ROOT)/third_party/manifest.yaml
	@if [[ -d claims ]]; then \
		find claims -name '*.claim.yaml' -type f -print0 | while IFS= read -r -d '' file; do \
			(cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate "$(ATLAS_ROOT)/$$file") || exit 1; \
		done; \
	fi
	@if [[ -d evidence ]]; then \
		find evidence -name '*.evidence.yaml' -type f -print0 | while IFS= read -r -d '' file; do \
			(cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate "$(ATLAS_ROOT)/$$file") || exit 1; \
		done; \
	fi
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate \
		$(ATLAS_ROOT)/evals/postgresql-router.skill-eval.json \
		$(ATLAS_ROOT)/evidence/completion-certificate.json

audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT)

test-static:
	bash scripts/static-gates.sh

evidence-freshness:
	ruby tools/evidence-freshness.rb

lab:
	bash scripts/run-lab.sh $(LAB)

eval:
	bash evals/run.sh

claims:
	ruby tools/generate-claims.rb

provenance:
	ruby tools/generate-provenance.rb

certificate-verify:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas certificate verify $(ATLAS_ROOT)

refresh-evidence: eval test-static provenance

test: validate audit evidence-freshness certificate-verify
