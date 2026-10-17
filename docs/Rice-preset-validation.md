# Rice preset — preview implemented, automatic sending blocked

Based on feature/read-only-smart-meal-advisor at 2757c5d. No live commands, pump settings, or Trio files were changed. The pre-existing read-only dashboard remains read-only.

## Implemented

One Rice toggle; no Pizza preset. Whole-gram carbs split into 75% now / 25% at confirmation +1800 seconds, rounding the delayed grams and preserving the total. Minimum preview total 4 g. Independent preset/custom upfront percentage (0–100), full existing comparison visible, selected amount rounded down to the DASH 0.05 U increment. No automatic second bolus. The existing comparison already includes its saved percentage/limits: the upfront selection applies to that displayed comparison, not to an unbounded raw dose. Existing comparison freshness/settings blockers still apply. No preview amount is transferred to the Meal or Bolus screen.

## Why sending is blocked

1. PushNotificationManager sends one entry per command and assigns the command type as apns-collapse-id. Two pending meal pushes can replace one another.
2. HTTP 200 reports APNs acceptance, not receiver storage or bolus delivery.
3. CommandPayload has no stable meal transaction ID or entry ID. A transport timeout cannot distinguish rejection from successful receipt. Retrying a meal containing bolus can repeat insulin delivery.
4. The local Trio reference checks for carbs newer than a command timestamp. An immediate entry can invalidate the other command depending on arrival order; future entries are not a durable replay ledger. The installed Trio version has not been established.
5. A phone timer at +30 min cannot guarantee background execution. Future-dating a carb record is a different mechanism: it must be shown that the installed Trio stores it, exposes it for verification, and excludes it from current COB until due.

## Required isolated acceptance tests before enabling

Use a test receiver with insulin enactment replaced by a recording stub and no live credentials. Establish the actual installed Trio revision first. Prefer one authenticated transaction that durably stores both carb entries with stable IDs and confirms both independently. If retaining two sends, use distinct collapse identifiers, stable receiver-recognized idempotency keys and correlated acknowledgements; a sender-only change cannot provide exactly-once execution.

Verify 80 g becomes exactly 60 g now and 20 g at confirmation +30 min. Test receiver refusal, max-carb rejection, missing/late ack, APNs timeout after receiver success, duplicate/replayed payload, reversed arrival, app termination/relaunch, offline receiver, delayed delivery, edits/cancel, overlapping meals and clock changes. Never auto-retry an ambiguous bolus. Persist transaction state before sending; surface partial acceptance and unknown outcomes prominently. Ensure any delayed entry has no bolus field. Ensure fat/protein are not duplicated or counted as extra delayed carbs. Confirm existing meal confirmation and bolus authentication happen before any transaction begins. Test confirmation double-taps and callback duplication.

Acceptance requires observing both durable receiver entries, not merely two successful APNs requests. None of these receiver acceptance or insulin-enactment tests have been run against a live system.

## Mac build / installation

Xcode 26.1.1 is present. Open LoopFollow.xcworkspace in this checkout. An unsigned simulator build can validate compilation without installing the app. Device installation additionally requires the existing bundle identifiers/entitlements, Apple signing team and provisioning, an accessible device and Developer Mode. Do not replace the working monitoring app to test scheduling. No credentials need to be pasted into chat. Automatic Rice sending is deliberately unavailable in this version.

## Validation completed

- Final unsigned iOS Simulator app build: succeeded (Xcode 26.1.1).
- RiceMealPlanTests: passed through Swift Testing in an isolated macOS package containing the exact model and test sources; 997 integer totals, conservation, +1800-second date, independent percentages, DASH rounding, invalid inputs, zero delayed insulin and conspicuous sending blocker. This does not test iOS UI interaction or receiver delivery.
- Standalone compiled assertions for the same model: passed.
- No live APNs, Nightscout writes, insulin delivery, settings changes, installation or receiver acceptance tests.

The production automatic split remains unimplemented and disabled pending receiver version/access and protocol work. These changes alone do not satisfy reliable automatic scheduling.
