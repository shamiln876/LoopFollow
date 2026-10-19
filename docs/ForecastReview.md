# Meal forecast review

Low pre-meal forecasts no longer impose the Advisor's extra, unconditional 70 mg/dL calculated-dose transfer block when the paired receiver supports review. The Advisor shows selected minimum, guard minimum and eventual endpoint separately. These are different model values and exclude the new meal.

The user enters full carbs, reviews or edits upfront units, then taps **Use these values**. If a positive selected dose accompanies a selected/guard forecast below 70 mg/dL, **Review low forecast** displays the actual forecasts and selected meal/dose. **Cancel** stays in the Advisor; **Accept and continue** opens the standard editable Meal. Nothing is sent from the warning or Advisor. Standard confirmation/authentication remain.

The acknowledgement belongs to one draft and its exact calculation/settings context, not a persistent setting. Changed snapshots or expired inputs require a new automatic review. A zero-insulin draft does not silently acknowledge a warning for insulin added later.

## Native behavior and manual entry

Trio's existing calculator returns zero recommended insulin when current glucose or its selected minimum is below 54 mg/dL. The local calculation now preserves that zero as well. Automatic positive prefill still requires current glucose at least 70 mg/dL and selected minimum at least 54 mg/dL. The guard forecast is shown for explicit review; it is not an additional native bolus-calculator cutoff. Normal limits, recent-bolus protection, current settings, exact calculator agreement, duplicate prevention and authentication remain.

**Enter Meal manually** is available from the Advisor even when automatic calculation cannot be verified. It copies the full valid carb amount with zero calculated insulin, no delayed entry and no advisor authorization. The standard Meal fields remain editable and retain their ordinary validation and authentication. This is an explicit manual route, never a silent downgrade of a calculated/split transaction.

## Receiver compatibility

The version-1 status adds optional `allowsLowPredictionReview`; a request adds optional `lowPredictionAcknowledged`. Missing fields preserve old message encoding and receipt identity. The client requires the advertised capability before enabling low-forecast calculated transfer. Older receivers retain their prior behavior; manual Meal remains available. The matching receiver validates the acknowledgement against its own current prediction and calculation timestamp before any storage/bolus effect. A native selected forecast below 54 cannot be overridden by this flag.

No later insulin bolus is scheduled. The existing split, opt-in nutrients and transaction receipt behavior are unchanged.

## Verification

Synthetic tests cover the 65/29 mg/dL minimum/guard case, explicit acceptance, native threshold boundaries, current low glucose, stale/changed data, old receiver capability, zero-dose acknowledgement, request/receipt compatibility and replay prevention. UI journeys stop before Send Meal. No live meal, insulin or pump-setting changes are performed.
