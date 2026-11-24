# Benchmarks

Measurements of the loader and, from phase 2, of the app's queries (spec §6.3). Until the server arrives in P6-02, everything runs in the local Docker stack, on the machine below.

**Units.** Database and disk sizes are in PostgreSQL's units, 1 GB = 1,024 MB, which is also what Windows and `df -h` show. The sizes of the portal's files, ZIP and CSV, are in millions of bytes, as the portal and the loader's messages give them.

## At a glance (P2-06)

The full window, 202510 to 202609, in the local Docker stack on the machine below, 24 November 2026:

| | |
| --- | --- |
| Source rows | 218,504,372: for every month, the count, items, NIC and actual cost equal the portal's |
| Fact rows, one per month × prescriber × presentation | 112,769,791 |
| Fact table with its two covering indexes | 21,151 MB (20.7 GB) |
| The database | 21,445 MB (20.9 GB), 47 MB more than after the load (P2-02), for P2-05's indexes |
| Loading a month | 175 s, the mean of P2-02's eleven loads, 48 s of it downloading; 171 s (122 s without the download) leaving out the two months that tests slowed. Measured before P2-05 added the vacuum of the rollups after each swap |
| The swap's transaction, the only step the app can wait for | about 1 s; the rollups are vacuumed after it, without blocking the app |
| App queries, warm | Every check under 50 ms: the slowest, a two-letter search, takes 33 ms, and 13 of the 21 under 1 ms |
| Fact table | Read only by index-only scans of the months asked for, with no heap fetches |

## Machine (P1-08)

| | |
| --- | --- |
| Host | Windows 11 Pro, 137 GB of memory, 732 GB free on the system drive (23 November 2026) |
| Docker | Docker Desktop with WSL 2. Its virtual machine has 16 CPUs, 100 GB of memory and 32 GB of swap (`.wslconfig`). Its virtual disk grows on the system drive, which is the real limit on space |
| PostgreSQL | 18.7 (`postgres:18.7-trixie`) in the Compose stack |
| R | 4.6.1, in the `rstudio` container, which runs the loads |

## Database settings

`docker/db/postgresql.dev.conf` (the default) suits a laptop. `docker/db/postgresql.full.conf`, selected with `PREXP_DB_CONFIG=full` and `PREXP_DB_SHM_SIZE=8gb`, is sized for the machine above and the full window:

| Setting | dev | full | Why |
| --- | --- | --- | --- |
| `shared_buffers` | 1GB | 16GB | The hot indexes of twelve months stay in PostgreSQL's cache |
| `effective_cache_size` | default (4GB) | 48GB | What the planner may assume the kernel caches |
| `work_mem` | 64MB | 64MB | Per sort or hash in each query; the app's queries are small |
| `maintenance_work_mem` | 1GB | 4GB | Index builds and `VACUUM` of a 9.5-million-row month |
| `max_wal_size` | 8GB | 32GB | Fewer checkpoints while a month loads |
| `checkpoint_timeout` | default (5min) | 15min | Same |
| `wal_compression` | off | lz4 | Smaller full-page images in the write-ahead log |
| `random_page_cost` | default (4) | 1.1 | Solid-state disk |
| Parallel workers | defaults (8, 2 per query) | 16 processes, 12 workers, 4 per query, 4 for maintenance | 16 CPUs |
| `/dev/shm` | 1 GB | 8 GB | Parallel queries share memory through it |
| `jit` | off | off | Compilation costs more than it saves on short queries |

### Tuned against the twelve months (P2-05)

On 24 November 2026 `check_plans()` was run against the full window with samples picked from the data as the worst cases: the chemical with the most presentation rollup rows (2003, wound management and dressings, 89,282 rows), the practice with the most prescribing rows (B83033), and for each search the two characters that start the most names' words. Two queries failed:
- **Common two-letter drug searches** took 40 to 67 ms. 'le' alone matches 14,199 names, since every "tablets" contains it.
- **`drug_presentations` for the largest chemicals** took 60 to 100 ms.

Five changes fix them and widen the margin elsewhere:

