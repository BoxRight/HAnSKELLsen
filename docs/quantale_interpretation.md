# Quantale Interpretation of the Normative System

This document formalizes the quantale interpretation of the existing runtime structures (rule engine, generators, fixpoint closure). The quantale is an **algebraic interpretation** of the system—a precise mathematical description of the structure that emerges from the normative engine. The quantale module is **interpretative rather than operational**: the runtime rule engine does not depend on it; it describes the algebraic structure that the system exhibits.

## Carrier Definition

To avoid ambiguity between implementation types and mathematical objects:

- **G** = the set of all possible `IndexedGen`
- **Q** = 𝒫(G), the powerset of G
- Runtime `Norm` values correspond to **finite elements** of Q

Each `IndexedGen` = (capability, time, generator) where generator ∈ {GAct, GClaim, GObligation, GProhibition, GPrivilege, GEvent, GFulfillment, GViolation, GEnforceable, GStatute, Overridden}.

## Formal Definition

The quantale is a structure (Q, ≤, ∨, ·, 1) where:

- **(Q, ≤)** is a complete lattice under set inclusion ⊆
- **∨** (join) = set union
- **·** (multiplication) = Kleisli lifting of partial composition to sets (see below)
- **1** (unit) = singleton containing the identity act

## Lattice Structure

(Q, ⊆) is a complete lattice. Join = union. Meet = intersection (exists but not used in current code). In the codebase, `Norm` is a finite set of generators; the mathematical quantale lives over the full powerset Q = 𝒫(G).

---

## ⚠️ Critical: Two Closure Operators

> **This section is essential.** Many readers assume that quantale multiplication drives rule inference. It does not. The two closures operate over **completely different structures**. The runtime engine currently uses **only the first**.

### 1. Rule fixpoint (order-theoretic layer)

**Definition**: S* = μS.(S₀ ∪ R(S))

Standard least-fixpoint semantics for forward-chaining rules. The rule engine (`Logic.runSystem`) computes:

```
runSystem rules = fixpoint (applyRules rules)
```

- Closure under **rule application**: repeatedly apply rules until no new generators appear
- Each rule: `S.insert consequent` when condition holds → join-like
- Models: *if A ∧ B then derive C* → S = S ∨ {C} when condition matches

**Algebraic interpretation**: Rule derivation corresponds to a **monotone closure operator over the lattice**, not to algebraic multiplication. Rules belong to the **order-theoretic layer**. A rule `A ∧ B → C` does not correspond to multiplication in the quantale; it corresponds to a monotone operator R such that when A, B ∈ S, we have S ≤ S ∨ {C}.

**Horn theory**: The rule engine computes the least fixpoint of a monotone operator over the lattice of generator sets, which corresponds to the **least model of the Horn theory defined by the DSL rules**. That connection ties the system directly to established logic-programming semantics and explains why the fixpoint behaves predictably.

### 2. Kleene star (monoidal layer)

**Definition**: x* = 1 ∨ x ∨ x² ∨ x³ ∨ …

**Implementation** (`Quantale.kleeneStar`): closure under multiplication (act composition).

- Models: *all finite sequences of acts from x* (e.g. lease; payment; certification)
- Belongs to the **monoidal layer**
- The rule engine does **not** call `mulNorm` or `kleeneStar`
- Procedures in the DSL could compile to multiplication implicitly

---

## Multiplication

**Definition**: `mulNorm a b` = set of all `mulIndexed x y` where x ∈ a, y ∈ b and composition succeeds.

**Partiality**: In the code, `composeGen : Generator × Generator → Maybe Generator` is a lifted partial operation. The monoidal product is technically partial. `mulNorm` corresponds to the **Kleisli lifting of partial composition to sets**: we lift the partial binary operation to the powerset by collecting all defined pairwise results.

