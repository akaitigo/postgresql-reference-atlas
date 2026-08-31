SHELL := /bin/bash
CORE_DIR ?= ../reference-atlas-core
LAB ?= sql
ATLAS_ROOT := $(CURDIR)

.NOTPARALLEL: test

.PHONY: validate audit non-regression-audit core-non-regression-audit authority-body-non-regression-audit definitive-audit parity-audit depth-parity-audit authority-locator-verify authority-body-verify authority-review-verify authority-review-determinism-test definitive-skill-eval-verify scenario-proofs-generate scenario-proofs-verify scenario-closure-plan-generate scenario-closure-plan-verify security-tranche-contract-test security-published-tranche-contract-test security-next-tranche-contract-test security-next-tranche-row-contracts-test security-next-tranche-runtime-implementation-test security-next-tranche-runtime-hygiene-test security-next-tranche-oracles-test security-next-tranche-negative-coverage-test security-query-partitioning-contract-test security-query-partitioning-sql-contract-test security-query-security-contract-test security-query-security-sql-contract-test security-query-security-runtime-auth-contract-test security-query-security-json-contract-test security-query-sql-surface-contract-test security-query-sql-surface-sql-contract-test security-query-types-constraints-contract-test security-query-types-constraints-sql-contract-test security-runtime-live-preflight-test security-runtime-readiness-contract-test security-query-catalog-inventory-contract-test security-query-extension-contract-test security-publication-provenance-contract-test security-performance-statistics-contract-test security-runtime-contract-test security-runtime-failure-retention-test security-failure-diagnostic-test security-wal-oracle-contract-test security-performance-execution-oracle-contract-test security-performance-execution-sql-contract-test security-performance-index-oracle-contract-test security-performance-index-sql-contract-test security-performance-index-fixture-math-test security-performance-structured-failure-contract-test query-sql-commands-partial-contract-test scenario-security-001-run scenario-evidence-atomicity-test docker-volume-cleanup-test workflow-supply-chain-test evidence-dependency-inputs-test evidence-dependency-rerun evidence-dependency-generate evidence-dependency-verify evidence-dependency-negative-test tracked-evidence-generate tracked-generated-freshness tracked-generated-freshness-test ledger-output-refresh ledger-output-refresh-test ledger-output-verify evidence-pipeline-refresh evidence-pipeline-clean evidence-pipeline-clean-test eval-evidence-dependency-refresh eval-evidence-dependency-clean core-evidence-dependency-audit core-scenario-trace-audit core-scenario-plan-audit core-evidence-durability-audit core-authority-audit core-authority-body-audit core-authority-review-audit core-skill-router-audit definitive-gate claims provenance certificate-verify commit-signature-verify test-static evidence-freshness lab eval refresh-evidence test

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

security-tranche-contract-test:
	ruby tests/security-scenario-tranche.rb

security-published-tranche-contract-test:
	ruby tests/security-published-tranche-contract.rb

security-next-tranche-contract-test:
	ruby tests/security-next-tranche-contract.rb

security-next-tranche-row-contracts-test:
	ruby tests/security-next-tranche-row-contracts.rb

security-next-tranche-runtime-implementation-test:
	ruby tests/security-next-tranche-runtime-implementation.rb

security-next-tranche-runtime-hygiene-test:
	ruby tests/security-next-tranche-runtime-hygiene.rb

security-next-tranche-oracles-test:
	ruby tests/security-next-tranche-oracles.rb

security-next-tranche-negative-coverage-test:
	ruby tests/security-next-tranche-negative-coverage.rb

security-query-partitioning-contract-test:
	ruby tests/security-query-partitioning-contract.rb

security-query-partitioning-sql-contract-test:
	ruby tests/security-query-partitioning-sql-contract.rb

security-query-security-contract-test:
	ruby tests/security-query-security-contract.rb

security-query-security-sql-contract-test:
	ruby tests/security-query-security-sql-contract.rb

security-query-security-runtime-auth-contract-test:
	ruby tests/security-query-security-runtime-auth-contract.rb

security-query-security-json-contract-test:
	ruby tests/security-query-security-json-contract.rb

security-query-sql-surface-contract-test:
	ruby tests/security-query-sql-surface-contract.rb

security-query-sql-surface-sql-contract-test:
	ruby tests/security-query-sql-surface-sql-contract.rb

security-query-types-constraints-contract-test:
	ruby tests/security-query-types-constraints-contract.rb

