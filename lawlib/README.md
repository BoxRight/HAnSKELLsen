# Lawlib: Legal Standard Library

The `lawlib` directory is a curated corpus of canonical legal modules for the HAnSKELLsen DSL. It functions as a **legal standard library** rather than a collection of ad-hoc examples.

## Directory Layout

| Directory | Purpose |
|-----------|---------|
| **statutes/** | Public-law frameworks: leasing, sales, permits, tax, licensing |
| **contracts/** | Private refinements: leases, sales, financing, insurance |
| **shared/** | Reusable declarations: parties, objects, vocabulary |
| **instantiations/** | Runnable assembled cases that compose statutes and contracts |
| **fixtures/invalid/** | Invalid DSL files for parser/compiler tests |

## Naming Conventions

- Each module has a `law` header with `authority` and `enacted` date.
- Use descriptive law names (e.g. `RenewableEnergyLeasingStatute`, `ProjectInsurance`).
- Shared modules use `Shared` suffix; statutes use `Statute` or `Regulation`; contracts use descriptive names.

## Composition Pattern

1. **Shared first**: Import shared declarations for parties, objects, and vocabulary.
2. **Statutes**: Define public-law obligations, claims, and permissions.
3. **Contracts**: Refine or add private obligations; may import statutes.
4. **Instantiations**: Assemble the full regime and define scenarios.

Example:

```text
law MyCase
authority private
enacted 2025-01-01

import "../statutes/some_statute.dsl"
import "../contracts/some_contract.dsl"

scenario MyScenario:
    at 2025-01-15
        act PartyA does Something to PartyB.
```

## Canonical Examples

- **Renewable energy benchmark**: `instantiations/renewable_energy_case.dsl` — multi-regime project with statutes, contracts, and layered composition. Run with:
  ```bash
  cabal run hanskellsen-app -- lawlib/instantiations/renewable_energy_case.dsl --scenario ProjectDisruptionAndStepIn --audit-at 2025-07-20
  ```
- **Leases**: `base_lease_shared.dsl`, `lease_framework_import.dsl`, `solar_farm_lease.dsl`, `residential_lease.dsl`
- **Sales**: `base_sale_shared.dsl`, `sales.dsl`, `car_sale.dsl`
- **Financing**: `project_financing.dsl`, `simple_loan.dsl`
- **Insurance**: `project_insurance.dsl`, `generic_indemnity.dsl`
- **Permits**: `environmental_permit.dsl`
- **Tax**: `renewable_tax_credit.dsl`, `generic_tax.dsl`
- **Licensing**: `professional_license.dsl`

## Import Resolution

Imports are resolved relative to:

1. The importing file's directory
2. The current working directory
3. `lawlib/` (when running from project root)

Use paths like `../shared/base_sale_shared.dsl` or `statutes/sales.dsl` from `lawlib/`.
