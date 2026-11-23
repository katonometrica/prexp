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
