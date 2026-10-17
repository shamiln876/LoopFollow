# Smart Meal Advisor implementation and test guide

This branch combines the currently installed meal dashboard and Carnival guide with editable Rice, Pizza, Fruit & Dessert, and Custom presets. It is delivered as an in-place update of regular LoopFollow, retaining the existing app identity and saved configuration. Nightscout and remote-control settings do not need to be re-entered. No treatments are sent by the Advisor screen.

| Preset | Carbs now | Remaining carbs | Delay | Initial insulin selection |
|---|---:|---:|---:|---:|
| Rice | 75% | 25% | 30 min | 75% |
| Pizza | 70% | 30% | 60 min | 70% |
| Fruit & Dessert | 100% | 0% | none | 100% |
| Custom | 100% initially | editable | editable | 100% initially |

Carb percentage, delay, and insulin percentage are separate controls. Whole-gram rounding preserves total carbs. These are editable experimental defaults, not validated patient treatment settings.

## Calculation and handoff

The existing Trio 1.0.2 standard calculator uses **all meal carbs** plus existing COB, effective ISF, target, recent glucose change and IOB. It applies copied Trio percentage and limits before DASH rounding. The preset insulin percentage applies to that full rounded recommendation, with one further round down to 0.05 U. The saved Trio 90% (or other explicitly entered value) is never modified. Example: full adjusted recommendation 5.80 U → Rice 75% selection = 4.35 U, irrespective of the 60 g now / 20 g later split for an 80 g meal.

The inherited calculator was previously compared with the extracted Trio calculation across 2,592 synthetic scenarios. Software equivalence is not physiological validation. Before dose prefill, the caregiver must enter the full recommendation checked in Trio using all meal carbs, without delivering the comparison there. It must match exactly. Settings must be explicitly current, connection/version matched, checked within 24 hours, and not historical. All existing glucose, IOB, treatment, pump and prediction freshness guards apply. This implementation supports only the verified Trio 1.0.2 standard calculation and reported DASH 0.05 U increment.

Prefill transfers carbs, the selected dose and explicitly opted-in protein/fat to LoopFollow's editable Meal screen. No command is sent by this action. The normal confirmation displays the actual selected values, and a positive insulin amount requires device-owner authentication. Input editing is disabled during authentication and sending. Changed carbs require another calculation review. Drafts expire after 120 seconds, a changed Trio snapshot, changed source or changed settings; guards run again after authentication. Edited insulin must obey the local bolus limit and 0.05 U increment. Protein and fat default to zero in the handoff unless opted in, because Trio can convert them to FPU equivalents.

## Unfinished receiver dependency: split-meal sending

**Rice/Pizza split drafts can be reviewed and prefilled, but Send Meal is disabled whenever delayed carbs are present. Nothing is scheduled.**

The inspected Trio receiver accepts one meal and one scheduledTime per command. It creates a new carb UUID for each accepted command and rejects some commands when newer carbs exist. There is no atomic multi-entry operation, durable request identifier, or per-entry acknowledgement in this protocol. Two independent APNs commands can be reordered, partially accepted, or replayed. A client timer would also not reliably survive app termination. Sending two commands cannot satisfy the requested one-confirmation, idempotent split-meal workflow with this receiver.

Completing that feature requires a coordinated Trio receiver change: a versioned batch capability, durable operation ID and deduplication, transactional acceptance of both carb entries, a delayed entry with no bolus field, and queryable acknowledgement. That receiver must then be installed and verified independently. This LoopFollow change does not modify or install Trio. No delayed insulin task exists.

For a supported single-entry draft, a local write-before-send pending journal blocks repeated advisor attempts across relaunches. An accepted APNs submission does not clear this journal or establish treatment delivery. The caregiver must inspect Trio/Nightscout and explicitly reconcile the previous attempt before another advisor send. File-write failures prevent sending. This is a conservative client guard, not receiver-side exactly-once delivery. Existing manual remote screens remain available and do not acquire this advisor-specific journal.

## Mac and iPhone testing

