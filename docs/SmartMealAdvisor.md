# Smart Meal Advisor

The advisor is built into regular LoopFollow. Build 21 defaults to Full Meal Bolus (100%), places Rice · 75/25 split next, and removes the IOB/COB duration captions from the corner information table. Its corner uses 16-point text and 22-point rows, with SAGE/CAGE hidden once; they can be enabled again in Information Display settings. The upfront insulin remains editable before its exact transfer into Meal. Reopening unchanged, still-current verified settings needs no repeated checkbox and does not refresh their verification time. Split carbs require the matching, versioned Trio receiver. Building source does not install either app.

## Daily workflow

1. Open **Home → Smart Meal Advisor**, or open it inside **Meal**.
2. Enter the full meal carbs or choose foods from the Carnival guide. The default is Full Meal Bolus (100% carbs and 100% of the adjusted recommendation). Select Rice · 75/25 split, Pizza, or Custom when needed.
3. Use the visible **− / +** insulin controls for 5-percentage-point changes with insulin and carbs-now linked by default. Review the **Full recommendation** and **Suggested upfront** amount. Keep it, or edit **Your upfront bolus (U)** directly. The edited number is copied exactly; no percentage is applied to it again.
4. Tap **Use these values**. The standard Meal screen receives the selected carbs, dose and any explicitly selected nutrients.
5. Review Meal, tap **Send Meal**, then use the standard confirmation/authentication. The advisor itself cannot send treatments.

| Preset | Carbs now | Carbs later | Delay | Initial insulin selection |
|---|---:|---:|---:|---:|
| Full Meal Bolus (default) | 100% | none | none | 100% |
| Rice · 75/25 split | 75% | 25% | 30 minutes | 75% |
| Pizza | 70% | 30% | 60 minutes | 70% |
| Custom | 100% initially | editable | editable | 100% initially |

Expand **Custom percentages and timing** and turn linking off to edit the percentages independently. Selecting Custom also turns linking off. Reducing the default Full Meal percentage stages the remaining carbs at +30 minutes; Rice uses +30 and Pizza +60. A positive custom delay is retained. An explicit units edit keeps the displayed carb split and replaces the selected insulin exactly. Whole-gram rounding preserves total carbs. These are editable test defaults, not validated patient treatment settings.

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

Verification: 45 LoopFollow calculation/freshness/draft/request tests and two cross-app integration tests passed for build 21 source. New tests cover linked percentages and exact receiver decimals, configuration identity and receipt digests. A captured read-only Trio upload reproduced the settings-import failure before the parser correction and imported successfully afterward. Current receiver telemetry now supplies live configuration instead of relying on an expired manual checkbox. Genuine stale or invalid telemetry still holds transfer. The integration tests exercise the actual command decoder without a pump or credentials.

Prior verification includes the signed regular LoopFollow build 20 installed in place with all 33 protected settings preserved, the simulator percentage-to-Meal journey, 14 receiver/replay/concurrency/SQLite tests and 42 native Trio tests. Trio 1.0.2 build 9 was uploaded successfully to TestFlight and independently reported VALID and IN_BETA_TESTING for internal testing. The two linked simulator journeys passed, and the Custom override journey passed after correcting the test to tap the switch track. Tests verify exact percentage-adjusted units and the matching carb split in Meal, stopping before Send Meal. Build 21 phone installation is recorded separately once completed. Physical treatment delivery and clinical efficacy are not established by these checks.

## Installation

Update the existing apps in place with their original bundle IDs, signing team and App Groups. Back up settings/Documents and retain the prior signed build first; do not uninstall. Install regular LoopFollow build 21 on the caregiver phone and the matching Trio receiver update on the pump-controller phone. Verify the actual installed versions and preserved configuration after each update. No test should send a hypothetical meal or insulin to the live controller.

Actual bolus/SMB/peak/nadir outcome logging remains deferred. No live treatments, authentication or pump-setting changes were exercised in development. Physical-device behavior and clinical efficacy are not established by simulator tests.

Earlier build/deployment details are retained in [SmartMealAdvisorHistory.md](SmartMealAdvisorHistory.md).
