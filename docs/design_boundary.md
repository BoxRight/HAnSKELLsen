# Design Boundary: DSL and Compiler vs Backend

## Principle

Extend the DSL's expressive power through **compilation strategies and metadata**, not through changes to the reasoning kernel. The backend remains a monotonic fixpoint system over indexed generators with authority-based override semantics. The DSL evolves as a richer frontend that compiles down to the same structures.

All extensions described below have been implemented. See [docs/DSL_grammar.md](DSL_grammar.md) for syntax and [docs/renewable_energy_benchmark.md](renewable_energy_benchmark.md) for usage in the benchmark.

## Backend as Stable Kernel

The backend (Logic, NormativeGenerators, Quantale, Patrimony, FixedPoint, Runtime.Audit, Runtime.RuleExecution) is the **stable reasoning kernel**. It provides:

- Monotonic rule application
- Fixpoint closure
- Indexed generators with `CapabilityIndex` and `Day`
- Authority-based override and conflict resolution
- `SystemState` (normState, patrState)
- Rule type: `SystemState -> SystemState`

These invariants are not changed when extending the DSL.

## Frontend-Only Extensions

All of the following improvements occur at the DSL and compiler layer:

- **Multi-premise rule conditions** — Compiled into conjunction checks before emitting a rule; no Logic changes.
- **Explicit override and suspension** — DSL constructs compile into `Overridden` generators or rules that insert markers; backend override machinery unchanged.
- **Richer institutional relations** — New relation facts compile to existing `PatrimonyGen` or `IndexedGen`; engine treats them as ordinary facts.
- **Temporal validity and retroactivity** — DSL constructs compile into existing `time` indexing and scenario slicing; no future-fact dependence.
- **Event-triggered rule conditions** — DSL rules triggered by events compile into rules that fire on `GEvent` generators; backend already supports these.
- **Lawyer-readable reports** — Implemented entirely in the pretty-printing layer; engine representation unchanged.

## Institutional Semantics

Override and suspension semantics, authority conflict resolution, and institutional fact schema are documented in [docs/institutional_semantics.md](institutional_semantics.md) and [docs/institutional_facts.md](institutional_facts.md).

## Postponed: Haskell Intrinsic Layer

The Haskell intrinsic layer (arithmetic, thresholds, tax formulas, filing windows) is postponed until the DSL can express legal structures using only the existing rule model. Introducing that layer too early risks entangling the DSL with backend implementation.

## Summary

- Backend: stable reasoning kernel.
- DSL/Compiler: richer frontend that compiles down to existing backend structures.
- Extend through compilation strategies and metadata, not through changes to the reasoning kernel.
