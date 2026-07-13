# ElectricalSignoffEngine

Power-integrity and electrical-reliability analysis over shared extracted topology.

## Status

This repository contains a native, process-independent electrical signoff implementation over verified JSON source artifacts or a canonical extracted-topology artifact. It provides typed axis APIs, deterministic topology/report encoding, immutable report references, structured blocked diagnostics and a standalone CLI. It does not claim foundry qualification without a process-specific rule set and external oracle.

## Products

| Product | Responsibility |
|---|---|
| `ElectricalSignoffCore` | Shared electrical-signoff request, topology reference and Foundation artifact boundary |
| `PowerIntegrityEngine` | Static and dynamic IR plus EM |
| `ERCEngine` | Electrical rule checking |
| `ESDEngine` | ESD path and clamp validation |
| `LatchUpEngine` | Well, substrate and latch-up analysis |
| `AgingEngine` | NBTI, HCI and TDDB analysis |
| `ElectricalSignoffEngine` | Umbrella API |
| `ElectricalSignoffQualification` | Qualification corpus, oracle observations and release-profile gate |
| `electrical-signoff` | Developer/agent CLI for analysis, extraction, qualification and release-gate replay |

## Native implementation

`ElectricalTopology` is the canonical extracted topology. It binds design, layout, PDK, optional power-intent and parasitic digests, then carries power nets, sources, loads, routed segments, vias, voltage domains, ESD clamps, wells, substrate contacts and lifetime models.

The native products are:

- `DefaultPowerIntegrityEngine`: nodal static/dynamic IR analysis and segment/via current-density EM checks.
- `DefaultERCEngine`: floating-net, multiple-driver, voltage-domain, terminal-overstress and sequencing checks.
- `DefaultESDEngine`: clamp coverage, path references, resistance, trigger voltage and current-capacity checks.
- `DefaultLatchUpEngine`: well spacing, substrate-contact connectivity and contact-area checks.
- `DefaultAgingEngine`: NBTI/HCI/TDDB lifetime projection against the configured lifetime requirement.

Each request carries one or more explicit `ElectricalOperatingCondition` values with PDK corner, temperature, supply-voltage scale and activity scale. `cornerResults` retains every per-corner envelope, while `axisResults` deterministically selects the most severe envelope for gate evaluation. Canonical extraction requires a verified PDK-scoped `ElectricalProcessRuleSet`; this is process provenance, not foundry qualification.

Every product implements its domain protocol and returns `ElectricalSignoffResult`. Design findings complete with violations; missing or unverifiable semantics are blocked. Cross-engine artifacts, diagnostics and execution provenance use CircuiteFoundation directly.

## CircuiteFoundation boundary

The public `ElectricalSignoffExecuting` contract refines
`CircuiteFoundation.Engine<ElectricalSignoffRequest, ElectricalSignoffRunResult>`.
ElectricalSignoffEngine keeps its domain request and result while DesignFlowKernel
owns run lifecycle. The engine consumes and returns Foundation artifact
references directly; path containment, regular-file checks, SHA-256 capture and
byte-count capture are provided by CircuiteFoundation.

`ElectricalSignoffFoundationEvidence` is the canonical cross-engine evidence
view for Agent and human review. It contains `ExecutionProvenance`, input and
output artifact references, and typed `DesignDiagnostic` values, but does not
introduce a signoff verdict into Foundation. Xcircuite may persist both the
domain run result and `foundation-evidence.json` under its run directory. The
in-memory artifact store remains available for isolated engine tests and
explicit non-persistent callers.

`ElectricalSignoffEngineAPI.capabilitySnapshot` exposes the supported axes, topology format, external adapter boundary and qualification status to developer and agent tooling. External process-specific implementations can be injected through `ExternalElectricalSignoffRunning` without changing the native result contract.

## Qualification corpus

`ElectricalSignoffQualification` provides a versioned, Codable corpus contract. Each case declares its request, axis, expected execution status, violation count, diagnostic codes and metric tolerances. `ElectricalSignoffQualificationRunner` records native payloads and artifacts, optionally correlates them with an injected independent oracle, and exports a `ToolEvidence` value for the surrounding `ToolQualification` policy. Native-only evidence is limited to `corpusChecked`; the runner never self-promotes to production eligibility. A process-qualified release profile must additionally attach a separate `ToolProcessQualificationEvidence` record with fresh PDK scope, independent evidence, health evidence and human approval.

