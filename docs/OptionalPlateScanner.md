# Optional plate scanner

## Native iOS 27 integration (build 24 source)

Smart Meal Advisor now has a direct **Scan plate photo** button. The default analysis mode is **This iPhone · Apple Intelligence**. It checks iOS 27, device eligibility, Apple Intelligence enablement and model readiness before allowing photo selection. The ordinary Carnival guide remains available without photo analysis. A device OS update alone does not add this feature to older installed builds.

The native path explicitly uses `SystemLanguageModel.default` and the iOS 27 `Attachment(CGImage)` API. It never selects Private Cloud Compute or an external provider automatically. A bounded local catalog tool returns only IDs, food names, venues and exact base portions, with no nutrition or clinical telemetry. At most two tool calls, six queries per call and four candidates per query are permitted. All catalog matches must have been returned by that photo session's lookup; unoffered IDs are retained as unresolved foods. The model reports food labels, catalog IDs, base-portion multipliers and uncertainty, never carbs or insulin. Incomplete or invalid responses fail closed. Local grounding/review logic requires explicit match and portion confirmation. The existing catalog computes nutrition and the existing Advisor receives only the accepted reviewed meal.

A single typed sheet route presents settings, the manual guide or the photo scanner; this avoids competing sheet modifiers after integrating the forecast warning. Photo cancellation preserves entered Advisor carbs. Both direct-Advisor and guide entry use the same scanner. A session ID prevents an older cancelled analysis from changing a newer photo's results or busy state. All image inputs are redrawn in memory to normalize orientation/remove metadata. A separate explicitly selected cloud-service mode retains the previous authenticated backend; native errors do not enable it or incur API costs.

`PlateScanOnDevice.swift` compiles the native API only with Swift 6.4 / Xcode 27 and checks iOS 27 at runtime. Older SDK builds show an explicit unavailable message, not a simulated recognition result. The native CI job defines `PLATE_SCAN_REQUIRE_NATIVE`, so it fails rather than silently compiling out the API. Local Mac remains macOS 26.1 / Xcode 26.1.1 and the caregiver iPhone was read-only verified at iOS 26.5.1 during this change. Actual device recognition and portion accuracy remain untested until a compatible build and updated phone are available.

The new `Native iOS 27 plate scanner` workflow uses GitHub's standard `xcode-27` runner, released Xcode 27, nine Swift model/transport/grounding tests, twelve mocked server/quota tests and five synthetic UI journeys, including the retained forecast acceptance/manual Meal routes. Results must be checked; source presence is not a successful native compile. LoopFollow's branch-targeted, manual-only TestFlight workflow selects the Xcode 27 runner/SDK, requires native compilation, reuses the existing family certificate read-only, and verifies SDK/app identity/build number in the IPA before upload. It cannot run the certificate replacement lanes. No signing secrets, bundle IDs, entitlements, App Groups, clinical settings, Trio receiver or treatment transport were changed. The original Trio dispatcher retains its separately reviewed source pin. The dedicated native release is isolated in `shamiln876/Trio` branch `feature/native-plate-distribution` / PR #2 and builds only pinned LoopFollow source with the working family signing secrets. It verifies all three LoopFollow checks before upload. The LoopFollow repository's stored Match password failed decryption; it was not changed or copied. No certificate was replaced. This manual-only workflow change applies to this feature branch; it does not alter the default branch schedule.

Build 24 combines the photo scanner with the independently implemented forecast-review update (`29b61d0`, installed as build 23). It retains that update's warning acknowledgement, changed-snapshot check and manual Meal route. The scanner does not change those clinical calculations or receiver rules. A native run compiled the image API and passed all three original screen journeys; a later run exposed an obsolete test assumption that upload must be disabled even when the native model is available. That assertion was replaced by checking model-status visibility. The latest combined source still requires its own full verification before upload.

References:
- https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting
- https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling
- https://developer.apple.com/xcode/system-requirements
- https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md

## Earlier API implementation and verification history


Branch `feature/optional-plate-scanner`, based on Smart Meal Advisor build 21 (`8c535de`).

## User workflow

