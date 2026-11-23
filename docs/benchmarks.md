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
