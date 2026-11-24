# The source dataset

What the loader and the app rely on about the English Prescribing Dataset (EPD) with SNOMED Code, checked on 22 and 23 November 2026 against the portal's metadata, its SQL API and one downloaded month (September 2026, `EPD_SNOMED_202609`). This settles the items marked **(phase 0)** in [spec.md](spec.md) (ticket P0-07).

## Source, licence and attribution

- **Dataset**: [English Prescribing Dataset (EPD) with SNOMED Code](https://opendata.nhsbsa.net/dataset/english-prescribing-dataset-epd-with-snomed-code), published by the NHS Business Services Authority (NHSBSA). CKAN slug `english-prescribing-dataset-epd-with-snomed-code`, id `906115a6-4155-44be-8b81-f8e83cebfb84`. Tagged "Experimental" on the portal.
- **Licence**: Open Government Licence 3.0 (United Kingdom), `OGL-UK-3.0`.
- **Required statement**: every reuse must include "NHSBSA Copyright 2021-2026". The year range is page text and will change, so the README and the app keep it in one place each.
- **Citation**, as the portal gives it: NHS Business Services Authority. "English Prescribing Dataset (EPD) with SNOMED Code" NHS Business Services Authority Open Data. Accessed [date]. URL: https://opendata.nhsbsa.net/dataset/english-prescribing-dataset-epd-with-snomed-code
- **Before publishing**, the portal asks reusers to contact NHSBSA's data services team, quoting the dataset name, so the figures are not misunderstood. This is a request, not an approval step; it is a task in P6-02, before the app goes live.
- **Documentation**: there is no separate data dictionary file. The authoritative column definitions are each resource's `schema` (shown as "Data Dictionary" on the resource page). The package-level `tableschema` is stale and malformed. The "English Prescribing Dataset Release Guidance" v004 adds context but is partly out of date (it still describes 42 ICBs).
- **Scope** (from the dataset notes): prescriptions issued in England and dispensed in the community, including items prescribed under hospital cost-centre codes. Excluded: dental prescribing, supplies under Patient Group Directions (for example Pharmacy First), items prescribed under hospital site codes, private prescriptions, and items not dispensed or not submitted.

## Publication

- One CSV resource per month, named `EPD_SNOMED_YYYYMM`, from 202011. The newest is 202609 (created 2026-11-20). Months are published around the 20th, two months after the month they cover.
- Resource ids are random, so a month is found by its name in `package_show`, never by building a URL.
- `last_modified` is empty on recent resources; `created` is the publication time.
- Months can be re-published: `EPD_SNOMED_202311` was refreshed on 2026-01-14 "due to upload error". Each resource carries a `sha256`, which changes when the file does. The loader records it and reloads a month whose hash has changed.

## Files and download

| | CSV (`url`) | ZIP (`zip_url`, non-standard field) |
| --- | --- | --- |
| Size, 202609 | 7,701,102,484 bytes | 666,467,200 bytes (11.6 times smaller) |
| Link | Redirects to a storage link signed for 15 minutes; supports HTTP range requests, so downloads can resume | Signed link valid for one hour, refreshed on every `package_show` call; GET only |
| Integrity | `sha256` published | No size or hash published, but the CSV inside has the CSV's `sha256` |

**Decision.** Download the ZIP, fetching `package_show` again just before each attempt, and stream it with `bsdtar -xOf` (libarchive). Ubuntu's `unzip` 6.0 cannot read these archives: the entry needs "version 6.3 to extract", and `unzip -p` then writes nothing and still exits with status 0, so a pipeline would silently load an empty month. `bsdtar` extracted the 202609 CSV in about 18 seconds, and the SHA-256 of the extracted stream equalled the resource's published `sha256`. The loader checks that equality on every load. If a month has no `zip_url`, it downloads the CSV instead (same check). The download of the 202609 ZIP took 112 seconds on a home connection.

The image needs `libarchive-tools` for `bsdtar`; it is added with the loader (P1-05).

## File format

- UTF-8 without a byte-order mark, comma-separated, CRLF line endings, one header line.
- In the header, the 21 text column names are quoted and the 6 numeric ones are not.
- In data rows every field is quoted except `ITEMS`, an unquoted integer. Numeric fields are quoted text with a trailing decimal point for whole numbers (`"60."`, `"0."`) and a leading zero for fractions (`"0.75199"`). PostgreSQL's `numeric` accepts these; `integer` would not.
- Empty values are written as `""`, which `COPY ... CSV` loads as an empty string, not NULL. The loader converts them to NULL.
- About 45% of rows have commas inside quoted fields (addresses, ICB names, `"12: Ear, Nose and Oropharynx"`), so the file must go through a real CSV parser (`COPY ... WITH (FORMAT csv, HEADER true)`).
- 27 columns, listed with their definitions and how they are loaded in [`inst/extdata/epd_columns.csv`](../inst/extdata/epd_columns.csv).

**Schema history.** The column names changed twice. 202011 to 202204 used STP columns; 202205 renamed them to ICB. From 202503 the BNF columns were renamed (`BNF_CODE` became `BNF_PRESENTATION_CODE`, `ADQUSAGE` became `ADQ_USAGE`, and `BNF_CHEMICAL_SUBSTANCE` changed from the code to the name) and `YEAR_MONTH` became the text `'YYYY-MM'`. In 202503 alone three measures were typed as text. Every month from 202504 has the header in `epd_columns.csv`; the rolling window (from 202510) never needs the older forms, and an older file fails the header check by design.

## Row grain

**Rows are finer than practice × presentation.** One row is a practice × BNF presentation × SNOMED product × quantity per item, with `ITEMS` counting how many items had that quantity. In 202609:

| Key | Distinct values |
| --- | --- |
| Rows | 18,395,376 |
| Practice × BNF presentation | 9,459,744 |
| Practice × BNF presentation × SNOMED code | 9,595,470 |
| Practice × BNF presentation × SNOMED code × quantity | 18,395,374 |

Even the finest key is not unique: two pairs of rows on the national unidentified practice differ only in their measures. Across all 71 months the same key repeats in 62 months (1,483 pairs), always on the national unidentified practice, and in 28 months 173 pairs are identical in all 27 columns. They are separate published rows, so the source has no natural key, and the loader never deduplicates: staging has no unique key, and the aggregation sums every row.

**Decision.** The fact table aggregates on load to one row per month × practice × BNF presentation, summing the measures. The app works at presentation level and never needs the SNOMED product or the quantity per item, and the table halves: about 9.5 million rows a month instead of 18.4 million, about 113 million for twelve months. `TOTAL_QUANTITY` can be summed within a presentation, whose unit is fixed. The load check compares row counts and sums against staging (spec §4).

Within a month, practice attributes depend only on `PRACTICE_CODE`, and the BNF and chemical attributes depend only on `BNF_PRESENTATION_CODE`, so the dimensions can be built from staging. Each SNOMED code maps to one BNF presentation, but a presentation can have several SNOMED codes, so `dim_presentation` keeps no SNOMED code.

## Measures

| Column | Facts (202609) | Stored as |
| --- | --- | --- |
| `ITEMS` | Whole numbers, 1 to 6,152 per row; sum 110,562,925 | `int4` |
| `QUANTITY` | Quantity per item, up to 2 decimals; part of the grain | Not stored |
| `TOTAL_QUANTITY` | Always `QUANTITY × ITEMS`; up to 2 decimals; unit depends on the presentation | `numeric`, summed |
| `ADQ_USAGE` | Average daily quantities; up to 5 decimals. Never blank: **0 means no ADQ is defined** (50.8% of rows; whole chapters such as dressings, and every oral anticoagulant and insulin) | `numeric`, summed; NULL where the sum is 0 |
| `NIC` | Net ingredient cost in pounds, at most 2 decimals; sum £1,040,583,068.38 | `numeric`, summed |
| `ACTUAL_COST` | Pounds, up to 5 decimals; sum £999,891,865.68296; can exceed `NIC` (32.5% of rows) | `numeric`, summed |

Exact `numeric` keeps the load check exact to the penny. No measure is ever negative or NULL.

**Trend break.** From April 2024 data, actual cost uses discount rates per product group instead of one national rate. The rolling window starts after that, but any longer series would show the break. The methods page says so.

## Prescribers and geography

- 9,308 prescriber codes in 202609. Key on `PRACTICE_CODE`, never the name: 8,777 names, and "UNIDENTIFIED DOCTORS" alone covers 121 codes.
- **Unidentified prescribers** (`UNIDENTIFIED = 'Y'`): 121 codes, 0.07% of items. One is the national code `-`, whose region, ICB and postcode are all `-` and names `UNIDENTIFIED` (60,513 items). The other 120 are pseudo-codes per commissioner, such as `52R998`, with a real ICB and region. They stay in the fact table, so national totals reconcile, and `dim_practice.is_unidentified` lets views leave them out of practice lists.
- **Non-GP prescribers** have no type column. Codes of a letter A to P plus 5 digits are mostly GP practices (95.8% of items). Codes starting with Y (4.2% of items) mix real GP practices (many APMS contracts, for example Y01008 with 109,155 items) with out-of-hours, urgent care, appliance, prison and community services. Code patterns therefore cannot define a GP practice. v2 defines one as a code that appears in NHS England's list-size file for the same month (V2-01).
- **Geography follows the commissioner**, not the location: a non-GP service can carry the ICB that commissions it, far from its postcode. Regional totals are therefore commissioning totals. The methods page says so.
- **ICBs were reorganised in April 2026**: 202603 has 42 ICBs, 202604 has 36, with six new 5-character codes (for example `Z9B2Z`, NHS West and North London). The rolling window crosses the change. `dim_practice` keeps the region and ICB of each prescriber's own last month: a prescriber still prescribing after April 2026 is shown in its new ICB for every month, while one that stopped before keeps its old ICB, which no longer exists. The seven NHS England regions did not change.
- Addresses and postcodes are empty strings for 57 identified prescribers (0.01% of items), mostly closed or merged practices.

## BNF codes

- Chapters 01 to 19: 15-character presentation codes and 9-character chemical codes. Appliance and dressing chapters 20 to 23: 11-character presentation codes and 4-character chemical codes (for example `2003`). `dim_chemical` therefore uses the source's `BNF_CHEMICAL_SUBSTANCE_CODE`, not the first 9 characters of the presentation code.
- Characters 10 and 11 of a 15-character code identify the product: `AA` is generic. Appliance codes do not follow this rule, so `is_generic` is NULL for chapters 20 to 23.
- 21,565 presentations and 1,790 chemical substances in 202609. The codes follow the NHSBSA's version of the BNF classification as it was before BNF edition 70.

## v2 groups: findings to review in V2-03

The planned BNF prefixes (spec §10) were checked against 202609. Each captures its intended drugs, but several also capture things the group does not mean, and one group cannot use ADQ. These are proposals for V2-03, where the final list is reviewed.

| Group | Finding | Proposal |
| --- | --- | --- |
| Lipid lowering (`0212`) | Every lipid-regulating drug, including inclisiran and the PCSK9 injectables. Bile-acid sequestrants (39,664 items) are mostly used for bile-acid diarrhoea and pruritus. ADQ is defined for 98.4% of items | Optionally exclude `0212000F0`, `0212000AD`, `0212000K0`, `0212000J0` |
| Antihypertensives (`0204`, `020505`, `020602`, `0202`) | `0202` is 42% loop diuretics and 23% aldosterone antagonists, mostly heart failure and oedema; only `0202010` (thiazides) is mainly antihypertensive. `0204` includes propranolol (732,696 items, mostly anxiety, migraine and tremor) and sotalol. `020505` includes sacubitril/valsartan (181,596 items, heart failure only, no ADQ). Doxazosin (`0205040D0`, 675,521) and moxonidine are left out | Use `0202010` rather than `0202`; exclude `0204000R0`, `0204000T0` and `0205052AE`; decide on doxazosin |
| Oral anticoagulants (`020802`) | Includes INR test strips (`0208020W0`, 2,879 items) and pentosan polysulfate (`0208020I0`, 125). ADQ is 0 for every item | Exclude both; outcome items (as planned) |
| Insulins (`060101`) | All insulins; ADQ is 0 for every item. Insulin glargine/lixisenatide (`0601012AB`) sits here, while insulin degludec/liraglutide (`0601023AU`) sits in `060102` | Outcome items (as planned); decide where the combinations go |
| Non-insulin antidiabetics (`060102`) | **ADQ is 0 for 44.4% of items** (SGLT2 inhibitors, several DPP-4 inhibitors, GLP-1 drugs). All GLP-1 and dual-agonist products, weight-management brands included, are coded here; none are in `0405` (obesity). Dapagliflozin and empagliflozin are also licensed for heart failure and kidney disease | **Outcome items, not ADQ.** Flag the GLP-1 family (`0601023AW`, `AB`, `AQ`, `Y0`, `AI`, `AU`, `AZ`, `BA`) as a subgroup |
| Inhaled bronchodilators (`0301`) | 95.4% handheld inhalers; also theophylline (`0301030`, 36,321 items), ephedrine (`0301012`) and nebuliser or oral salbutamol and terbutaline | Exclude `0301030` and `0301012`; nebuliser and oral forms need a name or route rule |
| Inhaled corticosteroids (`0302`) | All respiratory corticosteroids. ADQ is 0 for 62.6% of items, and one product (WockAIR 160/4.5) inflates the section's ADQ by about 35% | Outcome items (as planned) |

**GLP-1 drugs for weight management** can be told apart only partly, by presentation code: Wegovy, Saxenda and the weight-licensed liraglutide brands have their own codes (for example `0601023AWBD…` for Wegovy), but tirzepatide (Mounjaro and generic, 377,396 items, 65% of the family) uses the same presentations whatever the licence, and so does orforglipron. Characters 10 and 11 of a presentation code are the brand, and characters 14 and 15 the strength of the generic equivalent, which gives this rule for the GLP-1 family (checked on 202609; V2-03 reviews it, and new presentations need adding as they appear):

| Label | Presentations | Items, 202609 |
| --- | --- | --- |
| Weight | Brands Wegovy (`0601023AWBD…`), Saxenda (`0601023ABBC…`), Nevolat (`0601023ABBD…`), Biolide (`0601023ABBG…`) and Plaobes (`0601023ABBH…`); generic semaglutide strengths that exist only as Wegovy: `0601023AWAAAGAG`, `…AWAAAHAH`, `…AWAAAIAI`, `…AWAAAJAJ`, `…AWAAAPAP`, `…AWAAAQAQ`, `…AWAAARAR` | 2,782 |
| Ambiguous | Tirzepatide (`0601023AZ`) and orforglipron (`0601023BA`), whose presentations serve both licences; generic semaglutide strengths shared by Ozempic or Rybelsus and Wegovy (`0601023AWAAABAB`, `…AWAAAKAK`, `…AWAAALAL`, `…AWAAAMAM`); generic liraglutide (`0601023ABAAAAAA`) | about 400,500 |
| Diabetes | Everything else in the family: Ozempic, Rybelsus, Victoza, Zegluxen, Diavic, dulaglutide, exenatide, lixisenatide, Xultophy; and Suliqua, though it is coded with the insulins (`0601012AB`) | 175,501 |

EPD has no indication field, so heart failure, kidney and weight-management use of shared drugs is a stated limitation of the model.

## Reference totals for 202609

For the load check on a real month (P1-09):

| Measure | Value |
| --- | --- |
| Source rows (lines in the CSV, header excluded) | 18,395,376 |
| Practice × presentation rows after aggregation | 9,459,744 |
| Items | 110,562,925 |
| NIC | £1,040,583,068.38 |
| Actual cost | £999,891,865.68296 |
| Total quantity | 8,778,983,306.46 |
| ADQ usage | 2,442,227,120.64017 |
| Prescriber codes / presentations / chemical substances | 9,308 / 21,565 / 1,790 |
| CSV SHA-256 | `5f9dcebaccaa3bce6bdfd5f6d609609e6b8ffaaa9cb1d649c7bde9f85b367841` |

The last twelve months (202510 to 202609) hold about 218.5 million source rows.

## Checking the data without downloading it

The portal's `datastore_search_sql` endpoint runs BigQuery SQL on each month (table name in backticks, for example `` `EPD_SNOMED_202609` ``). Besides `sql`, it needs the month's resource name as `resource_id` (`EPD_SNOMED_202609`), or it answers 400 with "resource_id is mandatory". Results are in `result.result.records`. Aggregate queries over a whole month return in seconds. Numeric values come back as JSON numbers, so exact sums need `CAST(SUM(x) AS STRING)`. The portal's terms discourage bulk extraction through the API: the loader downloads files.