security-query-types-constraints-sql-contract-test:
	ruby tests/security-query-types-constraints-sql-contract.rb

security-runtime-live-preflight-test:
	ruby tests/security-runtime-live-preflight.rb

security-runtime-readiness-contract-test:
	ruby tests/security-runtime-readiness-contract.rb

security-query-catalog-inventory-contract-test:
	ruby tests/security-query-catalog-inventory-contract.rb

security-query-extension-contract-test:
	ruby tests/security-query-extension-contract.rb

security-publication-provenance-contract-test:
	ruby tests/security-publication-provenance-contract.rb

security-performance-statistics-contract-test:
	ruby tests/security-performance-statistics-contract.rb

query-sql-commands-partial-contract-test:
	ruby tests/query-sql-commands-partial-contract.rb

security-runtime-contract-test:
	ruby tests/security-runtime-contract.rb

security-runtime-failure-retention-test:
	ruby tests/security-runtime-failure-retention.rb

security-failure-diagnostic-test:
	ruby tests/security-failure-diagnostics.rb

security-performance-execution-oracle-contract-test:
	ruby tests/security-performance-execution-oracle.rb

security-performance-execution-sql-contract-test:
	ruby tests/security-performance-execution-sql-contract.rb

security-performance-index-oracle-contract-test:
	ruby tests/security-performance-index-oracle.rb

security-performance-index-sql-contract-test:
	ruby tests/security-performance-index-sql-contract.rb

security-performance-index-fixture-math-test:
	ruby tests/security-performance-index-fixture-math.rb

security-performance-structured-failure-contract-test:
	ruby tests/security-performance-structured-failures.rb

security-wal-oracle-contract-test:
	ruby tests/security-wal-oracle.rb

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

ledger-output-refresh:
	ruby tools/refresh-evidence-output-bindings.rb

ledger-output-refresh-test:
	ruby tools/test-refresh-evidence-output-bindings.rb

ledger-output-verify:
	ruby tools/verify-evidence-output-bindings.rb

tracked-generated-freshness:
	ruby tools/verify-tracked-generated-freshness.rb

tracked-generated-freshness-test:
	ruby tools/test-tracked-generated-freshness.rb

evidence-pipeline-refresh:
	$(MAKE) tracked-evidence-generate
	$(MAKE) ledger-output-refresh
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
	$(MAKE) definitive-audit parity-audit authority-locator-verify authority-body-verify authority-review-verify authority-review-determinism-test definitive-skill-eval-verify security-tranche-contract-test security-published-tranche-contract-test security-next-tranche-contract-test security-next-tranche-row-contracts-test security-next-tranche-runtime-implementation-test security-next-tranche-runtime-hygiene-test security-next-tranche-oracles-test security-next-tranche-negative-coverage-test security-query-partitioning-contract-test security-query-partitioning-sql-contract-test security-query-security-contract-test security-query-security-sql-contract-test security-query-security-runtime-auth-contract-test security-query-security-json-contract-test security-query-sql-surface-contract-test security-query-sql-surface-sql-contract-test security-query-types-constraints-contract-test security-query-types-constraints-sql-contract-test security-runtime-live-preflight-test security-runtime-readiness-contract-test security-query-catalog-inventory-contract-test security-query-extension-contract-test security-publication-provenance-contract-test security-performance-statistics-contract-test query-sql-commands-partial-contract-test security-runtime-contract-test security-runtime-failure-retention-test security-failure-diagnostic-test security-performance-execution-oracle-contract-test security-performance-execution-sql-contract-test security-performance-index-oracle-contract-test security-performance-index-sql-contract-test security-performance-index-fixture-math-test security-performance-structured-failure-contract-test security-wal-oracle-contract-test scenario-proofs-verify scenario-closure-plan-verify scenario-evidence-atomicity-test core-scenario-trace-audit core-scenario-plan-audit core-evidence-durability-audit core-authority-audit core-authority-body-audit core-authority-review-audit core-skill-router-audit depth-parity-audit
	@if $(MAKE) definitive-gate; then echo "incomplete repository unexpectedly passed Definitive promotion" >&2; exit 1; fi
	$(MAKE) evidence-pipeline-refresh
	$(MAKE) ledger-output-refresh-test
	$(MAKE) tracked-generated-freshness
	$(MAKE) evidence-dependency-verify evidence-dependency-negative-test core-evidence-dependency-audit docker-volume-cleanup-test evidence-freshness certificate-verify
	$(MAKE) evidence-pipeline-clean
