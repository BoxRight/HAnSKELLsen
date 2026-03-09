# Renewable Energy Benchmark

This benchmark uses a deliberately convoluted multi-regime project to test the current DSL boundary before adding any computational helper layer.

## Benchmark Files

- `lawlib/shared/renewable_project_shared.dsl`
- `lawlib/statutes/renewable_energy_leasing.dsl`
- `lawlib/statutes/biodiversity_regulation.dsl`
- `lawlib/statutes/renewable_tax_credit.dsl`
- `lawlib/contracts/solar_farm_lease.dsl`
- `lawlib/contracts/project_financing.dsl`
- `lawlib/contracts/project_insurance.dsl`
- `lawlib/instantiations/renewable_energy_case.dsl`

The benchmark models:

- a legislative renewable-energy leasing framework
- a later administrative biodiversity regulation
- a later tax-credit statute
- a private lease refinement
- private financing and insurance modules
- a dated instantiation scenario with storm damage, payment default, bank step-in, repair, and certification

## Coverage Map

### Directly Expressible Now

- Multiple authorities with per-file metadata preservation.
- Layered `lawlib` composition across statutes, contracts, shared declarations, and instantiations.
- Parties, services, things, money objects, and dated scenarios.
- Obligations, claims, prohibitions, privileges, and single-condition rules.
- Counter-acts for breach modeling.
- Institutional assertions for ownership, capability, asset, and liability facts.
- Rule chains that derive later duties from earlier acts or institutional assertions.

### Expressible Now, But Awkwardly

- Bank step-in versus lease termination.
  - The benchmark models this as a derived duty that the farmer must refrain from termination after the bank assumes step-in.
  - This approximates override/suspension, but it is not an explicit legal-surface override relation.

- Storm damage and insurance processing.
  - The benchmark uses asserted liabilities and assets such as `StormDamage`, `InsuranceClaimFiled`, and `ApprovedContractorEngaged`.
  - This works, but it forces procedural states into generic asset/liability facts.

- Administrative certification and tax-credit path.
  - The benchmark models certification as an act and tax-credit entitlement as a rule consequence.
  - This captures the dependency chain, but not the full richness of certification status or retroactive application.

- Performance and threshold issues.
  - The benchmark can record the performance problem as a scenario event.
  - It cannot yet use that event directly in legal rules or compare the project output against a numeric threshold in a legal condition.

- Domain-specific action rendering.
  - The benchmark runs, but many actions still collapse to generic delivery or transfer language in reports because the backend act/object representation is more generic than the desired legal surface.
  - This makes the scenario executable, but less lawyer-readable than intended.

### Not Yet Expressible Cleanly

- Multi-premise rule conditions.
  - Example: a tax credit should require both certification and compliance with a threshold or filing deadline.

- Explicit override, suspension, or conditional dominance at the legal surface.
  - Example: bank step-in right suspends farmer termination right.

- Richer institutional relation facts.
  - Example: collateral assignment, secured creditor status, incorporated-by-reference contract clauses, approved-contractor registries.

- Event-triggered rule conditions for general human or natural events.
  - Current rules can react to acts or institutional facts, but not directly to `event` or `natural event` assertions.

- Retroactive temporal effect as a first-class legal construct.
  - The benchmark can represent later-enacted norms and dated events, but not retroactive application semantics explicitly.

- Structured procedural compliance chains.
  - Example: claim filed within thirty days and repair performed by an approved contractor.

- Numeric and date-based threshold reasoning.
  - Example: project size above threshold, production below threshold, filing deadline calculations, tax-credit amounts, revenue-share formulas.

## Ranked Legal-Structural Gaps

These should be addressed before adding a computational layer.

1. Multi-premise conditions.
   This is the biggest structural blocker for real legal chains.

2. Explicit legal-surface override and suspension constructs.
   This would let the DSL say that one right blocks or suspends another, rather than encoding the effect indirectly.

3. Richer institutional fact vocabulary.
   Add relation facts for financing, approval, collateral, assignment, certification, and similar legal statuses.

4. Better legal-surface act semantics and reporting.
   Preserve more domain-specific action meaning through lowering and pretty printing so reports read like the authored law rather than generic transfer/delivery events.

5. Better temporal/legal validity forms.
   Add constructs for later-enacted effects, retroactivity, filing windows, and temporal applicability conditions.

6. Rule conditions over general events.
   Let legal rules respond to human or natural events directly instead of only acts and patrimony-like assertions.

## Residual Computational Needs

Only after the legal-structural gaps above are addressed should a narrow intrinsic layer be considered.

Likely future intrinsic candidates:

- threshold comparisons for project size, emissions, or production
- `daysBetween`-style filing-window checks
- tax-credit amount calculations
- insurance payout calculations
- revenue-share calculations
- percentage and bracket computations

These should be restricted to pure deterministic helpers and used only where the benchmark still needs calculator-like support.

## Guidance

This benchmark supports the following design rule:

- If a feature looks like legal structure, model it in the DSL first.
- If a feature looks like a calculator or threshold helper, consider a later Haskell-backed intrinsic only after the legal structure is in place.

That keeps the DSL readable as law while still leaving room for a future narrow computation layer where it is genuinely useful.
