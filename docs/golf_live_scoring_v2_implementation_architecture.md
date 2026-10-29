# Golf Live Scoring V2 — Implementation Architecture v1.0

**Status:** FROZEN v1.0 — approved implementation authority.
**Repository:** `JCSchoeman96/golf-scoring`
**Product/domain authority:** `docs/golf_live_scoring_v2_spec_v1.0.md`
**Execution tracker:** Plane project `GLS` — Golf Live Scoring V2

This document defines implementation structure and sequencing. It does not override product/domain semantics in the frozen specification. If this architecture conflicts with the frozen Product & Domain Spec, the spec wins. Architecture changes that materially alter product/domain behavior require owner approval and a corresponding spec amendment. Amendments 1 and 2 supersede conflicting historical spec text.

## Principles and authority

Build greenfield V2 in this repository; the legacy repository is reference only. Use Phoenix, LiveView, Ash and AshPostgres. PostgreSQL is durable authority. Use named Ash actions and policies for explicit resource boundaries, pure Elixir for golf mathematics, short PostgreSQL locks for critical operations, idempotent group-hole submissions, and Phoenix PubSub only after commit. IndexedDB stores browser pending/offline commands; it is not score authority. Do not add Redis or distributed locks without measured need. Do not use event sourcing, a generic scoring/rules DSL, microservices or multi-tenancy.

The target is approximately 144 players, 36 PlayingGroups and an 18-hole shotgun event. Correctness takes priority over speculative scale infrastructure. Preserve the distinctions between Player and RoundEntry, group and side, catalog and snapshot, raw HoleResult and derived score, base handicap and competition handicap, rule and reveal, and message definition and dispatch.

## Domains and resources

The Ash domains and entry files are:

- `GolfScoring.Accounts`: `lib/golf_scoring/accounts.ex`
- `GolfScoring.GolfCatalog`: `lib/golf_scoring/golf_catalog.ex`
- `GolfScoring.Competition`: `lib/golf_scoring/competition.ex`
- `GolfScoring.Scoring`: `lib/golf_scoring/scoring.ex`
- `GolfScoring.Communications`: `lib/golf_scoring/communications.ex`
- `GolfScoring.Sponsorship`: `lib/golf_scoring/sponsorship.ex`
- `GolfScoring.SideCompetitions`: `lib/golf_scoring/side_competitions.ex`
- `GolfScoring.Audit`: `lib/golf_scoring/audit.ex`

`GolfScoring.Golf` is prohibited as a broad catch-all context. The resources below are durable AshPostgres resources. Their fields and lifecycle rules follow the spec; this map does not authorize generic CRUD over protected state.

