law RenewableEnergyLeasingStatute
authority legislative
enacted 2025-01-01

import "../shared/renewable_project_shared.dsl"

article 1 Core Public Framework
    fact authority legislative is present.
    obligation Farmer must grant SolarLeaseUse to Developer.
    obligation Developer must preserve AgriculturalCapacity to Farmer.
    obligation Developer must pay MunicipalShare to Municipality.
    claim Municipality may demand pay of MunicipalShare from Developer.

article 2 Public Permissions
    privilege Agency may grant EnvironmentalWaiver to Developer.
    rule OperatingRightAfterLease
        If Farmer grants SolarLeaseUse to Developer
        then Developer may use SolarLeaseUse to Farmer.
    rule InstallationAfterWaiver
        If Agency grants EnvironmentalWaiver to Developer
        then Developer may install SolarInstallation to Farmer.
