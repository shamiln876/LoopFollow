# Carnival food guide integration

Feature branch: `feature/carnival-food-guide`, based on the tested meal-review/history implementation at `2757c5d`.

## Intended experience

1. Search a food by name, venue or meal category in LoopFollow.
2. Select the matching guide entry and confirm the listed base portion.
3. Choose the amount eaten: a fraction of that portion, a piece count when the base is one piece, or grams when a usable reference weight exists.
4. Build a plate from multiple entries and inspect its estimated total carbohydrates, protein, fat and available planning range.
5. Explicitly use the total-carbohydrate estimate in the existing Smart Meal Advisor. Preserve the current calculation checks, historical-setting labels, independent manual controls and review history.

Search and portion arithmetic should run locally after the guide is imported. No language-model request or internet connection is needed for those operations. Live Trio data still require the existing connection.

## Original source

The existing Carnival Mardi Gras guide was prepared for the October 24, 2026 sailing using 2024–2026 menu research. Its original chat reports 1,085 entries: 1,031 entries with estimated macros and 54 unresolved recipes. It explicitly reports zero verified Carnival prepared-dish macro sets. These counts must be checked against the actual imported dataset.

The original package contains:

- `food-data.json`: full records and recipe/portion assumptions; preferred integration input.
- `guide-metadata.json`: research methodology and references.
- `Mardi_Gras_Food_Data.csv`: tabular export.
- `Mardi_Gras_Offline_Food_Guide.html`: embedded database and offline guide.
- `Mardi_Gras_Food_Guide.xlsx`: spreadsheet/database and plate calculator.

The source records use `id`, `venue`, `name`, `meal`, `portion`, `weight`, `c` (total carbohydrate), `fi` (fibre), `p` (protein), `f` (fat), `k` (energy), `low`, `high`, `nutrition`, `evidence`, `period`, `flags`, `assumptions`, `notes`, `source` and `ingredients`.

## Data and arithmetic requirements

- Keep menu evidence separate from nutritional reliability. A verified menu item does not imply verified macros.
- Multiply nutrient values and available planning bounds by the selected base-portion quantity. Display the original base portion beside that quantity.
- Use total carbohydrate for the existing review input. Display net carbohydrate separately; never substitute it automatically.
- Missing recipes or nutrients remain unavailable. Never count an unresolved food as zero carbohydrate or present an incomplete plate as a complete total.
- Treat planning ranges as source assumptions, not measured confidence intervals or guaranteed bounds.
- Preserve quarter-plate assumptions verbatim. Plate area alone does not establish food volume or weight.
- Require confirmation for ambiguous food matches and portions. Unmatched typed text must not produce invented nutrient values.
- Record chosen food IDs, quantities, source version/fingerprint and estimation labels alongside a food-derived meal review.
- Food selection does not establish clinical dosing accuracy or introduce calculated insulin delivery.

## Current status

The feature branch and source review are prepared. The project mirror's `sources/` directory is empty, and the guide's generated files are in the original cloud chat/Library rather than this Mac. The actual dataset has not been imported, bundled, tested or installed in LoopFollow. No food-search interface or food-derived recommendation is claimed as implemented.

The original complete package, JSON or HTML is needed to finish the integration without recreating or inventing the database. Keep synced source files read-only and work from a derived application resource.

## Required verification after the source is available

- Check record count, unique IDs, missing nutrients and the guide's estimate labels.
- Test fractional servings, per-piece quantities, gram conversions, mixed plates and incomplete totals.
- Test food search and ambiguous matches against real guide entries.
- Verify that selecting food-derived carbs updates only the intended meal review and records its provenance.
- Compile and test the app, inspect normal/accessibility layouts, and verify offline lookup on the iPhone before reporting completion.