| Resource | Domain | Exact file | Persistence | Responsibility |
|---|---|---|---|---|
| `StaffUser` | `Accounts` | `lib/golf_scoring/accounts/staff_user.ex` | PostgreSQL | Staff authentication, global SYSTEM_ADMIN capability and staff lifecycle |
| `EventStaffAssignment` | `Accounts` | `lib/golf_scoring/accounts/event_staff_assignment.ex` | PostgreSQL | Event-scoped staff authority |
| `PlayerAccessGrant` | `Accounts` | `lib/golf_scoring/accounts/player_access_grant.ex` | PostgreSQL | Event-scoped player access and revocation |
| `Course` | `GolfCatalog` | `lib/golf_scoring/golf_catalog/course.ex` | PostgreSQL | Reusable course |
| `CourseHole` | `GolfCatalog` | `lib/golf_scoring/golf_catalog/course_hole.ex` | PostgreSQL | Physical course hole |
| `TeeSet` | `GolfCatalog` | `lib/golf_scoring/golf_catalog/tee_set.ex` | PostgreSQL | Reusable tee set |
| `TeeRatingProfile` | `GolfCatalog` | `lib/golf_scoring/golf_catalog/tee_rating_profile.ex` | PostgreSQL | Tee rating context |
| `Event` | `Competition` | `lib/golf_scoring/competition/event.ex` | PostgreSQL | Event lifecycle |
| `Round` | `Competition` | `lib/golf_scoring/competition/round.ex` | PostgreSQL | Round lifecycle and locked configuration |
| `RoundHole` | `Competition` | `lib/golf_scoring/competition/round_hole.ex` | PostgreSQL | Ordered round route |
| `RoundTeeProfileSnapshot` | `Competition` | `lib/golf_scoring/competition/round_tee_profile_snapshot.ex` | PostgreSQL | Frozen tee rating context |
| `RoundTeeHoleSnapshot` | `Competition` | `lib/golf_scoring/competition/round_tee_hole_snapshot.ex` | PostgreSQL | Frozen tee-hole data |
| `Player` | `Competition` | `lib/golf_scoring/competition/player.ex` | PostgreSQL | Reusable player identity |
| `RoundEntry` | `Competition` | `lib/golf_scoring/competition/round_entry.ex` | PostgreSQL | Player participation in one round |
| `CompetitionCategory` | `Competition` | `lib/golf_scoring/competition/competition_category.ex` | PostgreSQL | Competition category |
| `RoundEntryCategoryMembership` | `Competition` | `lib/golf_scoring/competition/round_entry_category_membership.ex` | PostgreSQL | Entry category membership |
| `PlayingGroup` | `Competition` | `lib/golf_scoring/competition/playing_group.ex` | PostgreSQL | Physical group, starting assignment and progression |
| `RoundCompetition` | `Competition` | `lib/golf_scoring/competition/round_competition.ex` | PostgreSQL | Concrete competition configuration |
| `CompetitionSide` | `Competition` | `lib/golf_scoring/competition/competition_side.ex` | PostgreSQL | Competing side |
| `CompetitionSideMembership` | `Competition` | `lib/golf_scoring/competition/competition_side_membership.ex` | PostgreSQL | Entry membership in a competition side |
| `CompetitionSideResult` | `Competition` | `lib/golf_scoring/competition/competition_side_result.ex` | PostgreSQL | Side readiness and official result state |
| `GroupRoleAssignment` | `Competition` | `lib/golf_scoring/competition/group_role_assignment.ex` | PostgreSQL | Scorer and verifier authority history |
| `ScoringTrack` | `Competition` | `lib/golf_scoring/competition/scoring_track.ex` | PostgreSQL | Standard or Mystery scoring configuration |
| `MysteryHoleRule` | `Competition` | `lib/golf_scoring/competition/mystery_hole_rule.ex` | PostgreSQL | Secret rule for a track and round hole |
| `MysteryReveal` | `Competition` | `lib/golf_scoring/competition/mystery_reveal.ex` | PostgreSQL | One global reveal of one rule, with no PlayingGroup ownership |
| `HandicapSnapshot` | `Scoring` | `lib/golf_scoring/scoring/handicap_snapshot.ex` | PostgreSQL | Frozen base handicap facts |
| `CompetitionHandicap` | `Scoring` | `lib/golf_scoring/scoring/competition_handicap.ex` | PostgreSQL | Competition-specific playing handicap |
| `Scorecard` | `Scoring` | `lib/golf_scoring/scoring/scorecard.ex` | PostgreSQL | One entry scoring container |
| `HoleResult` | `Scoring` | `lib/golf_scoring/scoring/hole_result.ex` | PostgreSQL | Current raw player outcome and revision |
| `HoleSubmission` | `Scoring` | `lib/golf_scoring/scoring/hole_submission.ex` | PostgreSQL | Idempotent whole-hole receipt |
| `ScoreVerification` | `Scoring` | `lib/golf_scoring/scoring/score_verification.ex` | PostgreSQL | Independent certification of a result revision |
| `ScoreQuery` | `Scoring` | `lib/golf_scoring/scoring/score_query.ex` | PostgreSQL | Dispute against a result revision |
| `ScoreRevision` | `Scoring` | `lib/golf_scoring/scoring/score_revision.ex` | PostgreSQL | Correction history |
| `EventMessage` | `Communications` | `lib/golf_scoring/communications/event_message.ex` | PostgreSQL | Reusable message and trigger definition |
| `MessageDispatch` | `Communications` | `lib/golf_scoring/communications/message_dispatch.ex` | PostgreSQL | Durable trigger occurrence |
| `MessageDelivery` | `Communications` | `lib/golf_scoring/communications/message_delivery.ex` | PostgreSQL | Recipient/channel delivery state |
| `Sponsor` | `Sponsorship` | `lib/golf_scoring/sponsorship/sponsor.ex` | PostgreSQL | Reusable sponsor |
| `SponsorPlacement` | `Sponsorship` | `lib/golf_scoring/sponsorship/sponsor_placement.ex` | PostgreSQL | Event, hole or challenge placement |
| `SideCompetition` | `SideCompetitions` | `lib/golf_scoring/side_competitions/side_competition.ex` | PostgreSQL | Physical-board challenge configuration and lifecycle |
| `SideCompetitionResult` | `SideCompetitions` | `lib/golf_scoring/side_competitions/side_competition_result.ex` | PostgreSQL | Verified and finalized challenge result |
| `AuditEvent` | `Audit` | `lib/golf_scoring/audit/audit_event.ex` | PostgreSQL | Structured actor, action, context and change history |

`StaffUser.system_admin` is a boolean with `NOT NULL DEFAULT false`. It is a global capability, not a separate resource or an event-policy bypass. An active SYSTEM_ADMIN manages staff identities and system bootstrap; ordinary Event operations require an active event assignment and role policy. The first SYSTEM_ADMIN uses an explicit operator-controlled infrastructure bootstrap that refuses ordinary repetition while an active SYSTEM_ADMIN exists. No permanent bootstrap endpoint exists. Audited grant, revoke, suspend and disable actions must preserve at least one active SYSTEM_ADMIN under concurrency. Operator-controlled infrastructure recovery covers an initial or unrecoverable zero-admin deployment. Event Admin authority over catalog actions remains as specified.

