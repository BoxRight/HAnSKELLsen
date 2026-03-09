# DSL Grammar

This DSL slice uses a controlled legal language with deterministic parsing and a lawyer-facing surface.

## File Shape

```text
law <LawName>
authority <private|legislative|judicial|administrative|constitutional>
enacted <YYYY-MM-DD>

vocabulary
    verb <surface>: <canonical>
    object <surface>: <canonical>

parties
    <Alias>: <DisplayName>[, natural person|legal person][, enjoy capacity|exercise capacity][, address <Text>]

objects
    <Alias>: <movable|nonmovable|expendable|money|service>[, performance|omission][, of <Object>][, start <YYYY-MM-DD>][, due <YYYY-MM-DD>][, end <YYYY-MM-DD>]

article <Number> [Optional Heading]
    fact <Party> owns <Object>.
    fact authority <private|legislative|judicial|administrative|constitutional> is present.
    fact asset <Name> is present.
    fact liability <Name> is present.
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

scenario <Name>:
    at <YYYY-MM-DD>
        act <Party> <verb>s <Object> to <Party>.
        counteract <Party> fails to <verb> <Object> to <Party>.
        assert <Party> owns <Object>.
        assert authority <private|legislative|judicial|administrative|constitutional> is present.
        event <Text>
        natural event <Text>
```

## Notes

- Indentation is significant.
- Use four spaces for section contents.
- Use eight spaces for `procedure` and `rule` bodies.
- Use eight spaces for scenario assertions inside an `at` block.
- Symbolic algebra is intentionally hidden from the legal surface language.
- The current compiler slice resolves parties, objects, and verbs strictly.

## Controlled Forms

Accepted legal-style action forms include:

- `<Party> must <verb> <Object> to <Party>.`
- `<Party> must not <verb> <Object> to <Party>.`
- `<Party> may <verb> <Object> to <Party>.`
- `<Party> must refrain from <verb> <Object> to <Party>.`
- `<Party> may refrain from <verb> <Object> to <Party>.`
- `<Party> fails to <verb> <Object> to <Party>.`

Institutional fact forms include:

- `<Party> owns <Object>.`
- `authority legislative is present.`
- `asset RentLedger is present.`
- `liability RentArrears is present.`

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
