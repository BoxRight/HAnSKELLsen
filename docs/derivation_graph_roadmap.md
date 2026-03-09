# Derivation Graph Roadmap

This document captures the technical evaluation of the derivation graph output and the planned improvements. The underlying reasoning engine is structurally sound; the remaining work is primarily **representation and visualization**.

## Current Assessment

### What Works Well

1. **Three-layer structure** — Facts → rules → derived generators. The DSL compiler lowers rules into the existing generator/fixpoint system without alternative execution paths. Derivations are produced through monotonic rule firing.

2. **Authority indexing** — Capability indices (LegislativePower, AdministrativePower, PrivatePower) are preserved. Derived outputs keep the authority of the rule source rather than the triggering act.

3. **Temporal indexing** — Each generator carries a `time` field; rule nodes include timestamps. Scenario slicing and audit replay work consistently.

4. **Institutional facts** — PatrFact nodes (Liability, Asset, ApprovedContractor) connect directly into rules. Patrimony facts act as triggers without special inference semantics.

5. **Counter-acts** — Act:Counter nodes trigger breach rules (FarmerTerminationAfterNonPayment, StepInRightAfterLoanDefault) correctly.

6. **Provenance traceability** — The path `trigger fact → rule → resulting generator` is explicit. DSL-defined rules are traceable independently from built-in engine rules.

7. **Tropical/semiring readiness** — The graph has generators as algebraic elements, rule edges as derivation operators, timestamps as weights, and authority levels as ordering dimensions. It can be interpreted as a weighted DAG.

### Structural Issues to Address

| Priority | Issue | Direction |
|----------|------|-----------|
| 1 | **Graph readability** | Replace raw `show` output with canonical labels (e.g. `privilege(actor, object, target, date, authority)`) using `prettyIndexedGenWithDisplay` |
| 2 | **Seed vs derived norms** | Visually distinguish seed norms from derived norms (node classes, DOT `fillcolor` or `style`) |
| 3 | **Rule condition visibility** | Annotate rule nodes with the logical condition (for multi-premise rules, show condition structure) |
| 4 | **Epoch date (0001-01-01)** | Display "triggered by institutional fact" instead of synthetic date when rule fires from static patrimony |
| 5 | **Patrimony provenance** | Add authority/time metadata to PatrFact nodes (longer-term: indexed patrimony generators) |
| 6 | **Grouping** | Optionally group nodes by time or authority rank |

## Implementation Plan

### Phase 1: Canonical Labels and Provenance (Done)

- [x] Pass `CompiledLawModule` to `buildDerivationGraph` for DSL vocabulary
- [x] Use `prettyIndexedGenWithDisplay` for generator node labels
- [x] Use short patrimony form: `asset(name)`, `liability(name)`, etc.
- [x] Add node provenance: `SeedNorm` | `DerivedNorm` | `PatrimonyFact`
- [x] Emit provenance in DOT via `fillcolor` (lightblue=seed, lightgreen=derived, lightyellow=patrimony, lavender=rule)
- [x] Special-case epoch date in rule labels: `[institutional fact]` instead of `0001-01-01`
- [x] Add rule condition to rule node labels via `prettyCondition`

### Phase 3: Patrimony and Grouping (Future)

- [ ] Document limitation: patrimony facts lack authority/time indexing
- [ ] Explore indexed patrimony generators for full provenance
- [ ] Add optional DOT subgraphs for grouping by date or authority

## Evaluation Summary

| Dimension | Status |
|-----------|--------|
| Kernel correctness | Strong |
| Provenance traceability | Strong |
| Institutional modeling | Good |
| Graph usability | Improved (canonical labels, provenance colors, condition annotations) |
| Patrimony provenance | Incomplete (no authority/time on PatrFact) |
| Condition representation | Implemented (rule labels include `prettyCondition`) |

## References

- [src/Runtime/DerivationGraph.hs](../src/Runtime/DerivationGraph.hs) — graph construction and export
- [src/Pretty/PrettyNorm.hs](../src/Pretty/PrettyNorm.hs) — canonical generator labels
- [docs/audit_infrastructure.md](audit_infrastructure.md) — CLI usage
