law ProjectFinancing
authority private
enacted 2025-01-20

import "../shared/renewable_project_shared.dsl"

article 1 Financing Duties
    obligation Developer must pay LoanRepayment to Bank.
    claim Bank may demand pay of LoanRepayment from Developer.
    privilege Bank may assume StepInService to Developer.

article 2 StepIn Consequences
    rule StepInRightAfterLoanDefault
        If Developer fails to pay LoanRepayment to Bank
        then Bank may assume StepInService to Developer.
    rule RentDutyTransfersAfterStepIn
        If Bank assumes StepInService to Developer
        then Bank must pay LeaseRent to Farmer.
    rule StepInBlocksTermination
        If Bank assumes StepInService to Developer
        then Farmer must refrain from terminate LeaseTermination to Developer.
