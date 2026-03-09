{-# LANGUAGE GADTs #-}

module Pretty.PrettyNorm
  ( prettyAct
  , prettyClaim
  , prettyGenerator
  , prettyIndexedGen
  , prettyModalityHeading
  ) where

import Capability (prettyCapability)
import Data.Char (toLower)
import qualified Data.Set as S
import LegalOntology
import NormativeGenerators

prettyIndexedGen :: IndexedGen -> String
prettyIndexedGen indexed =
  prettyGenerator (gen indexed)
    ++ " ["
    ++ prettyCapability (capIndex indexed)
    ++ ", "
    ++ show (time indexed)
    ++ "]"

prettyGenerator :: Generator -> String
prettyGenerator generator =
  case generator of
    GAct act ->
      prettyAct act ++ "."
    GClaim claim ->
      prettyClaim claim ++ "."
    GObligation (Obligation act) ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyObligation act
        ++ "."
    GProhibition (Prohibition act) ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyProhibition act
        ++ "."
    GPrivilege (Privilege act) ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyPrivilege act
        ++ "."
    GEvent event ->
      prettyEvent event ++ "."
    GFulfillment act ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyFulfillment act
        ++ "."
    GViolation act ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyViolation act
        ++ "."
    GEnforceable act ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyEnforceable act
        ++ "."
    GStatute act ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ prettyStatute act
        ++ "."
    Overridden inner ->
      prettyModalityHeading generator
        ++ "\n\n"
        ++ "Overridden norm: "
        ++ stripTrailingPeriod (prettyGenerator inner)
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
  case act of
    Id -> "The identity act applies"
    Simple actor obj target ->
      prettyPerson actor ++ " " ++ actionPredicate obj ++ targetSuffix target
    Counter actor obj target ->
      prettyPerson actor ++ " performs the counter-act for " ++ objectReference obj ++ " against " ++ prettyPerson target
    Seq acts ->
      joinWith " then " (map prettyAct acts)
    Par acts ->
      joinWith " in parallel with " (map prettyAct (S.toList acts))

prettyClaim :: Claim r -> String
prettyClaim (Claim act) =
  case act of
    Simple actor obj target ->
      "Derived claim\n\n"
        ++ prettyPerson target
        ++ " may demand "
        ++ demandPhrase obj
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
        ++ stripTrailingPeriod (prettyAct act)

prettyObligation :: Act r -> String
prettyObligation act =
  case act of
    Simple actor obj target ->
      prettyPerson actor ++ " must " ++ actionPredicate obj ++ targetSuffix target
    Counter actor obj target ->
      prettyPerson actor ++ " must refrain from the counter-act for " ++ objectReference obj ++ " against " ++ prettyPerson target
    _ ->
      stripTrailingPeriod (prettyAct act)

prettyProhibition :: Act r -> String
prettyProhibition act =
  case act of
    Simple actor obj target ->
      prettyPerson actor ++ " must not " ++ basePredicate obj ++ targetSuffix target
    Counter actor obj target ->
      prettyPerson actor ++ " must not perform the counter-act for " ++ objectReference obj ++ " against " ++ prettyPerson target
    _ ->
      "A prohibited act exists: " ++ stripTrailingPeriod (prettyAct act)

prettyPrivilege :: Act r -> String
prettyPrivilege act =
  case act of
    Simple actor obj target ->
      prettyPerson actor ++ " may " ++ basePredicate obj ++ targetSuffix target
    Counter actor obj target ->
      prettyPerson actor ++ " may perform the counter-act for " ++ objectReference obj ++ " against " ++ prettyPerson target
    _ ->
      "A privilege exists: " ++ stripTrailingPeriod (prettyAct act)

prettyFulfillment :: Act Active -> String
prettyFulfillment act =
  "The following act was fulfilled: " ++ stripTrailingPeriod (prettyAct act)

prettyViolation :: Act Passive -> String
prettyViolation act =
  "The following counter-act occurred, creating a violation: " ++ stripTrailingPeriod (prettyAct act)

prettyEnforceable :: Act Active -> String
prettyEnforceable act =
  "The following claim became enforceable: " ++ stripTrailingPeriod (prettyAct act)

prettyStatute :: Act Active -> String
prettyStatute act =
  "A legislative act was recognized as a statute: " ++ stripTrailingPeriod (prettyAct act)

prettyEvent :: LegalEvent -> String
prettyEvent event =
  case event of
    NaturalFact description -> "Natural fact: " ++ description
    HumanAct description -> "Human act: " ++ description

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
