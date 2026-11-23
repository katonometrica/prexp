# Test fixtures

## Monthly files

`EPD_SNOMED_202509.zip` to `EPD_SNOMED_202609.zip`: thirteen fixture months for the loader's tests, written by [`data-raw/make_fixtures.R`](../../../data-raw/make_fixtures.R), which also documents the choices below.

**Source.** NHS Business Services Authority. "English Prescribing Dataset (EPD) with SNOMED Code", September 2026 (`EPD_SNOMED_202609`). NHS Business Services Authority Open Data. Accessed 23 November 2026. https://opendata.nhsbsa.net/dataset/english-prescribing-dataset-epd-with-snomed-code

**Licence.** NHSBSA Copyright 2021-2026. Contains public sector information licensed under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).

**What they hold.** Each month has the same 3,984 rows, taken from the September 2026 file:

- every row of eight prescribers in all seven NHS England regions: five small practices and services that between them prescribe from all seven v2 groups, brands and generics of the same substances, presentations with no ADQ, two drugs no other practice prescribed and appliances; a lymphoedema service; a community service; and the unidentified prescribers of one commissioner
- 800 rows of the national unidentified prescriber (code `-`), sampled with a fixed seed, including its two pairs of rows that share every key and differ only in their measures
- one of those national rows written twice, because real months can hold rows identical in all 27 columns

**Only `EPD_SNOMED_202609` is real data.** The other twelve months repeat its rows with `YEAR_MONTH` shifted and the measures scaled by a factor between 0.8 and 1.2, so that series are not flat. They are test data, not statistics.

The files keep the source's layout exactly: the published header line, every field quoted except `ITEMS`, numbers written as the publisher writes them (`"60."`, `"0.75199"`), and CRLF line endings. Each ZIP holds one CSV and is written with fixed times and owners, so regenerating the fixtures gives identical files.
