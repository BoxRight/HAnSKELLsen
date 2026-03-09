law BiodiversityRegulation
authority administrative
enacted 2025-03-01

import "../shared/renewable_project_shared.dsl"

article 1 Biodiversity Duties
    fact authority administrative is present.
    rule OffsetDutyAfterOperation
        If Developer uses SolarLeaseUse to Farmer
        then Developer must provide BiodiversityOffset to Municipality.

article 2 Certification Path
    rule CertificationAfterOffset
        If Developer provides BiodiversityOffset to Municipality
        then Agency may approve BiodiversityCertification to Developer.
