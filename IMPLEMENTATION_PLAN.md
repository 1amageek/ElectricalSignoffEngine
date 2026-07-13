# ElectricalSignoffEngine Implementation Plan

## Milestone order

See `MILESTONES.md` for the promotion gates. The implementation order is:

1. Goal and contract baseline
2. Canonical topology extraction from LogicDesign, PhysicalDesign, PowerIntent, PDK and PEX
3. Corner- and process-aware native analysis
4. Qualification corpus and independent oracle correlation
5. Xcircuite flow, approval, resume and repair loop
6. Release-profile eligibility

## Completed native slice

- Implemented the complete process-independent native JSON topology lane for all P0 axes and the declared P1 reliability axes.
- Added deterministic clean and blocked topology fixtures.
- Added JSON request/payload round-trip tests and digest/integrity negative-path tests.
- Added the `electrical-signoff` JSON CLI.
- Added the Xcircuite `FlowStageExecutor` adapter and per-axis flow gates.
- Added explicit multi-corner result retention and PDK digest-scoped process rules.
- Added the `ElectricalSignoffQualification` corpus runner with metric tolerances, diagnostic comparison, independent-oracle correlation and `ToolEvidence` export.
- Added `electrical-signoff --qualification-spec` for developer-operable corpus execution.
- Retained the fixture manifest with explicit non-qualified oracle scope.
- Added digest-bound input manifests for standard-layout and qualification stages so the run ledger records the exact source files consumed by extraction and corpus execution.
- Added process-qualified release policies that consume a separate, fresh, PDK-scoped `ToolProcessQualificationEvidence` artifact; corpus success alone cannot satisfy this gate.
- Added a typed release-profile evaluator that requires explicit all-axis/all-corner evidence, PDK/run identity, independent qualification, zero violations and artifact hashes.
- Added the Xcircuite external-oracle process boundary with validated argument templates, timeout/cancellation, immutable observation validation, and retained stdout/stderr/execution evidence.
- Added `ElectricalSignoffProcessQualificationRequest`, a typed evaluator that requires PDK scope, exact corpus/report identity, independent oracle agreement, hashed corpus/oracle/health/approval artifacts and a bounded qualification window before producing `ToolProcessQualificationEvidence`; the Xcircuite stage and CLI additionally verify each retained reference against the actual project file before promotion.
- Added the `--process-qualification-request` CLI mode with project-root artifact verification, qualified/blocked exit semantics and structured checks.
- Added the Xcircuite process-qualification stage, runtime-spec entry and persisted result/evidence artifacts for Agent and human review.
- Added a standalone release-gate CLI replay that re-verifies persisted artifact integrity before evaluating a serialized gate request.
- Added the Xcircuite release-gate stage and persisted the canonical electrical run result so the gate consumes immutable run artifacts rather than UI state.
- Added the direct CircuiteFoundation `Engine` boundary, artifact locator/reference bridge, Foundation evidence projection and typed diagnostic mapping.
- Added request, configuration, topology, run-result, qualification-report and release-gate identity validation, including conflict detection for incompatible shared paths and deterministic identifier escaping for retained artifacts.
- Added deterministic SPEF parse run identity, finite-value validation for extracted electrical semantics and regression coverage for malformed topology, ambiguous topology discovery and artifact-name collisions.

This slice is the executable analysis kernel. It is not the completion of M1-M5.

## Completion gates

- Public APIs remain protocol-first and Sendable.
- Every unsupported semantic produces a structured blocked result.
- Native and external backends produce the same result schema.
- No UI type enters a public contract.
- No result claims foundry qualification without process-scoped oracle evidence.
- Xcircuite can execute, persist, review and resume the stage without circuit-studio.

The native implementation, qualification contract, release-gate contract and typed repair-revision handoff satisfy the current executable package contract. Real process qualification, independent oracle evidence and final release eligibility remain separate gates and cannot be inferred from the generic fixture corpus or a self-generated report.
