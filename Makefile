SHELL := /bin/bash
CORE_DIR ?= ../reference-atlas-core
LAB ?= sql
ATLAS_ROOT := $(CURDIR)

.PHONY: validate audit definitive-audit definitive-gate claims provenance certificate-verify test-static evidence-freshness lab eval refresh-evidence test

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
		$(ATLAS_ROOT)/evals/postgresql-atlas.definitive-skill-eval.json \
		$(ATLAS_ROOT)/migrations/definitive-v2.yaml
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

definitive-audit:
	ruby tools/audit-definitive.rb

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
	@if [[ -f evidence/completion-certificate.json ]]; then \
		(cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas certificate verify $(ATLAS_ROOT)); \
	else \
		echo "Definitive再監査中のため現行Certificateは未発行です"; \
	fi

refresh-evidence: eval test-static provenance

test: validate audit definitive-audit evidence-freshness certificate-verify
