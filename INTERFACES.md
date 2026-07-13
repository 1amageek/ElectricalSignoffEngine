# ElectricalSignoffEngine Interface Contract

## Common shape

```swift
public protocol DomainExecuting: Sendable {
    func execute(
        _ request: DomainRequest
    ) async throws -> DomainResult
}
```

Requests carry a schema version, run ID and typed artifact references. Payloads contain domain metrics only. Diagnostics and artifacts belong to the shared envelope.

The concrete native request additionally carries an optional `topologyArtifact` and `ElectricalSignoffConfiguration`. The topology loader verifies every referenced artifact before decoding JSON, rejects conflicting references for one path, and compares design, layout, PDK and parasitic digests before an axis is allowed to run. Without `topologyArtifact`, only an explicitly topology-named JSON input is eligible; unrelated JSON inputs are never guessed as topology.

## Products

### ElectricalSignoffCore

Shared electrical-signoff request and topology reference.

### PowerIntegrityEngine

Static and dynamic IR plus EM.

### ERCEngine

Electrical rule checking.

### ESDEngine

ESD path and clamp validation.

### LatchUpEngine

Well, substrate and latch-up analysis.

### AgingEngine

NBTI, HCI and TDDB analysis.

### ElectricalSignoffEngine

Umbrella API.

`ElectricalSignoffEngine.execute(_:axes:)` executes requested axes sequentially and returns `ElectricalSignoffRunResult`. The no-axis overload uses `request.configuration.requiredAxes`, so the same request deterministically controls API and CLI aggregate execution. Each axis remains independently addressable for review and retry.

### Canonical extraction

`ElectricalTopologySourceLoading` verifies and decodes the JSON source bundle. `NativeElectricalTopologyExtractor` converts routed physical segments, vias, physical pins, gate cells, power intent domains, PDK identity and canonical PEX resistance into `ElectricalTopology`. `ElectricalTopologyExtractionProfile` is required for explicit source, load, layer, device and process characterization; missing characterization produces a typed blocked error.

`ElectricalSignoffConfiguration.operatingConditions` carries one or more PDK corners, temperatures, supply-voltage scales and activity scales. `ElectricalSignoffRunResult.cornerResults` retains every condition, while `axisResults` contains a deterministic worst-case envelope for gate evaluation. Canonical extraction requires a verified PDK-scoped `ElectricalProcessRuleSet`; `ElectricalTopology.rulesByCorner` prevents a corner-aware request from silently using unrelated process limits.

The Xcircuite standard-layout bridge accepts LEF technology plus DEF routed connectivity and optionally GDSII/OASIS geometry. It persists a `PhysicalDesignSnapshot` with source-format metadata and artifact integrity. GDSII/OASIS without explicit connectivity is blocked rather than treated as a netlist. The local source loader accepts canonical `ParasiticIR` JSON and verified SPEF, using `PEXParsers` for SPEF lowering and rejecting invalid lowered IR.

`ElectricalSignoffQualification` defines a versioned corpus case with expected status, violation count, diagnostics and metric tolerances. Metric comparisons use declared absolute and relative tolerances. A corpus-only report can reach `corpusChecked`; `oracleChecked` requires an independent oracle ID, matching PDK digest and agreement for every case. The report can be converted to `ToolEvidence`, but never to `productionEligible` by itself.

`ElectricalSignoffOracleObservationSet` is the immutable JSON boundary for externally produced case observations. `LocalElectricalSignoffQualificationOracle` validates the oracle identity, tool version, case uniqueness and PDK digest before serving observations to the runner. The CLI accepts it through `--oracle-observations`.

`DefaultElectricalSignoffReleaseGateEvaluator` consumes a run result, qualification report and `ElectricalSignoffReleaseGatePolicy`. It checks run/PDK identity, qualification freshness and level, independent-oracle coverage, explicit axis/corner coverage, zero violations and verified artifact integrity. `ElectricalSignoffReleaseGateFlowStageExecutor` additionally emits `ElectricalSignoffReleaseArtifactBundle`, whose digest-bound references provide the request, policy, topology/provenance, qualification, per-corner evidence, plan/action, repair and approval resume surface. It returns a typed passed/blocked/failed result; it does not mutate design state or grant process qualification.


## Error contract

- Throw only when execution cannot produce a valid result envelope.
- Represent design findings and failed checks as typed diagnostics and a completed domain payload.
- Represent missing prerequisites or insufficient semantics as `blocked`.
- Complete findings are not converted to `failed` execution: the envelope remains `completed`, carries error-severity diagnostics and records the failing payload metrics.
- Preserve cancellation as `cancelled`.
- Do not swallow parser, process or persistence failures.

## Composition

Xcircuite invokes these protocols directly and persists returned
`ArtifactReference` values in its workspace store. DesignFlowKernel owns flow
status, approval and resume; ToolQualification owns capability and trust
decisions. Engines only return domain results, diagnostics and provenance.
