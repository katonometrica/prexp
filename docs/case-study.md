# Case study: how the build went

Prescription Explorer was built by spec-driven development with a coding agent. The developer wrote the project plan, the architecture included, and decided the questions the agent raised. [Claude Code](https://claude.com/claude-code) wrote the specification and the 55 issues from that plan and those decisions, and the developer approved them before any code. The agent then wrote the code, at times on several issues side by side. The work stopped at the end of each of Phases 0 to 5 for the developer's go-ahead. Who wrote what, and the stops, come from the session record ([who did what](#who-did-what)).

Apart from the first commit and the five pull requests before CI arrived in [#61](https://github.com/katonometrica/prexp/pull/61), every change went through a pull request and CI. This page shows, from the repository's own record, how that went.

- **When:** measured on 26 November 2026, against `main` at [25cd2f4](https://github.com/katonometrica/prexp/commit/25cd2f41fc3b8140677da31ff8ee74009ef8d10a), after pull request #134. All times are UTC. Milestone links show each milestone as it is today.
- **Evidence:** figures link to the issue, pull request, commit, CI run or file they come from, say how they were measured, or are marked as from the session record. Line links are pinned to a commit.
- **The session record:** some facts come only from the record of the build session, which is not public. They are marked *(session record)*.

## Contents

- [Who did what](#who-did-what)
- [The specification during the build](#the-specification-during-the-build)
- [Drift against the targets](#drift-against-the-targets)
- [What the reviews caught](#what-the-reviews-caught)
- [Estimates against time](#estimates-against-time)
- [Where the agent failed](#where-the-agent-failed)
- [One requirement, end to end](#one-requirement-end-to-end)

## Who did what

Who wrote what, and the stops at each phase's end, are from the session record, which is not public.

**Before the first pull request,** from 21 to 23 November:

- **The developer** had written the project plan: the goal and the 300 ms lookup target, the scope of v1, the phases, the architecture, the app's design and the testing approach. The architecture put a PostgreSQL fact table, partitioned by month, behind read-only views as the app's only access. The app's design kept all its SQL in one place, with query functions passed in so that screens test without a database. The tests were to use a real PostgreSQL, with SQL never mocked, an 85% coverage gate and a nightly plan check on the full data. The developer then decided the questions the agent raised, such as twelve months of data, the report's formats, the shareable link and a public repository.
- **Claude Code, the agent,** wrote the specification and the text of the 55 issues from that plan and those decisions, each issue with an estimate, tasks and "done when" checks ([milestones](https://github.com/katonometrica/prexp/milestones?state=all)). The developer approved both on 23 November, before any code, and the agent opened the issues by script.

The public record fits this. The 55 issues were opened between 08:24 and 08:28 on 23 November, before the first pull request, [#56](https://github.com/katonometrica/prexp/pull/56), which committed the specification "made self-contained". Every commit on `main` names Claude as co-author.

**From the first pull request on:**

- **Claude Code** wrote the code, the tests, the other documents and every pull request's description. It edited the specification and the issues as it went, and ran review agents on its own work.
- **The developer** gave the go-ahead at the end of each of Phases 0 to 5, set new directions, and used the app ([the developer's catches](#the-developers-catches)).
- **Review agents** checked pull requests, most of them before the merge. Once, at Phase 0's end, they checked the whole phase, already merged. As a rule, one to four finders each looked through one lens, such as security, behaviour in the browser, or the tests with mutants; then a verifier tried to refute each finding, often by experiment ([#77](https://github.com/katonometrica/prexp/pull/77), [#88](https://github.com/katonometrica/prexp/pull/88)).
- **CI** ran lint, the migrations and the tests with two coverage gates on every pull request from [#61](https://github.com/katonometrica/prexp/pull/61), and the browser flows too from [#113](https://github.com/katonometrica/prexp/pull/113) ([ci.yaml](../.github/workflows/ci.yaml)).

Four facts bound what "review" means here:

- **None of the 74 merged pull requests has a review or a comment on GitHub.** The public record of the reviews is what the agent wrote in the descriptions, and all 74 end with its "Generated with Claude Code" line.
- **The 39 edits to the specification after #56 came in pull requests like any other change,** each commit naming Claude as co-author. *(Session record)* The agent made all of them, and no one signed them off one by one.
- **All 74 merged pull requests were merged from one account.** The [ruleset](../.github/rulesets/protect-main.json) asks for no approval, only the `test` check. *(Session record)* Under the developer's working agreement, the agent merged each pull request once CI passed (before CI existed, once its local checks did), apart from [#126](https://github.com/katonometrica/prexp/pull/126) and [#127](https://github.com/katonometrica/prexp/pull/127), which the developer merged, and stopped at the end of each of Phases 0 to 5.
- *(Session record)* The agent started the review agents itself, under a setting the developer chose that has it run multi-agent workflows on substantive work.

## The specification during the build

The specification was edited throughout the build, not held fixed. But it changed by adding to itself: its structure and most of its first text still stand.

- **Up to #134, 40 commits on `main` changed [docs/spec.md](https://github.com/katonometrica/prexp/commits/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md).** One is [#56](https://github.com/katonometrica/prexp/pull/56), which created it. The other 39 are 53% of the 73 pull requests after it: 13 on 23 November, 14 on the 24th, 7 on the 25th and 5 on the 26th.
- **36 of the 39 pull requests that edited it also changed code, tests or infrastructure.** The other three, [#81](https://github.com/katonometrica/prexp/pull/81), [#87](https://github.com/katonometrica/prexp/pull/87) and [#119](https://github.com/katonometrica/prexp/pull/119), record measurements or the server's settings.
- **It grew from 5,872 words to 10,308 (+75.5%),** but only from 438 lines to 484, because it keeps each paragraph and table row on one line ([first version](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md), [now](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md)).
- **Most of the first version stands:** 90.6% of its words, in order, and 242 of its 318 non-blank lines, word for word.
- **Its structure did not change.** All 28 headings are as first written, and so are §1 Versions and §8 Repository conventions. Four of the [five targets](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L26-L34) are word for word the same; the fifth, the row count, was rewritten from the real data.
- **No rule made spec edits travel with the code.** [§8](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L410-L419) makes tests ship in the same pull request as the code they test, and has no such rule for the spec. It was a habit.

*How it was measured:* the commits from `git log -- docs/spec.md`; words are whitespace-separated tokens, compared with Python's `difflib` (autojunk off), each commit against its parent; sections by mapping each changed line to the heading above it. "The first version" is the one #56 committed.

### Every change

Kinds: **fact**, something learned during the build; **design**, a change of design; **target**, a target changed or relaxed; **wording**, a clarification; **scope**, new scope. A second kind is given where one applies. Kinds and reasons are judgments made from each pull request's description.

| Pull request | Merged | Sections | Words + / − | Kind | Why |
| --- | --- | --- | ---: | --- | --- |
| [#56](https://github.com/katonometrica/prexp/pull/56) | 23 Nov 08:36 | all | +5,872 | – | The specification, "made self-contained", committed with the repository ([who wrote it](#who-did-what)) |
| [#64](https://github.com/katonometrica/prexp/pull/64) | 23 Nov 09:23 | preamble, §3.2, §3.4, §4, §7, §10 | +358 / −128 | fact | The dataset check replaced every "(phase 0)" assumption: a source row is finer than practice, presentation and month, so the loader aggregates on load; exact `numeric` measures; `bsdtar` for the ZIP; `sha256`, because months are published again |
| [#65](https://github.com/katonometrica/prexp/pull/65) | 23 Nov 09:34 | §2.2 | +16 / −2 | design | RStudio opens without a sign-in, its port bound to 127.0.0.1 |
| [#66](https://github.com/katonometrica/prexp/pull/66) | 23 Nov 10:16 | §6.2 | +153 / −28 | design | Phase 0 review: a cancelled run could pass the required check, the build cache froze OS security updates, and re-running an old run could move `:main` back |
| [#67](https://github.com/katonometrica/prexp/pull/67) | 23 Nov 11:01 | Goal, §2.1, §2.2, §3.5, §6.3 | +168 / −21 | design | Phase 0 review: row counts from before the decision to aggregate, password resets, a snapshot test of the migrations' checksums, the RStudio trade-off stated |
| [#68](https://github.com/katonometrica/prexp/pull/68) | 23 Nov 11:35 | §2.1, §6.2 | +149 / −32 | design | CI images refreshed monthly and otherwise reused; the required check became a gate job |
| [#69](https://github.com/katonometrica/prexp/pull/69) | 23 Nov 12:41 | §2.3, §6.2, §6.3, §7, §9 | +117 / −58 | design, target | The server comes late: phases 1 to 5 run on the local stack, and the server arrives in P6-02. §9's hours went from 231 to 235 |
| [#70](https://github.com/katonometrica/prexp/pull/70) | 23 Nov 12:53 | §6.2 | +32 / −4 | design | The Ubuntu mirror passed as a build secret: as a build argument, it broke the cache |
| [#72](https://github.com/katonometrica/prexp/pull/72) | 23 Nov 14:20 | §3.2, §3.3 | +149 / −13 | design | Schema details found while writing the migrations: one `load_log` row per attempt, `first_seen` and `last_seen` on chemicals, the chapter's name, `app.v_region` |
| [#73](https://github.com/katonometrica/prexp/pull/73) | 23 Nov 14:25 | §5.1 | +12 / −0 | design | The source file's code in a file of its own, `fct_source.R` |
| [#74](https://github.com/katonometrica/prexp/pull/74) | 23 Nov 14:31 | §6.1 | +38 / −15 | fact | The fixtures as built: 3,984 rows from eight prescribers in all seven regions |
| [#76](https://github.com/katonometrica/prexp/pull/76) | 23 Nov 14:54 | §6.2 | +22 / −7 | design | After an 11.5-minute build, CI times the candidate mirrors and takes the fastest |
| [#79](https://github.com/katonometrica/prexp/pull/79) | 23 Nov 15:56 | §3.1, §4 | +227 / −46 | design | The loader's review: the planned 10 s lock timeout let app queries reach their own 5 s timeout, and the planned upsert changed `core` before the check. The dimensions are now written in the swap, and each lock wait is 1 s, tried up to 10 times |
| [#81](https://github.com/katonometrica/prexp/pull/81) | 23 Nov 16:08 | §3.4 | +80 / −51 | fact, target | One real month measured: the free disk asked for went from 80 GB to 50 GB |
| [#82](https://github.com/katonometrica/prexp/pull/82) | 24 Nov 09:19 | §4 | +100 / −12 | design | A smaller window must drop every month beyond it |
| [#84](https://github.com/katonometrica/prexp/pull/84) | 24 Nov 09:59 | §5.2 | +18 / −2 | design | Review: keyset paging by cost repeated and skipped rows, because a double is not a decimal |
| [#83](https://github.com/katonometrica/prexp/pull/83) | 24 Nov 10:06 | Goal, §3.4, §4, §6.3 | +92 / −21 | fact | Twelve months measured: 112.8 million fact rows, 20.7 GB |
| [#85](https://github.com/katonometrica/prexp/pull/85) | 24 Nov 10:50 | §5.2 | +139 / −27 | design, target | The plan check made stricter: it fails on any fact read that is not index-only, on heap fetches, on time and on no rows; review made its samples the worst cases |
| [#86](https://github.com/katonometrica/prexp/pull/86) | 24 Nov 11:35 | §3.2, §3.3, §4, §5.2 | +133 / −15 | design | Two-letter searches took 40 to 67 ms: prefix indexes, a covering rollup key, and two letters now match only the starts of words |
| [#87](https://github.com/katonometrica/prexp/pull/87) | 24 Nov 11:58 | §3.4, §5.2 | +43 / −23 | fact | Phase 2's indexes added about 50 MB; the database is 20.9 GB |
| [#88](https://github.com/katonometrica/prexp/pull/88) | 24 Nov 13:02 | §5.4 | +79 / −7 | design | Review: a client setting could talk the read-only check round, so the setting must come from the server |
| [#89](https://github.com/katonometrica/prexp/pull/89) | 24 Nov 13:38 | §5.2 | +160 / −4 | wording | The fetch functions' contract as built: 2 to 100 characters, wildcards escaped, return shapes, an error class |
| [#91](https://github.com/katonometrica/prexp/pull/91) | 24 Nov 14:52 | §6.1 | +64 / −7 | design | One fixture database per test run, so two runs at once never collide |
| [#92](https://github.com/katonometrica/prexp/pull/92) | 24 Nov 15:37 | §5.4 | +149 / −3 | design | Review: a plain hash in the log could give a search away, so the hash is keyed |
| [#94](https://github.com/katonometrica/prexp/pull/94) | 24 Nov 17:03 | §3.2 | +32 / −14 | wording | Review: a prescriber keeps the ICB and region of its own last month, not the latest month's |
| [#99](https://github.com/katonometrica/prexp/pull/99) | 24 Nov 19:44 | §5.2 | +18 / −0 | design | Regions that did not prescribe a drug were left out instead of shown at 0, so `fetch_regions()` was added |
| [#100](https://github.com/katonometrica/prexp/pull/100) | 24 Nov 19:52 | §5.4 | +80 / −19 | design | `bindCache()` keeps an error as it keeps a value, so the cache wraps the fetch functions instead |
| [#102](https://github.com/katonometrica/prexp/pull/102) | 24 Nov 21:49 | §6.3 | +9 / −1 | wording | A link to the load test's results |
| [#108](https://github.com/katonometrica/prexp/pull/108) | 25 Nov 01:34 | §5.2, §5.5 | +318 / −14 | design, target | The link's rules as built; a 7,500-character limit replaces the promise of 8,000, which review had found "neither met nor enforced" |
| [#109](https://github.com/katonometrica/prexp/pull/109) | 25 Nov 02:45 | §5.5 | +207 / −12 | design | The PowerPoint layout as built: exports run on a worker, and tables are capped at 25 rows |
| [#110](https://github.com/katonometrica/prexp/pull/110) | 25 Nov 03:44 | §5.5 | +157 / −6 | wording | The Word layout as built |
| [#111](https://github.com/katonometrica/prexp/pull/111) | 25 Nov 04:23 | §5.5 | +137 / −7 | wording | The Excel layout as built |
| [#113](https://github.com/katonometrica/prexp/pull/113) | 25 Nov 11:18 | §2.1, §6.2 | +183 / −11 | design | Chrome from Google's repository, as Ubuntu's chromium is a snap that cannot run in a container; the five browser flows |
| [#114](https://github.com/katonometrica/prexp/pull/114) | 25 Nov 12:07 | §4, §7 | +120 / −22 | design | `load_latest()` as built: it reloads months published again; review caught a stale row in §7 |
| [#116](https://github.com/katonometrica/prexp/pull/116) | 25 Nov 17:16 | §2.3, §7 | +160 / −21 | fact, target | The server's setup, rehearsed; no `robots.txt`, as the proxy cannot serve one |
| [#119](https://github.com/katonometrica/prexp/pull/119) | 26 Nov 00:20 | §7 | +44 / −13 | target | The server's cores are about half as fast, and its slowest checks take 52 to 58 ms, so the nightly check allows 150 ms |
| [#123](https://github.com/katonometrica/prexp/pull/123) | 26 Nov 00:44 | §2.2 | +1 / −2 | wording | A link moved to `development.md` |
| [#125](https://github.com/katonometrica/prexp/pull/125) | 26 Nov 12:11 | §5.4 | +150 / −1 | design | On the server, lookups took 569 ms at the 95th percentile: one message per lookup, and each chart drawn once |
| [#118](https://github.com/katonometrica/prexp/pull/118) | 26 Nov 13:51 | §6.2 | +83 / −17 | design | Deploys from CI through Coolify's API; the image packages public |
| [#133](https://github.com/katonometrica/prexp/pull/133) | 26 Nov 18:35 | §5.1, §5.3, §6.2 | +934 / −9 | scope | New scope ([#129](https://github.com/katonometrica/prexp/issues/129)): the company's look, and where the app departs from it for WCAG AA; browser flows 6 and 7 listed |

In all, the 39 edits added 5,131 words and removed 695.

| Kind | Edits | Words added |
| --- | ---: | ---: |
| Design | 25 | 2,886 |
| Fact | 6 | 771 |
| Wording | 6 | 496 |
| Scope | 1 | 934 |
| Target | 1 as the main kind ([#119](https://github.com/katonometrica/prexp/pull/119)), 5 more as the second | 44 |

| What set the edit off | Edits | Pull requests |
| --- | ---: | --- |
| A review's finding | 10 | #66, #67, #79, #84, #85, #88, #92, #94, #99, #108 |
| A measurement | 7 | #76, #81, #83, #86, #87, #119, #125 |
| A decision about the plan or the scope | 4 | #65 *(session record)*, #68, #69, #133 |
| The dataset check (P0-07) | 1 | #64 |
| The server's setup | 1 | #116 |
| A detail found while building | 16 | the rest |

Each edit is counted once, under its main trigger. Two had a review's finding as well: #83's and #114's own reviews caught spec text the change had made stale ([below](#where-the-spec-lagged-the-code)).

The sections edited most often were §6.2 CI (8 edits), §5.2 the query catalogue (7), §4 the loader (6) and §7 deployment (5). §5.3 Screens grew most, from 157 words to 1,014, not counting its heading, all of it in #133.

### Where the first version was wrong, and what caught it

Line links are to [the first version](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md).

1. **The loader contradicted itself twice.**
   - Step 5 upserted the dimensions ([L204](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md?plain=1#L204)), yet the spec promised that "a failure before step 8 changes nothing in `core`" ([L210](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md?plain=1#L210)). The loader's review reproduced it: a refused load left every dimension row with `last_seen = 202610`, a month that never loaded ([#78](https://github.com/katonometrica/prexp/pull/78)).
   - The swap's 10 s `lock_timeout` ([L207](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md?plain=1#L207)) was longer than the app's 5 s `statement_timeout` ([L85](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md?plain=1#L85)). The review reproduced an app query failing after 5,001 ms ([#79](https://github.com/katonometrica/prexp/pull/79)).
2. **The link's length.** "Keeps the worst case under 8,000 characters" ([L315](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md?plain=1#L315)) was, in the words of [#104](https://github.com/katonometrica/prexp/pull/104)'s review, "neither met nor enforced". A 7,500-character limit went into the code in #104 and into the spec in [#108](https://github.com/katonometrica/prexp/pull/108).
3. **`bindCache()`** ([L292](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md?plain=1#L292)) would have served one session's passing database error to every session asking the same. It was found while building the cache ([#100](https://github.com/katonometrica/prexp/pull/100)).
4. **The geography.** "Name, ICB and region take the latest month's values" ([L144](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md?plain=1#L144)) was wrong: a prescriber keeps those of its own last month. [#94](https://github.com/katonometrica/prexp/pull/94)'s review caught it.
5. **The row counts** went stale once the loader aggregated on load. The Phase 0 review caught it ([#67](https://github.com/katonometrica/prexp/pull/67)).
6. **Two requirements could not both hold.** Two-letter searches that match anywhere in a name took up to 67 ms against the 50 ms limit, so two letters now match only the starts of words ([#86](https://github.com/katonometrica/prexp/pull/86)).

### Where the spec lagged the code

| The code changed in | The spec caught up in | After |
| --- | --- | --- |
| [#78](https://github.com/katonometrica/prexp/pull/78), the dimensions written in the swap | [#79](https://github.com/katonometrica/prexp/pull/79) | 6 min |
| [#104](https://github.com/katonometrica/prexp/pull/104), the link's 7,500-character limit | [#108](https://github.com/katonometrica/prexp/pull/108) | 1 h 18 min |
| [#121](https://github.com/katonometrica/prexp/pull/121), the link to the source in the app's footer | [#133](https://github.com/katonometrica/prexp/pull/133) | 18 h |
| [#117](https://github.com/katonometrica/prexp/pull/117), typing over a pick, and browser flow 6 | [#133](https://github.com/katonometrica/prexp/pull/133), as a CI flow only | 26 h 54 min |

Still open on `main`:

- **The app's address.** §7 says it "never appears in the repository or its issues" ([L404](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L404)), and §8 says "no app URL in the repository" ([L419](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L419)). The README has linked the app since [#127](https://github.com/katonometrica/prexp/pull/127).
- **§2.1's system libraries** list `unzip`, but not `libarchive-tools`, whose `bsdtar` the loader uses, nor `tini`, process 1 in the app's image since [#66](https://github.com/katonometrica/prexp/pull/66) ([Dockerfile](../docker/Dockerfile)).
- **§5.1's package layout** names two files the exports' split by format replaced, `fct_export_office.R` and `fct_export_excel.R`, and leaves out nine in [R/](../R/), among them `fct_cache.R` and `fct_workers.R`.
- **§8's rule of "One pull request per ticket, on a branch `phase-N/<ticket id>-<short-name>`, with `Closes #<issue>`"** ([L415](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L415)). Counting the issue each names first, the 74 merged pull requests served 51 issues, and 13 of those issues took two to six. 62 of the 74 branches follow the pattern, and 47 descriptions open with "Closes", 27 with "Refs".
- **§9's work breakdown** has v1's 48 tickets, not the three added since: [#129](https://github.com/katonometrica/prexp/issues/129), [#131](https://github.com/katonometrica/prexp/issues/131) and [#135](https://github.com/katonometrica/prexp/issues/135), 19 h between them.

Twice a pull request's own review caught spec text the change had made stale: "Stale numbers" in [#83](https://github.com/katonometrica/prexp/pull/83), and a §7 row in [#114](https://github.com/katonometrica/prexp/pull/114).

## Drift against the targets

The five targets in [the first version](https://github.com/katonometrica/prexp/blob/465c59cc1abfe64cd0a0e51c0da6303df5b1f019/docs/spec.md?plain=1#L26-L34), and where each stands:

| Target | Now | Status |
| --- | --- | --- |
| Lookups under 300 ms at the 95th percentile, warm database | Development machine, five users: 191 ms, and 236 ms for the largest chemical after [#101](https://github.com/katonometrica/prexp/issues/101)'s fix ([benchmarks](benchmarks.md#the-app-under-load-p4-08)). Production server: 540 ms, and 699 ms for the largest chemical, after [#125](https://github.com/katonometrica/prexp/pull/125); 569 and 957 ms before it ([benchmarks](benchmarks.md#one-message-for-each-lookup-p6-02)) | **Met on the development machine, missed in production.** The target is unchanged. [#44](https://github.com/katonometrica/prexp/issues/44)'s box for it is open, and [#131](https://github.com/katonometrica/prexp/issues/131) is the next fix |
| Each app query under 50 ms in psql, with no sequential scan of the fact table | Development machine: every check passes, the slowest at 33 ms ([benchmarks](benchmarks.md#at-a-glance-p2-06)). Server: every plan is index-only and pruned, but 2 of the 25 checks take 52 to 58 ms warm ([benchmarks](benchmarks.md#the-server-measured-p6-02)) | **Met on the development machine; missed on time on the server.** The nightly check there allows 150 ms ([§7](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L401), [#119](https://github.com/katonometrica/prexp/pull/119)), while the targets still say 50 ms ([L31](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L31)) |
| Any export under 10 s, as a background task | A worst-case 15-item report takes 2.3 to 2.9 s in PowerPoint, on a worker ([#109](https://github.com/katonometrica/prexp/pull/109), [#112](https://github.com/katonometrica/prexp/pull/112)) | **Met,** and enforced by a test ([L206](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/test-export-formats.R#L206)), on the fixture database. Not measured on the production server |
| Coverage of 85% or more, enforced in CI | 98.94%, and CI also fails on any function without a test ([ci.yaml](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/.github/workflows/ci.yaml#L226-L243), [run](https://github.com/katonometrica/prexp/actions/runs/45893747192)) | **Met** |
| About 200 million rows | 218,504,372 source rows, 112,769,791 after aggregation ([benchmarks](benchmarks.md#at-a-glance-p2-06)) | **Changed in the spec** in [#67](https://github.com/katonometrica/prexp/pull/67) and [#83](https://github.com/katonometrica/prexp/pull/83): the rows are finer than assumed, and the loader aggregates them ([#64](https://github.com/katonometrica/prexp/pull/64)) |

The production figures are measured from the development machine over the internet, with the round trip and TLS included and the search's 300 ms wait left out; [benchmarks.md](benchmarks.md#the-server-measured-p6-02) gives the method.

Other requirements of the first version that changed:

| First version | Now | Why |
| --- | --- | --- |
| `unzip -p`; a 10 s lock; the dimensions upserted | `bsdtar`; lock waits of 1 s, tried up to 10 times; the dimensions written in the swap | [#64](https://github.com/katonometrica/prexp/pull/64), [#78](https://github.com/katonometrica/prexp/pull/78), [#79](https://github.com/katonometrica/prexp/pull/79) |
| `bindCache()`; links under 8,000 characters | A 200 MB cache around the fetch functions; a 7,500-character limit | [#100](https://github.com/katonometrica/prexp/pull/100), [#104](https://github.com/katonometrica/prexp/pull/104), [#108](https://github.com/katonometrica/prexp/pull/108) |
| The plan check fails on a sequential scan or on more than 50 ms | Also on any fact read that is not index-only, on heap fetches, on partitions not pruned and on no rows | [#85](https://github.com/katonometrica/prexp/pull/85) |
| 80 GB of free disk | 50 GB, from one real month measured | [#81](https://github.com/katonometrica/prexp/pull/81) |
| A server from Phase 1, and staging in Phase 4 | The local stack until P6-02, and no staging | [#69](https://github.com/katonometrica/prexp/pull/69) |
| Private image packages; a `robots.txt` if the proxy can serve one | Public packages; no `robots.txt` | [#118](https://github.com/katonometrica/prexp/pull/118), [#116](https://github.com/katonometrica/prexp/pull/116) |

## What the reviews caught

43 of the 74 pull requests' descriptions record a review. By their own count, they hold at least 275 confirmed findings:

- **18** from Phase 0's review of work already merged, in the tables of [#66](https://github.com/katonometrica/prexp/pull/66) and [#67](https://github.com/katonometrica/prexp/pull/67);
- **2** that came after the change they were about had merged, in [#68](https://github.com/katonometrica/prexp/pull/68) and [#90](https://github.com/katonometrica/prexp/pull/90);
- **at least 255** before a merge.

The count takes the loader's eight distinct problems once ([#77](https://github.com/katonometrica/prexp/pull/77) to [#79](https://github.com/katonometrica/prexp/pull/79)). Six descriptions that record a review give no count: #84, #85, #86, #114, #128 and #132.

### At the phase's end

The only review of a whole phase in the record is Phase 0's, by review agents, across CI and the images, the database setup, the tests and the documents. [#66](https://github.com/katonometrica/prexp/pull/66) and [#67](https://github.com/katonometrica/prexp/pull/67) list 18 of its findings and fix them: "Each finding was checked by a second agent that tried to refute it". A second round, on those two fix branches, led to the smaller fixes in [#68](https://github.com/katonometrica/prexp/pull/68).

| What it found | Fixed in | Why CI had not caught it |
| --- | --- | --- |
| Cancelling a run left the required check `test` skipped, and GitHub counts a skipped required check as passed | #66, then a gate job in #68 | It shows only when a run is cancelled, and CI cannot check the rules about its own required check |
| The build cache froze `apt-get upgrade` at the first build, so the images would never get Ubuntu's security fixes | #66; monthly from #68 | Builds and tests passed; nothing checked how old the OS layer was |
| Every pull request's run, Dependabot's included, held a token that could write packages | #66 | Token scopes are not tested |
| Re-running an older run on `main` moved `:main` back to an older commit | #66 | It happens only on a re-run |
| R ran as process 1, so `docker stop` waited for a kill | #66, with `tini` | CI never stops the app's container |
| The required check was not strict, so a green `test` could stand for a merge that was never tested | #66, the ruleset | A setting of the ruleset, outside CI |
| After a password change in `.env`, an existing database kept the old passwords | #67 | Each CI run starts from an empty database |
| Password statements reached the server's log when statement logging was on | #67 | CI does not turn that logging on |
| Nothing noticed an edit to a migration already applied | #67: a snapshot test of their checksums. At first CI skipped it in silence, so CI now sets `NOT_CRAN` ([5aa4cf4](https://github.com/katonometrica/prexp/commit/5aa4cf45b1908d617a24415d22d0fc93d37c9af5), in #67) | No test existed, and then CI skipped the new one |
| The README's steps for adding a package failed as written, and it called RStudio without a sign-in "safe" | #67 | CI does not run the README |

Phase 0 also ended with a change of plan, the only one that moved an estimate: the server would come late, so phases 1 to 5 ran on the local stack ([#69](https://github.com/katonometrica/prexp/pull/69)).

*(Session record)* There were six phase-end stops, one after each of Phases 0 to 5. At each, the agent reported and the developer gave the go-ahead. The change of plan came just before the first stop's report. Phase 6 began after Phase 5's go-ahead on 25 November; after the developer's "continue and finish" that evening, Phases 6 and 7 ran on together without a stop, and both are still open.

### Before the merge

From Phase 1 on, the reviews were of pull requests, one at a time or a few together, such as the loader's three ([#77](https://github.com/katonometrica/prexp/pull/77) to [#79](https://github.com/katonometrica/prexp/pull/79)), and most of them came before the merge ([when the merge came first](#when-the-merge-came-first)).

- **From [#83](https://github.com/katonometrica/prexp/pull/83) to [#117](https://github.com/katonometrica/prexp/pull/117), every pull request but the two that only add packages records a review.** From #118 to #124, none does.
- **Eight name mutation tests:** #91, #95, #96, #97, #98, #113, #114 and #117. In [#88](https://github.com/katonometrica/prexp/pull/88), [#90](https://github.com/katonometrica/prexp/pull/90), [#91](https://github.com/katonometrica/prexp/pull/91) and [#92](https://github.com/katonometrica/prexp/pull/92), the agent broke the code to show that a new test fails.

The findings that mattered most:

| Pull request | What the review found | What guards it now |
| --- | --- | --- |
| [#78](https://github.com/katonometrica/prexp/pull/78), [#79](https://github.com/katonometrica/prexp/pull/79) | A refused month still stamped every practice, presentation and chemical with a month that never loaded. Under the planned 10 s lock timeout, an app query failed at 5,001 ms behind the swap | "A file for another month is refused, and changes nothing in core"; a swap that meets a real lock retries, then gives up unchanged ([test-loader.R](../tests/testthat/test-loader.R)) |
| [#84](https://github.com/katonometrica/prexp/pull/84) | Keyset paging by cost repeated and skipped rows: RPostgres reads the total as a double, with 17 significant digits | Paging walked through RPostgres for each measure |
| [#85](https://github.com/katonometrica/prexp/pull/85) | The plan check let heap reads through, and its large samples were not the worst cases | Heap reads fail the check; the worst cases are picked from the data |
| [#88](https://github.com/katonometrica/prexp/pull/88), [#90](https://github.com/katonometrica/prexp/pull/90) | The read-only check could be talked round with `PGOPTIONS`, and it tested the role a connection acts as, not its login | Tests of the login; the key ones were shown to fail with the check broken ([the trace below](#one-requirement-end-to-end)) |
| [#92](https://github.com/katonometrica/prexp/pull/92) | Anyone with the log could recover a search by hashing guesses until one matched | A keyed hash |
| [#94](https://github.com/katonometrica/prexp/pull/94) | A lost database connection could stop the app, through the pool's background check | Connections checked only when borrowed |
| [#102](https://github.com/katonometrica/prexp/pull/102) | The load test picked only small drugs, so the largest chemical went unmeasured | A recording of the largest chemical, whose run found [#101](https://github.com/katonometrica/prexp/issues/101) |
| [#104](https://github.com/katonometrica/prexp/pull/104) | A link of about 300 characters, nested tens of thousands deep, crashed the R process that serves every session. Another made the server fetch a URL or read a file | Depth checked before parsing; tests for nested, oversized and foreign links, and for links that hold a URL or a file's path |
| [#108](https://github.com/katonometrica/prexp/pull/108) | A link could show one drug's figures under another drug's name | Each drug and practice looked up by its code |
| [#113](https://github.com/katonometrica/prexp/pull/113) | CI would pass with every browser flow skipped if Chrome failed to start | A skipped flow fails the step |
| [#116](https://github.com/katonometrica/prexp/pull/116) | The deploy token would have crossed in clear to Coolify's plain-HTTP address | The deploy step builds an HTTPS address only ([#118](https://github.com/katonometrica/prexp/pull/118)) |
| [#117](https://github.com/katonometrica/prexp/pull/117) | The first version of the fix for [#115](https://github.com/katonometrica/prexp/issues/115) had a 50 ms race that could empty the view | Browser flow 6 |
| [#133](https://github.com/katonometrica/prexp/pull/133) | Bootstrap, bslib or reactable had removed the focus outlines, and disabled buttons looked enabled | Browser flow 7 and a unit test, for the focus outlines; a unit test of the disabled colour's contrast in both themes ([test-theme.R L191–L216](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/test-theme.R#L191-L216)) |

### When the merge came first

The descriptions show four merges that came before their review had finished:

- [#88](https://github.com/katonometrica/prexp/pull/88): the last verifier's note arrived after the merge. [#90](https://github.com/katonometrica/prexp/pull/90) closed the gap 10 minutes later.
- [#126](https://github.com/katonometrica/prexp/pull/126) and [#127](https://github.com/katonometrica/prexp/pull/127) merged while #126's review was running. *(Session record)* The developer merged both. [#128](https://github.com/katonometrica/prexp/pull/128) brought the review's confirmed fixes: "How it was built said more than the history shows".
- [#130](https://github.com/katonometrica/prexp/pull/130): "#130 merged before its review had finished" ([#132](https://github.com/katonometrica/prexp/pull/132)). For 53 minutes, `docs/benchmarks.md` on `main` misstated what made up a run's slowest 5%.

### What CI caught

- **On pull requests, 111 runs:** 101 passed, 7 were cancelled and 3 failed. One failure was meant: [#62](https://github.com/katonometrica/prexp/pull/62) deleted a test to show the coverage gate fails ([run](https://github.com/katonometrica/prexp/actions/runs/45144399668)). The other two stopped a change: #68's CI image did not build ([run](https://github.com/katonometrica/prexp/actions/runs/45165458126)), and #72 failed lint ([run](https://github.com/katonometrica/prexp/actions/runs/45189890111)).
- **On `main`, 69 runs:** 68 passed. #80's failed while pushing the app's image to the registry ([run](https://github.com/katonometrica/prexp/actions/runs/45211653716)).
- **CI itself had holes, which reviews found:** a cancelled run counted as passed ([#66](https://github.com/katonometrica/prexp/pull/66)); a snapshot test skipped in silence ([#67](https://github.com/katonometrica/prexp/pull/67)); and browser flows that would have been skipped, and CI passed, if Chrome could not start ([#113](https://github.com/katonometrica/prexp/pull/113)).

### The developer's catches

*(Session record)* Who found what is mostly not in the public record. These are the developer's catches that changed the work, each with the public change that followed.

| When | What the developer caught | What followed |
| --- | --- | --- |
| 23 Nov | #68's own CI image builds were still running after 18 minutes; both were cancelled by later pushes ([run](https://github.com/katonometrica/prexp/actions/runs/45157726144), [run](https://github.com/katonometrica/prexp/actions/runs/45161611380)). The cause was Ubuntu's mirror: "28.6 MB in 7min 36s" | [#68](https://github.com/katonometrica/prexp/pull/68)'s faster builds, [#70](https://github.com/katonometrica/prexp/pull/70), [#76](https://github.com/katonometrica/prexp/pull/76) |
| 25 Nov | After one pick, the search box took no more keys. A review had flagged it, the agent had shipped a clear button, and the browser flows never searched twice | [#115](https://github.com/katonometrica/prexp/issues/115), [#117](https://github.com/katonometrica/prexp/pull/117) |
| 25 Nov | A finished deploy step sat in a local commit that the agent had not pushed | [#118](https://github.com/katonometrica/prexp/pull/118), opened that evening |
| 26 Nov | The README's screenshots still showed the old look after the restyle went live; the agent had queued them behind other work | [#134](https://github.com/katonometrica/prexp/pull/134) |

*(Session record)* Outside readers' assessments, which the developer brought in, led to [#121](https://github.com/katonometrica/prexp/pull/121), [#123](https://github.com/katonometrica/prexp/pull/123), [release v0.1.0](https://github.com/katonometrica/prexp/releases/tag/v0.1.0) and this page ([#135](https://github.com/katonometrica/prexp/issues/135)). Instructions, decisions and new directions are not counted as catches: RStudio without a sign-in ([#65](https://github.com/katonometrica/prexp/pull/65)), the server coming late ([#69](https://github.com/katonometrica/prexp/pull/69)), crediting Claude Code in the README, which the agent asked about ([#126](https://github.com/katonometrica/prexp/pull/126)), and the restyle ([#129](https://github.com/katonometrica/prexp/issues/129)).

### What this says about the person in the loop

Apart from Phase 0's review, which agents ran, the record shows no defect caught at a phase's end. Review agents caught most of the defects on record before the merge, and the planned load test caught [#101](https://github.com/katonometrica/prexp/issues/101). The three checks that only a person could make, that each export opens in PowerPoint, Word and Excel, were still unticked when [#39](https://github.com/katonometrica/prexp/issues/39), [#40](https://github.com/katonometrica/prexp/issues/40) and [#41](https://github.com/katonometrica/prexp/issues/41) closed on merge ([the unticked boxes](#other-failures-in-brief)). *(Session record)* Each stop ended in a go-ahead. Some of what got past the reviews and the tests, the developer caught after the last stop: by using the app ([#115](https://github.com/katonometrica/prexp/issues/115), 25 November) and by looking at the README ([#134](https://github.com/katonometrica/prexp/pull/134), 26 November).

## Estimates against time

**How it was measured.**

- **Estimates:** the "**Estimate** N h" on each issue's first line. **Days planned:** [spec §9](spec.md#9-work-breakdown).
- **Time taken:** from the first commit of a milestone's pull requests to its last merge. Commit times are their author dates, from GitHub's API.
- **A pull request belongs to** the milestone of the issue it names first.

| Milestone | Issues (closed) | Estimate | Days planned | Pull requests | First commit to last merge | Hours |
| --- | --- | ---: | ---: | ---: | --- | ---: |
| [Phase 0 · Setup](https://github.com/katonometrica/prexp/milestone/1) | 7 (7) | 18 h | 2 | 15 | 23 Nov 08:36 to 14:54 | 6.3 |
| [Phase 1 · Data](https://github.com/katonometrica/prexp/milestone/2) | 9 (9) | 29 h | 4 | 10 | 23 Nov 13:59 to 16:08 | 2.1 |
| [Phase 2 · Scale](https://github.com/katonometrica/prexp/milestone/3) | 6 (6) | 24 h | 3 | 6 | 24 Nov 08:25 to 11:58 | 3.6 |
| [Phase 3 · Data layer](https://github.com/katonometrica/prexp/milestone/4) | 4 (4) | 16 h | 2 | 5 | 24 Nov 12:21 to 15:37 | 3.3 |
| [Phase 4 · App](https://github.com/katonometrica/prexp/milestone/5) | 9 (9), the bug #101 among them | 33 h | 4 | 10 | 24 Nov 15:50 to 22:44 | 6.9 |
| [Phase 5 · Reports](https://github.com/katonometrica/prexp/milestone/6) | 8 (8) | 32 h | 4 | 9 | 24 Nov 22:45 to 25 Nov 04:30 | 5.8 |
| [Phase 6 · Ship](https://github.com/katonometrica/prexp/milestone/7) | 6 (3), the bug #115 and the new #131 among them | 19 h, and 5 h for #131 | 2 | 11 | 25 Nov 08:35 to 26 Nov 16:59 | 32.4, open |
| [Phase 7 · Write up](https://github.com/katonometrica/prexp/milestone/8) | 4 (2), the new #129 and #135 among them | 8 h, and 14 h for #129 and #135 | 1 | 8 | 25 Nov 23:26 to 26 Nov 20:48 | 21.4, open |
| [v2 · Practice variation](https://github.com/katonometrica/prexp/milestone/9) | 7 (0) | 56 h | 7 | 0 | – | – |

**In all:**

- **The spec's work breakdown priced v1, #1 to #48, at 179 h, and v2 at 56 h.** It was paced for a person: 22 working days for v1, or "about 18 weeks" at 10 hours a week ([§9](spec.md#9-work-breakdown)).
- **Phases 0 to 5, 152 h and 19 days planned,** ran from the first commit on `main`, 23 Nov 08:22, to [#112](https://github.com/katonometrica/prexp/pull/112)'s merge, 25 Nov 04:30: **44.1 calendar hours,** two nights included.
- **46 of v1's 48 issues had closed by 26 Nov 16:50,** 80.5 hours after the first commit: 168 h of estimates.
- **Two are open:** [#44](https://github.com/katonometrica/prexp/issues/44), 7 h, whose open boxes include the plan check and the 300 ms target on the production server, where lookups take 540 ms, and [#45](https://github.com/katonometrica/prexp/issues/45), 4 h, which waits on a live monthly reload there.
- **Merges per day, up to #134:** 25 on 23 November, 21 on the 24th, 13 on the 25th and 15 on the 26th.

**The change of plan at Phase 0's end.** [#69](https://github.com/katonometrica/prexp/pull/69) moved the server's work in Phases 1 to 5 into P6-02. It changed two estimates, P1-08 ([#15](https://github.com/katonometrica/prexp/issues/15)) from 3 h to 2 h and P6-02 ([#44](https://github.com/katonometrica/prexp/issues/44)) from 2 h to 7 h, and §9's totals from 175 h to 179 h for v1 and from 231 h to 235 h in all. No other estimate changed, but the issues' text did. After the first pull request, 29 of the 55 issues were edited beyond their ticked boxes, 26 of them on 23 November in two batches that share #12, #44 and #45: 11 took the dataset check's findings just before [#64](https://github.com/katonometrica/prexp/pull/64) merged, and 18 took this change of plan, as #69 says: "P1-08, P1-09, P2-02, P4-08 and P6-02 have new titles and tasks". Later edits added and removed notes on [#12](https://github.com/katonometrica/prexp/issues/12) the same day, followed the loader's review ([#13](https://github.com/katonometrica/prexp/issues/13), [#14](https://github.com/katonometrica/prexp/issues/14)), added tasks found while building ([#27](https://github.com/katonometrica/prexp/issues/27), [#33](https://github.com/katonometrica/prexp/issues/33), [#34](https://github.com/katonometrica/prexp/issues/34)), or recorded a decision: the app's address made public ([#48](https://github.com/katonometrica/prexp/issues/48), 26 November). *How it was measured:* each issue's edit history from GitHub's API (`userContentEdits`), with successive versions compared after unticking every box.

**Caveats.**

- **Calendar time is not effort.** The estimates, which the agent wrote into the issues ([who did what](#who-did-what)), price one person working by hand, and the developer's own hours were not measured. The comparison measures how fast the work went, not how good the estimates were.
- **Most pull requests were committed when the work was done.** 50 of the 74 have a single commit, and in 45 the first commit came at most two minutes before the pull request opened. Writing and reviewing before a milestone's first commit is not counted. P1-07 ([#14](https://github.com/katonometrica/prexp/issues/14)), at 8 h the largest v1 ticket, went from its one commit to its merge in 4 minutes ([#79](https://github.com/katonometrica/prexp/pull/79)): the loader had been written and reviewed before ([#77](https://github.com/katonometrica/prexp/pull/77)).
- **The agent worked on issues side by side.** In Phase 4 the issues' own times add up to 17.3 hours, inside a phase of 6.9.
- **Work before the first commit on 23 Nov is not counted.** *(Session record)* The session began on 21 Nov at 22:03. The agent wrote the specification and the issues' text that evening, from the developer's project plan, and the developer approved them on 23 Nov at 08:13, nine minutes before the first commit.
- **Open milestones have no final figure.**

**Where the time went.**

- **P6-02 ([#44](https://github.com/katonometrica/prexp/issues/44)), 2 h, then 7 h:** six pull requests over 29.6 hours, and still open.
  - [#118](https://github.com/katonometrica/prexp/pull/118) waited 15.4 hours for "a deploy-only token", "the four repository secrets" and Coolify's renewed HTTPS certificate.
  - The server's measurements ([#124](https://github.com/katonometrica/prexp/pull/124): 569 ms) led to a rework ([#125](https://github.com/katonometrica/prexp/pull/125)) and a second measurement ([#130](https://github.com/katonometrica/prexp/pull/130): 540 ms), whose finding became [#131](https://github.com/katonometrica/prexp/issues/131).
- **P6-03 ([#45](https://github.com/katonometrica/prexp/issues/45)), 4 h:** two pull requests over 15.6 hours, and still open.
- **P7-02 ([#48](https://github.com/katonometrica/prexp/issues/48)), 5 h:** four pull requests over 16.2 hours. The architecture page came first ([#122](https://github.com/katonometrica/prexp/pull/122)), then the README, reworked after review ([#126](https://github.com/katonometrica/prexp/pull/126) to [#128](https://github.com/katonometrica/prexp/pull/128)).
- **P0-06 ([#6](https://github.com/katonometrica/prexp/issues/6)), 4 h:** five pull requests over 6 hours, most about the speed of Ubuntu's mirror in CI ([#68](https://github.com/katonometrica/prexp/pull/68), [#70](https://github.com/katonometrica/prexp/pull/70), [#76](https://github.com/katonometrica/prexp/pull/76)).

## Where the agent failed

### #101: the Drug view, slow for the largest chemical

| | |
| --- | --- |
| **Found by** | The planned load test, P4-08 ([#34](https://github.com/katonometrica/prexp/issues/34)), after its review objected: "The session picked only small things, so the largest chemical went unmeasured" ([#102](https://github.com/katonometrica/prexp/pull/102)). The ticket's rule then opened the issue: "an issue is open for each slow path" |
| **Symptom** | For the chemical with the most presentations, 2003 (dressings, 2,068 presentations), lookups took 864 ms at the 95th percentile with five users, against 300 ms. While its table was built, every other session waited: search results took up to 661 ms ([#101](https://github.com/katonometrica/prexp/issues/101)) |
| **Root cause** | The presentations table had no row limit, and two of its columns had an R function that reactable calls once per row: about 300 ms of the table's 430 ms. One R process answers every session. The database's part was 24 to 32 ms |
| **On `main`** | 3 h 27 min, from [#97](https://github.com/katonometrica/prexp/pull/97) (24 Nov 19:17) to [#103](https://github.com/katonometrica/prexp/pull/103) (22:44). The production server's first measured image was built a day later, from [#116](https://github.com/katonometrica/prexp/pull/116), and already had the fix ([benchmarks](benchmarks.md#the-server-measured-p6-02)) |
| **The fix** | [#103](https://github.com/katonometrica/prexp/pull/103), 1 h 34 min after the issue was opened: the two columns formatted once each, into hidden columns that a JavaScript cell shows. Replayed the same way, 236 ms at the 95th percentile |
| **Regression test** | ["a chemical's thousands of presentations are written once per column (#101)"](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/test-mod-drug.R#L620), in CI's `checks` job. It checks how the table is built, not how long it takes: the time is still checked by hand |
| **Back in the spec** | Not from this fix. The spec's first rules about drawing came 37 hours later, in [#125](https://github.com/katonometrica/prexp/pull/125), once the production server had missed the target too |

**Why the tests missed it.**

- **CI does not time lookups.** The 300 ms target is one of the checks that need the full database, which are run by hand ([§6.3](spec.md#63-checks-that-need-the-full-database)).
- **CI's database is the fixtures.** There, the chemical with the most presentations has 132, and 2003 has 79, by a count of the distinct presentation codes per chemical in two fixture months ([fixtures](../tests/testthat/fixtures/)).
- **The view's own checks were small.** Its tests used fake fetches, and its check by hand on the full database used atorvastatin ([#97](https://github.com/katonometrica/prexp/pull/97)).
- **The worst case was written down already.** When #97 merged, `docs/benchmarks.md` named 2003 and its 2,068 presentations as the presentations query's large sample ([L243](https://github.com/katonometrica/prexp/blob/e2b78e0312d6f7e69a4c541d2e822a96626096ce/docs/benchmarks.md?plain=1#L243)). That served the query checks; neither the view's tests nor the load test used it.
- **The plan check had made the same mistake,** and its review had caught it: "The large samples are now the worst cases, which the first version missed" ([#85](https://github.com/katonometrica/prexp/pull/85)).

**What the spec missed.** It kept a worst case for every query: "the chemical with the most presentation rollup rows" ([§5.2 before the fix](https://github.com/katonometrica/prexp/blob/ff264954e2d32078afd8da3a49ae641073eeaaf8/docs/spec.md?plain=1#L282)). It asked the load test only for "a session of searches and view changes" ([§6.3](https://github.com/katonometrica/prexp/blob/ff264954e2d32078afd8da3a49ae641073eeaaf8/docs/spec.md?plain=1#L364)), and set no size for the Drug view's table ([§5.3](https://github.com/katonometrica/prexp/blob/ff264954e2d32078afd8da3a49ae641073eeaaf8/docs/spec.md?plain=1#L300)). The time went into building the view in R, and none of the spec's worst cases covered that.

**How it reached the spec.** It has not, quite. The per-column rule is in a code comment ([utils_view.R](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/R/utils_view.R#L321-L330)), in `docs/benchmarks.md`, and in the largest-chemical recordings that later load tests replay ([bench/](../bench/)). The same view then took 370 ms on the rehearsal's four shared CPUs ([benchmarks](benchmarks.md#the-server-rehearsed-p6-02)) and 957 ms on the production server ([benchmarks](benchmarks.md#the-server-measured-p6-02)). [#125](https://github.com/katonometrica/prexp/pull/125) answered each lookup in one message and drew each chart once, and put those two rules in [§5.4](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L337). The largest chemical still takes 699 ms there.

**What failed:** the agent built the view without the worst case its own notes had recorded, checked it by hand on a small drug, recorded the load test on small drugs, and closed the issue on a check that held on one machine. **What worked:** the ticket's rule for slow paths, the review of the load test, and a fix measured the same way before and after.

### #115: typing over a pick did nothing

| | |
| --- | --- |
| **Found by** | Trying the app locally: "one search and one pick reached the app, then nothing more" ([#115](https://github.com/katonometrica/prexp/issues/115)). *(Session record)* The developer found it. The agent's first answers blamed the input; its second look, at the app's log, found the cause |
| **Seen earlier** | A day before, P4-03's review flagged it. [#96](https://github.com/katonometrica/prexp/pull/96) counts "typing could not start a new search after a pick" among the findings it fixed, with a clear button. The merged code says so: "a clear button for a new search, which typing cannot start while a pick fills the box" ([mod_search.R](https://github.com/katonometrica/prexp/blob/e0662017e5c8cb6b456293df8aaca7a146d1c573/R/mod_search.R#L30-L31)) |
| **Symptom** | After a pick, the search box dropped every key and paste without a sign. Only Backspace or a small × freed it |
| **Root cause** | In single-pick mode, selectize ignores keys and pastes while it holds a pick, and the code relied on the clear button |
| **On `main`** | 20 h 40 min, from [#96](https://github.com/katonometrica/prexp/pull/96) (24 Nov 19:00) to [#117](https://github.com/katonometrica/prexp/pull/117) (25 Nov 15:41). The production server's first measured image was built later that day, from [#116](https://github.com/katonometrica/prexp/pull/116), and already had the fix |
| **The fix** | [#117](https://github.com/katonometrica/prexp/pull/117): typing, pasting or text with no key takes the pick out of the box without telling Shiny, so the view keeps it; leaving the box puts it back ([search.js](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/inst/app/www/search.js#L28)). Its own review confirmed nine findings on the fix's first version, among them a 50 ms race that could empty the view |
| **Regression test** | Browser flow 1 types a second drug straight over the first ([L259](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/e2e-flows.R#L259)), and a new flow 6 types, pastes and enters text with no key over a pick ([L473](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/e2e-flows.R#L473)). "Before the fix, flows 1 and 6 fail at these checks" |
| **Back in the spec** | Not from this fix. 26 h 54 min later, a restyle ([#133](https://github.com/katonometrica/prexp/pull/133)) changed §6.2's "Five flows" to seven, one of them "type, paste or dictate over a picked drug" ([L379](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L379)). §5 still does not describe the behaviour itself |

The fix came before the issue: its first commit, [951db76](https://github.com/katonometrica/prexp/commit/951db76daac8217a1f8231505a71adf0ba9facd6), is 1 h 17 min older than #115, and #115 has no estimate and no "done when" checks.

**Why the tests missed it.**

- **The unit tests never ran a browser.** The search module's tests use `testServer()`, as P4-03's ticket asked ([#29](https://github.com/katonometrica/prexp/issues/29)). One of them asserted the workaround: `expect_match(ui, "clear_button", fixed = TRUE)` ([test-mod-search.R](https://github.com/katonometrica/prexp/blob/e0662017e5c8cb6b456293df8aaca7a146d1c573/tests/testthat/test-mod-search.R#L249-L255)).
- **The browser flows never searched twice.** They came that morning ([#113](https://github.com/katonometrica/prexp/pull/113)), and each used each search box once ([flow 1](https://github.com/katonometrica/prexp/blob/e0662017e5c8cb6b456293df8aaca7a146d1c573/tests/testthat/e2e-flows.R#L156-L162)). Their helper never checked that the box took the keys; it now does ([L96](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/e2e-flows.R#L96)).

**What the spec missed.** §5.4 described a first search only: a script "sends typed text to the server, which ignores fewer than two characters, debounces at 300 ms, and sends back up to 20 matches" ([L312](https://github.com/katonometrica/prexp/blob/e0662017e5c8cb6b456293df8aaca7a146d1c573/docs/spec.md?plain=1#L312)). It said nothing about a box that already holds a pick, and §6.2's five flows each searched once ([L356](https://github.com/katonometrica/prexp/blob/e0662017e5c8cb6b456293df8aaca7a146d1c573/docs/spec.md?plain=1#L356)).

**How it reached the spec.** Only as a CI flow, and 27 hours late: for that day the spec listed five flows while CI ran six. §5.4's search sentence is word for word what it was ([L334](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L334)). The requirement lives in the issue, the script and the test. Flow 6 covers the Drug box only: the Practice and Region boxes share the script, but no flow types over their picks.

**What failed:** the agent's own review found the bug, and the agent shipped a cheaper workaround and called it fixed; its browser flows never searched twice; and the behaviour itself has not reached §5. **What worked:** a person using the app, a review that caught a worse bug in the fix's first version, and a flow shown to fail without the fix.

### Other failures in brief

- **CI's setup needed four follow-ups in a day,** all naming P0-06 ([#6](https://github.com/katonometrica/prexp/issues/6)): [#66](https://github.com/katonometrica/prexp/pull/66), [#68](https://github.com/katonometrica/prexp/pull/68), [#70](https://github.com/katonometrica/prexp/pull/70) and [#76](https://github.com/katonometrica/prexp/pull/76). Two fixed the one before. With #66's change to the required job, Cancel could no longer stop the tests, which #68 fixed; #68's mirror, passed as a build argument, broke the cache, which #70 fixed.
- **The read-only check, a second time.** It tested `current_user`, the role a connection acts as, not the login. A superuser whose own settings made it read-only could have connected as the app's role and got through. A verifier's note found it after #88 merged, and [#90](https://github.com/katonometrica/prexp/pull/90) fixed it.
- **A chart drawn twice.** The load test recorded that every drug or practice pick drew its chart twice ([benchmarks](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/benchmarks.md?plain=1#L342)), but no issue was opened. [#125](https://github.com/katonometrica/prexp/pull/125) fixed it two days later, once the server had shown the cost, along with the Practice view's paging after Try again: "This was a bug on main too".
- **A fix that made something else slower.** #125 computes every view's outputs as a session opens. On the server, opening became slower: 527 ms at the median, against 384 ms before ([#130](https://github.com/katonometrica/prexp/pull/130), [benchmarks](benchmarks.md#one-message-for-each-lookup-p6-02)). That now sets the 95th percentile, and [#131](https://github.com/katonometrica/prexp/issues/131) is open to fix it.
- **A wrong call.** After the rehearsal measured 370 ms for the largest chemical, [#116](https://github.com/katonometrica/prexp/pull/116) left it to be "measured again on the server before anything changes". The server's cores were about half as fast, and lookups for that chemical took 957 ms at the 95th percentile ([#124](https://github.com/katonometrica/prexp/pull/124)).
- **The unticked boxes.** [#39](https://github.com/katonometrica/prexp/issues/39), [#40](https://github.com/katonometrica/prexp/issues/40) and [#41](https://github.com/katonometrica/prexp/issues/41) closed on merge with their one box that needs a person still unticked: that the file opens in PowerPoint, Word or Excel. §8 says "a ticket is done when every **Done when** box is ticked and CI is green", but the "Closes" lines in [#109](https://github.com/katonometrica/prexp/pull/109), [#110](https://github.com/katonometrica/prexp/pull/110) and [#111](https://github.com/katonometrica/prexp/pull/111) closed the issues as they merged, at 02:45, 03:44 and 04:23 on 25 November. Up to #134, the 48 closed issues have 314 boxes ticked and these 3 unticked.
- **A README that claimed more than the history shows,** fixed in [#128](https://github.com/katonometrica/prexp/pull/128): three documentation issues name no section of the spec, the first five pull requests merged before CI existed, and the first commit was pushed directly.

## One requirement, end to end

The app must never run with a login that can write. This traces that requirement from the specification to production. Links are pinned to [25cd2f4](https://github.com/katonometrica/prexp/commit/25cd2f41fc3b8140677da31ff8ee74009ef8d10a) unless they name another commit.

| Link | What it says or does | Where |
| --- | --- | --- |
| **Specification** | §5.4: every connection the app opens "must be read-only by default from the server's settings for the login or the database (a default the client asks for, with `PGOPTIONS` or the `options` parameter, does not count), and its login must not be a superuser or able to use the `core` and `raw` schemas. Otherwise the connection is closed and refused" | [spec.md L333](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L333) |
| **Issue** | P3-01, 2 h: "Startup safety check: the app's connection must report `default_transaction_read_only = on`, or the app refuses to start", and "Tests: … a writable role is refused". Its "done when" is "Tests pass" | [#23](https://github.com/katonometrica/prexp/issues/23) |
| **Pull request** | Branch `phase-3/P3-01-pool`, `Closes #23`, opened 24 Nov 12:21 and merged 13:02. Its review: "Seven were confirmed, and all are fixed in 1a79c59" | [#88](https://github.com/katonometrica/prexp/pull/88), squashed as [601a372](https://github.com/katonometrica/prexp/commit/601a372f2aeb472b659f85213ee4faf7f74f0146) |
| **Follow-up** | `Refs #23`, "from the last verifier of its review, whose note arrived after the merge": tests the login, `session_user`, not the role it acts as. Merged 10 minutes after #88 | [#90](https://github.com/katonometrica/prexp/pull/90), [c3770d9](https://github.com/katonometrica/prexp/commit/c3770d94b54b7ba8db145e7ac771e0baf4d7b7fe) |
| **Code** | `check_read_only()`, called by `db_connect("app")` and as the pool's `onCreate` | [db.R L162–L196](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/R/db.R#L162-L196), [L87–L89](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/R/db.R#L87-L89), [L131](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/R/db.R#L131) |
| **The server's side** | `ALTER ROLE prexp_app SET default_transaction_read_only = on;` | [02-database.sql L7](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docker/db/init/02-database.sql#L7) |
| **Tests** | "the app refuses a login that can write, even one the client made read-only"; "a refused connection is closed before the error"; "a refused app login fails the tests that need it, rather than skip them" | [test-db.R L77–L119](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/test-db.R#L77-L119), [L121–L144](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/test-db.R#L121-L144), [L146–L155](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/test-db.R#L146-L155) |
| **No skipping** | A refused app login is raised again, never turned into a skip; with `PREXP_TEST_DB_REQUIRED=true`, a database that cannot be reached fails the tests | [helper-db.R L18–L29](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/helper-db.R#L18-L29), [L62–L67](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/helper-db.R#L62-L67) |
| **CI** | The `checks` job: a PostgreSQL 18.7 service, `PREXP_TEST_DB_REQUIRED: "true"`, the real role scripts, then every test under covr with the two coverage gates | [ci.yaml L163–L190](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/.github/workflows/ci.yaml#L163-L190), [L202–L211](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/.github/workflows/ci.yaml#L202-L211), [L226–L243](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/.github/workflows/ci.yaml#L226-L243) |
| **The required check** | The `test` job fails unless `checks` succeeded. The ruleset requires `test`, strict, with pull requests only, squash merges only and no one able to bypass it | [ci.yaml L284–L302](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/.github/workflows/ci.yaml#L284-L302), [protect-main.json](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/.github/rulesets/protect-main.json) |
| **Proof it ran** | On `main`'s run at 25cd2f4, PostgreSQL's log in the `checks` job shows "cannot execute CREATE TABLE in a read-only transaction" for `CREATE TABLE app.not_allowed (x int)`, the statement at test-db.R L59. Coverage of `R/db.R`: 99.52% | [run 45893747192](https://github.com/katonometrica/prexp/actions/runs/45893747192), [test-db.R L58–L60](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/test-db.R#L58-L60) |
| **Production** | The app's image runs `prexp::run_app()`, whose `onStart` opens the pool; each export worker connects with `db_connect("app")`. The server gives the app only its host, port, database and password: "The app refuses to start with a login that can write" | [Dockerfile L247](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docker/Dockerfile#L247), [run_app.R L32–L35](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/R/run_app.R#L32-L35), [fct_workers.R L85–L91](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/R/fct_workers.R#L85-L91), [server.md L70](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/server.md?plain=1#L70) |

**What fails if a step is removed.** Any of these fails "Test with coverage", so `checks` fails, so `test` fails, and the ruleset blocks the merge. This comes from reading the code and tests. The agent tried three of the breaks: two in #88 and one in #90.

| Break | What fails (lines of test-db.R) |
| --- | --- |
| Remove the check from `db_connect()` | L96, L102, L112–L113 and L141 expect a refusal and get none; L153 expects the loader's login to be refused |
| Remove `onCreate = check_read_only` from `db_pool()` | L89–L91, L94, L99, L109–L110, L139–L140 and L154 |
| Drop the rule that the setting must come from the server | L99, L102 and L112–L113. #88: "Without the source check, the client-request test fails" |
| Test `current_user` instead of `session_user` | L109–L113. #90: "With `current_user` put back, the test fails" |
| Drop the disconnect before the error | L126 and L143. #88: "Without the disconnect, the closing test fails" |
| Drop `ALTER ROLE prexp_app SET default_transaction_read_only = on` | L41, and every test that connects as the app, since `helper-db.R` raises the refusal again as a failure |
| Break the database setup so that the tests cannot connect | Every database test fails instead of skipping ([ci.yaml L181](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/.github/workflows/ci.yaml#L181)) |

One gap: nothing in CI stops someone deleting the refusal tests themselves. `check_read_only()` would still be covered by every other test that connects as the app, so both coverage gates would pass. Only a review would catch it.

**How it happened.**

1. The spec's line before the change was "The app refuses to start unless its connection is read-only", and the issue asked only that the connection "report `default_transaction_read_only = on`".
2. The agent's first commit, [91d2553](https://github.com/katonometrica/prexp/commit/91d2553b4ffe5a9a5050a62c27d403f8eb4ada42), did exactly that, and [its CI run](https://github.com/katonometrica/prexp/actions/runs/45392800770) passed. But the loader's or the owner's login got through if the client asked for the read-only default with `PGOPTIONS`, and could then turn it off again.
3. The review in #88 found it: two finders, then a verifier that checked each of their eight findings. The fix is [1a79c59](https://github.com/katonometrica/prexp/commit/1a79c597affec26bb77ac5252f6c18b7ffade713), whose [CI run](https://github.com/katonometrica/prexp/actions/runs/45398671895) passed too.
4. The spec moved with the code. The squash commit [601a372](https://github.com/katonometrica/prexp/commit/601a372f2aeb472b659f85213ee4faf7f74f0146) rewrote §5.4's line to the rule above, and it is the only commit that adds that wording.
5. A verifier's late note led to #90, ten minutes after the merge. The spec already said "its login", so it did not change.
6. Issue #23's text was never edited, apart from its ticked boxes.

The ticket was estimated at 2 h. From the merge before its pull request, [#87](https://github.com/katonometrica/prexp/pull/87) at 11:58, to #90's at 13:12 took 1 h 13 min, with P3-02 under way alongside it.

**A second chain, and its limit.** The target "Report export, any format: Under 10 s" ([L32](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/docs/spec.md?plain=1#L32)), unchanged since #56, runs to [#42](https://github.com/katonometrica/prexp/issues/42) (P5-08), then [#112](https://github.com/katonometrica/prexp/pull/112), then `expect_lt(took, 10, ...)` ([test-export-formats.R L206](https://github.com/katonometrica/prexp/blob/25cd2f41fc3b8140677da31ff8ee74009ef8d10a/tests/testthat/test-export-formats.R#L206)) in the same `checks` job and required check. But the test runs on the fixture database, so it guards the export code's speed, not the production server's.