`LocalElectricalSignoffQualificationOracle` loads an immutable `ElectricalSignoffOracleObservationSet` from JSON. This makes oracle correlation available to a developer or Agent through a file artifact and the CLI, while still requiring the observation set to declare an independent oracle identity, tool version and matching PDK digest.

Xcircuite can also invoke an independent oracle as a separate process through `ElectricalSignoffOracleProcessConfiguration`. The command receives the qualification spec and must write an `ElectricalSignoffOracleObservationSet` JSON artifact to the expanded `{{outputPath}}`; `{{specPath}}`, `{{projectRoot}}` and `{{runID}}` are available in argument templates. The executable path is absolute, the working directory is constrained, and timeout/cancellation are enforced. stdout, stderr, exit status, timestamps and all produced hashes are retained below `.xcircuite/runs/<run-id>/qualification/oracle/`. A process exit failure, missing output or invalid observation set is a typed qualification failure and is never promoted as oracle evidence.

`ElectricalSignoffProcessQualificationRequest` is the promotion boundary from corpus/oracle execution to process qualification evidence. It requires a PDK-complete `ToolQualificationScope`, exact corpus/report identity and case coverage, independent oracle agreement, real hashed corpus/oracle/health/approval/evidence artifacts, and a bounded qualification window. `DefaultElectricalSignoffProcessQualificationEvaluator` returns a structured qualified or blocked result and emits `ToolProcessQualificationEvidence`; missing human approval or unverifiable artifact identity cannot become a qualified record.

`DefaultElectricalSignoffReleaseGateEvaluator` is the final package-local eligibility contract. Its policy names every required axis and corner and binds the decision to the run ID, PDK digest, qualification level, independent-oracle status, zero violations and hashed per-corner artifacts. The release request also retains the qualification spec; the gate validates the spec and requires the report to contain exactly the declared cases with matching axis, corner and PDK-corner provenance. A passed gate is a reproducible decision artifact; it is not foundry qualification unless the policy references real process-specific rule and oracle evidence.

Run a corpus spec locally:

```bash
swift run electrical-signoff --qualification-spec Fixtures/electrical-signoff-runnable-spec-v1.json --project-root . --pretty
swift run electrical-signoff --qualification-spec Fixtures/electrical-signoff-qualification-spec-v1.json --project-root . --pretty
swift run electrical-signoff --qualification-spec Fixtures/electrical-signoff-qualification-spec-v1.json --oracle-observations Fixtures/electrical-signoff-oracle-observations-v1.json --project-root . --pretty
swift run electrical-signoff --process-qualification-request process-qualification-request.json --project-root . --output process-qualification-result.json --pretty
```

The runnable fixture uses the checked-in extracted topology and intentionally expects the power-integrity missing-parasitics block; it returns `0` when all five declared cases match their expected outcomes. The contract fixture uses placeholder references and is expected to return a non-passing report until its project-specific artifacts are supplied. The command returns `0` only when the declared corpus gates pass. A spec that requires an independent oracle returns a non-passing report when no oracle is injected by the host application.

The process-qualification command verifies every retained corpus, oracle, health, approval and evidence reference against the selected project root before evaluation. It returns `0` only when every required evidence group is complete and the resulting evidence is fresh, PDK-scoped and independently approved; a readable but incomplete request returns `2` with a blocked result, while a missing or tampered retained artifact returns `1` with a structured input-integrity error.

## CLI

Build and run the deterministic JSON CLI with a request containing verified artifact references:

```bash
swift run electrical-signoff --request request.json --project-root . --pretty
swift run electrical-signoff --request request.json --axis power-integrity --output .xcircuite/runs/run-1/power.json
swift run electrical-signoff --request request.json --project-root . --extract-topology --output .xcircuite/runs/run-1/electrical-topology.json
swift run electrical-signoff --release-gate-request .xcircuite/runs/run-1/electrical-signoff/gate-request.json --project-root . --pretty
```

The CLI returns exit code `0` for completed runs, `2` for completed analysis with violations or blocked axes, and `1` for malformed CLI/input execution. `--allow-unverified-inputs` is available only for local parser exploration; signoff requests should retain SHA-256 and byte-count provenance.

The request must select an explicit `topologyArtifact`, or include a uniquely named topology JSON input whose path or artifact ID identifies it as topology; the loader never guesses a design or PDK JSON artifact. `--extract-topology` uses `topologyProfileArtifact` and `processRuleArtifact` to build the canonical topology from LogicDesign, PhysicalDesign, PowerIntent, PDK and canonical PEX JSON inputs. A parasitic reference may be canonical `ParasiticIR` JSON or verified SPEF; SPEF is lowered through `PEXParsers` and invalid IR is blocked. Missing electrical characterization or an out-of-scope process rule is blocked instead of inferred. The artifacts must use schema version 1. See `Fixtures/` for the contract corpus.

