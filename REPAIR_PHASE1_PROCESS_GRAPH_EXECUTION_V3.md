# Repair Phase 1 — Process Graph & Execution Eligibility V3

## Closed client-side gaps

AURORA now compiles the declared flowsheet into a directed process graph with explicit nodes and edges. Existing linear `units` arrays remain backward-compatible and are deterministically translated into graph form. Explicit split, merge and recycle topologies can be supplied directly.

Graph validation fails closed on duplicate/missing IDs, unknown endpoints, self loops, disconnected nodes and non-recycle cycles. Intentional recycle closure edges must be tagged `recycle=true`.

## Execution eligibility

Every canonical engine receives an explicit eligibility decision from route and processing-mode evidence. Explicit Dry mode blocks water-dependent flotation, hydrometallurgy, aqueous thermodynamics and water-circuit execution, and rejects wet unit operations in the declared graph.

Direct selected-engine dispatch is blocked on-device before HTTP when the requested engine is ineligible. Full DAG creation is blocked when the graph or route/mode policy is non-executable.

## Raw ore diagnosis exception

An explicit `raw_ore_diagnosis` objective may run a graphless diagnostic DAG. This exemption does not make process engines eligible; it only avoids requiring process equipment when the task is diagnosis rather than flowsheet simulation.

## Server enforcement boundary

The client emits `executionGovernance` with `serverEnforcementRequired=true`. A separate backend staging branch implements selective server fan-out and fail-closed validation. Production Railway has not been changed by this repair branch.

## Verification

`Process Execution Governance V3` CI validates source invariants and performs a full native iOS simulator compile. The initial graph/eligibility gate passed both invariant and compile jobs before the graphless diagnosis policy extension; the extension is subject to the same gate on the updated head.
