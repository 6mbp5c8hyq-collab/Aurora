# AURORA Repair Phase 1 — Scientific Project Contract V3

## Purpose

Repair the mismatch between the production AURORA runtime, which already supports objective-aware and flowsheet-conditioned governance, and the native iOS client, whose legacy project contract only supplied a target component, target grade and notes.

## Contract introduced

Schema identifier: `AURORA-SCIENTIFIC-PROJECT-CONTRACT-V3-2026.09.17`

The native project contract now declares:

- scientific objective;
- processing mode: dry / wet / hybrid;
- valuable component;
- optional target grade;
- optional target recovery;
- optional maximum impurity component and grade;
- optional product specification;
- allowed unit operations;
- prohibited unit operations;
- explicit water-requirement semantics;
- user-declared scientific-basis authority.

## Compatibility boundary

The V3 overlay is merged into outgoing validation, DAG, engine-job and export payloads while retaining `targetComponent` and `targetGrade` for the current V220 backend adapter.

For this first repair slice, V3 state is stored per project in a versioned UserDefaults record rather than changing the SwiftData model. This deliberately avoids destructive/migration-sensitive changes to existing device project stores before the new contract is proven by build and runtime tests.

## Governance behavior

- `dry` declares `waterRequirement = not_applicable`.
- The scientific objective is explicit and is not inferred from ore family.
- The valuable component is explicit and is synchronized with the current legacy target-component field.
- Grade and recovery are optional in the V3 contract so raw-ore diagnosis can remain targetless when the server permits it.
- Targets and constraints remain design-basis declarations; they are not promoted to measured evidence.
- Unit-operation policy is declared to the runtime but server-side governance remains authoritative for final engine/DAG eligibility.

## Files

- `AURORA/ScientificProjectBasisV3.swift`
- `AURORA/AURORAAPI.swift`
- `AURORA/CommandCenterView.swift`
- `.github/workflows/scientific-project-contract-v3.yml`

## Not included in this slice

The following remain subsequent Repair Phase 1 work items:

1. graph-based flowsheet compiler with explicit nodes, ports, streams, splits, merges and recycle;
2. deterministic engine/DAG eligibility compiler from objective + mode + flowsheet + evidence;
3. scientific validation laboratory and gold-dataset status model;
4. migration of the proven V3 basis into a versioned persistent SwiftData schema.

No production Railway deployment or backend mutation is performed by this iOS repair branch.
