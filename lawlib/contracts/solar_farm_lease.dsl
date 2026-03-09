law SolarFarmLease
authority private
enacted 2025-01-15

import "../statutes/renewable_energy_leasing.dsl"

article 9 Lease Refinement
    obligation Developer must pay LeaseRent to Farmer.
    obligation Developer must share ProjectRevenueShare to Farmer.
    privilege Developer may install SolarInstallation to Farmer.

article 10 Termination Path
    rule FarmerTerminationAfterNonPayment
        If Developer fails to pay LeaseRent to Farmer
        then Farmer may terminate LeaseTermination to Developer.
