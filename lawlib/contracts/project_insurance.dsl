law ProjectInsurance
authority private
enacted 2025-01-18

import "../shared/renewable_project_shared.dsl"

article 1 Insurance Duties
    obligation Developer must pay InsurancePremium to Insurer.

article 2 Claim And Repair Path
    rule PayoutClaimAfterStormDamage
        If liability StormDamage is present
        then Developer may demand pay of InsurancePayout from Insurer.
    rule PayoutDutyAfterClaimFiling
        If asset InsuranceClaimFiled is present
        then Insurer must pay InsurancePayout to Developer.
    rule RepairPermissionAfterApprovedContractor
        If asset ApprovedContractorEngaged is present
        then Developer may repair RepairService to Farmer.
