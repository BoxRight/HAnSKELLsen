# Renewable Energy Benchmark

This benchmark uses a deliberately convoluted multi-regime project to test the DSL boundary and drive legal-structural extensions before adding any computational helper layer.

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

## Running the Benchmark

```bash
cabal run hanskellsen-app -- lawlib/instantiations/renewable_energy_case.dsl --scenario ProjectDisruptionAndStepIn --audit-at 2025-07-20
```

## Coverage Map

### Directly Expressible Now

- Multiple authorities with per-file metadata preservation.
- Layered `lawlib` composition across statutes, contracts, shared declarations, and instantiations.
- Parties, services, things, money objects, and dated scenarios.
- Obligations, claims, prohibitions, privileges, and single-condition rules.
- **Multi-premise rule conditions** (`if A and B and C then ...`).
- **Override and suspend clauses** (`override <modality> by <condition>`, `suspend <modality> by <condition>`).
- **Richer institutional facts**: asset, liability, collateral, certification, approved contractor.
- **Event-triggered rule conditions** (`if event <text>` or `if natural event <text>`).
- **Temporal validity** (`valid from <date>` or `valid from <date> to <date>` on rules).
- **Lawyer-readable reports** using domain-specific verbs from vocabulary (grant, pay, install, etc.).
- Counter-acts for breach modeling.
- Rule chains that derive later duties from earlier acts or institutional assertions.
- **Numeric and date-based threshold reasoning**: `aboveThreshold`, `belowThreshold`, `between`, `withinWindow`, `daysBetween` in rule conditions; `assert numeric <Name> <value>` and `assert date <Name> <YYYY-MM-DD>` in scenarios.

### Used in This Benchmark

The lawlib currently uses:

- **Approved contractor fact**: `project_insurance.dsl` uses `approved contractor ApprovedContractorEngaged is present` in the repair-permission rule; `renewable_energy_case.dsl` asserts it in the scenario. This replaces the generic asset form for procedural preconditions.
- Asset and liability facts for `StormDamage` and `InsuranceClaimFiled`.
- A prohibition-based rule for bank step-in blocking farmer termination (see note below on suspend semantics).

### Expressible But With Semantic Constraints

- **Bank step-in versus lease termination**: The benchmark uses a derived prohibition (`Farmer must refrain from terminate LeaseTermination`) when the bank assumes step-in. The DSL also supports `suspend` clauses, but the backend's override semantics (inserting `Overridden` markers) do not currently deactivate the original privilege when the marker is present. For equivalence preservation, the prohibition-based rule is used.
- **Storm damage and insurance**: Uses asserted liabilities and assets. The `approved contractor` institutional fact is used for the repair-permission precondition.
- **Performance and threshold issues**: The scenario can record performance problems as events. Rules can now compare against numeric thresholds using intrinsics (e.g. `If aboveThreshold production 10000 then ...`).

### Not Yet Expressible

- **Structured procedural compliance chains**: e.g. claim filed within thirty days and repair performed by an approved contractor (as a single multi-premise condition with date arithmetic). The `daysBetween` intrinsic supports date arithmetic; combining it with other conditions in a single rule is supported.

## Residual Computational Needs

The intrinsic layer is implemented. Available intrinsics include:

- `aboveThreshold`, `belowThreshold`, `between` — numeric threshold comparisons
- `withinWindow` — date in validity window (e.g. filing deadlines)
- `daysBetween` — date order or "within N days" checks
- `percentage`, `taxAmount` — placeholders for future formula support

Example: to add production-threshold eligibility to the tax credit, use `assert numeric production 12000` in the scenario and `If aboveThreshold production 10000 then ...` in the rule. See [test/fixtures/intrinsic_tests.dsl](../test/fixtures/intrinsic_tests.dsl) for a minimal example.

## Verification

When updating the lawlib to use new DSL constructs, run the benchmark before and after changes and compare output. The compliance verdict, violations, fulfillments, and normative state should remain equivalent when the change is purely syntactic (e.g. `asset X` → `approved contractor X` for the same scenario fact).

## Design Boundary

See [docs/design_boundary.md](design_boundary.md) for the principle that all DSL extensions compile down to the existing backend structure. The backend remains the stable reasoning kernel.
