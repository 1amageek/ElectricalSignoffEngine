# Electrical signoff fixtures

The fixture corpus is a process-independent contract corpus. It exercises the native JSON extracted-topology lane and deliberately does not claim foundry qualification.

| Case | Expected result | Coverage |
|---|---|---|
| `electrical-topology-clean-v1.json` | completed when referenced by a request with verified artifacts | extracted topology, power grid, domains, ESD, well and aging semantics |
| `electrical-topology-blocked-no-grid-v1.json` | blocked for power integrity | missing extracted power-grid semantics |
| `electrical-topology-extraction-profile-v1.json` | extraction input | explicit net, source, load, layer and device characterization |
| `electrical-process-rules-v1.json` | extraction input | PDK digest-scoped corner limits for IR, EM and ESD |
| `electrical-signoff-qualification-spec-v1.json` | qualification input | versioned expected status/count/diagnostic/metric corpus contract |
| `electrical-signoff-runnable-spec-v1.json` | qualification input | self-contained developer fixture covering all five axes with one intentional fail-closed parasitic prerequisite case |
| `electrical-signoff-oracle-observations-v1.json` | oracle input | immutable case-keyed independent observation set |
| `electrical-signoff-release-policy-v1.json` | release-gate input | explicit axis/corner coverage, qualification, artifact-integrity and freshness policy |

The request must provide verified `XcircuiteFileReference` values for the design, layout, PDK, parasitic, topology-profile and process-rule artifacts. The topology and process-rule digest fields must match those request references and the declared PDK corner scope.

`electrical-signoff-runnable-spec-v1.json` can be executed directly from this package and returns a passing corpus report. The generic qualification and release-policy fixtures remain contract fixtures with placeholder digests; replace the placeholder references and supply a real retained run result before using them for a release decision.
