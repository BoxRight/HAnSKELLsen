# DSL Grammar

This DSL slice uses a controlled legal language with deterministic parsing and a lawyer-facing surface.

## File Shape

```text
law <LawName>
authority <private|legislative|judicial|administrative|constitutional>
enacted <YYYY-MM-DD>

import "path/to/file.dsl"

vocabulary
    verb <surface>: <canonical>
    object <surface>: <canonical>

facts
    <Name>: numeric
    <Name>: date

parties
    <Alias>: <DisplayName>[, natural person|legal person][, enjoy capacity|exercise capacity][, address <Text>]

objects
    <Alias>: <movable|nonmovable|non_movable|expendable|money|service>[, performance|omission][, of <Object>][, start <YYYY-MM-DD>][, due <YYYY-MM-DD>][, end <YYYY-MM-DD>]

article <Number> [Optional Heading]
    fact <Party> owns <Object>.
    fact authority <private|legislative|judicial|administrative|constitutional> is present.
    fact asset <Name> is present.
    fact liability <Name> is present.
    override <modality> by <condition>.
    suspend <modality> by <condition>.
    obligation <Party> must <verb> <Object> to <Party>.
    claim <Party> may demand <verb> of <Object> from <Party>.
    prohibition <Party> must not <verb> <Object> to <Party>.
    privilege <Party> may <verb> <Object> to <Party>.
    privilege <Party> may refrain from <verb> <Object> to <Party>.
    procedure <Name>:
        <Party> <verb>s <Object> to <Party>.
        or
        <Party> <verb>s <Object> to <Party>.
    rule <Name>
        If <Party> owns <Object>
        then <Party> may demand <verb> of <Object> from <Party>.
    rule <Name>
        If <Condition> and <Condition> [and <Condition> ...]
        then <consequence>.
        [valid from <YYYY-MM-DD> [to <YYYY-MM-DD>].]
    rule <Name>
        If event <Text> [or natural event <Text>]
        then <consequence>.

scenario <Name>:
    at <YYYY-MM-DD>
        act <Party> <verb>s <Object> to <Party>.
        counteract <Party> fails to <verb> <Object> to <Party>.
        assert <Party> owns <Object>.
        assert authority <private|legislative|judicial|administrative|constitutional> is present.
        assert asset <Name> is present.
        assert liability <Name> is present.
        assert collateral <Name> is present.
        assert certification <Name> is present.
        assert approved contractor <Name> is present.
        assert numeric <Name> <value>.
        assert date <Name> <YYYY-MM-DD>.
        event <Text>
        natural event <Text>

template <TemplateName>(<Param>, <Param>, ...):
    <ordinary sections, articles, scenarios, or instantiate forms>

instantiate <TemplateName>(<Param>=<Value>, <Param>=<Value>, ...)
```

## Vocabulary and Canonical Verbs

The `vocabulary` block maps surface verbs (as used in drafting) to canonical verbs (internal representation). The compiler maintains a **canonical verb registry** for extraction stability. Vocabulary entries should map surface forms to registry verbs when possible; controlled extensions (e.g. `collect`, `apply`, `maintain` for usufruct or anticresis) are allowed.

The default registry includes: `transfer`, `pay`, `deliver`, `perform`, `refrain`, `refrain from`, `refrain from interfering with`, `collect`, `apply`, `maintain`, `notify`, `cancel`, `damage`. The registry is compiler-internal; object-derived verbs from `baseVerbForObject` (transfer, deliver, perform, refrain from) align with this set.

## Notes

- Indentation is significant.
- Use four spaces for section contents.
- Use eight spaces for `procedure` and `rule` bodies.
- Use eight spaces for scenario assertions inside an `at` block.
- `event` and `natural event` are standalone (no `assert` prefix); other scenario facts use `assert`.
- Use four spaces for forms inside a `template` body.
- Symbolic algebra is intentionally hidden from the legal surface language.
- The current compiler slice resolves parties, objects, and verbs strictly.
- Templates are compile-time authoring aids. They disappear before lowering and runtime execution.
- Imports are frontend-only composition directives. Imported files are resolved before template expansion.
- A recommended `lawlib` layout is: `statutes/` for public-law frameworks, `contracts/` for private refinements, `shared/` for reusable declarations, and `instantiations/` for runnable assembled cases.
- The intended CLI entrypoint for layered examples is an `instantiations/` file, not a raw statute or contract module.

