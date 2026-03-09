law GenericTaxStatute
authority legislative
enacted 2025-01-01

import "../shared/commercial_shared.dsl"
import "../shared/base_sale_shared.dsl"

article 1 Tax Obligation
    fact authority legislative is present.
    obligation Borrower must pay TaxAmount to TaxAuthority.
    claim TaxAuthority may demand pay of TaxAmount from Borrower.
