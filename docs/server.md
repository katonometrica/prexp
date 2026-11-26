# The server

Production runs on one server under [Coolify](https://coolify.io) v4 (these steps were written against v4.7.6): a PostgreSQL 18 database, the `jobs` container and the app, the last two from this repository's app image (spec §2.3, §7). This page sets the server up, step by step, in Coolify's web interface. The runbook (P6-04) covers operating it.

What must stay private never goes in this repository or its issues: the app's address, the server's and Coolify's, and every password and token. They live in Coolify, and those that CI needs in the repository's GitHub secrets, one value to each, because Actions hides a secret in its logs only where its whole value appears. Below they appear as `<app-host>`, `<coolify-host>`, `<server-ip>`, `<db-id>`, `<app-id>` and `<jobs-id>`.

## Before you start

- **The server:** at least 4 vCPUs, 16 GB of RAM and 100 GB of free disk, with Coolify's default proxy (Traefik). [docs/benchmarks.md](benchmarks.md#the-server-p6-02) records the one in use: 4 vCPUs and 15 GiB, shared with other projects. `docker/db/postgresql.prod.conf` is sized for it. On a server of prexp's own, or a larger one, raise `shared_buffers` (to a quarter of the RAM) and the database's memory limit with it (section 1, step 6), to `shared_buffers` plus about 3 GB: with no swap, shared buffers larger than the limit get the database's processes killed once they fill. Then set `effective_cache_size` to the limit less about 1 GB, and the parallel workers to the CPUs.
- **A shared server:** give prexp a project of its own, named `prexp` (Projects → +) and a Docker network of its own (Servers → the server → Destinations → +), and choose that destination for each resource below. Containers on one Coolify network can reach each other, so other projects would otherwise reach the database's port. Cap each container's memory, as below: there may be no swap.
- **The images:** make `ghcr.io/katonometrica/prexp-app`, which the server pulls, and `prexp-ci` public packages, so that the server needs no registry login. They start private. On GitHub, for each: the organisation → Packages → the package → Package settings → Danger Zone → Change visibility → Public, which cannot be undone. Then check from any machine that `curl -s 'https://ghcr.io/token?scope=repository:katonometrica/prexp-app:pull'` prints a token, and the same for `prexp-ci`. `authentication required` means the package is still private, and the deployments in sections 2 and 3 would fail at the pull.
- **DNS:** an A record for `<app-host>` pointing at the server's public IPv4, and ports 80 and 443 open to the internet. Let's Encrypt publishes the certificate's name in its public Certificate Transparency logs: the name is not a secret, and the noindex header keeps the app out of search engines.
- **Coolify on HTTPS:** Coolify → Settings → General → **URL:** `https://<coolify-host>`, with **Redirect HTTP to HTTPS** on, and an A record for `<coolify-host>` pointing at the server. Coolify's proxy then gets that name a Let's Encrypt certificate, so it is in the Certificate Transparency logs too. Until the name resolves, Coolify answers only at `http://<server-ip>:8000`, in clear text, and the steps below carry the three passwords and the API token: do them at `https://<coolify-host>`. Once the dashboard, its live updates and its terminal work there, and nothing else uses port 8000 (another project's GitHub App webhook, for example), close ports 8000, 6001 and 6002 in the provider's firewall. UFW does not block the ports Docker publishes.
- **Three passwords**, for the roles `prexp_owner`, `prexp_loader` and `prexp_app`: long, random, letters and digits only (for example `openssl rand -hex 24`). Coolify strips spaces at either end of a value, and a `$` needs its "Literal" setting.

## 1. The database

New resource → Databases → PostgreSQL → PostgreSQL 18, named `prexp-db` (General → Name): the runbook and section 5 find each resource by its name. Coolify creates it stopped. **Before the first start**, on its pages:

1. **General → Image:** `postgres:18.7-trixie@sha256:eb63372c1e05c755f55fa30cbd07aecc443676fc6c0fa90b9002d01537841e1a`, the reference `compose.yaml` and CI pin (Debian, so the same C library and collations). Coolify pulls the image again at every start, and the digest keeps it the build CI tests: when `compose.yaml`'s digest changes, change it here too and restart the database. Then check **Persistent Storage**: the volume is mounted at `/var/lib/postgresql`. PostgreSQL 18 keeps its cluster in `/var/lib/postgresql/18/docker`, and an image name Coolify does not recognise can give the wrong path.
2. **General → Username:** leave `postgres`. It is Coolify's superuser; the app's roles are ordinary logins.
3. **Environment Variables:** `PREXP_OWNER_PASSWORD`, `PREXP_LOADER_PASSWORD` and `PREXP_APP_PASSWORD`, set to the three passwords. The initialization scripts read them.
4. **General → Initialization scripts:** + Add three, with these names and these files' contents. On the first start the image runs them in this order, once:
   - `00-owner.sh`: [docker/db/server/00-owner.sh](../docker/db/server/00-owner.sh). It creates `prexp_owner`, an ordinary login, and the `prexp` database, which it owns.
   - `01-roles.sh`: [docker/db/init/01-roles.sh](../docker/db/init/01-roles.sh). It creates `prexp_loader`, `prexp_app` and an empty `prexp_test`.
   - `02-database.sql`: [docker/db/init/02-database.sql](../docker/db/init/02-database.sql). It makes `prexp_app` read-only, with a 5-second statement timeout.
5. **General → Custom PostgreSQL configuration:** the contents of [docker/db/postgresql.prod.conf](../docker/db/postgresql.prod.conf). It replaces the server's configuration, so it starts by including initdb's.
6. **General → Custom Docker options:** `--shm-size=1g`. Parallel queries share memory through `/dev/shm`, which Docker limits to 64 MB.
   **Resource Limits → Memory:** `6g`. It holds the shared buffers (3 GB), the kernel's cache of the database's files, and the connections' and the loads' own memory. With no swap, the rehearsal's twelve-month load stayed within it, with at most about 3.8 GB that the database could not give back, and no process killed ([docs/benchmarks.md](benchmarks.md#the-server-rehearsed-p6-02)).
7. **Leave it private:** "Make it publicly available" off, and no port mappings. The app and the `jobs` container reach it over prexp's Docker network, by its internal host name, `<db-id>` (General → "Postgres URL (internal)").

**Start it.** Its log shows `00-owner.sh: role prexp_owner and database prexp are ready`, then the same from `01-roles.sh`, then `02-database.sql` running. The scripts never run again. If one failed, delete the database and its volume, and start again. A change to the configuration, the Docker options or the variables later needs a restart, which Coolify does not prompt for.

## 2. The `jobs` container

New resource → Docker Image: `ghcr.io/katonometrica/prexp-app`, tag `main`, named `prexp-jobs` (General → Name).

1. **Ports Exposes:** empty, and no domain. Nothing connects to it.
2. **Custom Docker options:** `--init --entrypoint 'sleep infinity'`. It waits for Coolify's scheduled tasks and terminal instead of running the app. Coolify has no start-command field. `--init` gives `sleep` a process 1 that passes signals on, so a stop takes a second, not the 30-second grace period.
3. **Persistent Storage → Add → Volume Mount:** name `epd`, destination `/data/epd`, the loader's download folder. The image creates that folder for its user, so the new volume belongs to it.
4. **Environment Variables:**
   - `PREXP_DB_HOST=<db-id>`, `PREXP_DB_PORT=5432` and `PREXP_DB_NAME=prexp`;
   - `PREXP_OWNER_PASSWORD` and `PREXP_LOADER_PASSWORD`;
   - never `PREXP_APP_PASSWORD`.
5. **Post-deployment command:** `Rscript -e "prexp::migrate()"`. Coolify runs it in the new container after each deployment.
6. **Health check:** off (the default). `sleep` serves nothing to check.
7. **Resource Limits → Memory:** `3g`, for the loader's R process and its download stream.

**Deploy it.** Then, in its **Terminal**:

1. Load the twelve months. Run it in the background, so that it outlives the browser tab:

   ```sh
   nohup Rscript -e "prexp::load_window()" > /data/epd/load_window.log 2>&1 &
   tail -f /data/epd/load_window.log
   ```

   It downloads and loads the months oldest first. A run that stops can be started again, and carries on.
2. `Rscript -e "prexp::check_plans(max_ms = 150)"`: every check must pass. It allows 150 ms a query, as the nightly check does (section 5): at the default 50 ms, two checks fail on time on this server.

## 3. The app

New resource → Docker Image: `ghcr.io/katonometrica/prexp-app`, tag `main`, named `prexp-app` (General → Name).

1. **Ports Exposes:** `3838`.
2. **Domains → Add domain:** `https`, `<app-host>`, port `3838`.
   - **Search engine indexing:** Noindex. Coolify's proxy then sends `X-Robots-Tag: noindex, nofollow` with every response, as the page's own head says.
   - **Redirect HTTP to HTTPS:** on.
   - There is no `robots.txt`. A rule that kept crawlers out would also keep them from seeing the noindex header, and a URL linked from elsewhere could then be listed.
3. **Environment Variables:** `PREXP_DB_HOST=<db-id>`, `PREXP_DB_PORT=5432`, `PREXP_DB_NAME=prexp` and `PREXP_APP_PASSWORD`, and nothing else. The app refuses to start with a login that can write.
4. **Health check:** on, HTTP, GET, host `localhost`, port empty (it takes 3838), path `/`. The image has curl, which the check runs inside the container. A new container that is not healthy within about a minute is rolled back.
5. **Resource Limits → Memory:** `2g`. In the rehearsal the app peaked at 642 MiB with its two workers and a warm cache. A 15-item export grows the worker that makes it by up to 170 MiB (PowerPoint), and the worker keeps it, so with both workers grown the app holds about 1 GiB ([docs/benchmarks.md](benchmarks.md#the-server-rehearsed-p6-02)).

**Deploy it,** then check from any machine:

```sh
curl -sSI https://<app-host>/ | grep -i x-robots-tag
```

## 4. Deploys from CI

After CI pushes a new `:main` image, it asks Coolify to deploy the app and the `jobs` container (`.github/workflows/ci.yaml`, job `app-publish`). It needs the API access and the four secrets below; until they exist, the step fails, and each application deploys by hand with its Redeploy button.

1. **Coolify → Settings → Advanced → API access:** on. Leave **Allowed IPs** empty: GitHub's runners have no fixed addresses. Both settings apply to the whole instance: turning API access on also lets in every existing API token of every project on this Coolify, from any address. First delete the tokens no longer used (Keys & Tokens → API Tokens).
2. **Keys & Tokens → API Tokens → New token:**
   - description `prexp CI deploy`;
   - permissions **Deploy** only (clear Read);
   - access to the app and the `jobs` container only;
   - expiry 1 year. Coolify emails before a token expires; renew it then, and update the secret.

   Coolify shows the new token only once, so copy it straight away.
3. **GitHub → the repository → Settings → Secrets and variables → Actions → New repository secret,** four times, one value in each, so that each is hidden wherever it appears in the logs (curl's `Could not resolve host: …` names the host alone):
   - `COOLIFY_TOKEN`: the token;
   - `COOLIFY_HOST`: `<coolify-host>` alone, with no `https://`, port or path. The step always calls it over HTTPS, so the token never crosses in clear;
   - `COOLIFY_APP_UUID` and `COOLIFY_JOBS_UUID`: `<app-id>` and `<jobs-id>`, each from its application's page address in Coolify.

   The step asks for `https://<coolify-host>/api/v1/deploy?uuid=<app-id>,<jobs-id>&force=true`. Without `force=true`, Coolify skips a deployment asked for while another is queued.

From then on, a merge to `main` redeploys both. The step fails when Coolify does not queue both deployments.

## 5. Scheduled tasks and alerts

`prexp-jobs` → **Scheduled Tasks → Add Task**, twice. Coolify runs each in the `jobs` container, in a shell, on the server's clock (UTC).

| Name | Schedule | Command | Timeout (s) |
| --- | --- | --- | ---: |
| Monthly load | `0 2 18-28 * *` | `timeout 3h Rscript -e "prexp::load_latest()"` | 11400 |
| Nightly check | `0 4 * * *` | `Rscript -e "prexp::migrate(); prexp::check_plans(max_ms = 150)"` | 600 |

- **The monthly load** runs at 02:00 on days 18 to 28, because months are published around the 20th ([docs/dataset.md](dataset.md)). It loads a newly published month, which drops the oldest, and reloads a month the portal has published again; otherwise it logs "Nothing to load" and exits 0. A month takes about five minutes on this server. `timeout` stops a run that hangs before Coolify's own timeout, which is set just above it.
- **The nightly check** applies any new migration, then checks the app's query plans. It allows 150 ms a query, not the default 50 ms: this server's CPUs are slower than the development machine's, and its slowest checks take 52 to 58 ms there, 78 ms on the first run after a load ([docs/benchmarks.md](benchmarks.md)). A plan that goes wrong fails whatever its time: a sequential scan, partitions not pruned, or heap fetches.
- **Run each by hand** after setting it up, from its page: **Execute Now**, then **Executions** for its output. Both must succeed.

**Alerts.** The mail service is the instance's: Coolify → **Settings → Email** (its page is titled Transactional Email), for example Resend, with its API key and a sender on a domain verified there. Then Coolify → **Notifications → Email: Email service: Use system-wide settings**, with **Scheduled task failure** and **Deployment failure** among the events. A new team starts on its own settings, with no provider, and then sends no email at all, though its events can be ticked. **Send test** on Notifications → Email checks the whole path; the one on Settings → Email checks only the instance's provider. A task that fails ten times in a row is disabled, and its page says so.

## Rehearse it locally

`docker/rehearsal/compose.yaml` lays the same three containers out on this machine, beside the development stack, as Coolify runs them:
- the database with Coolify's superuser, the three initialization scripts mounted one by one, the production configuration, `--shm-size` and no published port;
- the `jobs` container sleeping under an init, with the owner's and loader's logins;
- the app with its login only, its memory limit and its health check.

They run on four of the machine's CPUs, with the server's memory limits and no swap, so the timings and the memory say what a server of this size would do, with this machine's disk and link to the portal. [docs/benchmarks.md](benchmarks.md#the-server-rehearsed-p6-02) has the results.

1. Write `docker/rehearsal/.env`, which git ignores, giving each of `POSTGRES_PASSWORD`, `PREXP_OWNER_PASSWORD`, `PREXP_LOADER_PASSWORD` and `PREXP_APP_PASSWORD` a random value of its own.
2. Build the app image from the working tree: `docker compose --profile app build app`.
3. Start the database and the `jobs` container, then run the post-deployment command:

   ```sh
   docker compose -f docker/rehearsal/compose.yaml up -d --wait db jobs
   docker compose -f docker/rehearsal/compose.yaml exec jobs Rscript -e "prexp::migrate()"
   ```
4. Load the window and check the plans in the `jobs` container, as in step 2 above: `docker compose -f docker/rehearsal/compose.yaml exec jobs sh`.
5. Start the app: `docker compose -f docker/rehearsal/compose.yaml up -d --wait app`, on <http://localhost:3839>.
6. Remove it all, its volumes included: `docker compose -f docker/rehearsal/compose.yaml down -v`.

There is no proxy in the rehearsal, so the noindex header and HTTPS are checked on the server.

## Good to know

- **Only prexp's containers and Coolify's proxy can reach the database's port.** They share prexp's own destination (Before you start), and Coolify connects its proxy to every destination. The roles' passwords are what protect it. Deploy nothing else to that destination: on the default `coolify` network, every other project's containers would reach the port too.
- **The two deployments run in no set order.** `migrate()` runs in the `jobs` container after its deployment has finished, which Coolify reports as success before the command runs. A migration that fails therefore sends no deployment email. The nightly scheduled task runs `migrate()` again before `check_plans()` (P6-03), and its failure does send an email.
- **A restart of the `jobs` container is a full deployment:** it pulls the image again and runs `migrate()`. It also stops a scheduled task that is running, so avoid it between 02:00 and 05:00.
- **Docker cleanup** (Servers → the server → Docker Cleanup): keep "Unused volumes" at its default, Keep. Deleting them can remove a stopped database's volume.
- **The database is not backed up.** It can be rebuilt from the source, from an empty database: `migrate()`, `load_window()`, `check_plans(max_ms = 150)` (spec §7; [docs/runbook.md](runbook.md)).
