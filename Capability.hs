module Capability where

import NormativeGenerators (CapabilityIndex(..))

capabilitySupremum :: CapabilityIndex -> CapabilityIndex -> CapabilityIndex
capabilitySupremum a b = max a b

