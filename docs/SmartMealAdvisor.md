# Smart Meal Advisor

The advisor is built into regular LoopFollow. Build 15 adds an editable insulin amount before the Meal handoff and a matching, versioned Trio receiver for split carbs. Build 14 remains the last verified installation on the user's iPhone; building source does not install either app.

## Daily workflow

1. Open **Home → Smart Meal Advisor**, or open it inside **Meal**.
2. Enter the full meal carbs or choose foods from the Carnival guide. Select Rice, Pizza, Fruit & Dessert, or Custom.
3. Review the **Full recommendation** and **Suggested upfront** amount. Keep it, or edit **Your upfront bolus (U)** directly. The edited number is copied exactly; no percentage is applied to it again.
4. Tap **Use these values**. The standard Meal screen receives the selected carbs, dose and any explicitly selected nutrients.
5. Review Meal, tap **Send Meal**, then use the standard confirmation/authentication. The advisor itself cannot send treatments.

| Preset | Carbs now | Carbs later | Delay | Initial insulin selection |
|---|---:|---:|---:|---:|
| Rice | 75% | 25% | 30 minutes | 75% |
| Pizza | 70% | 30% | 60 minutes | 70% |
| Fruit & Dessert | 100% | none | none | 100% |
| Custom | 100% initially | editable | editable | 100% initially |

Expand **Change carb split or insulin percentage** to edit the independent controls. Whole-gram rounding preserves total carbs. These are editable test defaults, not validated patient treatment settings.

The full recommendation uses **all meal carbs**, existing COB, current glucose/change, effective ISF and net IOB, then Trio's recommendation percentage and limits. The preset percentage applies afterward. Example: 80 g meal, full adjusted recommendation 5.80 U → Rice suggests 4.35 U, with 60 g now and 20 g later. Trio's existing 90% setting is preserved. Selecting a different dose replaces 4.35 U directly.

**There is no scheduled second insulin bolus.** A 75% insulin choice does not instruct Trio to deliver a fixed remaining 25%. Subsequent SMBs/basal remain decisions of the existing Trio algorithm from later inputs. The only delayed item created by this workflow is a dated carbs-only entry.

## Matching Trio update

Split sending requires the [matching Trio receiver update](https://github.com/shamiln876/Trio/pull/1) on the phone running the pump controller. Updating LoopFollow alone cannot add a receiver to an older Trio app.

The updated Trio uploads protocol version 1, its actual current calculator limits/percentage, pump increment and transaction receipts through its existing Nightscout device status. LoopFollow imports settings automatically only from fresh data matching the configured Trio bundle and calculation cycle. Old/historical settings never become verified just because an app was updated. Older Trio versions retain manual current-setting verification for supported single-entry drafts; they cannot send split drafts.

Once the matching Trio is installed, Remote Control and Nightscout upload must already be enabled as in the existing setup. After its next successful upload, LoopFollow automatically recognizes the receiver. No new Nightscout setup or second LoopFollow app is required.

## Transaction behavior

- One confirmed encrypted request contains both carb amounts, a delay measured from final confirmation, and only one upfront insulin amount.
- Trio independently checks current settings, freshness, predictions, any bolus since the calculation, native full-meal calculator agreement, and its standard bolus safety checks.
- Trio durably claims the transaction ID before effects. Both carb entries are stored in one Core Data save. A failed save rolls back the entire batch and does not request insulin.
- The later entry has a stable ID and future date. Native meal calculations exclude future carbs until due. No LoopFollow timer or second APNs command is needed.
- A replay/restart cannot repeat the storage or upfront bolus attempt. The receiver retains its durable transaction ledger. An unknown result blocks another smart meal until explicitly checked; no automatic retry exists.
- APNs acceptance means the request was submitted. A typed Trio receipt reports carb storage and, for a positive dose, bolus initiation. It does not prove complete pump delivery; actual treatments remain the delivery record.
- Trio requests an immediate status upload after processing or reconciliation. LoopFollow clears its pending attempt only for an exact matching accepted/rejected/reconciled receipt. Uncertain results stay pending and explain what needs checking.

Drafts expire after two minutes or changed inputs/settings and are rechecked after authentication. The standard Meal fields remain editable. Changed carbs need a fresh calculation; edited insulin must fit current limits and DASH 0.05 U increments. Protein/fat default to zero in the handoff, unless explicitly opted in. Opting in permits Trio's normal FPU conversion and is stated on screen. The Carnival guide retains estimated nutrition and source provenance.

## Mac verification

Use Xcode 26.1.1 or compatible, the existing workspace and pinned dependencies. Keep build products outside the repository because Trio's formatter scans its checkout.

```sh
# From LoopFollow:
bash Scripts/test-smart-meal-core.sh
bash Scripts/test-smart-meal-integration.sh /path/to/matching/Trio
# In Xcode, scheme SmartMealUI runs synthetic tap-through tests in a simulator.
# From Trio:
bash scripts/test-smart-meal-receiver.sh
```

The core scripts do not start the app, connect a pump, use remote credentials, or send treatments. The UI fixture is compiled only into debug simulators, skips app networking/telemetry/alarm startup and supplies synthetic data with empty treatment credentials. UI tests stop before Send Meal/authentication.

Verified during this iteration: 40 LoopFollow calculation/freshness/draft/request tests; 14 receiver/replay/concurrency/SQLite tests; two cross-app integration tests covering all presets, exact edited units, zero insulin, status correlation and restart replay. The full arm64 Trio simulator app build succeeded, and the final native run passed 42 tests across five suites, including the real storage adapter and future-carb behavior. Four real tap-through UI tests passed: Home handoff, Meal handoff, preserved Pizza settings on reopening, and an older-receiver split-send hold. Earlier failed/interrupted runs are not counted as passes. Signed-device build and installation status are recorded separately.

## Installation

Update the existing apps in place with their original bundle IDs, signing team and App Groups. Back up settings/Documents and retain the prior signed build first; do not uninstall. Install regular LoopFollow build 15 on the caregiver phone and the matching Trio receiver update on the pump-controller phone. Verify the actual installed versions and preserved configuration after each update. No test should send a hypothetical meal or insulin to the live controller.

Actual bolus/SMB/peak/nadir outcome logging remains deferred. No live treatments, authentication or pump-setting changes were exercised in development. Physical-device behavior and clinical efficacy are not established by simulator tests.

Earlier build/deployment details are retained in [SmartMealAdvisorHistory.md](SmartMealAdvisorHistory.md).
