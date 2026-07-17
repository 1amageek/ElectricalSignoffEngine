# Electrical signoff fixtures

The fixture corpus is a process-independent contract corpus. It exercises the native JSON extracted-topology lane and deliberately does not claim foundry qualification.

| Case | Expected result | Coverage |
|---|---|---|
| `electrical-topology-clean-v1.json` | completed when referenced by a request with verified artifacts | extracted topology, power grid, domains, ESD, well and aging semantics |
| `electrical-topology-blocked-no-grid-v1.json` | blocked for power integrity | missing extracted power-grid semantics |
| `electrical-topology-extraction-profile-v1.json` | extraction input | explicit net, source, load, layer and device characterization |
| `electrical-process-rules-v1.json` | extraction input | PDK digest-scoped corner limits for IR, EM and ESD |
| `electrical-signoff-runnable-spec-v1.json` | corpus input | self-contained developer fixture covering all five axes with one intentional fail-closed parasitic prerequisite case |

Requests must use verified Foundation `ArtifactReference` values for every declared artifact. The runnable corpus includes design, layout, PDK, and topology references; extraction requests additionally provide topology-profile and process-rule references, while parasitic references are required when topology declares parasitic provenance. Topology and process-rule digest fields must match the request references and the declared PDK corner scope.

`electrical-signoff-runnable-spec-v1.json` can be executed directly from this package and returns a passing corpus report. Independent oracle observations are runtime evidence and must be supplied by the host as a current `ElectricalSignoffOracleObservationSet`; this package does not ship placeholder oracle or release artifacts.