## Templates

Templates are single-file frontend macros over ordinary DSL forms.

- Define a reusable legal pattern with `template Name(...)`.
- Reuse it with `instantiate Name(...)`.
- Template expansion happens before symbol resolution, rule lowering, scenario compilation, and audit.
- Templates can be collected across imported files before instantiation expands.
- Runtime placeholders are not part of this slice.

Parameter use rules:

- In identifier positions such as party aliases, object aliases, and action references, use the bare parameter name.
- In free text such as article headings, scenario names, and rule names, use `{{ParamName}}` for interpolation.
- Every parameter must be bound exactly once at each `instantiate`.
- Unknown bindings and recursive instantiation are rejected during frontend expansion.

Example:

```text
template LeaseFramework(Lessor, Lessee, UseObject, RentObject):
    article 1 {{Lessor}} Framework
        obligation Lessor must grant UseObject to Lessee.
        rule RentDutyAfterUse
            If Lessor grants UseObject to Lessee
            then Lessee must pay RentObject to Lessor.

instantiate LeaseFramework(Lessor=DefaultLessor, Lessee=DefaultLessee, UseObject=LeaseUse, RentObject=MonthlyRent)
```

## Imports

Imports compose whole DSL files before template expansion.

- Use `import "relative/or/library/path.dsl"` at top level.
- Imports are resolved relative to the importing file first.
- If not found there, the frontend may resolve through the current working directory and then through `lawlib`.
- Import graphs must be acyclic.
- The same imported file is only composed once, even if multiple parents import it.
- Templates from imported files are visible to the whole composed frontend program before instantiation expands.

Composition order:

1. Parse entry file and imported files.
2. Resolve and compose imports deterministically.
3. Collect templates across the composed program.
4. Expand template instantiations.
5. Lower the resulting concrete program into the existing backend representation.

Metadata preservation:

- Imported articles, rules, and scenarios keep the `authority` and `enacted` metadata of the file that defined them.
- The entry file metadata remains the default CLI/report header metadata.
- Patrimony facts do not yet preserve per-import authority provenance because patrimony state is still unindexed.

Example:

```text
law CombinedLeaseCase
authority private
enacted 2025-02-01

import "../statutes/lease_framework_import.dsl"
import "../contracts/private_lease_refinement.dsl"

instantiate LeaseFramework(Lessor=Lessor, Lessee=Lessee, UseObject=LeaseUse, RentObject=MonthlyRent)

scenario PrivateBreach:
    at 2025-01-21
        act Lessor grants LeaseUse to Lessee.
    at 2025-02-21
        counteract Lessee fails to pay MonthlyRent to Lessor.
```

## Lawlib Layering

For larger legal libraries, use the following convention:

- `lawlib/statutes/`: legislative or institutional frameworks and default public-law rules.
- `lawlib/contracts/`: private refinements that import statutes and add contractual clauses.
- `lawlib/shared/`: reusable vocabulary, party, object, and baseline declarations shared by multiple modules.
- `lawlib/instantiations/`: concrete assembled cases that import statutes/contracts, perform `instantiate`, and define canonical scenarios.

Recommended rule:

1. Put general legal frameworks in `statutes/`.
2. Put reusable private refinements in `contracts/`.
3. Put executable case assembly and audit scenarios in `instantiations/`.

This keeps reusable law modules separate from runnable case files.

## Intrinsic Predicates

Rule conditions can use intrinsic predicates for numeric and temporal checks. Intrinsic arguments may be:

- `<numeric_literal>` — a numeric constant (e.g. `10000`)
- `<date_literal>` — a date in `YYYY-MM-DD` format
- `<fact_reference>` — a name referring to a numeric or date fact asserted in the scenario

Example rule conditions:

```text
If aboveThreshold production 10000
If withinWindow filingDate 2025-03-01 2025-04-15
If daysBetween filingDate deadline 30
```

Available intrinsics (prefix-style; exact argument order and types):