1. Open `LoopFollow.xcworkspace` in Xcode 26.1.1 or a compatible version, select scheme LoopFollow and an iPhone simulator. Existing CocoaPods and pinned Swift packages must resolve.
2. For isolated Mac verification, run `bash Scripts/test-smart-meal-core.sh` from the checkout (Swift 6). The final core source passed 32 tests in four suites during this task. Run the RiceMealPlanTests and MealReview calculation/snapshot/presentation tests. They use synthetic data, temporary journals and no treatment transport.
3. In a simulator with no live remote credentials, open Meal → Smart Meal Advisor. Check all four presets, editable percentages, whole-gram conservation, zero later insulin and full-versus-selected amounts. Missing/historical/stale settings should hold prefill. Do not configure live pump credentials for exploratory testing.
4. Confirm Rice/Pizza split drafts explicitly show the scheduling blocker. Changing the carb split to 100% creates a single-entry plan, not a working split schedule.
5. To install on an iPhone, select your signing team in Xcode for the app and extension, choose your connected iPhone, enable Developer Mode if prompted, then Build and Run. Installation and signing have not been confirmed by this implementation task. Do not replace a relied-upon production installation without preserving its configuration and confirming the new build separately.
6. Test handoff/confirmation with a separate non-treatment configuration. Do not tap a live Send Meal to test the feature. No live insulin, carbs, pump settings or remote commands were used during development.

The existing offline Carnival guide is retained. Selecting foods fills estimated carbs, protein and fat, rounded to whole grams for remote-entry compatibility. Protein/fat transmission resets to off after selection and requires explicit opt-in. The food guide contains estimates from the previously supplied source, not guaranteed meal composition. Actual bolus/SMB/peak/nadir outcome tracking remains deferred. Existing local comparison history retains food provenance and does not establish actual treatment delivery or outcomes.

## Verification from this task

- Xcode 26.1.1: final iOS Simulator app and test bundle `build-for-testing` succeeded with signing disabled. An existing extension Info.plist resource warning remains.
- Isolated macOS run of the exact core source: 32 tests passed across four suites.
- A clean iOS 26.1 iPhone 17 Pro simulator subsequently passed both presentation tests (standard text and accessibility text), with zero failures. The earlier stalled simulator run was interrupted.
- After explicit user approval, `group.com.D3GG62L9X8.LoopFollowSmartMealTest` was registered and associated with the separate test app and extension. The signed physical-iPhone build succeeded as **Meal Advisor Test**, bundle ID `com.D3GG62L9X8.LoopFollowSmartMealTest`. Temporary local signing edits were restored.
- Physical installation was confirmed over trusted USB using the Mac’s existing libimobiledevice installer after Apple’s CoreDevice tunnel repeatedly timed out. The installed test app is **Meal Advisor Test 7.1.0 (8)**, bundle ID `com.D3GG62L9X8.LoopFollowSmartMealTest`. A separate installed-app query confirmed the original **LoopFollow 7.1.0 (10)** remains installed under its original bundle ID.
- Automated physical-device launch could not be verified: the debugserver was unavailable because a developer disk image was not mounted, and Apple’s developer connection remained unreliable. Open Meal Advisor Test on the iPhone for the first launch. No actual authentication flow, remote treatment delivery, receiver batching or clinical efficacy test was performed.


## In-place update integration

The installed dashboard build was traced to source revision `80e3f82`. This integration retains that dashboard, its live data pipeline, the offline Carnival catalog and existing app preferences. The Home card is labelled **Smart Meal Advisor**; its compact glucose/IOB/COB summary keeps the preset controls near the top and expands to the full prior dashboard. Home and remote Meal both lead into the same advisor and standard editable Meal confirmation screen.

The update uses the regular app bundle and App Group, with build number 11. No storage-key, connection, alarm, keychain or migration changes are introduced. A private local backup of preferences and Documents was verified before preparing the update. Physical installation and post-update preservation verification are recorded below when complete. Split-carb sending remains held for the receiver dependency described above.

The combined upgrade passed 50 calculation, snapshot, history, food-guide and dashboard tests, plus six presentation tests (56 total). Rendered captures of the integrated advisor and standard editable Meal screen were inspected. The synthetic 80 g / 4.35 U handoff shows both editable values correctly and zero protein/fat. No send or authentication action was invoked during these checks.
