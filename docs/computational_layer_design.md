# Computational Layer Design (Specification Only)

This document defines the contract for a future numeric intrinsic layer. **No implementation is planned at this stage.** The document serves as a specification for a later phase when the legal-structural DSL is mature and the benchmark clearly requires calculator-like support.

## Context

[docs/renewable_energy_benchmark.md](renewable_energy_benchmark.md) identifies the remaining gap: numeric and threshold reasoning for tax credits, production levels, filing windows, and similar calculations. Rules cannot yet compare against numeric thresholds or perform date arithmetic.

## Design Contract

### 1. Scope

- **Pure, deterministic helpers only.** No side effects, no I/O, no non-determinism.
- Intrinsics are explicitly enumerated. No user-defined functions in this layer.
- Each intrinsic has a fixed type and semantics.

### 2. Call Sites

- Intrinsics are callable **only from rule conditions**.
- Example: `if daysBetween(eventDate, filingDeadline) <= 30 then ...`
- They are **not** available in:
  - Modality definitions (obligation, claim, prohibition, privilege)
  - Procedure blocks
  - Scenario assertions (except possibly in a future condition form)

### 3. Signature Candidates

From the benchmark and common legal patterns:

| Intrinsic | Signature (conceptual) | Use Case |
|-----------|------------------------|----------|
| `aboveThreshold` | `(value :: Int, threshold :: Int) -> Bool` | Project size, emissions |
| `belowThreshold` | `(value :: Int, threshold :: Int) -> Bool` | Production below minimum |
| `daysBetween` | `(from :: Day, to :: Day) -> Int` | Filing windows |
| `withinWindow` | `(date :: Day, start :: Day, end :: Day) -> Bool` | Validity windows |
| `taxCreditAmount` | Placeholder: `(baseAmount :: Int, rate :: Int) -> Int` | Tax-credit calculations |
| `insurancePayout` | Placeholder: `(claimAmount :: Int, deductible :: Int) -> Int` | Insurance payout |
| `revenueShare` | Placeholder: `(revenue :: Int, sharePct :: Int) -> Int` | Revenue-share formulas |
| `percentageOf` | Placeholder: `(value :: Int, pct :: Int) -> Int` | Percentage computations |
| `bracketLookup` | Placeholder: `(value :: Int, brackets :: [(Int, Int)]) -> Int` | Bracket computations |

### 4. Integration Point

The DSL would gain condition forms such as:

```text
rule FilingWindow
    If daysBetween(eventDate, filingDeadline) <= 30
    then ...
```

The compiler would:

1. Parse the intrinsic call in the condition.
2. Lower it to a `ResolvedCondition` that evaluates the intrinsic.
3. The runtime would call the intrinsic when evaluating the condition.

### 5. Implementation Constraints

- Intrinsics live in a dedicated module (e.g. `Runtime.Intrinsics`).
- Each intrinsic is a pure Haskell function.
- The compiler emits condition nodes that reference intrinsics by name.
- The runtime evaluates them only during condition checks; they do not affect the norm set directly.

### 6. Deferred

- **No implementation.** This document is a specification for a future phase.
- Implementation should begin only when:
  - The legal-structural DSL is stable.
  - The benchmark or a concrete use case clearly requires one or more intrinsics.
  - The design boundary (backend as stable kernel) remains respected.

## References

- [docs/renewable_energy_benchmark.md](renewable_energy_benchmark.md) — Residual computational needs
- [docs/design_boundary.md](design_boundary.md) — Backend kernel invariants
