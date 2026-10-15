# Smart Meal Advisor test build

Open Meal → Smart Meal Advisor and enter the hypothetical new meal carbs. The review updates from the current glucose history and latest Trio upload. It cannot log carbs, prefill a bolus, or send insulin. The existing Meal and Bolus actions are separate.

The **full calculation comparison** applies the current percentage and limits copied from Trio, plus the exact supported DASH rounding rule. Enter those four values using **Enter current Trio settings**, and confirm they were checked in Trio using Omnipod DASH. There are no prefilled defaults. These local entries do not change Trio or enable delivery. They are bound to the Nightscout connection by a SHA-256 fingerprint and to the checked Trio version; recheck them whenever settings or pump change.

The separate **uncapped balance** combines new meal carbs, existing COB, glucose relative to target, recent glucose change, and remaining net IOB before limits and percentage. Both numbers are read-only model comparisons, not clinically validated doses. Missing patient settings are never replaced with LoopFollow's own local limit or inferred from uploaded recommendations.

The calculation follows the component arithmetic in the user's Trio 1.0.2 `BolusCalculationManager`: existing COB uses whole grams, the glucose change is newest minus oldest within the preceding 20-minute window, and negative IOB represents insulin below scheduled basal. Other Trio versions hold the integrated review until their upload and calculation behavior have been checked. The full comparison caps combined carbs first, multiplies positive balance by the copied percentage, clamps to nonnegative/max bolus/remaining max IOB, and rounds down to the last supported n/20 U volume (0.05–30 U). Reduced and super bolus modes are excluded. A fresh explicitly reported 0.05 U increment and pump timestamp are required; a cached/default pump increment is not accepted.

The rounding implementation was checked against OmnipodKit commit `043b91dbf1958d26c55d927a6a8d651bc91f208d`, pinned by the user's Trio source. The extracted original Trio `calculateInsulin` body matched this implementation in 2,592 synthetic standard-meal scenarios. This verifies software behavior for those inputs; actual patient preferences and clinical effects remain unverified.

IOB already includes the configured insulin-action curve and elapsed time. Current net activity (U/min) is shown separately, with the modeled five-minute effect `−activity × effective ISF × 5`. This effect is relative to scheduled basal and excludes food and other influences. It must not be interpreted as an observed or guaranteed glucose fall. IOB is not discounted again.

Uploaded IOB, COB, UAM and ZT forecast curves are displayed as **before the new meal**. No new-meal absorption curve, future SMB simulation or individualized physiological validation is implied. Selected minimum and guard values are checked separately; an IOB-only curve minimum is not substituted for the selected prediction.

The integrated balance holds for missing or stale data (10 minutes), unmatched cycle/IOB times, mismatched calculation/current IOB, new known treatments after the snapshot, missing trend history, unknown upload units/version, low current glucose, or a low selected/guard prediction. The prediction hold at 70 mg/dL is a conservative review restriction, not a change to Trio's settings. Negative selected predictions remain negative rather than being treated as missing.

Trio's uploader converts target and reason glucose fields to display units but leaves structured ISF and forecast arrays in mg/dL. Its cached suggestion can be uploaded without conversion or timestamp injection. The parser distinguishes that verified source path by version, missing injected timestamp and original deliverAt; it does not infer units from numeric magnitude.

A zero-new-carb comparison is shown beside Trio's uploaded zero-new-carb recommendation. A disagreement warns to recheck settings and snapshot timing. Agreement, especially at zero or a cap, cannot prove the copied settings are correct. Values converted for Nightscout can be rounded.

Software tests and historical parser/component replay establish implementation behavior, not clinical dosing validity. A verified patient meal dose and any calculated-dose delivery handoff remain unavailable until actual settings and appropriate validation are established. No automatic insulin delivery, remote-send dependency, copy-to-bolus action or input write-back is added.

## Manual bolus adjustment

The existing manual Bolus screen has −0.1 U / +0.1 U buttons. They adjust only the amount explicitly selected on that screen, never transfer the meal comparison, and never send a command themselves. Controls require a compatible configured pump increment and an amount on that increment; they stop at zero and LoopFollow’s local maximum without silently clamping a smaller change. Editing is disabled during authentication and sending. The existing confirmation and device-owner authentication (Face ID or passcode fallback) remain required. This does not enable delivery from the unvalidated meal comparison.
