law RenewableEnergyCase
authority private
enacted 2025-01-01

import "../statutes/renewable_energy_leasing.dsl"
import "../statutes/biodiversity_regulation.dsl"
import "../statutes/renewable_tax_credit.dsl"
import "../contracts/solar_farm_lease.dsl"
import "../contracts/project_financing.dsl"
import "../contracts/project_insurance.dsl"

scenario ProjectDisruptionAndStepIn:
    at 2025-01-10
        act Farmer grants SolarLeaseUse to Developer.
    at 2025-01-12
        act Agency grants EnvironmentalWaiver to Developer.
    at 2025-02-01
        act Developer installs SolarInstallation to Farmer.
    at 2025-02-15
        act Developer pays LeaseRent to Farmer.
    at 2025-03-01
        act Developer shares ProjectRevenueShare to Farmer.
        act Developer pays MunicipalShare to Municipality.
    at 2025-03-05
        act Developer pays LoanRepayment to Bank.
    at 2025-03-10
        act Developer pays InsurancePremium to Insurer.
    at 2025-06-01
        assert numeric production 12000.
    at 2025-06-10
        assert liability StormDamage is present.
        natural event SevereStorm damaged the solar installation.
    at 2025-06-20
        assert asset InsuranceClaimFiled is present.
    at 2025-06-25
        counteract Developer fails to pay LeaseRent to Farmer.
        counteract Developer fails to pay LoanRepayment to Bank.
        event Electricity output temporarily fell below the expected threshold.
    at 2025-06-26
        act Bank assumes StepInService to Developer.
    at 2025-06-28
        assert approved contractor ApprovedContractorEngaged is present.
    at 2025-07-05
        act Developer repairs RepairService to Farmer.
    at 2025-07-15
        act Developer provides BiodiversityOffset to Municipality.
        assert date filingDate 2025-07-15.
    at 2025-07-20
        act Agency approves BiodiversityCertification to Developer.
