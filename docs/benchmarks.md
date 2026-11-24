# Benchmarks

Measurements of the loader and, from phase 2, of the app's queries (spec §6.3). Until the server arrives in P6-02, everything runs in the local Docker stack, on the machine below.

## Machine (P1-08)

| | |
| --- | --- |
| Host | Windows 11 Pro, 137 GB of memory, 786 GB free on the system drive (23 November 2026) |
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

Phase 2 tunes these against twelve loaded months (P2-05).

## One month (P1-09)

The real September 2026 month (`EPD_SNOMED_202609`), loaded on 23 November 2026 into the empty `prexp` database with `Rscript -e "prexp::load_month(202609)"` and the full settings, downloading the ZIP. For comparison, the same load of the same file with the laptop settings, from a ZIP already downloaded.

| Step | Full settings (s) | Laptop settings (s) |
| --- | ---: | ---: |
| Find the month on the portal | 0.3 | |
| Download (666.5 MB ZIP) | 223.1 | |
| Check the header | 0.0 | 0.0 |
| Stage: stream 7.7 GB of CSV into `raw.epd_staging` | 30.4 | 30.8 |
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

The download depends on the connection: the same ZIP took 112 s in P0-07. The full settings change little for one month, since each step is one large query; they matter for the twelve months' queries, which phase 2 tunes.

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
| Twelve months of fact table and indexes (12 × 1.77 GB) | 21.3 GB |
| Their rollup rows and the dimensions | 0.2 GB |
| While a month loads: staging, the month being built beside the live one, the write-ahead log and the ZIP | 11.1 GB |
| **Peak** | **about 33 GB** |

Docker's virtual disk had 835 GB free, and the host drive 786 GB, which is the real limit: the peak is about 4% of it, far under the 70% at which P2-02 would wait for more disk.

## Twelve months (P2-02)

The window's other eleven months, 202510 to 202608, were loaded on 24 November 2026 into the database that held 202609. The command was `Rscript -e "prexp::load_window(12)"` in the `rstudio` container, with the full settings. `load_window()` loads the missing months oldest first, so nothing was dropped on the way. It took 32.1 minutes, 175 s a month: 48 s to download each ZIP and 127 s to load it.

| Month | ZIP (MB) | Source rows | Fact rows | Download | Stage | Dimensions | Aggregate | Indexes | Rollups | Check | Swap | Total |
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

Steps are in seconds. Finding the month, checking the header, checking the staged month, `VACUUM` and cleaning up each take under 2 s; the table leaves them out, but the total includes them. While 202606 and 202608 loaded, tests were running against the same PostgreSQL server, which slowed them by 20 to 30 s.

### Every month matches the portal

`load_log` shows the twelve months as `loaded`, and `app.v_window` shows 202510 to 202609, 12 months. For each month, the source rows, items, NIC and actual cost, summed from the fact table, equal the portal's own figures exactly. Those come from one aggregate query per month through the portal's SQL API (see [dataset.md](dataset.md#checking-the-data-without-downloading-it)):

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

PostgreSQL's units: 1 GB is 1,024 MB.

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
| **The database** | **21,398 MB** (20.9 GB) | |
| Write-ahead log | 1,664 MB | |

The fact table is 0.5% under twelve times September's 1,772 MB.

**Disk use during the load.**
- **The database** peaked at 28,293 MB while 202608 loaded. That is eleven months, plus staging at its 7,226 MB peak and the month being built.
- **The write-ahead log** peaked at 1,664 MB.
- **Docker's virtual machine** grew by 29 GB. Its virtual disk file on the host did not grow: it stayed at 264.35 GB, because the virtual machine reused space the file already held.
- **The host drive** never had less than 777 GB free.
