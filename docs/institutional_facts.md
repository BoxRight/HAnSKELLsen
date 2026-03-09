# Institutional Fact Schema

This document defines the schema for institutional facts in the HAnSKELLsen DSL. These facts populate the patrimony state and are used in rule conditions.

## Fact Types

| Type | DSL Form | PatrimonyGen | Use Case |
|------|----------|--------------|----------|
| Asset | `asset <Name> is present` | `P.Asset String` | Claims, performance records, filed documents |
| Liability | `liability <Name> is present` | `P.Liability String` | Obligations, breach markers, outstanding duties |
| Collateral | `collateral <Name> is present` | `P.Collateral String` | Security interests, pledges, liens |
| Certification | `certification <Name> is present` | `P.Certification String` | Regulatory or third-party attestations |
| Approved Contractor | `approved contractor <Name> is present` | `P.ApprovedContractor String` | Procedural preconditions for permitted acts |
| Capability | `authority <private\|legislative\|...> is present` | `P.Capability String` | Authority or standing |
| Ownership | `<Party> owns <Object>` | `P.Owned Object` | Ownership of objects |

## Naming Conventions

- **Asset/Liability**: Use descriptive names that reflect the claim or obligation (e.g. `InsuranceClaimFiled`, `StormDamage`).
- **Collateral**: Use names that identify the security interest (e.g. `LeaseCollateral`, `LoanSecurity`).
- **Certification**: Use names that identify the certification type (e.g. `BiodiversityCertification`, `EnvironmentalCompliance`).
- **Approved Contractor**: Use names that identify the engagement (e.g. `ApprovedContractorEngaged`).

## Rule-Condition Patterns

Each fact type can appear in rule conditions:

```text
rule Example
    If asset InsuranceClaimFiled is present
    and approved contractor ApprovedContractorEngaged is present
    then ...
```

Allowed condition forms:

- `If <Party> owns <Object>`
- `If authority <capability> is present`
- `If asset <Name> is present`
- `If liability <Name> is present`
- `If collateral <Name> is present`
- `If certification <Name> is present`
- `If approved contractor <Name> is present`
- `If <Party> <verb>s <Object> to <Party>` (action condition)
- `If event <Text>` or `If natural event <Text>`
- Conjunctions: `If A and B and C then ...`

## Scenario Assertions

Scenario blocks can assert institutional facts at a given date:

```text
at 2025-06-20
    assert asset InsuranceClaimFiled is present.
at 2025-06-28
    assert approved contractor ApprovedContractorEngaged is present.
```

These assertions add the corresponding `PatrimonyGen` to the scenario timeline. The audit engine applies them at the specified date.

## Compilation Flow

1. **Standing facts** in articles compile to `CompiledInstitutionalFact` and populate `compiledInstitutionalFacts` (initial patrimony).
2. **Scenario assertions** compile to `ScenarioDelta` with `deltaPatrFacts`.
3. **Rule conditions** resolve to `ResolvedAssetCondition`, `ResolvedLiabilityCondition`, etc.
4. **RuleExecution** and **Scenario** handle all types via `conditionWitness` and `scenarioFactsUpTo`.

## Consistency

[RuleExecution.hs](../src/Runtime/RuleExecution.hs) and [Scenario.hs](../src/Compiler/Scenario.hs) handle all fact types consistently. When adding new institutional fact types:

1. Add the AST form in [AST.hs](../src/Compiler/AST.hs).
2. Add the `PatrimonyGen` constructor in [Patrimony.hs](../Patrimony.hs).
3. Add resolution in Compiler (resolveCondition, compileStandingFact).
4. Add handling in RuleExecution (conditionWitness) and Scenario (assertion compilation).
5. Add pretty-printing in PrettyReport and PrettyTrace.
6. Update this schema document.
