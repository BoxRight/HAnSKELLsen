law IntrinsicTests
authority private
enacted 2025-01-01

parties
    Developer: SolarGrowthLtd, legal person, exercise capacity
    Authority: RevenueOffice, legal person, exercise capacity

objects
    Benefit: money, due 2025-12-31
    ProductionRecord: expendable

vocabulary
    verb grant: grant
    verb produce: produce

facts
    production: numeric
    filingDate: date

article 1 Intrinsic Rules
    fact authority private is present.
    rule TaxEligibility
        If aboveThreshold production 10000
        then Developer may demand grant of Benefit from Authority.
    rule FilingValid
        If withinWindow filingDate 2025-03-01 2025-04-15
        then Authority must grant Benefit to Developer.
    rule MixedCondition
        If aboveThreshold production 10000 and asset InsuranceClaimFiled is present
        then Authority must grant Benefit to Developer.

scenario NumericThresholdPass:
    at 2025-06-01
        assert numeric production 12000

scenario FilingWindowValid:
    at 2025-04-01
        assert date filingDate 2025-04-01

scenario FilingWindowInvalid:
    at 2025-05-01
        assert date filingDate 2025-05-01

scenario MixedConditionPass:
    at 2025-06-01
        assert numeric production 12000
    at 2025-06-02
        assert asset InsuranceClaimFiled is present
