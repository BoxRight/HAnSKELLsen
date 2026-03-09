law InsuranceFinancingCase
authority private
enacted 2025-01-01

import "../contracts/simple_loan.dsl"
import "../contracts/generic_indemnity.dsl"

scenario LoanAndInsurance:
    at 2025-01-15
        act Lender lends CreditFacility to Borrower.
    at 2025-02-01
        act Borrower pays InsurancePremium to Insurer.
    at 2025-06-01
        act Borrower repays LoanRepayment to Lender.
