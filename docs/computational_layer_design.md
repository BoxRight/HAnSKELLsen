# Computational Layer Design (Specification Only)

This document defines the contract for a future numeric intrinsic layer. **No implementation is planned at this stage.** The document serves as a specification for a later phase when the legal-structural DSL is mature and the benchmark clearly requires calculator-like support.

## Core Principle

Arithmetic behaves as a **deterministic guard on rule activation**, not as part of the normative algebra. The backend remains a **monotonic fixpoint system over generators**. Arithmetic evaluates facts but never modifies the reasoning model directly.

The correct approach is to treat arithmetic as **deterministic predicates used only inside rule conditions**. Arithmetic cannot introduce side effects, mutable state, or non-monotonic reasoning. The rule fires only if the predicate returns `True`.

## Context

[docs/renewable_energy_benchmark.md](renewable_energy_benchmark.md) identifies the remaining gap: numeric and threshold reasoning for tax credits, production levels, filing windows, and similar calculations. Rules cannot yet compare against numeric thresholds or perform date arithmetic.

## Numeric Values from Facts

**Numeric values must come from facts**, not from rule literals. The rule checks the value using an intrinsic predicate. This keeps arithmetic separate from normative reasoning.

Example scenario assertions:

```text
assert asset ProjectOutput = 12000
assert production SolarPlant 12000
```

The rule then references the fact and applies an intrinsic predicate. The engine still derives obligations, claims, and privileges exactly the same way—it just consults numeric facts when evaluating eligibility conditions.

## DSL Syntax

At the DSL level, rules can include numeric checks such as:

```text
rule TaxCreditEligibility
    If SolarGrowthLtd productionAboveThreshold 10000
    then SolarGrowthLtd may demand grant of the renewableTaxCredit from RevenueOffice.
```

The actual comparison is handled by a pure intrinsic function. The DSL parses the condition; the compiler lowers it to a predicate node; the runtime evaluates the predicate during rule matching.

## Compiler Pipeline

1. **DSL parses** the condition (e.g. `IntrinsicConditionAst` in [AST.hs](../src/Compiler/AST.hs)).
2. **Compiler lowers** it to `ResolvedIntrinsicPredicate` in [Compiler.hs](../src/Compiler/Compiler.hs).
3. **Runtime evaluates** via `conditionWitness` in [RuleExecution.hs](../src/Runtime/RuleExecution.hs) — add a case that looks up the intrinsic in `IntrinsicEnv` and calls it with resolved arguments.

Conceptually the runtime receives something like:

```haskell
ResolvedCondition
  = ResolvedOwnershipCondition ...
  | ResolvedActionCondition ...
  | ResolvedEventCondition ...
  | ResolvedIntrinsicPredicate Text [Value]  -- NEW
  | ResolvedConjunction ...
```

The runtime simply calls a deterministic function.

## Intrinsic Whitelist (IntrinsicEnv)

The runtime maintains a **small whitelist** of allowed intrinsics:

```haskell
IntrinsicEnv :: Map Text ([Value] -> Bool)
```

This avoids arbitrary Haskell execution. Only registered intrinsics can be invoked. Unknown or unregistered intrinsics cause the condition to fail (or a diagnostic at compile time).

## Initial Intrinsic Set

The most useful initial intrinsics for tax and regulatory models:

| Intrinsic | Purpose |
|-----------|---------|
| `aboveThreshold(value, threshold)` | value > threshold |
| `belowThreshold(value, threshold)` | value < threshold |
| `between(value, lower, upper)` | value in range |
| `daysBetween(date1, date2)` | date arithmetic |
| `withinWindow(date, start, end)` | date in validity window |
| `percentage(amount, rate)` | percentage computation |
| `taxAmount(base, rate)` | tax calculation |

All must be:

- pure
- deterministic
- side-effect free
- independent of the normative state

## Example Intrinsic Implementation

```haskell
aboveThreshold :: Double -> Double -> Bool
aboveThreshold value threshold = value > threshold
```

The rule fires only if the predicate returns `True`.

## Minimal Code-Level Changes (Future)

For implementers, the extension points are:

- Extend `ConditionAst` in [AST.hs](../src/Compiler/AST.hs) with `IntrinsicConditionAst`.
- Extend `ResolvedCondition` in [Compiler.hs](../src/Compiler/Compiler.hs) with `ResolvedIntrinsicPredicate`.
- Add intrinsic function registry in runtime (e.g. `Runtime.Intrinsics`).
- Extend `conditionWitness` in [RuleExecution.hs](../src/Runtime/RuleExecution.hs) to evaluate intrinsic predicates.

**No change** is required to the fixpoint engine, generator model, or override semantics. Arithmetic only affects whether a rule fires.

## Call Sites

- Intrinsics are callable **only from rule conditions**.
- They are **not** available in:
  - Modality definitions (obligation, claim, prohibition, privilege)
  - Procedure blocks
  - Scenario assertions (except possibly in a future condition form)

## Deferred

- **No implementation.** This document is a specification for a future phase.
- Implementation should begin only when:
  - The legal-structural DSL is stable.
  - The benchmark or a concrete use case clearly requires one or more intrinsics.
  - The design boundary (backend as stable kernel) remains respected.

## References

- [docs/renewable_energy_benchmark.md](renewable_energy_benchmark.md) — Residual computational needs
- [docs/design_boundary.md](design_boundary.md) — Backend kernel invariants
