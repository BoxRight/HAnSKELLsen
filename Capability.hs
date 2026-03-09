module Capability where

import NormativeGenerators (CapabilityIndex(..))
import Data.Char (isAlphaNum, toLower)

capabilitySupremum :: CapabilityIndex -> CapabilityIndex -> CapabilityIndex
capabilitySupremum a b
  | capabilityRank a >= capabilityRank b = a
  | otherwise = b

capabilityDominates :: CapabilityIndex -> CapabilityIndex -> Bool
capabilityDominates a b =
  capabilityRank a >= capabilityRank b

parseCapability :: String -> Either String CapabilityIndex
parseCapability raw =
  case normalizeCapabilityToken raw of
    "baseauthority" -> Right BaseAuthority
    "private" -> Right PrivatePower
    "privatepower" -> Right PrivatePower
    "legislative" -> Right LegislativePower
    "legislativepower" -> Right LegislativePower
    "judicial" -> Right JudicialPower
    "judicialpower" -> Right JudicialPower
    "administrative" -> Right AdministrativePower
    "administrativepower" -> Right AdministrativePower
    "constitutional" -> Right ConstitutionalPower
    "constitutionalpower" -> Right ConstitutionalPower
    _ -> Left ("unknown capability `" ++ raw ++ "`")

prettyCapability :: CapabilityIndex -> String
prettyCapability capability =
  case capability of
    BaseAuthority -> "base authority"
    PrivatePower -> "private power"
    LegislativePower -> "legislative power"
    JudicialPower -> "judicial power"
    AdministrativePower -> "administrative power"
    ConstitutionalPower -> "constitutional power"

capabilityRank :: CapabilityIndex -> Int
capabilityRank capability =
  case capability of
    BaseAuthority -> 0
    PrivatePower -> 1
    AdministrativePower -> 2
    JudicialPower -> 3
    LegislativePower -> 4
    ConstitutionalPower -> 5

normalizeCapabilityToken :: String -> String
normalizeCapabilityToken =
  map toLower . filter isAlphaNum

