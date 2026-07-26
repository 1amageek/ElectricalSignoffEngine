# ElectricalSignoffEngine Remaining Tasks

Updated: 2026-07-26

The native process-independent PI/EM, ERC, ESD, latch-up, aging, topology,
multi-corner, corpus, correlation-contract, CLI, and repair-plan paths are
implemented.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| ESE-3 | P2 | ElectricalSignoffEngine | Improve numerical correlation and performance regression coverage. | Reference tolerances, corner/entity scale, latency, memory/allocation budgets, deterministic results, and regression failures are recorded for each analysis axis. |

## External prerequisites

| Former ID | Owner | Required evidence |
|---|---|---|
| ESE-2 | Electrical-signoff oracle workflow | Real process rules and independently operated oracle observations binding exact corners, inputs, implementation/oracle identities, raw outputs, entity coverage, correlation, and artifact digests. |
| ESE-W1 | Xcircuite integration | Retained success, blocked, failed, review, resume, tamper, and release-handoff flows over the same immutable electrical-signoff artifacts. |

Tool trust, approval policy, and release authorization remain
ToolQualification, DesignFlowKernel, Xcircuite, and ReleaseEngine
responsibilities.

## Completed P1 tasks

| ID | Completed | Evidence |
|---|---|---|
| ESE-1 | 2026-07-26 | Canonical JSON logic/physical/process/profile inputs and standard SPEF parasitics are digest-verified and lowered into one electrical topology. Retained tests cover exact logic/physical/SPEF entity mapping, malformed SPEF, missing characterization, multi-corner execution, exact per-axis entity coverage, and all native axes without partial-success promotion. Format parsing outside SPEF remains in the owning logic, physical, PEX, and mask-data packages. |

## Evidence reviewed

- `README.md`
- `DESIGN.md`
- `INTERFACES.md`
- `IMPLEMENTATION_PLAN.md`
- `MILESTONES.md`
- `GOAL_STATUS.md`
- `Sources` incomplete-implementation marker scan