Carnival guide → **Take / upload plate photo (optional)** → select/take a photo → review each food → adjust its base portions with −/+ → confirm food and portion → **Accept — fill Smart Meal Advisor**. Unknown foods need a catalog match or an explicit removal. Missing nutrition or unreviewed amounts block acceptance. Add overlooked foods from the catalog. The subtotal updates immediately. Missing/invalid totals never prefill the advisor. There is no scan on guide opening and no API use during manual food search.

Only catalog nutrition contributes to a total. AI supplies suggested IDs and portion multipliers, never carbohydrate values. All 1,085 guide entries remain available, including 54 unavailable recipes; zero verified Carnival nutrition sets are claimed. The ordinary offline guide, meal calculations, remote controls and Trio receiver are unchanged.

Photos are redrawn to at most 1280 pixels on the longest side, encoded as JPEG without source EXIF/GPS, and held in memory. Only this image and the catalog fingerprint are sent to the configured service. No clinical telemetry or pairing data is attached. Cancellation discards suggestions. Accept invokes the existing food-meal callback; standard Meal confirmation/authentication remains separate. This feature has no treatment transport.

## Provider assessment

OpenAI Responses supports image input and structured JSON output: https://developers.openai.com/api/docs/guides/images-vision and https://developers.openai.com/api/reference/resources/responses/methods/create . The supplied server pins `gpt-4.1-mini-2025-04-14`; an `OPENAI_MODEL` override is ignored; live availability/accuracy have not been verified in the user's account. A photograph cannot establish exact mass, hidden ingredients, sauces or carbohydrate reliability; all suggestions require review.

Apple's latest Foundation Models documentation describes multimodal prompting (https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting). However, the installed Xcode 26.1.1 iPhoneOS 26.1 FoundationModels Swift interface exposes text Prompt inputs and no ImageAttachment interface. This project supports iOS 18+. Apple image understanding is therefore not an implemented, tested option for this toolchain/deployment target. Do not claim it is impossible on newer SDKs. OCR/classification alone is insufficient for this catalog/portion task.

## Secure server package

`server/plate-scanner/worker.mjs` is a Cloudflare Worker with an authenticated `/scan` POST route, bounded JPEG input, exact catalog fingerprint, server-side catalog prompt, strict structured output, validated catalog IDs/portions, no request-body logging, no photo persistence, and no automatic retries. `store:false` is sent to OpenAI; this does not assert zero provider retention. Provider policy still applies. The client refuses HTTP, URL credentials/query secrets and redirects, uses ephemeral networking, and stores its service access token in device-only Keychain.

Server deployment requires an owner-controlled Cloudflare account and an OpenAI API project with billing/credits. ChatGPT subscription access alone does not configure this API. Neither account was supplied; no live provider test or deployment has occurred. The final credentials/account activation require the account owner. Do not put secrets in source, chat, GitHub artifacts, app bundle or UserDefaults.

When accounts are available, an operator should use `wrangler secret put OPENAI_API_KEY` and `wrangler secret put SCANNER_ACCESS_TOKEN` (at least 32 random characters), then `wrangler deploy` from this server directory. Configure the resulting HTTPS `/scan` URL and separate access token in Scanner setup. OpenAI key stays server-side. Before enabling scans, configure a dedicated OpenAI project with a US$3 enforced monthly hard spend limit and no automatic credit recharge. Keep the supplied five-requests-per-minute Cloudflare binding enabled; the service token is revocable. This is a private family deployment, not a multi-user authentication platform.

## Verification

`bash Scripts/test-plate-scanner.sh` runs seven pure Swift/transport tests and twelve server/quota tests without live API or pump access. The SmartMealUI synthetic scanner test exercises the real Advisor → guide → scanner → Advisor route, including unresolved blocking, explicit review, Add/Remove, immediate +/- totals and the accepted catalog total. A separate manual regression test checks scanner cancellation and offline half-bagel entry into Advisor using empty treatment credentials. No physical camera or live recognition accuracy is established by these tests. Full build/UI outcomes are recorded in the final delivery report, not inferred from source presence.

