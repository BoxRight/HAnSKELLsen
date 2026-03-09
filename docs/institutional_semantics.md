# Institutional Modeling Semantics

This document describes the intended semantics for override, suspension, and authority conflict resolution in the HAnSKELLsen system.

## Override and Suspension

Both `override` and `suspend` DSL constructs compile to rules that insert `Overridden(g)` markers when their conditions hold. They do **not** remove the original norm from the norm set.

### Backend Behavior

- **Override rule** (Logic.hs): For each pair of norms (g1, g2), if c1 dominates c2, g1 conflicts with g2, and t1 >= t2, the rule inserts `IndexedGen c2 t2 (Overridden g2)`. The original `IndexedGen c2 t2 g2` remains in the norm set.
- **activeNorms**: Filters out any `IndexedGen` whose `gen` is `Overridden _`. Used for compliance queries.
- **DSL override/suspend**: Compile to RuleSpecs whose consequent is `targetGen { gen = Overridden (gen targetGen) }`. When the condition holds, the rule inserts this marker.

### Semantic Constraint

Because the original norm is never removed, override and suspend **do not deactivate** the underlying privilege or obligation for purposes of rule derivation. The `Overridden` marker is a separate fact. For use cases requiring true deactivation (e.g. "bank step-in blocks farmer termination"), use a **prohibition-based rule** instead: derive a prohibition that conflicts with the privilege when the condition holds.

### Edge Cases

#### Nested Overrides

When A overrides B and B overrides C (by authority hierarchy):

- Higher authority norms override lower authority norms.
- The override rule considers each pair; dominance and conflict are checked.
- Only non-overridden generators can act as overriders; `Overridden` norms cannot override others.
- Result: Lower authority conflicting norms receive `Overridden` markers. The highest authority norm that conflicts wins.

#### Multiple Suspensions

When several rules suspend the same modality under different conditions:

- Each suspension rule inserts `Overridden(target)` when its condition holds.
- The same `Overridden(g)` may be inserted multiple times (idempotent: `S.member` check prevents duplicates).
- The original norm remains; only markers are added. For true blocking, use prohibition-based rules.

#### Authority Conflicts

When two rules from different authorities both override the same norm:

- `dominates` defines the hierarchy: Constitutional > Administrative > Legislative > Judicial > Private > BaseAuthority.
- The higher authority wins. Temporal ordering (t1 >= t2) is also required.
- If authorities are equal, neither overrides (dominates is reflexive only for equality).

## DSL Compilation

Override and suspend clauses use `sourceMeta` from the article when compiling. The resulting RuleSpec gets the same authority and enactment date as the defining article. This ensures that imported override rules from a legislative statute carry legislative authority when they fire.

## References

- [Logic.hs](../Logic.hs) — overrideRule, conflicts, dominates
- [NormativeGenerators.hs](../NormativeGenerators.hs) — activeNorms, isOverridden
- [docs/renewable_energy_benchmark.md](renewable_energy_benchmark.md) — prohibition-based step-in pattern
- [docs/design_boundary.md](design_boundary.md) — backend kernel invariants
