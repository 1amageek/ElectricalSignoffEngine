# ElectricalSignoffEngine Interface Contract

## Engine boundary

`ElectricalSignoffExecuting` refines the generic CircuiteFoundation `Engine`
contract with `ElectricalSignoffRequest` and `ElectricalSignoffRunResult`.
Requests and results are `Sendable` value types. Dependencies are injected
through protocols.

`ElectricalSignoffEngine.execute(_:axes:)` executes selected axes and retains
all operating-condition results. The no-axis overload uses
`request.configuration.requiredAxes`. Findings are typed domain payloads;
missing prerequisites produce a blocked status; execution failures throw typed
errors; cancellation remains cancellation.

## Artifact boundary

Requests consume `ArtifactReference` values. The topology source loader verifies
path containment, digest, byte count, identity, and schema before decoding. It
does not guess an unrelated JSON input as topology.

`ElectricalSignoffFoundationEvidence` publishes Foundation artifacts,
diagnostics, and provenance directly. The package does not define a parallel
file-reference type.

## Canonical topology

`ElectricalTopologySourceLoading` verifies and decodes the source bundle.
`NativeElectricalTopologyExtractor` converts routed segments, vias, pins,
power-intent domains, PDK identity, and parasitics into `ElectricalTopology`.
Explicit extraction profiles and process rules are required; absent semantics
produce typed blocked errors.

## Observation boundary

`ElectricalSignoffCorpusSpec` defines reproducible cases and measurement
expectations. `ElectricalSignoffCorpusRunner` produces
`ElectricalSignoffCorpusReport`. `ElectricalSignoffOracleObservationSet` is the
immutable boundary for independently produced measurements, and
`LocalElectricalSignoffOracle` validates identity, version, case uniqueness,
and PDK digest before correlation.

These types report observations only. Tool trust belongs to
`ToolQualification`, flow decisions belong to `DesignFlowKernel`, and release
authorization belongs to `ReleaseEngine`.

## Composition

Xcircuite invokes the public protocols directly and persists returned artifacts
in its workspace store. No runtime adapter is part of this package.
