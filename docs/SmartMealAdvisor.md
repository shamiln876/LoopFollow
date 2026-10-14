# Smart Meal Advisor test build

Open Meal → Smart Meal Advisor and enter the hypothetical new meal carbs. The review updates from the current glucose history and latest Trio upload. It cannot log carbs, prefill a bolus, or send insulin. The existing Meal and Bolus actions are separate.

The displayed **net model balance** combines new meal carbs, existing COB, glucose relative to target, recent glucose change, and remaining net IOB. It is **before** maximum COB, Recommended Bolus Percentage, maximum bolus, maximum IOB and pump rounding. It is not a finalized dose. Missing patient settings are never replaced with defaults.

The calculation follows the component arithmetic in the user's Trio 1.0.2 `BolusCalculationManager`: existing COB uses whole grams, the glucose change is newest minus oldest within the preceding 20-minute window, and negative IOB represents insulin below scheduled basal. Other Trio versions hold the integrated review until their upload and calculation behavior have been checked.

IOB already includes the configured insulin-action curve and elapsed time. Current net activity (U/min) is shown separately, with the modeled five-minute effect `−activity × effective ISF × 5`. This effect is relative to scheduled basal and excludes food and other influences. It must not be interpreted as an observed or guaranteed glucose fall. IOB is not discounted again.

Uploaded IOB, COB, UAM and ZT forecast curves are displayed as **before the new meal**. No new-meal absorption curve, future SMB simulation or individualized physiological validation is implied. Selected minimum and guard values are checked separately; an IOB-only curve minimum is not substituted for the selected prediction.

The integrated balance holds for missing or stale data (10 minutes), unmatched cycle/IOB times, mismatched calculation/current IOB, new known treatments after the snapshot, missing trend history, unknown upload units/version, low current glucose, or a low selected/guard prediction. The prediction hold at 70 mg/dL is a conservative review restriction, not a change to Trio's settings. Negative selected predictions remain negative rather than being treated as missing.

Trio's uploader converts target and reason glucose fields to display units but leaves structured ISF and forecast arrays in mg/dL. Its cached suggestion can be uploaded without conversion or timestamp injection. The parser distinguishes that verified source path by version, missing injected timestamp and original deliverAt; it does not infer units from numeric magnitude.

Software tests and historical parser/component replay establish implementation behavior, not clinical dosing validity. Finalized meal-dose use and any calculated-dose delivery handoff remain unavailable until the actual patient settings, source parity and appropriate validation are established.
