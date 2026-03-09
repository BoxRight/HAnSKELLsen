# Computational Layer Design

This document defines the contract for the numeric and temporal intrinsic layer. The implementation is in [Runtime.Intrinsics](../src/Runtime/Intrinsics.hs) and is wired through the compiler and rule execution.

## Core Principle

Arithmetic and date predicates behave as **deterministic guards on rule activation**, not as part of the normative algebra. The backend remains a **monotonic fixpoint system over generators**. Intrinsics evaluate facts but never modify the reasoning model directly.

Intrinsics are:

- **pure** — no side effects
- **deterministic** — same inputs always yield same output
- **used only in rule conditions** — they act as guards; the rule fires only if the predicate returns `True`

## Context

[docs/renewable_energy_benchmark.md](renewable_energy_benchmark.md) identifies the remaining gap: numeric and threshold reasoning for tax credits, production levels, filing windows, and similar calculations. Rules cannot yet compare against numeric thresholds or perform date arithmetic.

## Numeric and Date Values from Facts

**Numeric and date values** come from scenario assertions or literals in rule conditions. The rule checks the value using an intrinsic predicate. This keeps arithmetic separate from normative reasoning.

Example scenario assertions:

```text
assert numeric production 12000
assert date filingDate 2025-04-01
```

The rule then references the fact and applies an intrinsic predicate (e.g. `aboveThreshold production 10000` or `withinWindow filingDate 2025-03-01 2025-04-15`). The engine derives obligations, claims, and privileges exactly the same way—it consults numeric and date facts when evaluating eligibility conditions.

`DateFact` extends the patrimony state alongside `NumericFact`, allowing temporal scenario assertions to participate in rule conditions.

## DSL Syntax

At the DSL level, rules can include numeric and temporal checks such as:

```text
rule TaxCreditEligibility
    If aboveThreshold production 10000
    then Developer may demand grant of Benefit from Authority.

rule FilingValid
    If withinWindow filingDate 2025-03-01 2025-04-15
    then Authority must grant Benefit to Developer.
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

## Implementation Status

The intrinsic layer is implemented. See [test/fixtures/intrinsic_tests.dsl](../test/fixtures/intrinsic_tests.dsl) and [TestIntrinsics.hs](../test/TestIntrinsics.hs) for examples and tests. The design boundary (backend as stable kernel) is preserved—no changes were made to Logic, Quantale, NormativeGenerators, or the fixpoint engine.

## References

- [docs/renewable_energy_benchmark.md](renewable_energy_benchmark.md) — Residual computational needs
- [docs/design_boundary.md](design_boundary.md) — Backend kernel invariants
