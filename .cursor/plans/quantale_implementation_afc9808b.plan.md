---
name: Quantale Implementation
overview: Implement quantale structure for the legal reasoning system by adding identity generator, normalizing act sequences for associativity, and implementing quantale multiplication, unit, and Kleene star operations.
todos:
  - id: add_base_authority
    content: Add BaseAuthority to CapabilityIndex type in NormativeGenerators.hs (bottom element ⊥ of join-semilattice)
    status: completed
  - id: add_identity_act
    content: "Add Id :: Act r constructor (polymorphic in r) to LegalOntology.hs with Eq/Ord/Show instances"
    status: completed
  - id: add_identity_generator
    content: Add GId as GAct Id (not separate constructor) - helper function in NormativeGenerators.hs
    status: completed
    dependencies:
      - add_identity_act
  - id: normalize_acts
    content: Implement normalizeAct function in LegalOntology.hs - Seq [] → Id FIRST, collapse single Seq, remove Id, flatten nested Seq/Par (Par uses Set so already canonical, do NOT collapse Par {a})
    status: completed
    dependencies:
      - add_identity_act
  - id: compose_acts
    content: Implement composeActs function in LegalOntology.hs using normalizeAct, preserving type parameter r
    status: completed
    dependencies:
      - normalize_acts
  - id: capability_supremum
    content: Implement capabilitySupremum function (in Capability.hs or Logic.hs) as lattice supremum using Ord instance (max a b)
    status: completed
  - id: create_quantale_module
    content: Create new Quantale.hs module with imports and module structure
    status: completed
  - id: compose_generators
    content: Implement composeGen in Quantale.hs - strict act composition only (GAct a, GAct b), identity works automatically via composeActs, returns normalized acts
    status: completed
    dependencies:
      - add_identity_generator
      - compose_acts
  - id: multiply_indexed
    content: Implement mulIndexed in Quantale.hs using capabilitySupremum and max time combination
    status: completed
    dependencies:
      - compose_generators
      - capability_supremum
  - id: multiply_norms
    content: Implement mulNorm in Quantale.hs using powerset construction (automatically distributive)
    status: completed
    dependencies:
      - multiply_indexed
  - id: unit_norm
    content: Implement unitNorm in Quantale.hs using BaseAuthority (dedicated neutral capability)
    status: completed
    dependencies:
      - add_identity_generator
      - add_base_authority
  - id: kleene_star
    content: Implement kleeneStar in Quantale.hs reusing existing fixpoint function from Logic.hs (proven convergence)
    status: completed
    dependencies:
      - multiply_norms
      - unit_norm
  - id: integrate_logic
    content: Import Quantale module in Logic.hs and optionally expose operations
    status: completed
    dependencies:
      - kleene_star
  - id: add_tests
    content: Add quantale tests to logic.hs - associativity, identity, distributivity, normalization (Id removal, single-element collapse, Seq [] → Id, Par canonicalization), quantale zero tests
    status: completed
    dependencies:
      - integrate_logic
---

# Quantale Implementation Plan (Refined)

## Overview

Transform the current legal reasoning system into an explicit quantale algebra by adding multiplication operations, identity elements, and closure operators while preserving all existing functionality. The quantale layer remains orthogonal to the Horn rule engine, enabling both rule-based closure and algebraic composition.

## Architecture

```
LegalOntology (Acts: Simple, Counter, Seq, Par, Id)
       ↓
NormativeGenerators (Generators: GAct, helper gId)
       ↓
Capability.hs (capability lattice + supremum)
       ↓
Quantale.hs (NEW - Quantale operations)
       ↓
Logic.hs (Existing rules + quantale integration)
```

## Implementation Steps

### 1. Add Base Authority (`NormativeGenerators.hs`)

Add `BaseAuthority :: CapabilityIndex`:

- **Defined as bottom element (⊥) of the capability lattice**
- **CapabilityIndex forms a join-semilattice** with:
  - Bottom element: `BaseAuthority` (⊥)
  - Partial order: `BaseAuthority < PrivatePower < AdministrativePower < LegislativePower < ConstitutionalPower`