`lib/golf_scoring/scoring/score_query.ex` is the ScoreQuery resource, not a leaderboard read model. Leaderboards are deterministic derived reads, not a second authoritative store.

## Pure calculators, policies and services

Calculators and pure policies accept explicit values and return values or validation decisions. They must not access the database, own authorization, write resources, publish notifications or encode new product rules. Services orchestrate named actions and transactions; they do not own independent score truth. The following paths are fixed. Inputs and outputs are conceptual contracts, not function signatures.

| Path | Responsibility | Inputs | Outputs | Must not own |
|---|---|---|---|---|
| `lib/golf_scoring/scoring/calculators/course_handicap.ex` | Calculate course handicap | handicap index and frozen tee/rating inputs | course handicap | persistence or competition allowance |
| `lib/golf_scoring/scoring/calculators/playing_handicap.ex` | Apply competition allowance | course handicap and locked allowance | playing handicap | base handicap facts |
| `lib/golf_scoring/scoring/calculators/stroke_allocation.ex` | Allocate handicap strokes | playing handicap and frozen stroke indexes | strokes per hole | score facts |
| `lib/golf_scoring/scoring/calculators/stableford_points.ex` | Derive Stableford points | outcome, par and allocated strokes | points | gross score mutation |
| `lib/golf_scoring/scoring/calculators/four_ball_best.ex` | Derive side best-ball contribution | eligible player points | side contribution | membership |
| `lib/golf_scoring/scoring/calculators/solo_normalization.ex` | Apply accepted solo normalization | side formation and player points | normalized contribution | eligibility decisions |
| `lib/golf_scoring/scoring/calculators/mystery_aggregation.ex` | Apply BEST/WORST/BOTH | eligible contributions and revealed rule | Mystery contribution | reveal eligibility or secrecy authorization |
| `lib/golf_scoring/scoring/calculators/countback.ex` | Compute tie-break values | ordered track contributions and policy | deterministic tie-break keys | official state |
| `lib/golf_scoring/scoring/policies/pickup_eligibility.ex` | Decide permitted pickup | player hole context and competition policy | eligibility and reason | partner-dependent eligibility or persistence |
| `lib/golf_scoring/competition/policies/round_opening.ex` | Evaluate opening guards | complete locked setup and readiness facts | blockers and warnings | transition or authorization |
| `lib/golf_scoring/competition/policies/mystery_reveal_eligibility.ex` | Evaluate fixed cohort resolution | rule and authoritative group resolution facts | eligible or unresolved groups | resource writes or group exclusion |
| `lib/golf_scoring/scoring/services/submit_group_hole.ex` | Coordinate atomic submission | actor and whole-hole command | receipt or conflict | external HTTP or client trust |
| `lib/golf_scoring/scoring/services/finalization_readiness.ex` | Evaluate readiness | current results, verification, queries and policies | blockers and readiness | official transition |
| `lib/golf_scoring/scoring/services/leaderboard.ex` | Build deterministic standings | authorized track, current facts and reveals | provisional or official standings | hidden data disclosure or score authority |
| `lib/golf_scoring/scoring/services/finalize_results.ex` | Coordinate locked finalization and reopen | actor, current results and reason where required | official state or blockers | unlocked stale calculations |
| `lib/golf_scoring/competition/services/create_event.ex` | Coordinate SYSTEM_ADMIN-authorized Event, initial EVENT_ADMIN assignment and AuditEvent in one transaction | active SYSTEM_ADMIN and event input | draft Event with initial active assignment, or rollback | ordinary cross-event authority, later event lifecycle or policy bypass |
| `lib/golf_scoring/competition/services/open_round.ex` | Coordinate guarded opening | actor and round setup | opened round or blockers | bypassing guards |

## Ash and transaction responsibilities

| Mechanism | Responsibility |
|---|---|
| Named Ash action | Domain command or lifecycle entry point |
| Ash policy | Authorization |
| Ash validation | Useful local input errors |
| Ash change | Narrow local mutation |
| Ash calculation/aggregate | Simple safe derived fields |
| Pure Elixir calculator/policy | Golf and scoring mathematics |
| Domain service | Multi-resource orchestration |
| PostgreSQL constraint | Concurrency-safe structural integrity |
| Transaction coordinator | Cross-resource atomic operations |

An active SYSTEM_ADMIN creates a draft Event, their initial active EVENT_ADMIN assignment and an AuditEvent in one transaction; failure rolls back all three. The SYSTEM_ADMIN capability does not bypass event-scoped policy. Event and round lifecycle use named actions, policies and guarded orchestration. Staff and player permissions are enforced at server action boundaries against current grants and assignments. Group role handover locks authority and advances its revision. The Primary Scorer and Designated Verifier are different active RoundEntries; each queued scoring or verification command identifies the assignment under which it was captured. Whole-hole submission uses the scoring coordinator. Corrections create revisions and audit and invalidate prior verification. Verification binds an independent eligible actor to the current revision. Query resolution coordinates correction or acceptance with audit. Finalization and reopening use locked readiness rechecks and audit. Mystery reveal uses the locked global eligibility coordinator. Audit creation is part of the same transaction as each required audited mutation. A handicap correction preserves raw HoleResults and their valid raw-score verification while recalculating derived results. A tee correction after accepted scoring requires exceptional Event Admin repair and re-evaluation of affected outcomes. Do not put all internal business logic into one oversized Ash action.

