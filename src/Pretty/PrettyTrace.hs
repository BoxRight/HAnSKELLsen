module Pretty.PrettyTrace
  ( explainIndexedGen
  ) where

import NormativeGenerators

explainIndexedGen :: IndexedGen -> String
explainIndexedGen indexed =
  case gen indexed of
    GClaim _ ->
      "This claim was present in the source law or produced by a claim-producing rule."
    GObligation _ ->
      "This obligation was present in the source law or produced by an obligation-producing rule."
    GProhibition _ ->
      "This prohibition was present in the source law or produced by a prohibition-producing rule."
    GPrivilege _ ->
      "This privilege was present in the source law or produced by a privilege-producing rule."
    GFulfillment _ ->
      "A claimed act also appears in the state, so the engine marked it as fulfilled."
    GViolation _ ->
      "A counter-act occurred against an active obligation, so the engine marked a violation."
    GEnforceable _ ->
      "The opposite act occurred against a claim, so the engine marked the claim as enforceable."
    GStatute _ ->
      "A legislative act was lifted into a statute by the authority rules."
    Overridden _ ->
      "A higher-authority conflicting norm with suitable timing caused this norm to be overridden."
    GAct _ ->
      "This act is part of the current normative state."
    GEvent _ ->
      "This event was carried into the normative state from source facts or patrimony."