- **Migration 008, a `text_pattern_ops` index on each code.** With the trigram index on the name, every search is a `BitmapOr` of index scans in a plan made with the value, not a scan of the dimension. The collation is not C, so the codes' unique indexes cannot serve `LIKE 'ABC%'`.
- **Migration 008, `app.v_practice_presentation` with a `LEFT JOIN`.** The planner removes that join when no presentation column is used. With the inner join, it probed the presentations for every fact row: 50,000 for the largest practice, with a hash join in a custom plan and row by row in a generic one.
- **Migration 009, the presentation rollup's primary key carries its measures.** A chemical's presentations become an index-only scan of their rollup rows, in key order, instead of one heap page each. Index-only scans need the visibility map set, so the loader now vacuums the three rollups after each swap.
- **Two characters match the start of a word.** Two characters match a name that starts with them or has a word, after a space, that does; three or more match anywhere, as before. The search contract is two characters or more, which the app already enforces (spec §5.4). pg_trgm still uses the trigram index for a word start, but nearly every name contains a pair of letters, which `similarity()` then had to rank.
- **`similarity()` only for names that contain the text.** A match by code alone scores 0 without it. A code prefix such as '23' matches thousands of appliances by code, and ranking them took 37 ms; it now takes about 10.

| Query (sample) | Before (ms) | After (ms) |
| --- | ---: | ---: |
| `search_drugs` ('le') | 60 | 13 |
| `search_drugs` ('co', the most word starts) | 41 | 33 |
| `search_drugs` ('pitolisant') | 13.5 | 0.4 |
| `search_practices` ('N81655') | 3.3 | 0.2 |
| `drug_presentations` (2003, twelve months) | 98 | 25 |
| `practice_top_drugs` (B83033, twelve months) | 22.7 | 14.1 |
| The same as a generic plan | 40.2 | 16.1 |

"Before" is one run, or the median of five for 'le', 'co' and 2003; "after" is the median of five. The worst three-letter searches, such as 'sto' and 'tom', take about 30 ms and are unchanged. They are over 5,000 appliance names with "stoma" or "colostomy" in them.

