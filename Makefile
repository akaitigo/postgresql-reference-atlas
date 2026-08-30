SHELL := /bin/bash
CORE_DIR ?= ../reference-atlas-core
LAB ?= sql
ATLAS_ROOT := $(CURDIR)

.NOTPARALLEL: test

.PHONY: validate audit non-regression-audit core-non-regression-audit authority-body-non-regression-audit definitive-audit parity-audit depth-parity-audit authority-locator-verify authority-body-verify authority-review-verify authority-review-determinism-test definitive-skill-eval-verify scenario-proofs-generate scenario-proofs-verify scenario-closure-plan-generate scenario-closure-plan-verify scenario-security-001-run scenario-evidence-atomicity-test docker-volume-cleanup-test workflow-supply-chain-test evidence-dependency-inputs-test evidence-dependency-rerun evidence-dependency-generate evidence-dependency-verify evidence-dependency-negative-test tracked-evidence-generate tracked-generated-freshness tracked-generated-freshness-test ledger-output-verify evidence-pipeline-refresh evidence-pipeline-clean evidence-pipeline-clean-test eval-evidence-dependency-refresh eval-evidence-dependency-clean core-evidence-dependency-audit core-scenario-trace-audit core-scenario-plan-audit core-evidence-durability-audit core-authority-audit core-authority-body-audit core-authority-review-audit core-skill-router-audit definitive-gate claims provenance certificate-verify commit-signature-verify test-static evidence-freshness lab eval refresh-evidence test

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
		$(ATLAS_ROOT)/evidence/scenarios/closure-plan.json \
		$(ATLAS_ROOT)/artifacts/pattern-scenarios/results.json \
		$(ATLAS_ROOT)/evidence/dependency-graph.json \
		$(ATLAS_ROOT)/surface.inventory.yaml \
		$(ATLAS_ROOT)/verification.matrix.yaml \
		$(ATLAS_ROOT)/depth.parity.yaml \
		$(ATLAS_ROOT)/evals/postgresql-atlas.definitive-skill-eval.json \
		$(ATLAS_ROOT)/evals/definitive-skill-router.json \
		$(ATLAS_ROOT)/authority/body-inventory.snapshot.json \
		$(ATLAS_ROOT)/authority/review-queue.snapshot.json \
		$(ATLAS_ROOT)/authority/reviews/decisions.json \
		$(ATLAS_ROOT)/baselines/authority-body-inventory-v1.json \
		$(ATLAS_ROOT)/migrations/authority-body-inventory-v1.json \
		$(ATLAS_ROOT)/migrations/definitive-v2.yaml \
		$(ATLAS_ROOT)/non-regression.yaml \
		$(ATLAS_ROOT)/baselines/core-v1.4-v1.0.0.non-regression-baseline.json \
		$(ATLAS_ROOT)/baselines/core-v1.3-v1.0.0.non-regression-baseline.json \
		$(ATLAS_ROOT)/baselines/core-v1.2-v1.0.0.non-regression-baseline.json \
		$(ATLAS_ROOT)/baselines/core-v1.1-v1.0.0.non-regression-baseline.json \
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

authority-body-non-regression-audit:
	ruby tools/verify-authority-body-baseline.rb

definitive-audit:
	ruby tools/audit-definitive.rb

parity-audit:
	ruby tools/audit-fe-parity.rb

depth-parity-audit:
	ruby tools/audit-postgresql-depth-parity.rb

authority-locator-verify:
	ruby tools/verify-authority-locators.rb

authority-body-verify:
	ruby tools/verify-authority-body-inventory.rb

authority-review-verify:
	ruby tools/verify-authority-review-queue.rb

authority-review-determinism-test:
	ruby tests/authority-review-queue-determinism.rb

definitive-skill-eval-verify:
	ruby tools/verify-definitive-skill-eval.rb

scenario-proofs-generate:
ifeq ($(READ_ONLY_TRACKED_GENERATORS),1)
	ruby tools/verify-generated-output-readonly.rb scenario-proofs
else
	ruby tools/generate-scenario-proofs.rb
endif

scenario-proofs-verify:
	ruby tools/verify-scenario-proofs.rb

scenario-closure-plan-generate:
ifeq ($(READ_ONLY_TRACKED_GENERATORS),1)
	ruby tools/verify-generated-output-readonly.rb scenario-closure-plan
else
	ruby tools/generate-scenario-closure-plan.rb
endif

scenario-closure-plan-verify:
	ruby tools/verify-scenario-closure-plan.rb

scenario-security-001-run:
	ruby tools/run-scenario-security-001.rb

scenario-evidence-atomicity-test:
	ruby tools/test-atomic-evidence-publisher.rb

docker-volume-cleanup-test:
	bash tools/test-docker-volume-cleanup.sh