## Locking and atomic operations

All concurrency-critical paths use a shared, documented lock order across Round, PlayingGroup and relevant authority, Side/result, score/query/verification and Mystery rule rows. Establish and test the concrete total order before implementing concurrent paths; acquire multiple rows of the same kind in stable ID order. Re-read guards under locks, hold locks only for local database work, and retry or report conflicts without overwriting authority. Every path that touches the same invariant must follow that order, including round opening, role handover, hole submission, paper recovery, score correction, verification, query resolution, global Mystery reveal, side finalization, round finalization and reopen. Never hold locks while calling an external service.

Before any concurrent Phase 4B or Phase 5 write implementation, `/to-tickets` MUST create a dedicated lock-protocol design/characterization ticket, and that ticket must be accepted. It determines and tests the concrete total order for Round, PlayingGroup, GroupRoleAssignment/authority revision, CompetitionSide/CompetitionSideResult, score/query/verification rows, and MysteryHoleRule/MysteryReveal. Multiple rows of one relation are acquired in stable ID order. STOP concurrent Phase 4B/5 work until this gate passes.

Whole-hole submission authorizes the current scorer, locks the PlayingGroup and relevant authority rows, validates expected group revision and current scorer assignment, hole sequence, complete outcomes, and idempotency key plus fingerprint. It atomically writes HoleResults, HoleSubmission receipt, AuditEvent and local durable intents where applicable, then evaluates global Mystery eligibility where relevant. Commit before PubSub. Identical retries return the prior receipt; the same key with a different fingerprint is rejected. External HTTP delivery never runs inside this transaction. A missed broadcast is recovered by re-reading PostgreSQL.

## Migration dependencies and integrity

Build migration groups in dependency order:

- Group A, staff identity and audit: `staff_users`, `audit_events`.
- Group B, catalog and Event/Round: `courses`, `course_holes`, `tee_sets`, `tee_rating_profiles`, `events`, `event_staff_assignments`, `rounds`, `round_holes`, `round_tee_profile_snapshots`, `round_tee_hole_snapshots`.
- Group C, participation, competition structure and player access: `players`, `round_entries`, `competition_categories`, `round_entry_category_memberships`, `playing_groups`, `round_competitions`, `competition_sides`, `competition_side_memberships`, `competition_side_results`, `group_role_assignments`, `player_access_grants`.
- Group D, handicap and pre-open scoring configuration: `handicap_snapshots`, `competition_handicaps`, `scoring_tracks`, `mystery_hole_rules`.
- Group E, authoritative capture and reveal: `scorecards`, `hole_results`, `hole_submissions`, `mystery_reveals`.
- Group F, review and correction: `score_verifications`, `score_queries`, `score_revisions`.
- Group G, communications, sponsorship and side competitions: `event_messages`, `message_dispatches`, `message_deliveries`, `sponsors`, `sponsor_placements`, `side_competitions`, `side_competition_results`.

Use staged migrations where circular foreign keys require them, including optional Event/Round references on early AuditEvent records. Introduce supporting unique indexes or composite foreign keys for cross-round ownership. Historical, audit and score references default to `RESTRICT`, not cascade delete. Enforce `staff_users.system_admin` as `NOT NULL DEFAULT false`; enforce bootstrap and last-active-admin invariants using transactional database serialization and constraints where practical, never UI checks alone.

Required constraints include:

```text
RoundHole UNIQUE(round_id, play_order)
RoundHole UNIQUE(round_id, course_hole_id)
PlayingGroup CHECK(starting_position > 0)
PlayingGroup UNIQUE(round_id, starting_round_hole_id, starting_position)
RoundEntry UNIQUE(round_id, player_id)
Scorecard UNIQUE(round_entry_id)
HoleResult UNIQUE(scorecard_id, round_hole_id)
CompetitionSideMembership UNIQUE(round_competition_id, round_entry_id)
CompetitionHandicap UNIQUE(round_entry_id, round_competition_id)
RoundEntryCategoryMembership UNIQUE(round_entry_id, competition_category_id)
MysteryHoleRule UNIQUE(scoring_track_id, round_hole_id)
MysteryReveal UNIQUE(mystery_hole_rule_id)
HoleSubmission UNIQUE(client_submission_id)
MessageDispatch UNIQUE(event_message_id, trigger_identity)
MessageDelivery UNIQUE(message_dispatch_id, recipient_identity, channel)
```

