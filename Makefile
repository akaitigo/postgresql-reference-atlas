SHELL := /bin/bash
CORE_DIR ?= ../reference-atlas-core
LAB ?= sql
ATLAS_ROOT := $(CURDIR)

.PHONY: validate audit non-regression-audit core-non-regression-audit definitive-audit parity-audit depth-parity-audit authority-locator-verify core-authority-audit definitive-gate claims provenance certificate-verify test-static evidence-freshness lab eval refresh-evidence test

validate:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate \
		$(ATLAS_ROOT)/atlas.yaml \
		$(ATLAS_ROOT)/mastery.yaml \
		$(ATLAS_ROOT)/sources.lock.yaml \
		$(ATLAS_ROOT)/coverage.yaml \
		$(ATLAS_ROOT)/skill.package.yaml \
		$(ATLAS_ROOT)/provenance.yaml \
		$(ATLAS_ROOT)/third_party/manifest.yaml \
		$(ATLAS_ROOT)/definitive.yaml \
		$(ATLAS_ROOT)/surface.inventory.yaml \
		$(ATLAS_ROOT)/verification.matrix.yaml \
		$(ATLAS_ROOT)/depth.parity.yaml \
		$(ATLAS_ROOT)/evals/postgresql-atlas.definitive-skill-eval.json \
		$(ATLAS_ROOT)/migrations/definitive-v2.yaml \
		$(ATLAS_ROOT)/non-regression.yaml \
		$(ATLAS_ROOT)/baselines/v1.0.0.non-regression-baseline.json \
		$(ATLAS_ROOT)/evidence/history/v1.0.0/completion-certificate.json
	@if [[ -d claims ]]; then \
		find claims -name '*.claim.yaml' -type f -print0 | while IFS= read -r -d '' file; do \
			(cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate "$(ATLAS_ROOT)/$$file") || exit 1; \
		done; \
	fi
	@if [[ -d gaps/claims ]]; then \
		find gaps/claims -name '*.claim.yaml' -type f -print0 | while IFS= read -r -d '' file; do \
			(cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate "$(ATLAS_ROOT)/$$file") || exit 1; \
		done; \
	fi
	@if [[ -d evidence ]]; then \
		find evidence -name '*.evidence.yaml' -type f -print0 | while IFS= read -r -d '' file; do \
			(cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate "$(ATLAS_ROOT)/$$file") || exit 1; \
		done; \
	fi
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate \
		$(ATLAS_ROOT)/evals/postgresql-router.skill-eval.json
	@if [[ -f evidence/completion-certificate.json ]]; then \
		(cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas validate $(ATLAS_ROOT)/evidence/completion-certificate.json); \
	fi

audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT)

non-regression-audit:
	ruby tools/audit-non-regression.rb

core-non-regression-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate non-regression

definitive-audit:
	ruby tools/audit-definitive.rb

parity-audit:
	ruby tools/audit-fe-parity.rb

depth-parity-audit:
	ruby tools/audit-postgresql-depth-parity.rb

authority-locator-verify:
	ruby tools/verify-authority-locators.rb

core-authority-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate authority-extraction

definitive-gate:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate definitive

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
	ruby tools/verify-historical-certificate.rb

refresh-evidence: eval test-static provenance

test: validate audit non-regression-audit core-non-regression-audit definitive-audit parity-audit authority-locator-verify core-authority-audit depth-parity-audit evidence-freshness certificate-verify
