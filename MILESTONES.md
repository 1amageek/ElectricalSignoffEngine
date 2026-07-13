# ElectricalSignoffEngine Milestones

## Goal

Provide a reproducible electrical signoff path from canonical design artifacts to a human- and agent-reviewable release decision. A native engine that accepts a prebuilt topology is an intermediate capability, not the final goal.

## Milestones

### M0 — Goal and contract baseline

Status: complete.

Acceptance criteria:

- Native, external, qualification and release responsibilities are separated.
- Every result is typed, digest-bound, artifact-backed and structurally diagnosable.
- The remaining gaps are recorded as explicit milestones rather than implied completion.

### M1 — Canonical topology extraction

Status: complete for the canonical JSON source lane and Xcircuite standard-layout bridge.

Acceptance criteria:

- LogicDesign, PhysicalDesign, PowerIntent, PDK and PEX inputs can be loaded through typed protocols.
- A native extractor produces `ElectricalTopology` from those inputs and records all source artifact IDs and digests.
- Layout routes, vias, power structures and device terminals are preserved; missing electrical semantics block extraction.
- The extracted topology can be serialized, reloaded and validated without access to the UI or Xcircuite runtime.
- Extraction has positive, missing-input, digest-mismatch and unsupported-semantics fixtures.
- Xcircuite imports DEF routed connectivity and can combine GDSII/OASIS geometry with an explicit DEF connectivity artifact into a digest-bearing `PhysicalDesignSnapshot`. LEF technology inputs require an explicit digest-bound layer-map artifact because LEF does not carry GDS layer numbers; missing or duplicate mappings block the stage.
- The source loader accepts canonical `ParasiticIR` JSON and lowers verified SPEF through `PEXParsers`, validating the resulting IR before extraction.

The source lane intentionally requires an explicit electrical extraction profile for current, layer, device and process characterization. It does not infer signoff limits from incomplete artifacts.

`ElectricalStandardLayoutImportFlowStageExecutor` is the standard-format boundary: it loads LEF technology through `TechFormatConverter`, parses DEF/GDSII/OASIS through `MaskDataFormatConverter`, and blocks when standard mask geometry cannot be paired with explicit electrical connectivity.

### M2 — Corner and process-aware analysis

Status: complete for the native execution contract; qualification promotion remains M3.

Acceptance criteria:

- Voltage, temperature, activity/vector and PDK corner are explicit in the request.
- IR, EM, ERC, ESD, latch-up and aging results identify their operating corner.
- Process limits are sourced from a PDK-scoped process-rule artifact, not hidden constants; independent qualification is still required.
- Multi-corner aggregation retains per-corner payloads and deterministic worst-case selection.

Current implementation evaluates multiple `ElectricalOperatingCondition` values sequentially, retains per-corner envelopes and artifacts, and selects deterministic worst-case axis results. Canonical extraction verifies process-rule digest, process identity and declared PDK corner scope. Qualification corpus/oracle evidence remains a later milestone.

### M3 — Qualification and oracle correlation

Status: in progress; versioned corpus and evidence export are implemented, real process oracle qualification remains open.

Acceptance criteria:

- A versioned corpus format covers positive, negative, boundary and regression cases per axis.
- Expected metrics, tolerances, diagnostics and artifacts are compared deterministically.
- External/reference oracle results are represented as immutable evidence with tool and PDK provenance.
- Qualification reports map to `ToolQualification` evidence without allowing self-declared production trust.

Current implementation provides `ElectricalSignoffQualificationSpec`, `ElectricalSignoffQualificationRunner`, absolute/relative metric tolerances, diagnostic comparison, immutable native/oracle observations, `ElectricalSignoffOracleObservationSet`, `LocalElectricalSignoffQualificationOracle` and `ToolEvidence` export. Xcircuite also provides a timeout- and cancellation-bounded external oracle process boundary with templated spec/output paths and retained stdout, stderr, exit status and execution metadata. `DefaultElectricalSignoffProcessQualificationEvaluator` now forms the explicit promotion boundary: it requires PDK scope, exact case/report identity, independent agreement, hashed corpus/oracle/health/approval/evidence artifacts and a bounded window before emitting `ToolProcessQualificationEvidence`. The Xcircuite stage and CLI verify each retained reference against the actual project file before promotion. The process qualification is available through the CLI and an Xcircuite runtime stage. The bundled corpus and oracle observation set are process-independent contract fixtures; they cannot establish process qualification.

### M4 — Xcircuite flow and repair loop

Status: complete for the native typed repair-revision path; all-axis rerun remains an explicit downstream flow stage.

Acceptance criteria:

- The stage resolves and verifies all inputs, applies tool trust requirements and persists every output.
- Human approval, resume, cancellation and retry preserve the same run ledger.
- Repair candidates become typed plans; applying a repair creates a new immutable design revision.
- Agent and cockpit paths consume the same review bundle and diagnostics.

Current implementation provides direct protocol execution with canonical run-result and `ElectricalSignoffFoundationEvidence` persistence, Foundation-backed input/output artifact lineage, `ElectricalSignoffQualificationFlowStageExecutor` with spec/report/ToolEvidence/immutable oracle retention/retained release artifacts, DesignFlowKernel approval/resume participation, and `ElectricalSignoffRepairPlan` persistence for failed axes. `ElectricalSignoffRepairRevisionFlowStageExecutor` verifies plan provenance, applies the selected candidate through the native physical-design executor, persists a new digest-bound revision, and marks the required all-axis rerun explicitly.

### M5 — Release-profile eligibility

Status: in progress; the typed gate, complete release artifact bundle and Xcircuite persistence path are implemented, while real process/oracle promotion remains open.

Acceptance criteria:

- All required axes pass the selected PDK/corner policy.
- Qualification evidence is fresh, complete and independently correlated.
- Release artifacts include the request, plan, action log, topology, per-axis reports, provenance and approval records.
- A release gate blocks on any missing evidence, stale qualification, unresolved violation or artifact-integrity failure.

Current implementation provides `ElectricalSignoffReleaseGatePolicy`, `ElectricalSignoffReleaseGateRequest`, `ElectricalSignoffReleaseGateResult`, `ElectricalSignoffReleaseArtifactBundle` and `DefaultElectricalSignoffReleaseGateEvaluator`. The gate requires explicit corner/axis coverage, an independently retained and validated qualification spec/report pair with exact case, axis and corner provenance, run and PDK identity, independently correlated qualification, zero violations and hashed per-corner artifacts. Policies that require process qualification additionally consume a separate digest-bound `ToolProcessQualificationEvidence` artifact and block when it is missing, stale, unscoped or not independent. `ElectricalSignoffReleaseGateFlowStageExecutor` accepts only digest-bound input references or verified stage-artifact selectors, validates the qualification spec before evaluation and persists both the decision and a canonical bundle containing request, qualification, policy, topology/provenance, evidence, repair, plan/action and approval references. It does not promote synthetic fixtures to foundry eligibility.

## Promotion rule

Passing an earlier milestone never promotes a package to a later maturity level. In particular, native execution and generic fixtures cannot establish process qualification or foundry release eligibility.