`--release-gate-request` replays a serialized `ElectricalSignoffReleaseGateRequest`. Before evaluation it re-verifies every `artifactIntegrity` path against the supplied project root, so a copied or tampered report cannot be accepted by a self-declared `.verified` status. It returns `0` only for a passed gate, `2` for a valid but blocked/failed decision, and `1` for malformed input or execution errors.

For standard mask inputs, Xcircuite provides `ElectricalStandardLayoutImportFlowStageExecutor`. It parses DEF routed connectivity and imports GDSII/OASIS geometry through `LayoutIO`, loads LEF technology, applies an explicit digest-bound LEF-to-GDS layer-map artifact, then persists a verified canonical `PhysicalDesignSnapshot`. GDSII/OASIS geometry without an explicit connectivity source is blocked because mask geometry alone does not define electrical nets; LEF without an explicit layer map is also blocked because LEF does not define GDS layer numbers.

## Contract

Every executing product uses:

- a `Codable`, `Hashable`, `Sendable` domain request;
- `ElectricalSignoffResult` for status, diagnostics, artifacts and execution provenance;
- protocol-first dependency injection;
- immutable Foundation `ArtifactReference` inputs and outputs;
- explicit blocked, failed and cancelled states.

## Xcircuite integration

Xcircuite binds one design, layout, PDK, power-intent and parasitic digest set across every electrical axis so results cannot refer to different revisions. `ElectricalStandardLayoutImportFlowStageExecutor` is the standard-format bridge and persists an `ElectricalSignoffInputArtifactManifest` for the consumed layout, technology and connectivity files; `ElectricalSignoffFlowStageExecutor` persists both the canonical `ElectricalSignoffRunResult` and its Foundation `ElectricalSignoffFoundationEvidence`, while `ElectricalSignoffQualificationFlowStageExecutor` persists the corpus spec, input manifest, qualification report, `ToolEvidence`, `RetainedCorpusSuite`/`RetainedCorpusReport` and a release-consumable evidence set. `ElectricalSignoffReleaseGateFlowStageExecutor` accepts only digest-bound input references or verified stage-artifact selectors, consumes those immutable references and can require a separate process-qualification evidence artifact before persisting the typed release decision plus an `ElectricalSignoffReleaseArtifactBundle`. The bundle is a digest-bound review/resume surface for the request, policy, qualification, topology/provenance, per-corner evidence, repair plan, run plan/action ledger, run manifest and approval records. DesignFlowKernel owns approval, resume, retry and cancellation; failed signoff payloads are retained as `ElectricalSignoffRepairPlan` artifacts for a subsequent immutable design revision.

The library does not depend on the Xcircuite runtime. Xcircuite invokes the
public protocols directly and owns concrete artifact persistence; DesignFlowKernel
owns approval, resume, retry and cancellation.

## Build

```bash
swift build --target ElectricalSignoffEngine
swift build --target ElectricalSignoffCLI
```

## Test

```bash
swift test --filter ElectricalSignoffQualificationTests
swift test --filter ElectricalSignoffEngineTests
```

This Swift package does not define an Xcode test scheme; use the timeout-bounded Swift Package runner for local contract and qualification tests.

The package does not provide an Xcircuite adapter. A host may compose the
per-axis results with DesignFlowKernel while preserving the domain result and
Foundation artifact contracts.

## Verification snapshot

The current local verification passes the complete package test suite: 42 tests
across 8 Swift Testing suites. The executable targets also build successfully,
and the checked-in runnable qualification fixture completes with exit code `0`:

```bash
swift test
swift build --target ElectricalSignoffEngine
swift build --target ElectricalSignoffCLI
swift run electrical-signoff \
  --qualification-spec Fixtures/electrical-signoff-runnable-spec-v1.json \
  --project-root . \
  --pretty
```

The runnable fixture intentionally verifies that missing parasitic provenance is
reported as a blocked electrical axis while the declared corpus expectation
still passes. These checks validate the native implementation and its local
artifact contract; they do not claim foundry or process qualification.

See `DESIGN.md`, `INTERFACES.md` and `IMPLEMENTATION_PLAN.md` before implementing a backend.
