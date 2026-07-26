# ElectricalSignoffEngine Remaining Tasks

Updated: 2026-07-26

The native process-independent PI/EM, ERC, ESD, latch-up, aging, topology,
multi-corner, corpus, correlation-contract, CLI, and repair-plan paths are
implemented.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| ESE-3 | P2 | ElectricalSignoffEngine | Complete numerical correlation and resource regression coverage. | Independent reference tolerances and memory/allocation budgets are recorded for each analysis axis; ERC, ESD, latch-up, and aging gain axis-scale latency fixtures. |

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
| ESE-4 | 2026-07-26 | CLI command execution is isolated in the protocol-first `ElectricalSignoffCLICore`; the `@main` executable owns only process entry and exit. Evidence tests depend on the reusable command module instead of an executable target, so the full Xcode package test graph links correctly. |

## Completed P2 increments

| ID | Completed | Evidence |
|---|---|---|
| ESE-3A | 2026-07-26 | PI, ERC, ESD, and topology validation no longer repeat full-topology scans per entity. The isolated 8,000-rail solver fixture improved from 34.247 seconds to 0.052 seconds and the 8,000-contact validator fixture from 2.213 seconds to 0.017 seconds on the development host. The solver has a five-second full-package parallel debug budget and validation has a one-second budget; the solver also verifies repeated-result determinism. |

## Evidence reviewed

- `README.md`
- `DESIGN.md`
- `INTERFACES.md`
- `IMPLEMENTATION_PLAN.md`
- `MILESTONES.md`
- `GOAL_STATUS.md`
- `Sources` incomplete-implementation marker scan
