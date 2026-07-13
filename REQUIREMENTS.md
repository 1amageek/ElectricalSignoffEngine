# ElectricalSignoffEngine Requirements

## Goal

Evaluate power integrity and electrical reliability against one shared extracted design and process context.

## Required functions

| Function | Required behavior | Priority |
|---|---|---:|
| Electrical topology extraction | Bind logic, physical connectivity, power intent, parasitics and device semantics. | P0 |
| Power-grid extraction | Extract actual rails, vias, sources and loads from the routed layout. | P0 |
| Static and dynamic IR | Compute voltage-drop behavior from declared activity, vectors and operating conditions. | P0 |
| Electromigration | Evaluate wire and via current density under process and temperature rules. | P0 |
| ERC | Check voltage domains, floating nodes, multiple drivers, overstress and sequencing rules. | P0 |
| ESD | Validate discharge paths, clamps, domains, resistance and current handling. | P1 |
| Latch-up | Evaluate wells, substrate contacts, spacing and parasitic latch-up paths. | P1 |
| Aging | Evaluate NBTI, HCI, TDDB and declared lifetime models. | P1 |
| Repair candidates | Emit typed electrical repair proposals without mutating the layout. | P1 |

## Required outcomes

- IR, EM, ERC, ESD, latch-up and aging results reference identical design and PDK digests.
- Synthetic one-dimensional power models cannot satisfy signoff.
- Each axis retains an independent payload, CLI and qualification status.

## Common platform requirements

- Public execution surfaces are protocol-first, Sendable and dependency-injected.
- Requests and payloads are Codable, Hashable and schema-versioned.
- Inputs and outputs use immutable Foundation `ArtifactReference` artifacts.
- Diagnostics contain a stable code, severity, affected entity and suggested actions.
- Unsupported semantics and missing prerequisites produce blocked results.
- Native and external-tool backends conform to identical request and payload schemas.
- Execution capability, corpus validation, oracle correlation, process qualification and release approval remain distinct.
- Xcircuite owns concrete artifact persistence and composition; DesignFlowKernel owns flow construction, qualification gates, approval and resume.
- The package never imports Xcircuite or circuit-studio.

## Required developer surfaces

- Typed API
- Deterministic JSON CLI
- Positive and negative fixtures
- Contract and parser round-trip tests
- Reference corpus
- Capability and limitation report
- Xcircuite stage adapter tests