workflow-supply-chain-test:
	ruby tests/workflow-action-pins.rb

evidence-dependency-inputs-test:
	ruby tests/evidence-dependency-inputs.rb

core-scenario-trace-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate scenario-trace

core-scenario-plan-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate scenario-plan

core-evidence-durability-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate evidence-durability

evidence-dependency-rerun:
	ruby tools/rerun-evidence-dependencies.rb

evidence-dependency-generate:
ifeq ($(READ_ONLY_TRACKED_GENERATORS),1)
	ruby tools/verify-generated-output-readonly.rb graph
else
	ruby tools/generate-evidence-dependency-graph.rb
endif

evidence-dependency-verify:
	ruby tools/verify-evidence-dependency-graph.rb

evidence-dependency-negative-test:
	ruby tools/test-evidence-dependency-graph.rb
	ruby tools/test-tracked-generated-freshness.rb
	ruby tools/test-readonly-generator-command-baseline.rb
	ruby tests/evidence-pipeline-clean.rb
	ruby tests/evidence-dependency-inputs.rb

eval-evidence-dependency-refresh:
	$(MAKE) evidence-pipeline-refresh

eval-evidence-dependency-clean:
	$(MAKE) evidence-pipeline-clean

tracked-evidence-generate:
	bash scripts/static-gates.sh
	bash evals/run.sh
	ruby tools/generate-scenario-proofs.rb
	ruby tools/generate-scenario-closure-plan.rb
	ruby tools/generate-provenance.rb

ledger-output-verify:
	ruby tools/verify-evidence-output-bindings.rb

tracked-generated-freshness:
	ruby tools/verify-tracked-generated-freshness.rb

tracked-generated-freshness-test:
	ruby tools/test-tracked-generated-freshness.rb

evidence-pipeline-refresh:
	$(MAKE) tracked-evidence-generate
	$(MAKE) ledger-output-verify
	$(MAKE) evidence-dependency-generate

evidence-pipeline-clean:
	$(MAKE) ledger-output-verify
	$(MAKE) evidence-dependency-verify
	$(MAKE) tracked-generated-freshness

evidence-pipeline-clean-test:
	ruby tests/evidence-pipeline-clean.rb

core-evidence-dependency-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate evidence-dependency

core-authority-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate authority-extraction

core-authority-body-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate authority-body

core-authority-review-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate authority-review

core-skill-router-audit:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate skill-router

definitive-gate:
	cd $(CORE_DIR) && GOCACHE=$(CURDIR)/.cache/go-build go run ./cmd/atlas audit $(ATLAS_ROOT) --gate definitive

test-static:
ifeq ($(READ_ONLY_TRACKED_GENERATORS),1)
	ruby tools/verify-generated-output-readonly.rb static-gates
else
	bash scripts/static-gates.sh
endif

evidence-freshness:
	ruby tools/evidence-freshness.rb

lab:
	bash scripts/run-lab.sh $(LAB)

eval:
ifeq ($(READ_ONLY_TRACKED_GENERATORS),1)
	ruby tools/verify-generated-output-readonly.rb eval
else
	bash evals/run.sh
endif

claims:
	ruby tools/generate-claims.rb

provenance:
ifeq ($(READ_ONLY_TRACKED_GENERATORS),1)
	ruby tools/verify-generated-output-readonly.rb provenance
else
	ruby tools/generate-provenance.rb
endif

certificate-verify:
	ruby tools/verify-historical-certificate.rb

commit-signature-verify:
	git -c gpg.ssh.allowedSignersFile=$(CURDIR)/.github/allowed_signers verify-commit HEAD

refresh-evidence: eval test-static provenance

test:
	$(MAKE) validate audit
	$(MAKE) non-regression-audit core-non-regression-audit authority-body-non-regression-audit workflow-supply-chain-test
	$(MAKE) definitive-audit parity-audit authority-locator-verify authority-body-verify authority-review-verify authority-review-determinism-test definitive-skill-eval-verify scenario-proofs-verify scenario-closure-plan-verify scenario-evidence-atomicity-test core-scenario-trace-audit core-scenario-plan-audit core-evidence-durability-audit core-authority-audit core-authority-body-audit core-authority-review-audit core-skill-router-audit depth-parity-audit
	@if $(MAKE) definitive-gate; then echo "incomplete repository unexpectedly passed Definitive promotion" >&2; exit 1; fi
	$(MAKE) evidence-pipeline-refresh
	$(MAKE) tracked-generated-freshness
	$(MAKE) evidence-dependency-verify evidence-dependency-negative-test core-evidence-dependency-audit docker-volume-cleanup-test evidence-freshness certificate-verify
	$(MAKE) evidence-pipeline-clean
