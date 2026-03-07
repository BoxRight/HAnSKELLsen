module FixedPoint where

fixpoint :: Eq a => (a -> a) -> a -> a
fixpoint f x =
  let x' = f x
  in if x' == x
        then x
        else fixpoint f x'