No previous `optional_plate_scanner.zip` was found in this workspace or temporary-file search. A new patch/archive is generated from the validated commit for delivery; it must not be represented as the earlier claimed package.

Verified locally on October 18, 2026 with Xcode 26.1.1:

- Seven Swift model/transport tests passed; six mocked server tests passed.
- Cloudflare Wrangler 4.151.1 deployment dry-run passed, without credentials or deployment.
- `CarnivalManualUITests/testManualHalfBagelStillFillsAdvisorAfterCancellingScanner` passed in UI4, with 26 g in the real Advisor field.
- `SmartMealHandoffUITests/testOptionalScannerRequiresReviewAndUnknownResolution` passed in UI6, exercising real nested-sheet acceptance, unknown blocking, Add/Remove, 26→39→26 g changes and return to the real Advisor.
- UI testing found and fixed overlapping row navigation and a stale index-backed binding crash after deletion. Food rows now resolve bindings by stable UUID, including a safe fallback for deleted rows retained by Form animations/accessibility.
- Final app/test compile succeeded for the arm64 iOS 26.1 simulator. No physical camera, live OpenAI image recognition or clinical outcomes were tested.

Physical iPhone installation and TestFlight publication are coordinated separately by the primary “Complete LoopFollow development” chat. Do not infer installation from this branch's build number 22. Existing TestFlight release 21 and the father's Trio 1.0.2 (9) are not changed by a source commit.


## Cost protection added October 18, 2026

The user's new-service budget is $10/month; currency has not been confirmed, so no paid hosting subscription is activated. Start with Workers Free and its SQLite-backed Durable Object, which stops serving when free quotas are exceeded rather than charging overages. This plan selection is an account/deployment requirement, not something the source can enforce. Do not upgrade or introduce a paid model fallback automatically.

Every valid authenticated scan must first reserve one attempt in the single `family-scanner` Durable Object: **10 attempts per UTC day, 100 per UTC calendar month**. Reserve atomically before the OpenAI request; retain the reservation even on timeout, error, refusal or incomplete output. All devices and locations share the counter. Missing/broken storage fails closed. Restarts and service-token rotation do not reset it. Do not rename the Worker, binding, class, object ID or migration namespace, or delete its storage to bypass an allowance. A UTC month boundary intentionally grants the next month's allowance.

The provider model is pinned and output remains capped at 3,000 tokens; there is one provider call and no automatic retries. A five-per-minute regional rate limiter is not a monthly spending cap and is not relied on as one.

The actual catalog/instructions tokenize to 41,851 tokens with o200k_base. At the current GPT-4.1 mini rates of US$0.40/M input and US$1.60/M output, allowing 2,592 image tokens, 1,000 other input tokens, and 500–3,000 output tokens, estimated cost is US$0.019–0.023 per normal app scan, or US$1.90–2.30 for 100 attempts, without cache discounts. This is a usage estimate, not a guaranteed currency ceiling: provider pricing, request processing and taxes/FX are external. The separately configured provider project hard cap is needed as another layer; official documentation notes enforcement can lag slightly. A gateway counter cannot cap requests made outside that gateway. No account hard cap has yet been configured and no paid service has been activated.

Validation: twelve Node tests passed, including concurrent reservations, monthly exhaustion and rollover, corrupt state, failed storage, missing/exhausted quota preventing provider access, and no retry/refund on provider error. A separate actual local Workers/SQLite runtime check admitted exactly 10 of 100 concurrent requests and retained the exhausted allowance after runtime restart. Wrangler 4.151.1 deployment dry-run passed with the new SQLite Durable Object binding. No paid API calls or live deployment were made. Swift/app source and pump settings are unchanged by this server update.

Sources:
- https://developers.openai.com/api/docs/models/gpt-4.1-mini
- https://developers.openai.com/api/docs/guides/spend-limits
- https://developers.cloudflare.com/durable-objects/platform/pricing/

An iOS 27 update on the caregiver phone enables investigation of Apple's newer on-device image-input API, but does not implement it in the installed app. Integration needs a compatible SDK and actual device/food-photo evaluation. Offline photo recognition would not make remote Trio telemetry available offline. The existing app still requires fresh clinical data for a bolus recommendation.
