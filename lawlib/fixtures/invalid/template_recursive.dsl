law RecursiveTemplateExample
authority private
enacted 2025-01-01

template Loop(PartyAlias):
    instantiate Loop(PartyAlias=PartyAlias)

instantiate Loop(PartyAlias=Alice)
