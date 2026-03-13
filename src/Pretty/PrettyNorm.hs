{-# LANGUAGE GADTs #-}

module Pretty.PrettyNorm
  ( prettyAct
  , prettyClaim
  , prettyGenerator
  , prettyIndexedGen
  , prettyIndexedGenWithDisplay
  , prettyModalityHeading
  ) where

import Capability (prettyCapability)
import Compiler.Compiler (DisplayVerbMap(..))
import Data.Char (toLower)
import Data.Maybe (fromMaybe)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import LegalOntology
import NormativeGenerators

prettyIndexedGen :: IndexedGen -> String
prettyIndexedGen indexed =
  prettyGenerator (gen indexed)

prettyIndexedGenWithDisplay :: DisplayVerbMap -> IndexedGen -> String
prettyIndexedGenWithDisplay displayMap indexed =
  prettyGeneratorWithDisplay displayMap (gen indexed)
    ++ " ["
    ++ prettyCapability (capIndex indexed)
    ++ ", "
    ++ show (time indexed)
    ++ "]"

prettyGenerator :: Generator -> String
prettyGenerator generator =
  prettyGeneratorWithDisplay (DisplayVerbMap M.empty) generator

prettyGeneratorWithDisplay :: DisplayVerbMap -> Generator -> String
prettyGeneratorWithDisplay displayMap generator =
  case generator of
    GAct act ->
      prettyActWithDisplay displayMap act ++ "."
    GClaim claim ->
      prettyClaimWithDisplay displayMap claim ++ "."
    GObligation (Obligation act) ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyObligationWithDisplay displayMap act
        ++ "."
    GProhibition (Prohibition act) ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyProhibitionWithDisplay displayMap act
        ++ "."
    GPrivilege (Privilege act) ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyPrivilegeWithDisplay displayMap act
        ++ "."
    GEvent event ->
      prettyEvent event ++ "."
    GFulfillment act ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyFulfillmentWithDisplay displayMap act
        ++ "."
    GViolation act ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyViolationWithDisplay displayMap act
        ++ "."
    GEnforceable act ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyEnforceableWithDisplay displayMap act
        ++ "."
    GStatute act ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyStatuteWithDisplay displayMap act
        ++ "."
    Overridden inner ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ "Overridden norm: "
        ++ stripTrailingPeriod (prettyGeneratorWithDisplay displayMap inner)
        ++ "."

prettyModalityHeading :: Generator -> String
prettyModalityHeading generator =
  case generator of
    GClaim _ -> "Derived claim"
    GObligation _ -> "Derived obligation"
    GProhibition _ -> "Derived prohibition"
    GPrivilege _ -> "Derived privilege"
    GFulfillment _ -> "Derived fulfillment"
    GViolation _ -> "Derived violation"
    GEnforceable _ -> "Derived enforceability"
    GStatute _ -> "Derived statute"
    Overridden _ -> "Overridden norm"
    GAct _ -> "Act"
    GEvent _ -> "Event"

prettyAct :: Act r -> String
prettyAct act =
  prettyActWithDisplay (DisplayVerbMap M.empty) act

prettyActWithDisplay :: DisplayVerbMap -> Act r -> String
prettyActWithDisplay displayMap act =
  case act of
    Id -> "The identity act applies"
    Simple actor obj target ->
      prettyPerson actor ++ " " ++ actionPredicateWithDisplay displayMap obj ++ targetSuffix target
    Counter actor obj target ->
      prettyPerson actor ++ " fails to " ++ counterActPredicateWithDisplay displayMap obj ++ targetSuffix target
    Seq acts ->
      joinWith " then " (map (prettyActWithDisplay displayMap) acts)
    Par acts ->
      joinWith " in parallel with " (map (prettyActWithDisplay displayMap) (S.toList acts))

actionPredicateWithDisplay :: DisplayVerbMap -> Object -> String
actionPredicateWithDisplay (DisplayVerbMap m) obj =
  let base = baseVerbForObject obj
      surface = M.lookup (oName obj, base) m
  in fromMaybe (actionPredicate obj) (fmap (\v -> v ++ " " ++ objectReference obj) surface)

-- | Canonical form for counter-act: "fails to verb Object". Normalizes both
-- "does not" and "fails to" to consistent output.
counterActPredicateWithDisplay :: DisplayVerbMap -> Object -> String
counterActPredicateWithDisplay (DisplayVerbMap m) obj =
  let base = baseVerbForObject obj
      surface = M.lookup (oName obj, base) m
  in fromMaybe (baseVerbForObject obj ++ " " ++ objectReference obj)
        (fmap (\v -> v ++ " " ++ objectReference obj) surface)

baseVerbForObject :: Object -> String
baseVerbForObject obj =
  case oSubtype obj of
    ThingSubtype Expendable -> "transfer"
    ThingSubtype _ -> "deliver"
    ServiceSubtype (Performance (Just _)) -> "deliver"
    ServiceSubtype (Performance Nothing) -> "perform"
    ServiceSubtype (Omission (Just _)) -> "refrain from interfering with"
    ServiceSubtype (Omission Nothing) -> "refrain from"

prettyClaim :: Claim r -> String
prettyClaim claim =
  prettyClaimWithDisplay (DisplayVerbMap M.empty) claim

prettyClaimWithDisplay :: DisplayVerbMap -> Claim r -> String
prettyClaimWithDisplay displayMap (Claim act) =
  case act of
    Simple actor obj target ->
      "Derived claim\n\n"
        ++ prettyPerson target
        ++ " may demand "
        ++ demandPhraseWithDisplay displayMap obj
        ++ " from "
        ++ prettyPerson actor
    Counter actor obj target ->
      "Derived claim\n\n"
        ++ prettyPerson target
        ++ " may demand counter-performance regarding "
        ++ objectReference obj
        ++ " from "
        ++ prettyPerson actor
    _ ->
      "Derived claim\n\n"
        ++ stripTrailingPeriod (prettyActWithDisplay displayMap act)

prettyObligation :: Act r -> String
prettyObligation act =
  prettyObligationWithDisplay (DisplayVerbMap M.empty) act

prettyObligationWithDisplay :: DisplayVerbMap -> Act r -> String
prettyObligationWithDisplay displayMap act =
  case act of
    Simple actor obj target ->
      prettyPerson actor ++ " must " ++ actionPredicateWithDisplay displayMap obj ++ targetSuffix target
    Counter actor obj target ->
      prettyPerson actor ++ " must refrain from the counter-act for " ++ objectReference obj ++ " against " ++ prettyPerson target
    _ ->
      stripTrailingPeriod (prettyActWithDisplay displayMap act)

prettyProhibition :: Act r -> String
prettyProhibition act =
  prettyProhibitionWithDisplay (DisplayVerbMap M.empty) act

prettyProhibitionWithDisplay :: DisplayVerbMap -> Act r -> String
prettyProhibitionWithDisplay displayMap act =
  case act of
    Simple actor obj target ->
      prettyPerson actor ++ " must not " ++ basePredicateWithDisplay displayMap obj ++ targetSuffix target
    Counter actor obj target ->
      prettyPerson actor ++ " must not perform the counter-act for " ++ objectReference obj ++ " against " ++ prettyPerson target
    _ ->
      "A prohibited act exists: " ++ stripTrailingPeriod (prettyActWithDisplay displayMap act)

basePredicateWithDisplay :: DisplayVerbMap -> Object -> String
basePredicateWithDisplay (DisplayVerbMap m) obj =
  let base = baseVerbForObject obj
      surface = M.lookup (oName obj, base) m
  in fromMaybe (basePredicate obj) (fmap (\v -> v ++ " " ++ objectReference obj) surface)

prettyPrivilege :: Act r -> String
prettyPrivilege act =
  prettyPrivilegeWithDisplay (DisplayVerbMap M.empty) act

prettyPrivilegeWithDisplay :: DisplayVerbMap -> Act r -> String
prettyPrivilegeWithDisplay displayMap act =
  case act of
    Simple actor obj target ->
      prettyPerson actor ++ " may " ++ basePredicateWithDisplay displayMap obj ++ targetSuffix target
    Counter actor obj target ->
      prettyPerson actor ++ " may perform the counter-act for " ++ objectReference obj ++ " against " ++ prettyPerson target
    _ ->
      "A privilege exists: " ++ stripTrailingPeriod (prettyActWithDisplay displayMap act)

prettyFulfillment :: Act Active -> String
prettyFulfillment act =
  prettyFulfillmentWithDisplay (DisplayVerbMap M.empty) act

prettyFulfillmentWithDisplay :: DisplayVerbMap -> Act Active -> String
prettyFulfillmentWithDisplay displayMap act =
  "The following act was fulfilled: " ++ stripTrailingPeriod (prettyActWithDisplay displayMap act)

prettyViolation :: Act Passive -> String
prettyViolation act =
  prettyViolationWithDisplay (DisplayVerbMap M.empty) act

prettyViolationWithDisplay :: DisplayVerbMap -> Act Passive -> String
prettyViolationWithDisplay displayMap act =
  "The following counter-act occurred, creating a violation: " ++ stripTrailingPeriod (prettyActWithDisplay displayMap act)

prettyEnforceable :: Act Active -> String
prettyEnforceable act =
  prettyEnforceableWithDisplay (DisplayVerbMap M.empty) act

prettyEnforceableWithDisplay :: DisplayVerbMap -> Act Active -> String
prettyEnforceableWithDisplay displayMap act =
  "The following claim became enforceable: " ++ stripTrailingPeriod (prettyActWithDisplay displayMap act)

prettyStatute :: Act Active -> String
prettyStatute act =
  prettyStatuteWithDisplay (DisplayVerbMap M.empty) act

prettyStatuteWithDisplay :: DisplayVerbMap -> Act Active -> String
prettyStatuteWithDisplay displayMap act =
  "A legislative act was recognized as a statute: " ++ stripTrailingPeriod (prettyActWithDisplay displayMap act)

prettyEvent :: LegalEvent -> String
prettyEvent event =
  case event of
    NaturalFact description -> "Natural fact: " ++ stripTrailingPeriod description
    HumanAct description -> "Human act: " ++ stripTrailingPeriod description

prettyPerson :: Person -> String
prettyPerson = pName

targetSuffix :: Person -> String
targetSuffix person = " to " ++ prettyPerson person

actionPredicate :: Object -> String
actionPredicate obj =
  case oSubtype obj of
    ThingSubtype Expendable -> "transfer " ++ objectReference obj
    ThingSubtype _ -> "deliver " ++ objectReference obj
    ServiceSubtype (Performance (Just inner)) -> "deliver " ++ objectReference inner
    ServiceSubtype (Performance Nothing) -> "perform " ++ objectReference obj
    ServiceSubtype (Omission (Just inner)) -> "refrain from interfering with " ++ objectReference inner
    ServiceSubtype (Omission Nothing) -> "refrain from " ++ objectReference obj

basePredicate :: Object -> String
basePredicate obj =
  case oSubtype obj of
    ThingSubtype Expendable -> "transfer " ++ objectReference obj
    ThingSubtype _ -> "deliver " ++ objectReference obj
    ServiceSubtype (Performance (Just inner)) -> "deliver " ++ objectReference inner
    ServiceSubtype (Performance Nothing) -> "perform " ++ objectReference obj
    ServiceSubtype (Omission (Just inner)) -> "interfere with " ++ objectReference inner
    ServiceSubtype (Omission Nothing) -> "perform " ++ objectReference obj

demandPhraseWithDisplay :: DisplayVerbMap -> Object -> String
demandPhraseWithDisplay (DisplayVerbMap m) obj =
  let base = baseVerbForObject obj
      surface = M.lookup (oName obj, base) m
  in case surface of
    Just v -> v ++ " of " ++ objectReference obj
    Nothing -> demandPhrase obj

demandPhrase :: Object -> String
demandPhrase obj =
  case oSubtype obj of
    ThingSubtype Expendable -> "payment of " ++ objectReference obj
    ThingSubtype _ -> "delivery of " ++ objectReference obj
    ServiceSubtype (Performance (Just inner)) -> "delivery of " ++ objectReference inner
    ServiceSubtype (Performance Nothing) -> "performance of " ++ objectReference obj
    ServiceSubtype (Omission (Just inner)) -> "non-interference with " ++ objectReference inner
    ServiceSubtype (Omission Nothing) -> "forbearance regarding " ++ objectReference obj

objectReference :: Object -> String
objectReference obj =
  "the " ++ lowercaseHead (oName obj)

lowercaseHead :: String -> String
lowercaseHead [] = []
lowercaseHead (x : xs) = toLower x : xs

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [x] = x
joinWith separator (x : xs) = x ++ separator ++ joinWith separator xs

stripTrailingPeriod :: String -> String
stripTrailingPeriod [] = []
stripTrailingPeriod text
  | last text == '.' = init text
  | otherwise = text