- Update `Eq`, `Ord`, `Show` instances
- **For the quantale, only need the join operation**: `capabilitySupremum :: CapabilityIndex -> CapabilityIndex -> CapabilityIndex`
- Do not introduce `dominates` semantics in the quantale specification (that's a separate order relation)

**Rationale**: Provides a semantically clear, authority-neutral capability that serves as the lattice bottom element. The quantale only requires the join-semilattice structure via `capabilitySupremum`, not a separate dominance relation.

### 2. Add Identity Act (`LegalOntology.hs`)

Add `Id :: Act r` constructor (polymorphic in `r`):

- Works for both `Act Active` and `Act Passive`
- Acts as neutral morphism, not separate act category
- Update `Eq`, `Ord`, `Show` instances
- Must preserve GADT type parameter `r`
- **Normalization must eliminate `Id` wherever it appears**

**Rationale**: Polymorphic identity ensures type consistency when composing active and passive acts. Normalization ensures equality stability.

### 3. Add Identity Generator Helper (`NormativeGenerators.hs`)

**Do NOT add separate `GId` constructor**. Instead:

- Add helper function:
  ```haskell
  gId :: Generator
  gId = GAct Id
  ```

- Conceptually: `GId ≡ GAct Id`
- This maintains consistency between ontology and generator layers

**Rationale**: Prevents introducing a second notion of identity and keeps algebra consistent.

### 4. Normalize Act Sequences (`LegalOntology.hs`)

Create `normalizeAct :: Act r -> Act r`:

**Normalization order (critical for correctness)**:

1. `Seq []` → `Id`
2. `Seq [a] `→ `a`
3. `Seq xs` → `Seq (filter (/= Id) xs)` (filter before reconstruction to prevent `Seq []` reappearing)
4. `Seq xs` → flatten nested `Seq`
5. `Par xs` → flatten nested `Par`
6. `Par xs` → `Par (S.delete Id xs)` (explicitly remains a Set)

**Important rule**: `Par {a} ≠ a` - do NOT collapse single-element parallel sets. Parallel composition is distinct from sequential composition.

**Par uses Set representation** which already guarantees canonical form (no duplicates, order independence).

**Normalization pipeline**: Flattening must occur **before rebuilding the structure**. Specify helper functions:

- `flattenSeq :: [Act r] -> [Act r]`
- `flattenPar :: Set (Act r) -> Set (Act r)`

**Explicit `flattenSeq` rules**:

```haskell
flattenSeq (Seq xs : ys) = flattenSeq (xs ++ ys)
flattenSeq (x : xs)      = x : flattenSeq xs
flattenSeq []            = []
```

Normalization follows this exact sequence:

```
flattenSeq
remove Id (filter)
case length:
  0 → Id
  1 → element
  n → Seq xs
```

Conceptually: `flatten → filter Id → rebuild canonical form`

This avoids accidentally reconstructing `Seq []`.

- Ensures associativity: `(a ⊗ b) ⊗ c = a ⊗ (b ⊗ c)`
- Ensures identity elimination for stable equality comparisons

**Rationale**: Without normalization, equality comparisons fail and associativity tests break. The order matters: `Seq [] → Id` must come first to prevent `Seq [Id] `from normalizing incorrectly. Filtering before reconstruction prevents empty sequences from reappearing. `Par` is already canonical via Set representation.

### 5. Implement Act Composition (`LegalOntology.hs`)

Create `composeActs :: Act r -> Act r -> Act r`:

- `composeActs a b = normalizeAct (Seq [a, b])`
- Handles `Id` as identity: `composeActs Id a = a`, `composeActs a Id = a`
- Preserves type parameter `r` (Active/Passive)
- Normalization guarantees canonical forms

**Rationale**: Simplest approach maintaining compatibility with existing act algebra.

### 6. Implement Capability Supremum (`Capability.hs` or `Logic.hs`)

Create `capabilitySupremum :: CapabilityIndex -> CapabilityIndex -> CapabilityIndex`:

- **CapabilityIndex is a join-semilattice** with:
  - Bottom element: `BaseAuthority` (⊥)
  - Partial order: `BaseAuthority < PrivatePower < AdministrativePower < LegislativePower < ConstitutionalPower`
- Computes lattice supremum (least upper bound) of two capabilities
- Implementation: `capabilitySupremum a b = max a b` (using the `Ord` instance)
- **Essential property**: `sup(BaseAuthority, c) = c` and `sup(a, b) = max a b`
- Extensible: can add new capabilities without modifying multiplication logic

**Rationale**: Makes hierarchy explicit as join-semilattice structure rather than comparison chain. Enables proper algebraic operations. The quantale only needs the join operation, not a separate dominance relation.

### 7. Create Quantale Module (`Quantale.hs` - NEW)

New module with quantale operations:

#### 7.1 Generator Composition

- `composeGen :: Generator -> Generator -> Maybe Generator`
- **Restrict composition to acts only** (keeps quantale algebra clean and predictable):
  ```haskell
  composeGen (GAct a) (GAct b) = Just (GAct (composeActs a b))
  composeGen _ _ = Nothing
  ```

- **Identity works automatically** because:
  ```haskell
  composeActs Id a = a
  composeActs a Id = a
  ```


Since `gId = GAct Id`, it already matches the `GAct` pattern, so no special identity rules needed.

- **Must return normalized acts**: `composeActs` already normalizes, so `composeGen` returns normalized generators
- Ensures all composed generators are in canonical form

#### 7.2 Indexed Generator Multiplication

- `mulIndexed :: IndexedGen -> IndexedGen -> Maybe IndexedGen`
- **Explicitly define capability combination**:
  ```haskell
  cap' = capabilitySupremum cap1 cap2
  ```


(not dominance comparison - uses lattice supremum)

- **Explicitly define time combination**:
  ```haskell
  t' = max t1 t2
  ```


This ensures monotonic temporal composition.

- Only multiplies if generators can compose via `composeGen`
- Ensures associativity and monotonicity

#### 7.3 Quantale Multiplication

- `mulNorm :: Norm -> Norm -> Norm`
- Powerset construction: `A ⊗ B = { a ⊗ b | a ∈ A, b ∈ B }`
- **Implementation (no special cases)**:
  ```haskell
  mulNorm a b =
    S.fromList
      [ g
      | x <- S.toList a
      , y <- S.toList b
      , Just g <- [mulIndexed x y]
      ]
  ```


The list-comprehension implementation automatically guarantees the absorbing law. Do not add explicit special cases for empty norms, as this risks breaking distributivity later.

- **Automatically distributive** over union (powerset property)

#### 7.4 Unit Element

- `unitNorm :: Norm`
- **Use `BaseAuthority` as bottom element of capability lattice**
- Contains: `IndexedGen BaseAuthority epochDate (GAct Id)`
- **Explicit identity property**:
  ```haskell
  mulNorm unitNorm A = A
  mulNorm A unitNorm = A
  ```


This is what proves the structure is a quantale.

- **Semantics**: The unit element represents the neutral action under the lowest authority, ensuring it doesn't interfere with any capability-indexed composition

**Rationale**: Using the lattice bottom as the identity element ensures it's authority-neutral and won't dominate any composition. The explicit identity property is essential for the quantale structure.

#### 7.5 Kleene Star (Closure)

- `kleeneStar :: Norm -> Norm`
- Computes `x* = I ∨ x ∨ x² ∨ x³ ...`
- **Reuse existing `fixpoint` function from Logic.hs**
- **Correct implementation**: `fixpoint step (joinNorm unitNorm x)` where `step acc = joinNorm acc (mulNorm acc x)`
  - Start with `joinNorm unitNorm x` (not just `unitNorm`) so first iteration includes `x`
  - Otherwise the first iteration misses `x` and the closure is incorrect
- The existing fixpoint engine already guarantees convergence over finite lattices
- Related to existing rule closure but explicitly algebraic
- Both use the same convergence mechanism, ensuring consistent semantics

**Rationale**: Reusing the proven fixpoint engine guarantees termination and maintains consistency with the existing inference system. Starting with `joinNorm unitNorm x` ensures the closure correctly includes all powers of `x`.

#### 7.6 Join Helper (Optional but Recommended)

- `joinNorm :: Norm -> Norm -> Norm`
- Implementation: `joinNorm = S.union`
- Keeps the algebra notation consistent when writing `x* = I ∨ x ∨ x² ...`
- Useful for maintaining algebraic clarity in quantale operations

#### 7.7 Residuation (POSTPONED)

- `residual :: Norm -> Norm -> Norm` - **Defer implementation**
- Requires iterating over universe of generators (computationally expensive)
- Implement only when generator space is explicitly bounded or indexed
- Useful for compliance reasoning but not essential for quantale structure

### 8. Update Logic Module (`Logic.hs`)

Add quantale integration:

- Import `Quantale` module
- Optionally expose quantale operations for reasoning
- Keep existing rule engine completely unchanged
- Quantale layer remains orthogonal

### 9. Update Tests (`logic.hs`)

Add comprehensive quantale operation tests:

**Core Algebraic Laws**:

- Identity: `mulNorm unitNorm x == x` and `mulNorm x unitNorm == x`
- Identity idempotence: `mulNorm unitNorm unitNorm == unitNorm` (catches identity construction errors early)
- Associativity: `mulNorm (mulNorm a b) c == mulNorm a (mulNorm b c)`
- Distributivity: `mulNorm a (joinNorm b c) == joinNorm (mulNorm a b) (mulNorm a c)`
- **Zero element (absorbing law)**: `mulNorm emptyNorm x == emptyNorm` and `mulNorm x emptyNorm == emptyNorm` (empty norm is absorbing - automatically guaranteed by implementation)

**Normalization Tests**:

- Empty sequence first: `normalizeAct (Seq []) == Id` (must be tested first)
- Single-element collapse: `normalizeAct (Seq [a]) == a` (critical for equality)
- Identity removal: `normalizeAct (Seq [Id, a, Id]) == normalizeAct (Seq [a])`
- Nested flattening: `normalizeAct (Seq [a, Seq [b, c]]) == normalizeAct (Seq [a, b, c])`
- Par flattening: `normalizeAct (Par {a, Par {b, c}}) == normalizeAct (Par {a, b, c})`
- Par preserves single elements: `normalizeAct (Par {a}) == Par {a}` (do NOT collapse)
- Par duplicate handling: `Par {a, a} == Par {a}` (Set automatically handles this)

**Quantale Zero Tests**:

- Empty norm is absorbing: `mulNorm emptyNorm x == emptyNorm`
- Empty norm is zero for join: `joinNorm emptyNorm x == x`
- Zero multiplication: `mulNorm x emptyNorm == emptyNorm`

**Quantale Operations**:

- Kleene star convergence
- Capability hierarchy in multiplication (supremum behavior)
- Temporal combination (max time)
- Unit element neutrality

## Key Design Decisions

1. **Base Authority**: `BaseAuthority` as bottom element (⊥) of capability join-semilattice
2. **Identity Generator**: `GId ≡ GAct Id` (helper function, not separate constructor)
3. **Identity Act**: Polymorphic `Id :: Act r` (works for both Active and Passive)
4. **Normalization**: Must eliminate `Id`, collapse single-element sequences (but NOT `Par`), flatten nested structures, and handle `Seq [] → Id` FIRST for equality stability
5. **Capability Combination**: `CapabilityIndex` is a join-semilattice; use `capabilitySupremum` function (extensible, not hard-coded chain)
6. **Temporal Combination**: Use `max(t1, t2)` - later time dominates
7. **Unit Element**: Use `BaseAuthority` as lattice bottom (⊥) - authority-neutral and doesn't dominate any composition
8. **Module Structure**: New `Quantale.hs` module keeps quantale operations separate from inference rules
9. **Generator Composition**: Strict act composition only - `composeGen (GAct a) (GAct b) = Just (GAct (composeActs a b))`, identity works automatically via `composeActs Id a = a`
10. **Kleene Star**: Reuse existing `fixpoint` function from Logic.hs (proven convergence, consistent semantics)
11. **Residuation**: Postpone until generator space is bounded
12. **Backward Compatibility**: All existing rules and operations remain unchanged

## Files to Modify

1. `NormativeGenerators.hs` - Add `BaseAuthority` to `CapabilityIndex`, add `gId` helper function
2. `LegalOntology.hs` - Add polymorphic `Id` act, normalization (with single-element collapse), composition
3. `Logic.hs` or `Capability.hs` - Add `capabilitySupremum` function, import Quantale
4. `Quantale.hs` - **NEW** - All quantale operations
5. `logic.hs` - Add quantale tests including normalization (single-element collapse)

## Mathematical Properties to Verify

- **Associativity**: `(a ⊗ b) ⊗ c = a ⊗ (b ⊗ c)` (via normalization)
- **Identity**: `I ⊗ a = a = a ⊗ I` (via unitNorm and normalization)
- **Monotonicity**: `a ≤ b` implies `a ⊗ c ≤ b ⊗ c` and `c ⊗ a ≤ c ⊗ b` (powerset property)
- **Distributivity**: `a ⊗ (b ∨ c) = (a ⊗ b) ∨ (a ⊗ c)` (automatic from powerset)
- **Closure**: `x* = I ∨ x ∨ x² ∨ ...` converges (via existing fixpoint engine)
- **Zero element**: Empty norm is absorbing for multiplication

## Expected Outcome

The system will support both:

- **Horn closure** (existing rule engine) - unchanged
  - Operates on normative derivation
  - `closure_rules` computes fixpoint over rule applications
- **Quantale closure** (new algebraic operations) - orthogonal layer
  - Operates on action composition
  - `kleeneStar` computes closure over act multiplication

**Important conceptual note**: These are **two different closure operators on the same lattice**:

- `kleeneStar` operates on action composition
- `Horn closure` operates on normative derivation

They are **orthogonal** - the quantale layer remains separate from the inference rules, enabling both reasoning mechanisms to coexist without interference.

Enabling:

- Shortest legal path computation
- Compliance sequence planning
- Counterfactual reasoning
- Algebraic conflict detection
- Compositional legal action modeling

Both reasoning mechanisms operate over the same lattice of generators, coexisting without interference.