The starting RoundHole must belong to the same Round. Opening rejects missing or invalid assignments and duplicates. Position 1 displays as A, 2 as B, and so on; no ShotgunSlot resource exists. `display_hole_number` and labels are presentation data, not route uniqueness. Also enforce active player grant and active group role uniqueness, token digest uniqueness, SideResult uniqueness, result/outcome consistency and at most one open query for a current revision where practical. Back structural integrity with database enforcement rather than Ash validation alone.

## Global Mystery reveal

At `ready → scoring_open`, each rule's required cohort is fixed by locked Round, Side and Group configuration: every group containing at least one side participating in the rule's RoundCompetition. No separate cohort resource or arbitrary `exclude_group_from_mystery_reveal` action exists. A late, offline or inconvenient group remains required. IndexedDB capture is not server completion.

A required group resolves as `SUBMITTED` through a complete accepted authoritative group submission, `PAPER_RECOVERED` through the authoritative score path, or `NOT_APPLICABLE` when before play no side in that group remains eligible in the competition. Partial withdrawal or exclusion of only one side is insufficient while another applicable side remains eligible. Disqualification alone does not resolve the group. An accepted submission remains sufficient after later disqualification or exclusion. Paper recovery is limited to Event Admin or Competition Manager, uses normal outcome and pickup validation, `source=paper_recovery`, a mandatory reason and AuditEvent, revisions and normal verification.

After accepted submission or paper recovery, or a relevant eligibility transition, lock the MysteryHoleRule under the shared lock order and re-read all required group resolutions. If all are resolved and no reveal exists, create the unique global MysteryReveal. Commit before broadcasting. A reveal is terminal. Concurrent last submissions must not create duplicate or premature reveals. PostgreSQL retains the reveal even if the process crashes before broadcast.

Before reveal, public/player output cannot expose the hidden rule, contribution, total including it, rank movement, delta or hidden tie-break effect, including indirect inference. Do not preload rules into clients. Mystery standings use known ordinary contributions and globally revealed Mystery contributions only, and show pending/provisional status, including `Mystery result pending…`. Standard Better-Ball stays fully live from accepted HoleResults. After reveal, recompute standings from committed facts and send a post-commit refresh.

## Web and browser boundaries

Phoenix LiveView is the primary UI. Player access tokens are exchanged for an event-scoped session and removed from the redirected URL; they never grant staff access. Enforce current authorization server-side, CSRF/session protection, privacy-limited public payloads and safe structured message/sponsor content with URL scheme allowlisting and no-referrer external links. Only Event Admin and Competition Manager may access unrevealed rules. Shared UI components render domain decisions and never own authorization, scoring mathematics, state-transition guards, finalization rules or Mystery reveal logic.

The stateful and shared web paths are:

- `lib/golf_scoring_web/player/event_portal_live.ex`
- `lib/golf_scoring_web/player/pre_round_confirmation_live.ex`
- `lib/golf_scoring_web/player/access_controller.ex`
- `lib/golf_scoring_web/player/message_components.ex`
- `lib/golf_scoring_web/admin/session_controller.ex`
- `lib/golf_scoring_web/admin/dashboard_live.ex`
- `lib/golf_scoring_web/admin/registration_live.ex`
- `lib/golf_scoring_web/admin/staff_live.ex`
- `lib/golf_scoring_web/admin/group_support_live.ex`
- `lib/golf_scoring_web/admin/course_setup_live.ex`
- `lib/golf_scoring_web/admin/round_setup_live.ex`
- `lib/golf_scoring_web/admin/group_assignment_live.ex`
- `lib/golf_scoring_web/admin/score_queries_live.ex`
- `lib/golf_scoring_web/admin/finalization_live.ex`
- `lib/golf_scoring_web/admin/messages_live.ex`
- `lib/golf_scoring_web/admin/sponsors_live.ex`
- `lib/golf_scoring_web/admin/side_competitions_live.ex`
- `lib/golf_scoring_web/scoring/group_scoring_live.ex`
- `lib/golf_scoring_web/scoring/verification_live.ex`
- `lib/golf_scoring_web/scoring/components.ex`
- `lib/golf_scoring_web/leaderboard/leaderboard_live.ex`
- `lib/golf_scoring_web/leaderboard/components.ex`
- `lib/golf_scoring_web/admin/components.ex`

Browser modules:

- `assets/js/scoring/indexed_db.js`
- `assets/js/scoring/submission_serializer.js`
- `assets/js/scoring/queue.js`
- `assets/js/scoring/connection_state.js`
- `assets/js/scoring/leaderboard_cache.js`
- `assets/js/hooks/scoring_queue.js`

Store whole-hole commands with a stable idempotency key, captured scorer-assignment identity and expected group revision. Replay in order, one dependent command at a time; stop on conflict and never silently overwrite. Never cache unrevealed Mystery rules. Mark cached leaderboards explicitly stale. The server rechecks all authority on replay. Do not introduce another frontend framework.

## Background delivery

