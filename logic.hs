import LegalOntology
import NormativeGenerators
import Logic
import qualified Patrimony as P
import Data.Time.Calendar (fromGregorian)
import qualified Data.Set as S


main :: IO ()
main = do
    -- Test Person types
    let legalPerson = Person Legal "Alice Corp" Exercise "123 Business St"
    let physicalPerson = Person Physical "Bob" Enjoy "456 Home Ave"
    
    -- Test Object types
    let movableThing = Object
              (ThingSubtype Movable)
              "Car"
              (fromGregorian 2025 3 1)
              (fromGregorian 2025 3 10)
              Nothing
    
    let serviceObject = Object
              (ServiceSubtype (Performance Nothing))
              "Delivery Service"
              (fromGregorian 2025 3 1)
              (fromGregorian 2025 3 10)
              Nothing
    
    let omissionService = Object
              (ServiceSubtype (Omission (Just movableThing)))
              "Non-disclosure"
              (fromGregorian 2025 1 1)
              (fromGregorian 2025 12 31)
              (Just (fromGregorian 2025 12 31))
    
    -- Test Act types
    let simpleAct1 = Simple legalPerson serviceObject physicalPerson
    let simpleAct2 = Simple physicalPerson movableThing legalPerson
    let counterAct1 = Counter physicalPerson movableThing legalPerson
    let counterAct2 = Counter legalPerson serviceObject physicalPerson
    
    -- Seq and Par require all acts to have the same type (Active or Passive)
    let seqActActive = Seq [simpleAct1, simpleAct2]
    let seqActPassive = Seq [counterAct1, counterAct2]
    
    let parActActive = Par (S.fromList [simpleAct1, simpleAct2])
    let parActPassive = Par (S.fromList [counterAct1, counterAct2])
    
    -- Test LegalEvent types
    let naturalFact = NaturalFact "Earthquake occurred"
    let humanAct = HumanAct "Contract signed"
    
    -- Test Normative Modalities
    let claim = Claim simpleAct1
    let obligationActive = Obligation simpleAct1  -- Liability requires Active
    let obligationPassive = Obligation counterAct1
    let prohibition = Prohibition simpleAct1
    let privilege = Privilege counterAct1
    
    -- Test Patrimony
    let assetClaim = AssetClaim claim
    let liability = Liability obligationActive  -- Must be Active
    let ownedObject = OwnedObject movableThing
    
    let patrimony = Patrimony (S.fromList [assetClaim, liability, ownedObject])
    
    -- Test NormativeGenerators - Indexed Generator construction (Stage 5 with temporal indexing)
    let baseDate = fromGregorian 2025 1 1
    let laterDate = fromGregorian 2025 6 1
    
    let genAct1 = IndexedGen PrivatePower baseDate (GAct simpleAct1)
    let genAct2 = IndexedGen PrivatePower baseDate (actGen counterAct1)  -- Using lifting helper
    let genClaim1 = IndexedGen PrivatePower baseDate (GClaim claim)
    let genClaim2 = IndexedGen PrivatePower baseDate (claimGen claim)  -- Using lifting helper
    let genOblig1 = IndexedGen PrivatePower baseDate (GObligation obligationActive)
    let genOblig2 = IndexedGen PrivatePower baseDate (obligGen obligationPassive)  -- Using lifting helper
    let genProhib1 = IndexedGen PrivatePower baseDate (GProhibition prohibition)
    let genProhib2 = IndexedGen PrivatePower baseDate (prohibGen prohibition)  -- Using lifting helper
    let genPriv1 = IndexedGen PrivatePower baseDate (GPrivilege privilege)
    let genPriv2 = IndexedGen PrivatePower baseDate (privGen privilege)  -- Using lifting helper
    let genEvent1 = IndexedGen PrivatePower baseDate (GEvent naturalFact)
    let genEvent2 = IndexedGen PrivatePower baseDate (eventGen humanAct)  -- Using lifting helper
    
    -- Test different capability indices and temporal evolution
    let genLegislative = IndexedGen LegislativePower baseDate (GAct simpleAct1)
    let genJudicial = IndexedGen JudicialPower baseDate (GClaim claim)
    let genLater = IndexedGen PrivatePower laterDate (GClaim claim)  -- Same generator, later time
    
    -- Test Norm operations
    let emptyNorm1 = emptyNorm
    let norm1 = insertGen genAct1 emptyNorm1
    let norm2 = insertGen genClaim1 norm1
    let norm3 = insertGen genOblig1 norm2
    let norm4 = insertGen genProhib1 norm3
    let norm5 = insertGen genPriv1 norm4
    let norm6 = insertGen genEvent1 norm5
    
    -- Test memberGen
    let isMember1 = memberGen genAct1 norm6
    let isMember2 = memberGen genEvent2 norm6  -- Should be False
    
    -- Test unionNorm
    let normA = S.fromList [genAct1, genClaim1]
    let normB = S.fromList [genOblig1, genProhib1]
    let normUnion = unionNorm normA normB
    
    -- Test that different types can coexist in same Norm
    let mixedNorm = S.fromList [genAct1, genClaim1, genOblig1, genProhib1, genPriv1, genEvent1]
    
    -- Print test results
    putStrLn "=== Testing Person types ==="
    print legalPerson
    print physicalPerson
    putStrLn ""
    
    putStrLn "=== Testing Object types ==="
    print movableThing
    print serviceObject
    print omissionService
    putStrLn ""
    
    putStrLn "=== Testing Act types ==="
    print simpleAct1
    print counterAct1
    print seqActActive
    print seqActPassive
    print parActActive
    print parActPassive
    putStrLn ""
    
    putStrLn "=== Testing LegalEvent types ==="
    print naturalFact
    print humanAct
    putStrLn ""
    
    putStrLn "=== Testing Normative Modalities ==="
    print claim
    print obligationActive
    print obligationPassive
    print prohibition
    print privilege
    putStrLn ""
    
    putStrLn "=== Testing Patrimony ==="
    print patrimony
    putStrLn ""
    
    putStrLn "=== Testing equality ==="
    print (legalPerson == legalPerson)
    print (simpleAct1 == simpleAct1)
    print (counterAct1 == counterAct1)
    print (claim == claim)
    putStrLn ""
    
    putStrLn "=== Testing NormativeGenerators - Indexed Generator construction (Stage 5) ==="
    print genAct1
    print genAct2
    print genClaim1
    print genClaim2
    print genOblig1
    print genOblig2
    print genProhib1
    print genProhib2
    print genPriv1
    print genPriv2
    print genEvent1
    print genEvent2
    putStrLn "Different capability indices:"
    print genLegislative
    print genJudicial
    putStrLn "Temporal evolution (same generator, different time):"
    print genClaim1
    print genLater
    putStrLn ""
    
    putStrLn "=== Testing NormativeGenerators - Norm operations ==="
    putStrLn "Empty norm:"
    print emptyNorm1
    putStrLn "Norm after inserting generators:"
    print norm6
    putStrLn "Is genAct1 in norm6?"
    print isMember1
    putStrLn "Is genEvent2 in norm6?"
    print isMember2
    putStrLn "Union of normA and normB:"
    print normUnion
    putStrLn "Mixed norm with all generator types:"
    print mixedNorm
    putStrLn ""
    
    putStrLn "=== Testing Indexed Generator equality ==="
    print (genAct1 == genAct1)
    print (genClaim1 == genClaim2)  -- Should be True (same claim, same index)
    print (genAct1 == genAct2)  -- Should be False (different acts)
    -- Test that same generator with different indices are different
    let genClaimPrivate = IndexedGen PrivatePower baseDate (GClaim claim)
    let genClaimLegislative = IndexedGen LegislativePower baseDate (GClaim claim)
    print (genClaimPrivate == genClaimLegislative)  -- Should be False (different indices)
    putStrLn ""
    
    putStrLn "=== Testing Logic - Inference Engine (Stage 5 with Hierarchy & Time) ==="
    -- Create an indexed norm with a claim over a movable thing
    let testDate = fromGregorian 2025 3 1
    let thingClaim = IndexedGen PrivatePower testDate (GClaim (Claim (Simple legalPerson movableThing physicalPerson)))
    let initialNorm = S.fromList [thingClaim]
    putStrLn "Initial norm (claim over thing, PrivatePower index):"
    print initialNorm
    putStrLn ""
    
    -- Test applying a single rule (works on indexed Norm)
    let afterRule = objectClaimToDelivery initialNorm
    putStrLn "After applying objectClaimToDelivery rule:"
    print afterRule
    putStrLn ""
    
    -- Create SystemState for Stage 5 solver (with capability in patrimony)
    let initialState = SystemState
          { normState = initialNorm
          , patrState = S.fromList [P.Capability "legislative_power", P.Capability "private_power"]
          }
    putStrLn "Initial system state:"
    putStrLn "  Normative state (indexed):"
    print (normState initialState)
    putStrLn "  Patrimony state (with capabilities):"
    print (patrState initialState)
    putStrLn ""
    
    -- Run the inference system (fixpoint over SystemState with indexed norms)
    let derivedState = runExample initialState
    putStrLn "System state after running inference system (fixpoint):"
    putStrLn "  Derived normative state:"
    print (normState derivedState)
    putStrLn "  Derived patrimony state:"
    print (patrState derivedState)
    putStrLn ""
    
    -- Test that fixpoint is idempotent
    let fixpointState2 = runExample derivedState
    putStrLn "Running fixpoint again (should be unchanged):"
    putStrLn "  Normative state:"
    print (normState fixpointState2)
    putStrLn "  Patrimony state:"
    print (patrState fixpointState2)
    putStrLn (if fixpointState2 == derivedState then "✓ Fixpoint is idempotent" else "✗ Fixpoint issue")
    putStrLn ""
    
    -- Test Stage 5: Authority rules with legislative capability
    putStrLn "=== Testing Stage 5 - Authority Rules & Hierarchy ==="
    let authorityDate = fromGregorian 2025 4 1
    let legislativeAct = IndexedGen LegislativePower authorityDate (GAct (Simple legalPerson serviceObject physicalPerson))
    let legislativeNorm = S.fromList [legislativeAct]
    let authorityState = SystemState
          { normState = legislativeNorm
          , patrState = S.fromList [P.Capability "legislative_power"]
          }
    putStrLn "Initial state with legislative act:"
    putStrLn "  Normative state:"
    print (normState authorityState)
    putStrLn "  Patrimony state:"
    print (patrState authorityState)
    putStrLn ""
    
    let authorityDerived = runExample authorityState
    putStrLn "After running inference (should create statute and private obligation):"
    putStrLn "  Normative state:"
    print (normState authorityDerived)
    putStrLn "  Patrimony state:"
    print (patrState authorityDerived)
    putStrLn ""
    
    -- Test temporal filtering
    putStrLn "=== Testing Temporal Filtering ==="
    let earlyDate = fromGregorian 2025 1 1
    let midDate = fromGregorian 2025 6 1
    let lateDate = fromGregorian 2025 12 31
    
    let earlyGen = IndexedGen PrivatePower earlyDate (GClaim claim)
    let midGen = IndexedGen PrivatePower midDate (GObligation obligationActive)
    let lateGen = IndexedGen PrivatePower lateDate (GProhibition prohibition)
    let temporalNorm = S.fromList [earlyGen, midGen, lateGen]
    
    putStrLn "Temporal norm with generators at different times:"
    print temporalNorm
    putStrLn ""
    putStrLn "Norms valid at 2025-03-01 (should include early only):"
    print (normAt (fromGregorian 2025 3 1) temporalNorm)
    putStrLn "Norms valid at 2025-08-01 (should include early and mid):"
    print (normAt (fromGregorian 2025 8 1) temporalNorm)
    putStrLn "Norms valid at 2025-12-31 (should include all):"
    print (normAt lateDate temporalNorm)
    putStrLn ""
    
    -- Test override rule
    putStrLn "=== Testing Authority Hierarchy & Override ==="
    let privateProhib = IndexedGen PrivatePower baseDate (GProhibition prohibition)
    let legislativePriv = IndexedGen LegislativePower baseDate (GPrivilege privilege)
    let overrideNorm = S.fromList [privateProhib, legislativePriv]
    let overrideState = SystemState
          { normState = overrideNorm
          , patrState = P.emptyPatrimony
          }
    putStrLn "Initial state with conflicting norms (private prohibition vs legislative privilege):"
    print (normState overrideState)
    putStrLn ""
    
    let overrideDerived = runExample overrideState
    putStrLn "After override rule (legislative should override private):"
    print (normState overrideDerived)
    putStrLn "  (Look for Overridden(...) generators)"
