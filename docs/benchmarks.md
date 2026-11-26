# Benchmarks

Measurements of the loader, of the app's queries (from phase 2) and of the app under load (from phase 4); see spec §6.3. Phases 1 to 5 ran in the local Docker stack, on the machine below; from P6-02 the production server is measured too. [The server, rehearsed](#the-server-rehearsed-p6-02) repeats the server's setup on four of its CPUs.

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

The app on the production server, 26 November 2026 ([One message for each lookup](#one-message-for-each-lookup-p6-02)):

| | |
| --- | --- |
| Lookups, five users, the network included | 141 ms at the median and 540 ms at the 95th percentile, against a target of 300 ms; 699 ms at the 95th percentile for the chemical with the most presentations |
| What sets the 95th percentile | Opening a session, about half a second (about 0.4 s before #125), and the lookups that wait behind it |

## Machine (P1-08)

| | |
| --- | --- |
| Host | Windows 11 Pro on an Intel Core Ultra 9 285H, a laptop processor with 16 cores; 128 GB of memory, 732 GB free on the system drive (23 November 2026) |
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

## The app under load (P4-08)

The app image as it runs in production: `prexp-app:local`, built from the tree of `main` after P4-07 (`d2e459f`), and for run 4 with the fix for #101 as well. It ran on the full database with its settings for this machine (`full`), connected as the app role only, with its two background workers. On the machine above, otherwise idle, 24 November 2026.

**The sessions**, recorded through `shinyloadtest`'s proxy:
- **`bench/recording.log`**, 1 min 43 s, ordinary lookups:
  1. Drug: search "atorva", pick Atorvastatin; change From to Jan 2026.
  2. Practice: search "N81655", pick the practice; Next, then Previous.
  3. Region: search "metformin hydro", pick Metformin hydrochloride.
- **`bench/recording-largest.log`**, 56 s, the chemical with the most presentations: 2003 Wound Management & Other Dressings, with 2,068 over the twelve months. In the Drug view: search "2003", pick it; change From to Jan 2026; change the measure to Actual cost.

**What is measured.**
- **A lookup** is a user's action and the app's messages that answer it, up to the one that brings the view's table or chart. The action can be the page's first load, a search, a pick, or a change of month, measure, tab or page. The lookup's time is the sum of its messages' waits.
- **A pick's view comes in two or three messages:** its frame, a drug's CSV link, then its table and chart. `shinycannon` times each message as it waits for it, on the same machine, from the event before it.
- **Not counted:**
  - the browser's own work between and after the messages: loading the chart and table libraries on the first pick, laying out and drawing the view;
  - a chart drawn again after the view (below).
- **A search's answer includes a wait.** The server waits 300 ms after the last keystroke before it looks anything up (spec §5.4). That pause comes before the lookup, so the figures leave it out, and also give the figure with it counted.

**The runs.** `shinycannon` 1.1.3 replays a session for 5 users, each starting it again as soon as it ends, for 5 minutes once all five are running (`bench/replay.sh`). The figures are from `bench/report.R`: end to end over the sessions run while all five users were, and in the database over the whole run.
- **Run 1: ordinary lookups, as deployed.** The app container, restarted after the recording, with its 200 MB cache. Every session asks the same things, so after the first one the cache answers every lookup but the window's: the run's timing log has 32 fetches, 19 of them the window's.
- **Run 2: ordinary lookups, no cache.** Every lookup goes to the database, as when each user asks for something not yet in the cache. The database stays warm, though: every session sends it the same 15 queries. This is the same image, started with `app_cache()` giving `NULL`, which the server takes as no cache.
- **Run 3: the largest chemical, as deployed.** The cache keeps the fetch, not the table drawn from it, so every session builds the table again.
- **Run 4: the largest chemical again, after #101's fix**, in the app image built with it.

| | Run 1: ordinary, cache | Run 2: ordinary, no cache | Run 3: the largest chemical | Run 4: the same, after #101 |
| --- | ---: | ---: | ---: | ---: |
| Sessions, and in the steady part | 19, 11 | 19, 11 | 32, 24 | 32, 24 |
| **Lookups, the searches' wait aside: p50, p95, max** | **39, 191, 411 ms** | **39, 195, 228 ms** | **144, 864, 1,148 ms** | **150, 236, 304 ms** |
| Lookups counted | 132 | 132 | 120 | 120 |
| Messages, the searches' wait aside: p95 | 164 ms | 164 ms | 624 ms | 217 ms |
| Messages, the searches' wait counted: p95 | 318 ms | 322 ms | 634 ms | 317 ms |
| Search results, the wait included: p50, p95, max | 317, 322, 325 ms | 320, 330, 330 ms | 318, 580, 661 ms | 316, 321, 322 ms |
| The page itself: p50, max | 124, 162 ms | 120, 149 ms | 141, 1,215 ms | 145, 333 ms |

The page's files took 15 ms at most in every run.

**In the database**, from run 2's timing log (`timing_summary()`): all 19 sessions' 285 fetches, with no errors.

| Fetch | Count | p50 (ms) | p95 (ms) |
| --- | ---: | ---: | ---: |
| `fetch_window` | 19 | 3.02 | 19.4 |
| `fetch_search_drugs` | 38 | 4.51 | 5.56 |
| `fetch_search_practices` | 19 | 3.78 | 4.35 |
| `fetch_drug_series` | 38 | 3.38 | 4.08 |
| `fetch_drug_presentations` | 38 | 2.53 | 4.67 |
| `fetch_practice_profile` | 19 | 2.45 | 2.98 |
| `fetch_practice_series` | 19 | 1.70 | 6.52 |
| `fetch_practice_top_drugs` | 57 | 5.84 | 6.72 |
| `fetch_regions` | 19 | 9.15 | 10.3 |
| `fetch_region_comparison` | 19 | 10.8 | 11.8 |

In run 3, the largest chemical's presentations took 24 and 32 ms to fetch, and 31 and 34 ms in run 4. Those are its two fetches in each run before the cache had them.

What the runs show:
- **Ordinary lookups are under the 300 ms target, with the search's wait left out.**
  - Their p95 is 191 ms with the cache and 195 ms without.
  - The search's wait comes before the lookup and is not part of it, so the target is read without it.
  - Counting the wait, the p95 of all messages is 318 and 322 ms. That is because 3 of the session's 18 messages are search results, and each takes the wait plus 8 to 30 ms (17 and 20 ms at p50).
- **The largest chemical's lookups were over the target, p95 864 ms in run 3, until #101's fix: 236 ms in run 4.**
  - Its Drug view sends the table every presentation: 2,068 rows, in a message of 235 KB (240,682 bytes) when it was recorded. R wrote the table's Quantity and ADQ usage cells one call per row.
  - In run 3, the table-and-chart message took 543 ms at p50 in the pick's view and 585 ms after the change of month, each timed from the event before it; the worst was 1,148 ms. With one user, in the recording, timed the same way, it took 718 and 869 ms.
  - One R process answers every session, so every other answer waits while a table is built. In run 3, search results took up to 661 ms, and the page up to 1.2 s.
  - The fix writes the two columns once for all rows, into hidden columns that the cells show. In run 4 the table-and-chart message took 160 ms at p50 in the pick's view and 197 ms after the change of month; the search results took the wait plus 11 to 22 ms, and the page 333 ms at worst. Answers still wait while a table is built, but for less time: a pick's frame took 35 ms at p50, and up to 114 ms when it came while another session's table and chart were being built. That made one pick the run's slowest lookup, 304 ms.
- **The database is a small part.**
  - In runs 1 and 2 every fetch's p95 is under 20 ms, and the cache saves only those few milliseconds: the two runs have the same p95 per message, and are 4 ms apart per lookup. In runs 3 and 4 the largest chemical's presentations took 24 to 34 ms to fetch, against its lookups' p95 of 864 and 236 ms.
  - Most of an answer's time is the app's R process drawing the tables and charts. An ordinary update with a chart takes 105 to 165 ms at p50.
- **The slowest ordinary lookup took 411 ms:** run 1's region pick.
  - Its frame took 39 ms, then a region chart 372 ms; that chart's p50 is 115 ms.
  - The chart's message came while no other session was waiting for an answer, and these data do not show its cause.
  - Run 2's slowest lookup took 228 ms. P6-02 measures again on the server, which is smaller than this machine.
- **A chart drawn twice.** Picking a drug or a practice draws its chart twice.
  - Once the table below it has drawn, the page's scroll bar takes 10 px off the width (1,222 to 1,212 px). The browser reports the new width, and the app draws the chart again, which takes 120 to 135 ms at p50.
  - The user sees the first drawing straight away. A chart that kept its width through a change that small would save the second.
- **The page's files.**
  - `bench/recording.log`'s page load is a returning visitor's. The browser had most of the files from earlier visits, so it asks for the page and 16 files, 10 of them only revalidated.
  - `bench/recording-largest.log`'s is a first visit: the page and 32 files.
- **Sessions reported as failed.**
  - `shinycannon` reported 9 of 19, 10 of 19, 19 of 32 and 17 of 32 of the runs' sessions as failed. Each failed after its last event, as it closed the socket: its `onDisconnected` handler expects the server's close frame, and threw an exception when given none (`null`).
  - Every session replayed every event of its recording, up to the close, so the figures count all of them. The app's logs have no errors.

**The workers' timing lines.** No view fetches on the workers yet: none takes 100 ms, so in every run each fetch ran in the app's own process. Their timing lines reach the container's log as the app's do. This was checked in a container of the app image with two workers:
- a fetch on a worker (`fetch_window`) and one in the app's process (`fetch_regions`) each left one whole line in `docker logs`;
- the two lines carry the same hash for the same arguments, so they share the app's key;
- `timing_summary()` read both.

The package's tests check the same on every CI run (`tests/testthat/test-workers.R`).

**To run it again** (P6-02 does, on the server). Each script's header gives its commands. In Git Bash, put `MSYS_NO_PATHCONV=1` before them, or Git Bash turns their container paths into Windows paths.
1. Build the app image from the commit to measure, from a clean working tree, since the build copies it: `docker compose --profile app up -d --build app`. Note the commit, as this section does: nothing in a run's output says which build answered.
2. `bench/setup.sh` installs the tools in the rstudio container: a Java runtime, `shinycannon` 1.1.3 from Posit's release on GitHub, checked against its SHA-256, and `shinyloadtest`.
3. `bench/record.R` records a session through `shinyloadtest`'s proxy. `bench/tidy.R` then keeps the last session the proxy saw, and ends it with the socket's close if the proxy left that out.
4. `bench/replay.sh` replays the session, against one of:
   - the app container, restarted after the recording so that its cache starts empty (runs 1, 3 and 4);
   - a container of the app image without the cache (run 2).
5. Save the app's log over the run as `app.log` in the run's folder:
   - for the app container, use `docker compose logs` from the replay's start;
   - for the container without the cache, use `docker logs` before it stops. `docker compose logs` leaves out containers made by `docker compose run`, and `--rm` deletes the log with the container.
6. `bench/report.R` gives the figures above, each message's figures by its line in the recording, and writes `shinyloadtest`'s report into the run's folder. That report shows each session's slowest message, which in runs 1 and 2 is always over 300 ms, since every session has three searches.

## The server (P6-02)

The production server, checked in its terminal on 25 November 2026:

| | |
| --- | --- |
| Host | A virtual server with 4 vCPUs, 15 GiB of memory and no swap; a 193 GB disk, 159 GB of it free; shared with other projects, under Coolify v4 and its Traefik proxy |

It meets the spec's minimum: 4 vCPUs and 16 GB, as near as 15 GiB is, and 100 GB free. Because the server is shared, prexp has a network of its own and capped memory: 6 GB for the database, 3 GB for `jobs` and 2 GB for the app ([docs/server.md](server.md)). The rehearsal below ran on four of the development machine's CPUs with the same limits and no swap.

## The server, rehearsed (P6-02)

The server's setup ([docs/server.md](server.md)) laid out on the development machine ([Machine](#machine-p1-08)) by `docker/rehearsal/compose.yaml`, on 25 November 2026. The database, the `jobs` container and the app run on four of the machine's CPUs with the server's memory limits and no swap: 6 GB for the database, 3 GB for `jobs` and 2 GB for the app. The database runs `postgres:18.7-trixie`, pinned by digest, with `postgresql.prod.conf` (3 GB of shared buffers, `effective_cache_size = 5GB`), Coolify's superuser and the three initialization scripts. The app image was built from `main` at `637a26b`. There is no proxy, so HTTPS and the noindex header are checked on the server.

**Built from empty, as on a new server.**
- **The initialization scripts** ran in order. `prexp_owner` is an ordinary login, not a superuser, and `migrate()` ran as it, as the post-deployment command does.
- **`load_window()`** loaded the twelve months, 202510 to 202609, from the portal in **38.0 minutes**: 190 s a month, 49 s to download and 141 s to load. On the whole machine, P2-02's eleven loads took 175 s a month, 48 s to download and 127 s to load ([Twelve months](#twelve-months-p2-02)). Four CPUs instead of sixteen cost about 9% more a month, and 11% more for the load alone (11% and 15% against the nine months that tests did not slow, 171 s and 122 s), because the load mostly waits on the disk and on single-threaded steps. This is the time to rebuild the database from empty on a server of this size with a fast link to the portal.
- **Memory, with no swap:** the database's limit held. The kernel's cache of its files filled it, as the limit allows, and the memory the database cannot give back, its shared buffers and the loads' own, peaked at about 3.8 GB in samples taken every 5 s. No process was killed. `jobs` used at most 0.9 GB of its 3 GB.
- **`check_plans()`:** all 25 checks pass, in 2 s.
- **The app** turned healthy 7 s after it started, well inside the minute Coolify gives a new container.

**The scheduled tasks' commands** (P6-03), run in the `jobs` container with `docker exec ... sh -c`, as Coolify runs them:

| Task | Case | Exit status | Time |
| --- | --- | ---: | ---: |
| The load, `load_latest()` | Nothing new: "Nothing to load", then "No loaded month has been published again." | 0 | 2 s |
| The nightly check, `migrate(); check_plans()` | All 25 checks pass | 0 | 2 s |
| The load | The loader's password wrong: "password authentication failed" | 1 | 1 s |
| The load | 202609 removed by hand, as the loader drops a month: loaded again | 0 | 188 s |

A new browser session showed "Data: Oct 2025 – Aug 2026" after the removal, and "Oct 2025 – Sep 2026" after the load put the month back. The app was never restarted: the window is fetched for every session, and the cache's keys include it.

**The app under load.** These are [P4-08's](#the-app-under-load-p4-08) two sessions, replayed the same way: 5 users for 5 minutes after a restart, so that the cache starts empty. The rehearsal's database numbers its drugs and practices in its own load order, so the replays use copies of the recordings in which every id, the search options' included, is the rehearsal's, matched by code: `bench/recording-rehearsal.log` and `bench/recording-largest-rehearsal.log`. Every session replayed to its end.

| | Run R1: ordinary lookups | Run R2: the largest chemical |
| --- | ---: | ---: |
| Sessions, and in the steady part | 19, 11 | 31, 23 |
| **Lookups, the searches' wait aside: p50, p95, max** | **47, 224, 333 ms** | **177, 370, 422 ms** |
| Messages, the searches' wait aside: p95 | 175 ms | 268 ms |
| Search results, the wait included: p50, p95 | 318, 379 ms | 320, 374 ms |
| The page itself: p50, max | 145, 186 ms | 161, 378 ms |
| The app's peak memory, of its 2 GB | 642 MB | 634 MB |

On the whole machine the same sessions gave lookup p95s of 191 ms (run 1) and 236 ms (run 4).
- **Ordinary lookups stay under the 300 ms target** on four shared CPUs, at a p95 of 224 ms.
- **The largest chemical does not: 370 ms at p95.** Its Drug view builds a table of 2,068 presentations in R, on one CPU, and the four CPUs here are shared with the database. Its two fetches took 25 and 36 ms: the time is the table, not the database.
- **The database's part** is small: in run R1 every fetch's p95 is under 18 ms, and in run R2 every fetch's is under 10 ms but the largest chemical's two presentation fetches.
- **One stall:** one of run R2's 736 script and style requests took 7.1 s. The other sessions' requests at the same moment took at most 12 ms, so it was that connection, not the app.
- **Memory.** The app's peak, 642 MB, includes its two workers. A 15-item export, the worst case, grows the worker that makes it, which keeps the memory: by 168 MB for PowerPoint, 110 MB for Word and 70 MB for Excel, in 2.8, 1.0 and 1.5 s. These were measured in a fresh R process in the app's container, against the twelve months. With both workers grown by a PowerPoint export, the app holds about 1 GB. The database held 3.2 GB it cannot give back, its shared buffers, and its cache filled the rest of its limit. No process was killed.

[The server, measured](#the-server-measured-p6-02) has the same on the server.

## The server, measured (P6-02)

The same steps on the production server ([The server](#the-server-p6-02)), on 25 November 2026, with the app image CI built from `main` at `f17118f`.

**The twelve-month load.** `load_window()`, in the `jobs` container's terminal, from 21:51 to 22:55 UTC: **63.6 minutes**, 318 s a month, 8 s of it downloading.
- **Every step is about twice the rehearsal's,** on four of the development machine's CPUs: staging 66 s against 31, the dimensions 40 s against 18, the build 140 s against 63 and the check 38 s against 19. The server's CPU is an AMD EPYC 9354P at 3.25 GHz, and the steal from other tenants was 0 to 2%: its cores are about half as fast as the development machine's for this work.
- **The download is six times faster,** 8 s against 49 s.
- **This is the time to rebuild the database from empty** on this server.

**`check_plans()`.** Every plan is right: index-only reads, partitions pruned, no heap fetches. But two of the 25 checks take more than the 50 ms set on the development machine, which a third approaches:

| Check | Server, warm | Server, first run after the load | Development machine (the rehearsal) |
| --- | ---: | ---: | ---: |
| The search "co" (`search_drugs`, large) | 57, 58 ms | 78 ms | 33 ms |
| The largest chemical's presentations (`drug_presentations`, large) | 52, 54 ms | 54 ms | 26 ms |
| The largest practice's top drugs (`practice_top_drugs`, large) | 36, 40 ms | | 15 ms |

So the nightly scheduled task, which must fail only when a plan goes wrong, allows 150 ms a query (P6-03).

**The app under load.** [P4-08's](#the-app-under-load-p4-08) two sessions, replayed against `https://<app-host>` from the development machine: 5 users for 5 minutes after a restart, with the rehearsal's recordings, whose 42 ids all match the server's database. Every figure includes the round trip from the development machine to the server, about 37 ms (TCP connect, median of six), and every HTTP request a TLS handshake.

| | Run S1: ordinary lookups | Run S2: the largest chemical |
| --- | ---: | ---: |
| Sessions, and in the steady part | 19, 10 | 29, 21 |
| **Lookups, the searches' wait aside: p50, p95, max** | **192, 569, 2,436 ms** | **501, 957, 1,545 ms** |
| Messages, the searches' wait aside: p95 | 552 ms | 717 ms |
| Search results, the wait included: p50, p95 | 359, 611 ms | 362, 749 ms |
| The page itself: p50, max | 406, 640 ms | 446, 1,098 ms |

- **Neither run meets the 300 ms target.** Ordinary lookups take about 2.5 times the rehearsal's (p95 569 ms against 224), and the largest chemical 2.6 times (957 ms against 370).
- **The time is the app's own work,** as in the rehearsal: building the charts and tables in R, on cores about half as fast. A message that only updates a few outputs takes 95 to 115 ms, against about 35 ms on the development machine, the round trip included.
- **One session of S1 failed,** with a 502 on its first request, about 26 s after the restart began and 12 s after the app first answered again, while the proxy was still switching to the new container. S2 started only once the app had answered for 30 s straight, and all its sessions replayed to the end.

## One message for each lookup (P6-02)

The production server again, on 26 November 2026, with the app image CI built from `main` at `8846eca`: #125, which answers a lookup in one message, draws each chart once, at its width, and keeps drawn charts in the shared cache ([docs/architecture.md](architecture.md#the-app)).

**Measured by #125's review** on the development machine, one user, from the action to the complete view (the WebSocket trace in #125):

| Lookup | Before #125 | After, first time | After, repeated |
| --- | ---: | ---: | ---: |
| Drug pick | 229 ms, 3 messages, chart drawn again | 171 ms, 1 message | 51 ms |
| Practice pick | 229 ms, 2 messages, chart drawn again | 195 ms | 54 ms |
| Region pick | 212 ms, 2 messages | 167 ms | 40 ms |
| The largest chemical's pick | 255 ms, chart drawn again | 187 ms | 78 ms |

"Repeated" is a lookup another session has made, whose chart comes from the cache.

**The sessions, recorded again.** P4-08's recordings encode the messages before #125, so they no longer replay. `bench/drive.R` goes through the same two sessions ([The app under load](#the-app-under-load-p4-08)) in a headless Chrome, through `shinyloadtest`'s proxy (`bench/record.R`), with the first recordings' gaps between actions. Each new session lasts 3.6 to 5.1 s longer than the first recordings', and each is a first visit, so the page asks for all its files.
- **Each search is put in at once, as a paste is.** Typed, the browser sends the first letter at once, then the text after each pause of 50 ms between keys: the whole text in the first recordings, every longer prefix when typed more slowly. On a busy server the 300 ms wait for typing to stop can pass between two of them, so the earlier is answered too, and a replay, which expects the recording's messages in order, fails.
- **The recordings:**
  - `bench/recording-server-p602.log` and `bench/recording-largest-server-p602.log` were recorded against the server, with its address replaced by `<app-host>`;
  - `bench/recording-p602.log` and `bench/recording-largest-p602.log` were recorded against the development stack.

**The runs**, as in [The server, measured](#the-server-measured-p6-02): `shinycannon` 1.1.3, 5 users for 5 minutes, from the development machine, after a restart, so that the cache starts empty. Each started once the app had answered for 30 s straight. Every session replayed to its end.

| | Run S3: ordinary lookups | Run S4: the largest chemical |
| --- | ---: | ---: |
| Sessions, and in the steady part | 18, 10 | 28, 20 |
| **Lookups, the searches' wait aside: p50, p95, max** | **141, 540, 864 ms** | **255, 699, 1,271 ms** |
| The same before #125, runs S1 and S2: p50, p95, max | 192, 569, 2,436 ms | 501, 957, 1,545 ms |
| Lookups counted | 120 | 100 |
| Opening a session, its first message: p50, p95 | 527, 579 ms | 490, 1,036 ms |
| The same before #125, runs S1 and S2: p50, p95 | 384, 520 ms | 404, 504 ms |
| The pick: p50, p95 | Drug 243, 654 ms; practice 176, 253 ms; region 137, 209 ms | 291, 699 ms |
| Search results, the wait included: p50, p95 | 360, 614 ms | 359, 679 ms |
| The page itself: p50, max | 409, 723 ms | 422, 1,939 ms |

- **Lookups are faster.**
  - At the median: 141 ms against 192, and 255 ms against 501 for the largest chemical.
  - At the 95th percentile: 540 ms against 569, and 699 ms against 957.

  A pick is now one message, and a chart another session drew comes from the cache.
- **Opening a session is slower than before #125:** 527 ms at the median against 384 in S1, and 490 against 404 in S2. Since #125 every view's chart, table and CSV link is computed as a session opens, shown or not (`compute_always()`), so its first message also brings every view's download link and an empty answer for each chart and table.
- **The 95th percentile is still over the 300 ms target.** What sets it now is opening a session: the first message, which brings the outputs every view starts with, takes about half a second on the server. In S3 the 10 openings take 424 to 579 ms, and the 95th percentile, 540 ms, is one of them. The six slowest lookups, the top 5%, are four openings, a tab change to Region (864 ms) and a drug pick (654 ms), both answered while another session was opening. In S4 the 95th percentile, 699 ms, is a pick answered while another session was opening.
- **The development machine has not been measured again since #125.**
- **S4 ran while the development machine, which plays the five users, was busy** with other measurements for about half the run. Its figures may include some delay on that side.