Do not add Oban until the external delivery phase. Planned boundaries are `lib/golf_scoring/communications/workers/deliver_message.ex`, `lib/golf_scoring/communications/workers/reconcile_deliveries.ex`, `lib/golf_scoring/communications/adapters/whatsapp.ex`, and `lib/golf_scoring/communications/adapters/email.ex`. Record local durable, idempotent dispatch intent; deliver and retry externally after commit. Scoring correctness, Mystery reveal, authorization and finalization remain synchronous and database-authoritative. A worker outage cannot affect accepted scores.

## Test ownership and CI

Pure tests under `test/golf_scoring/scoring/calculators/` cover course handicap, playing handicap, stroke allocation, Stableford, mixed tees, Four-Ball BEST, solo normalization, Mystery BEST/WORST/BOTH and countback. `test/golf_scoring/scoring/policies/` covers pickup eligibility; `test/golf_scoring/competition/policies/` covers opening and reveal eligibility. Domain/resource and service tests under `test/golf_scoring/` cover state transitions, Ash policies, opening, atomic submission, idempotency, handover, verification revision invalidation, query/correction, global Mystery secrecy/reveal, finalization races and message dispatch idempotency. Concurrency-sensitive flows use simultaneous real database transactions, including last-group reveal and finalization races.

`test/golf_scoring_web/` owns registration and group scoring LiveViews, player access exchange and leaderboard privacy/behavior. Browser tests under `test/browser/` and JS tests under `assets/test/` own serialization, ordered replay, conflict stop and IndexedDB restart/recovery. Real IndexedDB recovery requires real browser evidence, not mocks alone. Test stale role devices, replay after restart, duplicate and mismatched fingerprints, no self-verification, no hidden Mystery data, post-commit notifications and recovery after missed PubSub.

Plan `.github/workflows/ci.yml` with `mix format --check-formatted`, `mix compile --warnings-as-errors`, and `mix test`, initially on one supported Elixir/OTP/PostgreSQL combination. Add JS/browser queue tests when their harness exists. No unnecessary matrix. This document does not implement CI.

## Implementation phases

Each phase inherits the global STOP conditions and frozen spec. Tests and exit criteria include the explicitly stated cases below; no phase authorizes weakening earlier invariants.

### Phase 0 — Engineering foundation

- Goal: Establish reproducible build and CI.
- Prerequisites: Accepted architecture.
- Resources/modules introduced: CI and test support.
- User-visible outcome: A verified development foundation.
- Critical tests: format, compile, test.
- Exit criteria: CI passes.
- Explicitly deferred work: Application domain work.
- STOP conditions: Toolchain or environment cannot be established.

### Phase 1 — Staff identity, system administration and audit

- Goal: Establish authenticated staff, safe SYSTEM_ADMIN bootstrap and global staff administration, with AuditEvent before audited mutations.
- Prerequisites: Phase 0.
- Resources/modules introduced: StaffUser, AuditEvent, SYSTEM_ADMIN actions/policies and the operator-controlled first-admin bootstrap mechanism.
- User-visible outcome: An active SYSTEM_ADMIN can administer staff identities.
- Critical tests: Non-system-admin Event creation denial, first bootstrap and repeated-bootstrap refusal, grant/revoke, last-active-admin protection including concurrent changes and disable/suspend, disabled staff denial, audit persistence.
- Exit criteria: An active SYSTEM_ADMIN can be safely established and global staff authority is enforceable and audited.
- Explicitly deferred work: Operational EventStaffAssignment, Event creation and PlayerAccessGrant.
- STOP conditions: Identity, bootstrap or last-active-admin authority cannot be enforced.

### Phase 2 — Catalog, Event and round setup

- Goal: Establish Event authority, catalog and immutable round snapshots.
- Prerequisites: Phase 1.
- Resources/modules introduced: Course, CourseHole, TeeSet, TeeRatingProfile, Event, EventStaffAssignment, Round, RoundHole, RoundTeeProfileSnapshot, RoundTeeHoleSnapshot and CreateEvent service.
- User-visible outcome: A SYSTEM_ADMIN creates an Event with their initial active EVENT_ADMIN assignment; event-authorized staff configure the round.
- Critical tests: Atomic Event, assignment and audit creation; rollback on assignment failure; non-SYSTEM_ADMIN denial; event-scoped permissions; catalog snapshot isolation; RoundHole routing constraints.
- Exit criteria: Atomic bootstrap and valid 18-hole setup persist.
- Explicitly deferred work: Player access and scoring opening.
- STOP conditions: Event bootstrap, snapshot or ownership constraint fails.

### Phase 3 — Participation and check-in

- Goal: Prepare participation, player access, groups and sides.
- Prerequisites: Phase 2.
- Resources/modules introduced: Player, RoundEntry, CompetitionCategory, RoundEntryCategoryMembership, PlayingGroup, RoundCompetition, CompetitionSide, CompetitionSideMembership, CompetitionSideResult, GroupRoleAssignment and PlayerAccessGrant.
- User-visible outcome: Registration, player access, check-in and assignments.
- Critical tests: Access exchange and revocation, uniqueness, check-in, shotgun A/B and same-round ownership.
- Exit criteria: `PARTICIPATION_SETUP_COMPLETE`, `SCORING_CLOSED` and `ROUND_OPENING_BLOCKERS_VISIBLE`. This phase never transitions `ready → scoring_open`.
- Explicitly deferred work: Opening scoring.
- STOP conditions: Assignments or eligible participation are ambiguous.

