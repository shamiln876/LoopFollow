# Carnival food guide integration

Feature branch: `feature/carnival-food-guide`, based on the tested meal-review/history implementation at `2757c5d`.

## Intended experience

1. Search a food by name or venue in LoopFollow.
2. Select the matching guide entry and confirm the listed base portion.
3. Choose the amount eaten: a fraction of that portion, a piece count when the base is one piece, using the exact base portion printed in the guide.
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

The supplied 153-page PDF has been extracted into the bundled `CarnivalFoodGuide.json` resource. All 1,085 IDs, 30 venue counts, 1,031 estimates, 54 missing recipes and 79 source references were checked. The source PDF SHA-256 is `fbf12613fa1574124e834424e077f7ea69b1af3615f0ab2645cb03e3e1074aa8`. Each entry retains its source page, ID, printed portion, printed rounded nutrients, planning range and source notes. Search and plate-building UI are implemented; compilation, testing and installation status are reported separately.

The PDF remains unchanged. `tools/extract_carnival_pdf.py` reproduces the application resource and fails on count/layout inconsistencies. PDF values are rounded; displayed net carbs are retained independently rather than reconstructed from rounded total carbs/fibre. Ingredient-model weights and meal-category fields from the original JSON are not recoverable from this PDF, so this version uses base-portion multipliers and venue/name search. It does not guess a grams-to-serving conversion. Food selections populate only the existing comparison input; manual carb edits clear linked food provenance. Food IDs, portions, source fingerprint and nutrient estimates are included in local review history.

## Verification

- The extractor and bundled-resource tests check all record counts, unique IDs, missing nutrients and estimate labels.
- Tests cover fractional servings, piece counts, mixed plates, incomplete totals, invalid quantities, malformed catalogs, matching source provenance and legacy history decoding.
- Search tests use actual guide entries, word/venue filters, accents and unmatched queries. Food selection is explicit; free-text matches do not invent foods or portions.
- Verify that selecting food-derived carbs updates only the intended meal review and records its provenance.
- Initial full simulator suite: 147 Swift Testing tests plus 2 existing presentation tests passed. Final focused run: 13 food/history tests plus 2 new presentation tests passed. Normal food search and accessibility plate captures were inspected. Signed build and iPhone installation status are recorded in the delivery report.