Every check now passes with a plan made with the values, as the app's are; [The app's queries](#the-apps-queries-p2-06) has the time and plan of each.

The slowest single run was 41.6 ms, the search 'co', whose median is 33 ms.

**Generic plans.** They still prune partitions when the plan starts: the small top-drugs sample reads 3 partitions, and the other 9 are removed. But a generic plan cannot use the trigram or prefix indexes, and it rebuilds the search patterns for every row, so the searches are slower that way: 'co' takes 49 ms, at the limit. `check_plans(generic = TRUE)` is for checking pruning and index-only reads, and its search times are not the app's: RPostgres sends unnamed statements, which the server plans with the values.

**Settings.** Each planner setting was then changed in turn. The 21 checks were timed three times each, and their plans compared by shape:

| Setting changed | Sum of the 21 medians (ms) | Plans that differ |
| --- | ---: | --- |
| None: the full settings above | 114.1 |  |
| `max_parallel_workers_per_gather = 0` | 120.6 | none |
| `max_parallel_workers_per_gather = 2` | 120.2 | none |
| `work_mem = '4MB'` | 120.9 | 1: `drug_presentations` (large) gets a one-worker parallel plan |
| `work_mem = '16MB'` | 111.5 | 1: the same |
| `work_mem = '256MB'` | 109.0 | none |
| `random_page_cost = 4` | 109.2 | 8, among them the search and the series |
| `effective_cache_size = '4GB'` | 108.8 | none |
| `jit = on` | 120.9 | none |

No setting changed a time beyond noise: the sums stayed between 109 and 121 ms, about the run-to-run spread. None made a check fail.
- **What the time goes on.** CPU work on pages already in shared buffers, which these settings do not touch:
  - the searches' `similarity()`;
  - a chemical's presentations: 2,068 index-only probes and the hash aggregate of 89,282 rollup rows for the largest;
  - a practice's top drugs: the hash aggregate of 49,902 fact rows for the largest;
  - the scan and sort of the 10,230 practices behind `app.v_region`, about 7 ms of every region comparison.
- **Parallel workers.** No app plan uses them at the settings above. Below 64MB of `work_mem`, `drug_presentations` (large) takes a one-worker parallel plan, in about the same time, which P6-02 should know.
- **`work_mem`.** The largest hash, the top drugs of the largest practice, reports 9.5 MB at 64MB, because PostgreSQL counts whole memory blocks, whose size grows with the limit. At 4MB the same hash reports 6.7 MB and still fits in hash memory (8 MB, with `hash_mem_multiplier` 2), in one batch.
- **JIT.** No app query costs enough to trigger it.

So the settings stay as they are: they serve the loads and keep the indexes cached, and P6-02 derives the server's from them. The search keeps the least margin, about 33 ms on this machine, and requiring three characters would not help, since the worst three-letter searches cost about the same. If the server's cores are much slower, the lever is to rank fewer names with `similarity()`.

## One month (P1-09)

The real September 2026 month (`EPD_SNOMED_202609`), loaded on 23 November 2026 into the empty `prexp` database with `Rscript -e "prexp::load_month(202609)"` and the full settings, downloading the ZIP. For comparison, the same load of the same file with the laptop settings, from a ZIP already downloaded.

| Step | Full settings (s) | Laptop settings (s) |
| --- | ---: | ---: |
| Find the month on the portal | 0.3 | |
| Download (a ZIP of 666.5 million bytes) | 223.1 | |
| Check the header | 0.0 | 0.0 |
| Stage: stream 7.7 billion bytes of CSV into `raw.epd_staging` | 30.4 | 30.8 |
| Check the staged month | 1.7 | 1.5 |
| Dimensions, in temporary tables | 7.5 | 10.8 |
| Build: aggregate to practice × presentation | 30.0 | 29.9 |
| Build: the two indexes | 7.1 | 8.3 |
| Build: `VACUUM (ANALYZE)` | 0.3 | 0.3 |
| Build: the month's rollup rows | 18.8 | 19.9 |
| Check against staging | 13.9 | 16.4 |
| Swap: the only step the app can ever wait for | 1.0 | 1.2 |
| Clean | 0.6 | 0.5 |
| **Total** | **335** (112 without the download) | **120** |

The download depends on the connection: the same ZIP took 112 s in P0-07. The full settings change little for one month, since each step is one large query. Nor do the planner settings change the app's queries over the twelve months ([P2-05](#tuned-against-the-twelve-months-p2-05)); `shared_buffers` keeps their indexes cached.

Every total matches the reference figures in [dataset.md](dataset.md#reference-totals-for-202609): 18,395,376 source rows, 9,459,744 rows after aggregation, 110,562,925 items, NIC £1,040,583,068.38, actual cost £999,891,865.68296, total quantity 8,778,983,306.46, ADQ usage 2,442,227,120.64017, and 9,308 prescribers, 21,565 presentations and 1,790 chemical substances.

### Sizes

| Object | Size | Per fact row |
| --- | ---: | ---: |
| `core.prescribing_202609` | 639 MB | 71 bytes |
| `prescribing_202609_presentation_idx` | 600 MB | 67 bytes |
| `prescribing_202609_practice_idx` | 533 MB | 59 bytes |
| The month in all | 1,772 MB | 196 bytes |
| The month's rows in the three rollups | 17 MB | |
| The three dimensions, with their indexes | 19 MB | |
| `raw.epd_staging` at its peak, while the month loads | 7,144 MB | |
| Write-ahead log at its peak during the load | 1,520 MB | |
| The database at its peak during the load | 8,946 MB | |
| The database after the load | 1,816 MB | |

A practice's month through `app.v_practice_presentation` is an index-only scan with no heap fetches, in 0.7 ms.

### Twelve months

The window holds about 218.5 million source rows, 18.2 million a month on average (dataset.md), so this month is typical:

| | Size |
| --- | ---: |
| Twelve months of fact table and indexes (12 × 1,772 MB) | 20.8 GB |
| Their rollup rows and the dimensions | 0.2 GB |
| While a month loads: staging, the month being built beside the live one, the write-ahead log and the ZIP | 10.8 GB |
| **Peak** | **about 32 GB** |

Docker's virtual disk had 835 GB free, and the host drive 732 GB, which is the real limit: the peak is about 4% of it, far under the 70% at which P2-02 would wait for more disk.

## Twelve months (P2-02)

The window's other eleven months, 202510 to 202608, were loaded on 24 November 2026 into the database that held 202609. The command was `Rscript -e "prexp::load_window(12)"` in the `rstudio` container, with the full settings. `load_window()` loads the missing months oldest first, as they were published, and none was dropped: the window had room for all eleven. It took 32.1 minutes, 175 s a month: 48 s to download each ZIP and 127 s to load it.

| Month | ZIP (million bytes) | Source rows | Fact rows | Download | Stage | Dimensions | Aggregate | Indexes | Rollups | Check | Swap | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 202510 | 672.1 | 18,453,220 | 9,495,962 | 50.8 | 34.0 | 8.2 | 31.7 | 6.6 | 21.7 | 15.3 | 1.1 | 173 |
| 202511 | 651.8 | 17,896,076 | 9,278,254 | 48.3 | 32.3 | 8.2 | 30.9 | 6.9 | 20.4 | 14.5 | 1.0 | 166 |
| 202512 | 671.9 | 18,452,674 | 9,481,683 | 51.2 | 34.5 | 7.9 | 31.2 | 7.3 | 22.3 | 15.6 | 1.2 | 176 |
| 202601 | 666.1 | 18,342,436 | 9,454,265 | 48.0 | 35.0 | 7.8 | 32.2 | 6.9 | 24.1 | 16.0 | 1.0 | 174 |
| 202602 | 643.9 | 17,721,345 | 9,213,606 | 47.9 | 31.6 | 7.3 | 29.8 | 6.9 | 19.2 | 13.7 | 1.0 | 160 |
| 202603 | 666.4 | 18,364,409 | 9,472,482 | 49.5 | 32.4 | 7.8 | 30.1 | 7.3 | 23.3 | 15.2 | 1.0 | 171 |
| 202604 | 657.7 | 18,148,307 | 9,366,597 | 48.7 | 32.6 | 8.2 | 30.9 | 6.6 | 21.1 | 15.2 | 1.1 | 167 |
| 202605 | 653.1 | 18,000,093 | 9,317,268 | 48.9 | 32.3 | 7.6 | 30.5 | 6.7 | 21.9 | 16.7 | 1.1 | 169 |
| 202606 | 666.3 | 18,374,449 | 9,475,283 | 45.5 | 35.7 | 8.2 | 44.3 | 10.6 | 27.8 | 17.8 | 1.4 | 196 |
| 202607 | 675.1 | 18,601,776 | 9,550,654 | 45.3 | 36.3 | 9.6 | 34.2 | 7.6 | 24.6 | 17.0 | 1.2 | 181 |
| 202608 | 644.2 | 17,754,211 | 9,203,993 | 48.3 | 30.4 | 36.2 | 30.0 | 6.5 | 21.5 | 15.3 | 1.1 | 192 |
| **Mean** | 660.8 | 18,191,727 | 9,391,822 | 48.4 | 33.4 | 10.6 | 32.3 | 7.3 | 22.5 | 15.7 | 1.1 | 175 |

Steps are in seconds. Finding the month, checking the header, checking the staged month, `VACUUM` and cleaning up each take about 2 s or less; the table leaves them out, but the total includes them. Tests ran against the same PostgreSQL server throughout the load; they visibly slowed 202606 and 202608, by 20 to 30 s. Without those two, a month took 171 s, 122 s without the download.

### Every month matches the portal

`load_log` shows the twelve months as `loaded`, and `app.v_window` shows 202510 to 202609, 12 months. For each month, the rows staged (`load_log`), and the items, NIC and actual cost summed from the fact table, equal the portal's own figures exactly. Those come from one aggregate query per month through the portal's SQL API (see [dataset.md](dataset.md#checking-the-data-without-downloading-it)):

| Month | Source rows | Fact rows | Items | NIC (£) | Actual cost (£) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 202510 | 18,453,220 | 9,495,962 | 114,940,153 | 1,050,423,761.25 | 993,687,466.98385 |
| 202511 | 17,896,076 | 9,278,254 | 102,909,621 | 918,390,084.38 | 872,635,862.34615 |
| 202512 | 18,452,674 | 9,481,683 | 112,584,291 | 988,675,308.52 | 941,476,684.33482 |
| 202601 | 18,342,436 | 9,454,265 | 108,270,468 | 946,909,253.35 | 904,922,906.47898 |
| 202602 | 17,721,345 | 9,213,606 | 99,540,567 | 873,773,110.19 | 836,095,347.96439 |
| 202603 | 18,364,409 | 9,472,482 | 108,935,496 | 959,243,011.88 | 918,230,263.41927 |
| 202604 | 18,148,307 | 9,366,597 | 106,667,509 | 946,791,809.46 | 906,736,725.22058 |
| 202605 | 18,000,093 | 9,317,268 | 104,152,360 | 938,136,598.43 | 900,092,569.97049 |
| 202606 | 18,374,449 | 9,475,283 | 109,213,199 | 997,308,762.63 | 957,516,334.18546 |
| 202607 | 18,601,776 | 9,550,654 | 113,369,726 | 1,044,634,937.47 | 1,000,555,532.15476 |
| 202608 | 17,754,211 | 9,203,993 | 102,050,994 | 943,194,933.77 | 904,525,399.92187 |
| 202609 | 18,395,376 | 9,459,744 | 110,562,925 | 1,040,583,068.38 | 999,891,865.68296 |
| **Twelve months** | **218,504,372** | **112,769,791** | **1,293,197,309** | **11,648,064,639.71** | **11,136,366,958.66358** |

### Sizes

| Object | Size | Per fact row |
| --- | ---: | ---: |
| The twelve partitions' tables | 7,626 MB | 71 bytes |
| Their practice indexes | 6,354 MB | 59 bytes |
| Their presentation indexes | 7,169 MB | 67 bytes |
| **The fact table in all** (112,769,791 rows) | **21,151 MB** (20.7 GB) | **197 bytes** |
| `core.agg_presentation_month` (1,298,136 rows) | 164 MB | |
| `core.agg_chemical_month` (136,411 rows) | 18 MB | |
| `core.agg_practice_month` (111,174 rows) | 12 MB | |
| The three dimensions (2,030 chemical substances, 26,589 presentations, 10,230 prescribers), with their indexes | 44 MB | |
| **The database after the load** | **21,398 MB** (20.9 GB) | |
| Write-ahead log | 1,664 MB | |

The fact table is 0.5% under twelve times September's 1,772 MB. These sizes are from just after the load: P2-05's indexes then added 47 MB, to the 21,445 MB in [At a glance](#at-a-glance-p2-06), most of it the presentation rollup's primary key, which now carries the measures.

**Disk use during the load.**
- **The database** peaked at 28,293 MB while 202608 loaded. That is eleven months (19,426 MB), the month being built (1,725 MB) and 202608's staged rows (6,895 MB). Staging itself peaked at 7,226 MB, while 202510 and 202512 loaded.
- **The write-ahead log** peaked at 1,664 MB.
- **Inside Docker's virtual machine**, disk use rose by up to 27.3 GB, and 19.3 GB of it remained after the load. Its virtual disk file on the host did not grow: it stayed at 246.2 GB, because the virtual machine reused space the file already held.
- **The host drive** never had less than 724 GB free.

## The app's queries (P2-06)

Each query of spec §5.2 runs with its large sample, the worst case the window holds, and its small sample, over the last three months. The times are from `check_plans()` on 24 November 2026, after P2-05: medians of five runs, warm, planning plus execution, as `EXPLAIN (ANALYZE, TIMING OFF)` measures them.
- **Custom** plans are made with the values, as the app's are: RPostgres sends unnamed statements.
- **Generic** plans are made once without the values, as for a statement prepared once.

| Query | Sample | Custom (ms) | Generic (ms) | Plan (custom) |
| --- | --- | ---: | ---: | --- |
| `window` | window | 0.12 | 0.02 | Bitmap scan of `load_log`'s index of live months; aggregate |
| `search_drugs` | large: co | 33.18 | 48.97 | On each dimension, `BitmapOr` of the trigram index on the name (pg_trgm reads the word starts in `'co%'` and `'% co%'` as padded trigrams) and the code prefix index; `similarity()` for the 5,235 names that start with 'co' or have a word, after a space, that does; top-20 sort |
| `search_drugs` | small: pitolisant | 0.44 | 17.16 | On each dimension, `BitmapOr` of the trigram index (contains) and the code prefix index; top-20 sort |
| `search_practices` | large: me | 8.07 | 11.87 | `BitmapOr` of the trigram index on the name (word starts) and the code prefix index; `similarity()` for the names; top-20 sort |
| `search_practices` | small: N81655 | 0.19 | 4.81 | `BitmapOr` of the trigram index on the name and the code prefix index |
| `drug_series_chemical` | large: 2003, 12 months | 0.11 | 0.09 | Index scan of `agg_chemical_month`'s primary key (chemical, months); grouped by month |
| `drug_series_chemical` | small: 0404000W0, 3 months | 0.08 | 0.04 | Index scan of `agg_chemical_month`'s primary key (chemical, months); grouped by month |
| `drug_series_presentation` | large: 0212000B0AAABAB, 12 months | 0.14 | 0.11 | Index-only scan of `agg_presentation_month`'s covering key (presentation, months); grouped by month |
| `drug_series_presentation` | small: 0404000W0BBAAAA, 3 months | 0.08 | 0.03 | Index-only scan of `agg_presentation_month`'s covering key (presentation, months); grouped by month |
| `drug_presentations` | large: 2003, 12 months | 24.95 | 39.58 | The chemical's 2,068 presentations by bitmap scan, each with an index-only scan of the rollup's covering key (89,282 rows); hash aggregate; sort. As a generic plan, a sort of the 89,282 rows and a group aggregate instead |
| `drug_presentations` | small: 0404000W0, 3 months | 0.16 | 0.06 | The same, for 4 presentations |
| `practice_profile` | large: B83033 | 0.03 | 0.02 | Index scan of `dim_practice`'s primary key |
| `practice_profile` | small: Y03965 | 0.03 | 0.01 | Index scan of `dim_practice`'s primary key |
| `practice_series` | large: B83033, 12 months | 0.05 | 0.03 | Index scan of `agg_practice_month`'s primary key (practice, months) |
| `practice_series` | small: Y03965, 3 months | 0.04 | 0.02 | Index scan of `agg_practice_month`'s primary key (practice, months) |
| `practice_top_drugs` | large: B83033, 12 months | 14.07 | 16.10 | Index-only scans of the practice index of the 12 partitions (49,902 rows, no heap fetches); hash aggregate of 6,419 presentations; top-25 sort; names joined to the page |
| `practice_top_drugs` | small: Y03965, 3 months | 0.60 | 0.33 | The same over the 3 partitions asked for; as a generic plan, the other 9 are removed when it starts |
| `region_comparison_chemical` | large: 2003, 12 months | 7.14 | 7.01 | Index scan of the rollup's primary key; merge left join to `app.v_region`, whose scan and sort of the 10,230 prescribers is most of the time |
| `region_comparison_chemical` | small: 0404000W0, 3 months | 8.67 | 6.92 | Index scan of the rollup's primary key; merge left join to `app.v_region`, whose scan and sort of the 10,230 prescribers is most of the time |
| `region_comparison_presentation` | large: 0212000B0AAABAB, 12 months | 7.24 | 7.18 | The same, with an index-only scan of the presentation rollup's covering key |
| `region_comparison_presentation` | small: 0404000W0BBAAAA, 3 months | 8.15 | 6.88 | The same, with an index-only scan of the presentation rollup's covering key |

Eight checks take more than a millisecond:
- **The searches over many names.** Their time is `similarity()` ranking every name the search matches. For two characters, those are the names that start with the text or have a word, after a space, that does: 5,235 drug names for 'co' and 2,626 practices for 'me', of the 7,274 and 3,029 that contain it. In a generic plan a search can use neither of its indexes, so 'pitolisant' takes 17 ms that way instead of 0.4.
- **A chemical's presentations, for the largest chemical.** It reads 89,282 rows of the rollup, index-only.
- **The largest practice's top drugs.** They read 49,902 fact rows, index-only.
- **The four region comparisons.** About 7 ms of each one's 7 to 9 ms is `app.v_region` naming the regions from every prescriber.

The other thirteen read a few rows through an index: the series and the profiles by primary key, the window, the small searches, the small chemical's presentations and the small practice's top drugs through the indexes the table names. The checks run nightly in the jobs container from P6-02 (spec §6.3), so a plan that changes as the window moves will show up there.