### Phase 4 — Handicap and complete competition policy/configuration

- Goal: Complete and make reproducible all scoring configuration required before opening.
- Prerequisites: Phase 3.
- Resources/modules introduced: HandicapSnapshot, CompetitionHandicap, ScoringTrack, MysteryHoleRule, CourseHandicap, PlayingHandicap, StrokeAllocation, StablefordPoints, FourBallBest, SoloNormalization, MysteryAggregation, Countback and PickupEligibility.
- User-visible outcome: Staff configure Standard and Mystery tracks, BEST/WORST/BOTH rules, allowance, Playing Handicap and tie-break/countback policy.
- Critical tests: Mixed tees, course handicap, playing handicap, stroke allocation, Stableford, pickup, Four-Ball BEST, solo normalization, Mystery BEST/WORST/BOTH, countback, rule completeness and server secrecy.
- Exit criteria: All scoring and competition configuration required by RoundOpening is reproducible, complete and lock-ready. ScoringTrack and MysteryHoleRule exist before scoring opens.
- Explicitly deferred work: Opening scoring, score capture and reveal state.
- STOP conditions: Formula or policy is unclear, or configuration cannot satisfy opening guards.

### Phase 4B — Round readiness and opening

- Goal: Exclusively own `ready → scoring_open` after all guards pass.
- Prerequisites: Phase 4 and the accepted lock-protocol ticket.
- Resources/modules introduced: Round opening policy and service.
- User-visible outcome: Authorized opening or actionable blockers.
- Critical tests: All opening guards, concurrent lock and audit races.
- Exit criteria: The transaction re-reads and validates the route and snapshots, tee/rating snapshots, RoundEntries, starting RoundHole and position, groups, sides and memberships, active scoring assignments, handicap snapshots, competition handicaps, RoundCompetition, ScoringTrack, MysteryHoleRule and tie-break/countback configuration, plus all other frozen opening invariants. Only a valid ready round opens and locks configuration.
- Explicitly deferred work: Score submission.
- STOP conditions: Any hard opening invariant fails or the shared lock protocol is not accepted.

### Phase 5 — Transaction-safe group scoring and global reveal state

- Goal: Accept complete authoritative holes and perform global Mystery reveal rechecks.
- Prerequisites: Phase 4B and the accepted lock-protocol ticket.
- Resources/modules introduced: Scorecard, HoleResult, HoleSubmission, MysteryReveal, SubmitGroupHole, MysteryRevealEligibility and the transactional global reveal recheck.
- User-visible outcome: Online whole-hole scoring with global reveal state.
- Critical tests: Atomic submission, idempotent retry and payload mismatch, current scorer and stale assignment rejection, simultaneous group submissions, last-required-group reveal race, `UNIQUE(mystery_hole_rule_id)`, no premature reveal, no hidden Mystery data in submission responses, and missed PubSub recovery.
- Exit criteria: No partial, lost or duplicated score; accepted submission, paper recovery and relevant eligibility transitions re-evaluate the fixed global cohort under the lock protocol. The authoritative command contract is complete before offline replay.
- Explicitly deferred work: Offline queue and leaderboard presentation.
- STOP conditions: Transaction or secrecy invariant cannot be preserved, or the shared lock protocol is not accepted.

### Phase 6 — Mobile scoring and offline recovery

- Goal: Preserve pending commands and reconcile safely against the completed Phase 5 submission contract, without a second scoring path.
- Prerequisites: Phase 5.
- Resources/modules introduced: IndexedDB pending commands, serializer, queue, connection state, leaderboard cache and scoring hook.
- User-visible outcome: Offline capture, ordered replay and conflict UI.
- Critical tests: Real browser restart, stable idempotency key, captured assignment identity, expected revision, order, role change and conflict stop.
- Exit criteria: Real browser recovery evidence passes; server acceptance remains authority.
- Explicitly deferred work: Official results.
- STOP conditions: Stale device can overwrite authority.

### Phase 7 — Verification and corrections

- Goal: Resolve individual score revisions.
- Prerequisites: Phase 5.
- Resources/modules introduced: ScoreVerification, ScoreQuery, ScoreRevision and review UI.
- User-visible outcome: Verify, query and correct scores.
- Critical tests: Independent revision-bound verification, correction, re-verification, audit and simultaneous correction/query.
- Exit criteria: Current revisions have explicit review state.
- Explicitly deferred work: Official finalization.
- STOP conditions: Revision or audit cannot be preserved.

### Phase 8 — Standard/Mystery leaderboard derivation and presentation

