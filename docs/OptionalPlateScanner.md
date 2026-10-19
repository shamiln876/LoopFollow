# Optional plate scanner

Branch `feature/optional-plate-scanner`, based on Smart Meal Advisor build 21 (`8c535de`).

## User workflow

Carnival guide → **Take / upload plate photo (optional)** → select/take a photo → review each food → adjust its base portions with −/+ → confirm food and portion → **Accept — fill Smart Meal Advisor**. Unknown foods need a catalog match or an explicit removal. Missing nutrition or unreviewed amounts block acceptance. Add overlooked foods from the catalog. The subtotal updates immediately. Missing/invalid totals never prefill the advisor. There is no scan on guide opening and no API use during manual food search.

Only catalog nutrition contributes to a total. AI supplies suggested IDs and portion multipliers, never carbohydrate values. All 1,085 guide entries remain available, including 54 unavailable recipes; zero verified Carnival nutrition sets are claimed. The ordinary offline guide, meal calculations, remote controls and Trio receiver are unchanged.

Photos are redrawn to at most 1280 pixels on the longest side, encoded as JPEG without source EXIF/GPS, and held in memory. Only this image and the catalog fingerprint are sent to the configured service. No clinical telemetry or pairing data is attached. Cancellation discards suggestions. Accept invokes the existing food-meal callback; standard Meal confirmation/authentication remains separate. This feature has no treatment transport.

## Provider assessment

OpenAI Responses supports image input and structured JSON output: https://developers.openai.com/api/docs/guides/images-vision and https://developers.openai.com/api/reference/resources/responses/methods/create . The supplied server defaults to `gpt-4.1-mini`, configurable with `OPENAI_MODEL`; live availability/accuracy have not been verified in the user's account. A photograph cannot establish exact mass, hidden ingredients, sauces or carbohydrate reliability; all suggestions require review.

Apple's latest Foundation Models documentation describes multimodal prompting (https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting). However, the installed Xcode 26.1.1 iPhoneOS 26.1 FoundationModels Swift interface exposes text Prompt inputs and no ImageAttachment interface. This project supports iOS 18+. Apple image understanding is therefore not an implemented, tested option for this toolchain/deployment target. Do not claim it is impossible on newer SDKs. OCR/classification alone is insufficient for this catalog/portion task.

## Secure server package

`server/plate-scanner/worker.mjs` is a Cloudflare Worker with an authenticated `/scan` POST route, bounded JPEG input, exact catalog fingerprint, server-side catalog prompt, strict structured output, validated catalog IDs/portions, no request-body logging, no persistence, and no automatic retries. `store:false` is sent to OpenAI; this does not assert zero provider retention. Provider policy still applies. The client refuses HTTP, URL credentials/query secrets and redirects, uses ephemeral networking, and stores its service access token in device-only Keychain.

Server deployment requires an owner-controlled Cloudflare account and an OpenAI API project with billing/credits. ChatGPT subscription access alone does not configure this API. Neither account was supplied; no live provider test or deployment has occurred. The final credentials/account activation require the account owner. Do not put secrets in source, chat, GitHub artifacts, app bundle or UserDefaults.

When accounts are available, an operator should use `wrangler secret put OPENAI_API_KEY` and `wrangler secret put SCANNER_ACCESS_TOKEN` (at least 32 random characters), then `wrangler deploy` from this server directory. Configure the resulting HTTPS `/scan` URL and separate access token in Scanner setup. OpenAI key stays server-side. Keep account spending limits/alerts and the supplied five-requests-per-minute Cloudflare binding enabled; the service token is revocable. This is a private family deployment, not a multi-user authentication platform.

## Verification

`bash Scripts/test-plate-scanner.sh` runs seven pure Swift/transport tests and six mocked server tests without live API or pump access. The SmartMealUI synthetic scanner test exercises the real Advisor → guide → scanner → Advisor route, including unresolved blocking, explicit review, Add/Remove, immediate +/- totals and the accepted catalog total. A separate manual regression test checks scanner cancellation and offline half-bagel entry into Advisor using empty treatment credentials. No physical camera or live recognition accuracy is established by these tests. Full build/UI outcomes are recorded in the final delivery report, not inferred from source presence.

No previous `optional_plate_scanner.zip` was found in this workspace or temporary-file search. A new patch/archive is generated from the validated commit for delivery; it must not be represented as the earlier claimed package.

Verified locally on October 18, 2026 with Xcode 26.1.1:

- Seven Swift model/transport tests passed; six mocked server tests passed.
- Cloudflare Wrangler 4.151.1 deployment dry-run passed, without credentials or deployment.
- `CarnivalManualUITests/testManualHalfBagelStillFillsAdvisorAfterCancellingScanner` passed in UI4, with 26 g in the real Advisor field.
- `SmartMealHandoffUITests/testOptionalScannerRequiresReviewAndUnknownResolution` passed in UI6, exercising real nested-sheet acceptance, unknown blocking, Add/Remove, 26→39→26 g changes and return to the real Advisor.
- UI testing found and fixed overlapping row navigation and a stale index-backed binding crash after deletion. Food rows now resolve bindings by stable UUID, including a safe fallback for deleted rows retained by Form animations/accessibility.
- Final app/test compile succeeded for the arm64 iOS 26.1 simulator. No physical camera, live OpenAI image recognition or clinical outcomes were tested.

Physical iPhone installation and TestFlight publication are coordinated separately by the primary “Complete LoopFollow development” chat. Do not infer installation from this branch's build number 22. Existing TestFlight release 21 and the father's Trio 1.0.2 (9) are not changed by a source commit.
