# HAnSKELLsen

Formal legal reasoning prototype in Haskell with:

- typed legal ontology (`LegalOntology.hs`)
- indexed normative generators (`NormativeGenerators.hs`)
- cross-domain inference over normative + patrimony state (`Logic.hs`)
- quantale operations over norms (`Quantale.hs`)

## DSL Boundary

The lawyer-facing DSL is intended to expose legal and institutional concepts directly, not the engine's algebraic machinery.

The intended split is:

- legal layer: actors, objects, acts, obligations, claims, prohibitions, privileges, procedures, rules, and scenarios
- institutional layer: authority, ownership, temporal validity, regime metadata, and audit context
- algebraic layer: norm lattice operations, quantale structure, and fixpoint machinery

The first two layers should be readable in the DSL. The third should remain mostly implicit and only appear through legal constructs such as procedures, alternatives, and audits.

See [docs/design_boundary.md](docs/design_boundary.md) for the principle that DSL extensions compile down to the existing backend. See [docs/renewable_energy_benchmark.md](docs/renewable_energy_benchmark.md) for the benchmark coverage map and [docs/DSL_grammar.md](docs/DSL_grammar.md) for the full grammar. See [docs/audit_infrastructure.md](docs/audit_infrastructure.md) for scenario replay, JSON export, and derivation graph features.

## Two Closure Operators

The system intentionally exposes **two different, orthogonal closures** over the same lattice `Norm = Set IndexedGen`:

1. **Horn closure** (`Logic.runSystem`)
   - Applies rule set fixpoint over `SystemState`
   - Used for normative derivation (claims, enforceability, violations, override, patrimony mappings)

2. **Quantale closure** (`Quantale.kleeneStar`)
   - Applies algebraic fixpoint over action composition
   - Used for compositional action reasoning (`I ∨ x ∨ x² ∨ ...`)

These closures are composable but not the same operator:

- Horn closure: derives legal consequences from rules
- Quantale closure: computes algebraic closure from multiplication

## Quantale Laws Implemented

Over `Norm`:

- order: subset `⊆`
- join: set union `joinNorm = S.union`
- multiplication: `mulNorm`
- identity: `unitNorm`
- zero: `emptyNorm`

Core laws covered by runtime checks in `logic.hs`:

- identity:
  - `mulNorm unitNorm x == x`
  - `mulNorm x unitNorm == x`
  - `mulNorm unitNorm unitNorm == unitNorm`
- associativity:
  - `mulNorm (mulNorm a b) c == mulNorm a (mulNorm b c)`
- distributivity over join:
  - `mulNorm a (joinNorm b c) == joinNorm (mulNorm a b) (mulNorm a c)`
- zero/absorbing:
  - `mulNorm emptyNorm x == emptyNorm`
  - `mulNorm x emptyNorm == emptyNorm`

## Normalization Guarantees

`LegalOntology.normalizeAct` provides canonical action terms for composition:

- `Seq [] -> Id`
- `Seq [a] -> a`
- removes `Id` inside `Seq`
- flattens nested `Seq`
- flattens nested `Par`
- removes `Id` from `Par`
- preserves parallel semantics (`Par {a}` is not collapsed to `a`)

This normalization supports stable equality and predictable quantale multiplication.

