# HAnSKELLsen

Formal legal reasoning prototype in Haskell with:

- typed legal ontology (`LegalOntology.hs`)
- indexed normative generators (`NormativeGenerators.hs`)
- cross-domain inference over normative + patrimony state (`Logic.hs`)
- quantale operations over norms (`Quantale.hs`)

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

