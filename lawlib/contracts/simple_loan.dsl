law SimpleLoanAgreement
authority private
enacted 2025-01-01

import "../shared/commercial_shared.dsl"

article 1 Loan Terms
    obligation Lender must lend CreditFacility to Borrower.
    obligation Borrower must repay LoanRepayment to Lender.
    claim Lender may demand repay of LoanRepayment from Borrower.
