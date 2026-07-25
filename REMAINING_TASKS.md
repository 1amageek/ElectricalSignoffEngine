# ElectricalSignoffEngine Remaining Tasks

Updated: 2026-07-26

The native process-independent PI/EM, ERC, ESD, latch-up, aging, topology,
multi-corner, corpus, correlation-contract, CLI, and repair-plan paths are
implemented.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| ESE-1 | P1 | ElectricalSignoffEngine | Expand standard-format topology fixtures and process-rule coverage. | Retained JSON/SPEF and additional standard-format cases cover exact entity mapping, incomplete topology failures, multi-corner rules, and all native axes without partial-success artifacts. |
| ESE-2 | P1 | ElectricalSignoffEngine and oracle workflow | Add real process data and independently operated oracle observations. | Exact process rules, corners, inputs, implementation/oracle identities, raw outputs, entity coverage, correlation, and artifact digests are retained for ToolQualification. |
| ESE-W1 | P1 | Xcircuite integration | Exercise immutable electrical-signoff artifacts through resume and human-review flows. | A retained flow proves success, blocked, failed, review, resume, tamper, and release-handoff behavior using the same canonical artifacts. |
| ESE-3 | P2 | ElectricalSignoffEngine | Improve numerical correlation and performance regression coverage. | Reference tolerances, corner/entity scale, latency, memory/allocation budgets, deterministic results, and regression failures are recorded for each analysis axis. |

## External prerequisites

Tool trust, approval policy, and release authorization remain
ToolQualification, DesignFlowKernel, Xcircuite, and ReleaseEngine
responsibilities.

## Evidence reviewed

- `README.md`
- `DESIGN.md`
- `INTERFACES.md`
- `IMPLEMENTATION_PLAN.md`
- `MILESTONES.md`
- `GOAL_STATUS.md`
- `Sources` incomplete-implementation marker scan
