# Car Sale Delivery Claim Mismatch Investigation

## Summary

The delivery obligation stays **pending** even though the scenario includes "Seller delivers Goods to Buyer". The payment obligation is correctly fulfilled. This document describes the mismatch, the two claim representations, the root cause, and a suggested backend verification.

---

## The Mismatch

- **Expected**: After the scenario runs, both the delivery obligation and the payment obligation should be fulfilled (excluded from `pendingObligations`).
- **Actual**: The payment obligation is fulfilled; the delivery obligation remains pending.
- **Scenario**: `lawlib/instantiations/car_sale_case.dsl` with scenario `ClosingDay`:
  - `at 2025-03-01`: Seller delivers Goods to Buyer; Buyer pays Price to Seller.

---

## Two Claim Representations (from JSON Audit)

The normative state contains **two** claims over delivery of Goods:

1. **Wrapped object** (from `objectClaimToDelivery`):
   ```
   Claim (Simple (Alice Corp) (Object {oSubtype = ServiceSubtype (Performance (Just (Object {..., oName = "Goods", ...}))), ...}) (Bob))
   ```

2. **Plain object** (original claim from sales.dsl):
   ```
   Claim (Simple (Alice Corp) (Object {oSubtype = ThingSubtype Movable, oName = "Goods", ...}) (Bob))
   ```

The scenario act compiles to:
```
Simple (Alice Corp) (Object {oSubtype = ThingSubtype Movable, oName = "Goods", ...}) (Bob)
```
i.e. the **plain** Goods object.

---

## Root Cause

Two factors prevent fulfillment:

### 1. Capability Mismatch (Primary)

- **Scenario acts** use `lawAuthorityAst meta` from the law that defines the scenario. For `CarSaleCase` (authority private), scenario acts get `PrivatePower`.
- **Claims and obligations** from the imported statute `sales.dsl` (authority legislative) keep `LegislativePower`.
- `hasVisibleAct` in Logic.hs requires `capIdx == expectedCap`. When `claimFulfilled` checks a claim with `LegislativePower`, it looks for `GAct` with `LegislativePower`. The scenario only has `GAct` with `PrivatePower`. **No match.**

### 2. Object Structure (Secondary for Derived Claim)

- `objectClaimToDelivery` derives a claim with `deliveryObject obj`, which wraps the object as `ServiceSubtype (Performance (Just obj))`.
- The scenario act uses the plain `ThingSubtype Movable` object.
- `show`-based matching in `hasVisibleAct` and `hasFulfillmentFor` compares the full act representation. The wrapped form differs from the plain form, so even if capability matched, the derived (wrapped) claim would not match the scenario act.
- The **original** claim (plain object) would match the scenario act structurally, but the capability mismatch blocks it.

---

## Backend Check

To verify how `objectClaimToDelivery` and delivery matching interact:

1. **`objectClaimToDelivery`** (Logic.hs): For each `GClaim (Claim act)` where the object is `ThingSubtype _`, it derives a new claim with `deliveryAct = Simple actor (deliveryObject obj) target`. The derived claim uses `deliveryObject`, which wraps the object. The original claim remains.

2. **`claimFulfilled`** (Logic.hs): For each claim, it checks `hasVisibleAct capIdx time act acc`. The `act` is the claim’s act (plain for original, wrapped for derived). Matching requires both `capIdx == expectedCap` and `show visibleAct == show expectedAct`.

3. **`deliveryObject`** (Logic.hs): `deliveryObject obj = obj { oSubtype = ServiceSubtype (Performance (Just obj)) }`. This changes the object’s `oSubtype`, so `show` differs from the plain object.

4. **`claimFulfilled` and `hasFulfillmentFor`**: Both rely on `show`-based act comparison. Acts with plain vs wrapped objects do not match.

**Suggested verification**: Add a test or debug path that:
- Confirms the obligation’s act uses the plain object.
- Confirms the derived claim’s act uses the wrapped object.
- Confirms scenario acts use the plain object and `PrivatePower`.
- Confirms that relaxing capability (e.g. allowing `PrivatePower` acts to fulfill `LegislativePower` claims) would allow the original claim to match, while the derived claim would still require object normalization or a semantic equivalence check.

---

## Possible Fixes

1. **Capability relaxation**: Allow scenario acts from a lower authority (e.g. `PrivatePower`) to fulfill claims/obligations from a higher authority (e.g. `LegislativePower`). This would require changing `hasVisibleAct` / `hasVisibleCounterAct` to consider capability hierarchy (e.g. `dominates` or a “fulfills” relation).

2. **Object normalization**: When comparing acts for fulfillment, treat `ServiceSubtype (Performance (Just obj))` as equivalent to `obj` for matching. This would align the derived claim with scenario acts that use the plain object.

3. **Scenario authority inheritance**: When a scenario is in a law that imports a statute, scenario acts could be indexed with the statute’s authority for fulfillment purposes. This is a compiler/design choice.

---

## References

- [Logic.hs](../Logic.hs) — `objectClaimToDelivery`, `claimFulfilled`, `deliveryObject`, `hasVisibleAct`, `hasVisibleCounterAct`
- [src/Runtime/Audit.hs](../src/Runtime/Audit.hs) — `hasFulfillmentFor`, `isPendingObligation`
- [src/Compiler/Scenario.hs](../src/Compiler/Scenario.hs) — scenario acts use `lawAuthorityAst meta`
- [lawlib/instantiations/car_sale_case.dsl](../lawlib/instantiations/car_sale_case.dsl) — CarSaleCase (private), imports sales.dsl (legislative)
