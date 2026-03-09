{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}


module Patrimony where

import LegalOntology
import qualified Data.Set as S

--------------------------------------------------
-- PATRIMONY GENERATORS
--------------------------------------------------

data PatrimonyGen
  = Asset String
  | Liability String
  | Capability String
  | Owned Object
  | Collateral String
  | Certification String
  | ApprovedContractor String
  deriving (Eq, Ord, Show)

--------------------------------------------------
-- PATRIMONY STATE
--------------------------------------------------

type PatrimonyState = S.Set PatrimonyGen

emptyPatrimony :: PatrimonyState
emptyPatrimony = S.empty

insertPatr :: PatrimonyGen -> PatrimonyState -> PatrimonyState
insertPatr = S.insert

memberPatr :: PatrimonyGen -> PatrimonyState -> Bool
memberPatr = S.member