| Intrinsic | Signature | Arity | Example |
|-----------|-----------|-------|---------|
| `aboveThreshold` | value, threshold | 2 (numeric, numeric) | `aboveThreshold production 10000` |
| `belowThreshold` | value, threshold | 2 (numeric, numeric) | `belowThreshold X T` |
| `between` | value, lower, upper | 3 (numeric, numeric, numeric) | `between v lo hi` |
| `withinWindow` | date, start, end | 3 (date, date, date) | `withinWindow filingDate 2025-03-01 2025-04-15` |
| `daysBetween` | date1, date2 | 2 (date, date) | `daysBetween d1 d2` — d2 >= d1 |
| `daysBetween` | date1, date2, maxDays | 3 (date, date, numeric) | `daysBetween d1 d2 30` — abs(days) <= maxDays |
| `percentage` | amount, rate | 2 (numeric, numeric) | `percentage AdvancePayment 50` |
| `taxAmount` | base, rate | 2 (numeric, numeric) | `taxAmount base rate` |

Numeric and date facts used in rule conditions must be declared in a `facts` block. Declare each fact with its kind:

```text
facts
    production: numeric
    filingDate: date
```

Numeric facts are asserted with `assert numeric <Name> <value>`. Date facts are asserted with `assert date <Name> <YYYY-MM-DD>`. Rule conditions that reference fact names in intrinsics (e.g. `aboveThreshold production 10000`, `withinWindow filingDate ...`) require those names to be declared.

## Controlled Forms

Accepted legal-style action forms include:

- `<Party> must <verb> <Object> to <Party>.`
- `<Party> must not <verb> <Object> to <Party>.`
- `<Party> may <verb> <Object> to <Party>.`
- `<Party> must refrain from <verb> <Object> to <Party>.`
- `<Party> may refrain from <verb> <Object> to <Party>.`
- `<Party> fails to <verb> <Object> to <Party>.`
- `<Party> does not <verb> <Object> to <Party>.` (accepted; output prefers `fails to`)

Institutional fact forms include:

- `<Party> owns <Object>.`
- `authority legislative is present.`
- `asset RentLedger is present.`
- `liability RentArrears is present.`
- `collateral <Name> is present.`
- `certification <Name> is present.`
- `approved contractor <Name> is present.`

## Fact Discipline (Convention)

- **Persistent facts**: `fact asset X`, `fact liability X`, etc. represent institutional state.
- **Contingent events**: Use `event X` or `natural event X` in rule conditions; they appear in scenarios without `assert`.
- **Lint**: The compiler may warn if a rule condition references `event X` and there is also a fact (asset/liability/collateral/certification) named `X`, as this may indicate confusion. Many contracts legitimately declare contingent states as facts (e.g. "force majeure declared"); the warning is advisory only.

## Design Boundary

The DSL is not intended to mirror the Haskell backend one-to-one. Its job is to provide a readable legal specification language that compiles into the backend's reasoning structures.

The intended boundary is:

- fully expose the legal layer
- fully expose the institutional layer
- only indirectly expose the algebraic layer

### Legal Layer

These are concepts the DSL should eventually express directly because they correspond to legal drafting and legal doctrine:

- actors and roles
- objects and services
- acts and procedures
- obligations, claims, prohibitions, and privileges
- conditions and scenarios
- rules that generate or transform norms

### Institutional Layer

These are structural concepts the DSL should also expose directly because they frame how legal rules apply:

- authority
- enactment and temporal validity
- ownership and other institutional facts
- regime metadata
- audit scenarios and factual timelines

### Algebraic Layer

These are backend mechanisms that should remain mostly implicit:

- generator lifting
- fixpoint iteration
- lattice operations over normative states
- quantale multiplication and closure operators

The DSL may expose legal constructs whose compilation relies on that machinery, such as procedures, alternatives, scenarios, and audit queries. It should not require authors to write the algebra directly.

## Design Principle

The DSL should aim to be semantically complete for legal and institutional modeling, without becoming a textual copy of the engine API.

In short:

- if the backend can represent a meaningful legal or institutional concept, the DSL should eventually be able to express it
- if a backend construct is mainly an implementation mechanism, it should stay internal unless it can be surfaced as an ordinary legal concept