- Goal: Produce deterministic Standard and Mystery standings and tie-breaks from existing Phase 4 configuration and Phase 5 reveal state.
- Prerequisites: Phases 6 and 7.
- Resources/modules introduced: Leaderboard service and presentation components; consume existing ScoringTrack, MysteryHoleRule, MysteryReveal and calculators.
- User-visible outcome: Standard standings, pending Mystery presentation and globally revealed contributions.
- Critical tests: Reproducible Standard/Mystery standings, read-model and UI secrecy including indirect inference, deterministic countback integration and correction recomputation.
- Exit criteria: Both tracks and tie-breaks are reproducible and hidden contributions cannot be inferred before Phase 9 finalization.
- Explicitly deferred work: Official finalization.
- STOP conditions: Secrecy or reproducibility cannot be proven.

### Phase 9 — Finalization, reopening and official standings

- Goal: Lock and publish official results safely.
- Prerequisites: Phase 8.
- Resources/modules introduced: readiness and finalize services, finalization UI.
- User-visible outcome: Official standings and controlled reopen.
- Critical tests: finalization races, recheck tracks/tie-breaks under locks, reopen audit.
- Exit criteria: No blocker can race official results.
- Explicitly deferred work: Prizegiving side challenges.
- STOP conditions: Locked recheck fails.

### Phase 10 — Messaging, sponsors and side competitions

- Goal: Deliver event communications and record side prizes.
- Prerequisites: Phase 9.
- Resources/modules introduced: Communications, Sponsorship, SideCompetitions, workers and adapters.
- User-visible outcome: Messages, placements and physical-board results.
- Critical tests: dispatch idempotency, provider failure and challenge lifecycle.
- Exit criteria: Delivery failure cannot affect scores.
- Explicitly deferred work: Operational rehearsal.
- STOP conditions: Provider behavior is unknown where correctness depends on it.

### Phase 11 — Operations and prizegiving readiness

- Goal: Expose event-day blockers.
- Prerequisites: Phase 10.
- Resources/modules introduced: dashboard and group support integration.
- User-visible outcome: Staff see readiness and required prizes.
- Critical tests: prizegiving blockers and recovery workflow.
- Exit criteria: All required operational readiness is visible.
- Explicitly deferred work: Full rehearsal.
- STOP conditions: A required blocker is invisible.

### Phase 12 — Security, recovery and 144-player rehearsal

- Goal: Prove event readiness at intended scale.
- Prerequisites: Phase 11.
- Resources/modules introduced: security, browser and operational test assets.
- User-visible outcome: Rehearsed event recovery.
- Critical tests: authorization, secrecy, concurrent load and recovery.
- Exit criteria: 144-player rehearsal has evidence and blockers resolved.
- Explicitly deferred work: Speculative scaling.
- STOP conditions: Security, recovery or score integrity cannot be proven.

## Dependencies and parallel work

```text
Engineering foundation
        ↓
Staff identity / SYSTEM_ADMIN / audit
        ↓
Catalog + Event bootstrap + round snapshots
        ↓
Participation / player access / groups / sides
        ↓
Handicap + complete scoring/competition configuration
        ↓
Guarded round opening
        ↓
Authoritative scoring + global Mystery reveal
       ↙                         ↘
Offline recovery          verification/correction
       \                         /
        leaderboard derivation/presentation
                       ↓
              official finalization
                       ↓
        messaging / sponsors / side prizes
                       ↓
        operations / prizegiving readiness
                       ↓
             144-player rehearsal
```

After their shared contracts are stable, offline queue and verification/correction may proceed in parallel. Independent calculators and test fixtures may proceed in parallel within Phase 4. Messaging, sponsor and side-prize work may be prepared independently after their domain prerequisites, but the phase gate follows official finalization. Shared database invariants and lock protocol require coordinated review.

## Performance and STOP conditions

Use PostgreSQL authority, Phoenix PubSub, LiveView, IndexedDB, short database locks, idempotency and bounded indexed reads. For roughly 144 players and 36 simultaneous groups, prove no lost or duplicated scores, responsive scoring interaction and deterministic recovery. Do not introduce Redis, Cachex architecture, read replicas, distributed locks, Kafka or event sourcing for MVP without measured evidence.

STOP rather than guess if the spec and architecture conflict, domain ownership is ambiguous, a scoring formula is unclear, a transaction cannot preserve an invariant, a stale device can overwrite current authority, Mystery secrecy cannot be proven, a database constraint conflicts with Ash resource design, implementation requires a new product decision, or external provider behavior is unknown and correctness depends on it. No implementation agent may silently weaken a frozen invariant.

## Execution tracker

Plane project: Golf Live Scoring V2. Identifier: `GLS`. Project ID: `3282f580-51da-42f5-bd82-8015ac9b9b35`. Plane tracks execution, tickets, blockers, dependencies, proof and status. It is not product/domain authority. When `/to-tickets` is later authorized, all approved implementation tickets must be created and tracked in this project. This architecture freeze creates no tickets.
