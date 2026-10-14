# Smart Meal Advisor — read-only test

Open the existing Meal screen and tap **Smart Meal Advisor · Read-only**.
The advisor has its own carb input, initially copied from the Meal screen. Closing
it does not write back to the meal, bolus, quick picks, or remote command layer.
There is no send, accept, or deliver action in the advisor.

## Data

The advisor consumes a single in-memory OpenAPS suggested record (enacted when
suggested is absent), its matching IOB object and the current glucose stream.
It does not reuse the persistent last-IOB/COB/CR caches. Missing values remain
missing on each update, and failed or non-OpenAPS records clear its snapshot.

CR uses a positive structured value, then a CR reason-string field, then the
current scheduled Nightscout profile ratio. The fallback is explicitly labeled
and warns that it may not reflect an active override. IOB requires its own `time`
or `timestamp`; COB uses the calculation timestamp. ISO timestamps with and
without fractional seconds are accepted.

The only numeric result is entered carbs / CR. This is labeled **carb-only insulin
equivalent**, never a dose recommendation. There is no correction, IOB subtraction,
COB subtraction, SMB forecast, or delay/absorption model. It is hidden with missing
IOB/COB/CR/glucose timestamps, records older than ten minutes, timestamps more than
one minute ahead, glucose below 70 mg/dL, missing trend, or falling glucose.
Ten minutes is a prototype freshness policy, not a claim of clinical validation.

Trio IOB is modeled active insulin above or below scheduled basal; a zero or
negative net IOB must not be interpreted as absence of all circulating insulin.
COB is a model estimate. All remote bolus and meal sending code is unchanged.

Clinical terminology references:
- https://triodocs.org/configuration/new-user-setup/
- https://diabetes.org/living-with-diabetes/hypoglycemia-low-blood-glucose

## Validation and distribution

Focused parsing/freshness tests live in `Tests/MealReviewSnapshotTests.swift`.
Local build logs and test results are in ignored `build-review/`.
Compilation and software tests do not validate dose selection for a patient.
No live delivery has been tested or initiated by the advisor.

The existing TestFlight workflow now skips upstream synchronization for `feature/`
branches, since the custom branch does not exist in the upstream project. Main's
sync behavior is unchanged. Use **4. Build LoopFollow** on the feature branch after
publication. Distribution still requires working repository secrets and Apple
signing; a successful simulator or unsigned iPhone build is not installable on an
iPhone. This workflow uses the existing app identifier, so the TestFlight build
updates that LoopFollow app rather than creating an independently installed app.
It does not install or modify Trio.