**Interpretation**: Because `composeGen` only succeeds for `GAct` cases, multiplication effectively models **sequential composition of acts**, not general normative composition. The quantale currently models **temporal composition of actions**, not composition of normative states. That distinction will matter for future analysis tools or tropical reasoning. The algebra represents a **quantale of act traces embedded inside a larger normative state space**. Other generator types (GClaim, GObligation, GEvent, etc.) remain **passive under multiplication** and only participate in join-based derivations.

**Partial composition** (`composeGen`): succeeds only for:

- `GAct Id` · `GAct b` = `GAct b`
- `GAct a` · `GAct Id` = `GAct a`
- `GAct (Simple a)` · `GAct (Simple b)` = `GAct (composeActs a b)`
- `GAct (Counter a)` · `GAct (Counter b)` = `GAct (composeActs a b)`
- All other pairs → `Nothing`

**Restriction is intentional**: Restricting multiplication to acts aligns with the intended interpretation: multiplication represents **temporal sequencing of actions**, not composition of norms. Normative generators (obligations, claims) arise from rules rather than sequential composition. Leaving them outside multiplication is consistent with the legal semantics and is not a flaw.

## Identity Element

**Unit**: `unitNorm` = singleton `{IndexedGen BaseAuthority epochDate (GAct Id)}`

**Identity laws** hold **within the subalgebra of act generators**:

- `mulNorm unitNorm x = x` (when x contains only composable acts)
- `mulNorm x unitNorm = x`
- `mulNorm unitNorm unitNorm = unitNorm`

If a set contains non-act generators, multiplication behaves more like a **partial monoid**: identity laws hold for the act components, while non-act generators are inert under multiplication.

## Worked Example

This example illustrates the separation between multiplication and rule inference:

**Multiplication** (sequential composition of acts):

- A = {install_solar}
- B = {pay_rent}
- A · B = {install_solar ; pay_rent}

Multiplication composes acts into a sequence. It does not derive new norms.

**Rule closure** (order-theoretic derivation):

- Given acts install_solar and pay_rent in the state
- A rule such as "If Developer installs SolarInstallation to Farmer then Developer must pay LeaseRent to Farmer" fires
- The rule engine adds the obligation to the state via join: S' = S ∨ {obligation}
- This is **rule inference**, not multiplication

The rule engine derives obligations, claims, and privileges from conditions. Multiplication composes acts into traces. These are orthogonal operations.

## Architecture Diagram

```
DSL (Parser, Compiler)
        │
        ▼
Rule Engine (applyRules) ──► Fixpoint ──► Logic.runSystem
        │                         │
        │  join: S.insert         │  S* = μS.(S₀ ∪ R(S))
        │  (rule derivation)      │  least model of Horn theory
        ▼                         ▼
   Normative State (Norm)

Quantale Module (interpretative)
        │
        ├── joinNorm = S.union
        ├── mulNorm = Kleisli lift of composeGen
        ├── unitNorm = {GAct Id}
        └── kleeneStar = 1 ∨ x ∨ x² ∨ ...
                │
                │  x* = closure under multiplication
                │  (sequential act composition)
                ▼
        Not used by rule engine
```

## Quantale Evaluation Mode

The CLI provides a quantale evaluation command that runs analysis over the compiled generator set:

```
hanskellsen-app quantale <file.dsl>
```

This compiles the DSL, extracts act generators and procedures, applies quantale operations (`mulNorm`, `joinNorm`, `kleeneStar`), and reports:

- **Act composition graph**: which acts compose in sequence (e.g. `grantLeaseUse → payRent`)
- **Procedure multiplication**: each procedure as a composed act or join of alternatives
- **Alternative branches**: procedures with multiple branches (join)
- **Closure**: size of act generators vs kleeneStar closure

This does not replace the rule engine. Both modes operate over the same compiled ontology.

## References

- [Quantale.hs](../Quantale.hs) — implementation
- [Logic.hs](../Logic.hs) — rule engine and fixpoint
- [NormativeGenerators.hs](../NormativeGenerators.hs) — generator types
- [LegalOntology.hs](../LegalOntology.hs) — `composeActs`, `Id`
