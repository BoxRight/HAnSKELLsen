# DSL Grammar

This first DSL slice uses a controlled legal language with a narrow, deterministic grammar.

## File Shape

```text
law <LawName>
authority <private|legislative|judicial|administrative|constitutional>
enacted <YYYY-MM-DD>

vocabulary
    verb <surface>: <canonical>
    object <surface>: <canonical>

parties
    <Alias>: <DisplayName>

objects
    <Alias>: <movable|nonmovable|expendable|money|service>

article <Number> [Optional Heading]
    obligation <Party> must <verb> <Object> to <Party>.
    claim <Party> may demand <verb> of <Object> from <Party>.
    prohibition <Party> must not <verb> <Object> to <Party>.
    procedure <Name>:
        <Party> <verb>s <Object> to <Party>.
        or
        <Party> <verb>s <Object> to <Party>.
    rule <Name>
        If <Party> owns <Object>
        then <Party> may demand <verb> of <Object> from <Party>.
```

## Notes

- Indentation is significant.
- Use four spaces for section contents.
- Use eight spaces for `procedure` and `rule` bodies.
- Symbolic algebra is intentionally hidden from the legal surface language.
- The current compiler slice resolves parties, objects, and verbs strictly.
