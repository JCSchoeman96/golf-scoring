# Golf Live Scoring V2 — Product & Domain Specification v1.0

**Status:** FROZEN v1.0 — approved product/domain authority. Changes require explicit owner approval.  
**Purpose:** Authoritative record of product decisions, domain rules, open questions, and deferred scope for the Golf Live Scoring V2 rebuild.  
**Primary use case:** Internal golf days operated by our own team.  
**Current MVP target:** One 144-player, single-course, single-day event with shotgun-start support.

> **Authority rule:** This document records the intended V2 product/domain behavior. The existing repository is useful implementation evidence and UX reference, but legacy architecture and semantics do not override decisions recorded here.


## Specification Freeze

**Version:** 1.0  
**Authority status:** Approved and frozen for repository reconciliation and implementation planning.

### Change control

This specification is the highest product/domain authority for Golf Live Scoring V2.

During `/wayfinder` repository reconciliation:

1. Existing repository code is evidence and reuse material, not product authority.
2. The agent may challenge this specification when concrete repository constraints or contradictions are discovered.
3. The agent may **not silently change** product/domain semantics.
4. Any proposed spec change must be:
   - stated explicitly;
   - justified with repository evidence;
   - classified as required, recommended, or optional;
   - approved by the owner before being treated as authority.
5. No implementation tickets may be generated while material spec/repository conflicts remain unresolved.

---

## 1. Product Intent

Build a **reliable internal golf-day operations and live-scoring system** that we can use at our own recurring golf events.

The product must be:

- correct enough to trust for event results;
- easy enough for golfers to use during a real round;
- resilient to common event-day problems such as forgotten phones, dead batteries, missing entries, poor connectivity, and score disputes;
- reusable across future years, courses, player lists, and competition formats;
- deliberately smaller and simpler than a commercial golf SaaS platform.

The objective is **not** to compete with mature platforms such as ScoreCapture.

### Guiding principle

> Build the smallest system we can confidently use to run the real golf day — not a miniature enterprise golf platform.

### Architectural principle

> Future capability may influence boundaries, but it may not create unnecessary present-day features.

---

## 2. MVP Scope

### Accepted

The initial production target is:

- approximately **144 players**;
- **one event**;
- **one day**;
- **one course**;
- **one round**;
- groups of **2 to 4 players**;
- **shotgun starts must be supported from V1**;
- individual player scorecards;
- mobile-first score entry;
- live leaderboard;
- score verification/cross-checking;
- organiser correction/resolution tools;
- event/player notifications;
- reusable course, event, player, and scoring data so the next golf day is not a rebuild.

### Explicitly deferred / non-goals

V1 does **not** require:

- SaaS multi-tenancy;
- customer organisations;
- billing/subscriptions;
- commercial onboarding;
- white-labelling;
- tenant-specific domains;
- enterprise RBAC;
- native mobile apps;
- support for every golf competition format;
- extensive social features;
- extensive advanced-shot statistics;
- Redis/distributed infrastructure unless actual requirements later justify it.

---

## 3. Future Direction Without SaaS Overengineering

### Accepted

The application should remain reusable for:

- different golf days in future years;
- different courses;
- different tee sets;
- different player lists;
- different group assignments;
- different starting holes;
- different competition formats added over time;
- potentially multiple rounds/events in future.

### Decision

**Do not implement multi-tenancy in V1.**

Future capability must be enabled by clean resource boundaries rather than premature tenant infrastructure.

Avoid singleton assumptions such as:

- “the current event”;
- “the course”;
- “the leaderboard”;
- “the admin”.

Resources should operate using explicit IDs and relationships.

---

## 4. Core Domain Direction

The following domain shape is currently the preferred direction.

### Golf Catalog

- Course
- Tee Set
- Hole / Tee Hole configuration

### Competition

- Event
- Round
- Entry / Round Participation
- Group / Fourball
- Group Membership
- Starting Hole / Tee Assignment

### Scoring

- Player Scorecard
- Hole Result
- Score Verification
- Score Query / Dispute
- Score Revision / Audit
- Handicap Snapshot
- Leaderboard Projection

### Access

- Organiser/Admin
- Player
- Group Scorer
- Group Verifier

### Messaging

- Event Message
- Audience
- Trigger
- Delivery state

> Exact resource names are not yet final. The conceptual boundaries are more important than naming at this stage.

---

## 5. Event and Round Structure

### Accepted

Even though the MVP has one round, **Round must exist as a first-class resource from V1**.

Preferred relationship:

```text
Event
└── Round
    ├── Course
    ├── Tee Set
    ├── Competition Format
    ├── Groups
    └── Scorecards
```

This avoids repeating the legacy design problem where scorecards belong directly to an event and multi-round support becomes structurally difficult.

---

## 6. Course and Tee Modelling

### Accepted direction

Do not store all course rating data directly on the Course.

Preferred model:

```text
Course
└── Tee Set
    ├── Course Rating
    ├── Slope Rating
    └── Holes
        ├── Hole Number
        ├── Par
        ├── Stroke Index
        └── Distance (where available)
```

This supports:

- different tees at the same course;
- correct handicap calculations;
- future events using a different tee set;
- plausibility checks using hole metadata.

---

## 7. Group / Fourball Rules

### Accepted

A scoring group may contain:

- **2 players**
- **3 players**
- **4 players**

A group must **never contain more than 4 players** in V1.

No scoring UI may assume exactly four players; it must render based on actual active group membership.

### Shotgun Start

Each group receives a starting hole.

Example:

```text
Group 12
Start Hole: 14
Players: 4
```

The starting-hole assignment should belong to the group/round assignment rather than being independently entered by every player.

---

## 8. Shotgun Playing Order

### Accepted

The scorecard UI must follow the golfer's actual playing order.

For a group starting on Hole 14:

```text
14 → 15 → 16 → 17 → 18 → 1 → 2 → ... → 13
```

The system must clearly communicate:

- starting hole;
- current hole;
- progress through the round;
- turn/clubhouse transition where relevant;
- final hole.

The system must distinguish:

- physical hole number;
- number of holes completed;
- halfway point;
- final hole.

These are **not equivalent** in a shotgun start.

---

## 9. Player Onboarding

### Preferred direction — provisional

Player information should be loaded before the event wherever practical.

Expected player/event data may include:

- first name;
- surname;
- email and/or mobile number where available;
- Handicap Index;
- group assignment;
- starting hole;
- tee set.

Players should be able to confirm their identity/details when opening their event access link.

### Fallback

Self-entry or organiser correction may be allowed where player details are missing or incorrect.

### Principle

Do not make full self-registration the primary event-day workflow unless operational experience shows it is necessary.

---

## 10. Access / Login Model

### Preferred direction — provisional

Do **not** require 144 traditional username/password accounts merely to participate.

Likely model:

#### Organiser/Admin

- normal authenticated account;
- full event management;
- corrections;
- dispute resolution;
- finalisation.

#### Player / Group access

Players or groups may use:

- personal secure event links;
- QR codes;
- group-scoring links;
- short-lived or event-scoped access tokens.

The scorecard belongs to the event/round/player data model — **not to one specific phone**.

### Critical resilience rule

A golfer must not require a functioning smartphone to participate.

The system must support:

1. normal scoring with two scoring-capable devices;
2. fallback scoring with one device;
3. emergency organiser/paper recovery if all devices fail.

---

## 11. Scoring Responsibility

### Accepted direction

Each group should have **two designated scoring roles where possible**:

- Primary Scorer
- Verifier / Backup Scorer

The primary scorer enters results for all active golfers in the group.

The verifier does **not** need to independently re-enter all scores.

Instead, the verifier reviews the submitted results and can:

- verify;
- raise a query/dispute.

This gives score redundancy with substantially less data-entry friction.

### Important

The verifier being unavailable must **not block the group from continuing play**.

---

## 12. Hole Progression Invariant

### Accepted

> A group may not advance its score-entry workflow to the next hole until every active player has a resolved outcome for the current hole.

A resolved outcome is either:

- a valid numeric score; or
- an explicit competition-format-valid non-score outcome.

An empty value is **not** a valid result.

Example:

```text
Hole 7

John   5
Susan  4
Peter  —
Mary   6
```

The group may not advance until Peter has a resolved outcome.

### Reason

This prevents silent incomplete scorecards and prizegiving-time data cleanup.

---

## 13. Missing Score Is Not a Golf Outcome

### Accepted

The system must never silently interpret a blank as:

- zero;
- no return;
- picked up;
- disqualified;
- withdrawn;
- completed.

`missing` means **data is missing**.

Golf-specific outcomes must be explicit.

---

## 14. Hole Outcomes vs Round Participation

### Accepted

These must be separate concepts.

### Hole-level examples

Depending on competition format:

- numeric score;
- picked up / no points;
- other explicit format-valid outcome.

### Round-participation examples

Current conceptual lifecycle:

```text
not_started
    ↓
active
    ├── completed
    ├── withdrawn
    └── disqualified
```

Exact transitions and rules remain to be formally modelled.

### Important distinction

- `withdrawn` is not a hole score;
- `disqualified` is not a hole score;
- `missing` is not a golf outcome;
- `picked_up` may be a legitimate hole outcome for formats such as Stableford.

If a player leaves after Hole 7, future holes should become not applicable due to round participation state rather than being populated with fake skipped scores.

---

## 15. Score Verification

### Accepted

Verification should be **asynchronous**.

The Primary Scorer can complete Hole 7 and proceed to Hole 8 once all active players have a resolved result.

The Verifier may review Hole 7 afterward.

### Verification granularity

Verification should be represented per **player/hole result**, even if the UI provides a convenient:

> Verify all

button.

Example:

```text
Hole 14

JC      5   verified
Peter   4   verified
Susan   6   queried
Mary    5   verified
```

This prevents one disputed score from invalidating the entire hole.

---

## 16. Score Query / Dispute Handling

### Accepted

The verifier may raise a query against a specific player's hole result.

A query does not stop the group from playing the next hole.

The recorded score remains usable for the live/provisional leaderboard while unresolved.

Before final results can be produced:

- no required hole results may be missing;
- no score queries may remain unresolved.

### Resolution

A dispute may be resolved by:

- scorer/verifier agreement; or
- organiser intervention.

Organiser resolution is sufficient for the internal/social event model.

A formal player + marker digital-signature workflow is **not required for MVP**.

---

## 17. Score Audit Trail

### Accepted

Score corrections require a lightweight audit trail.

At minimum retain:

- player;
- hole;
- original value/outcome;
- new value/outcome;
- actor;
- timestamp;
- reason/context where applicable.

Example:

```text
Player: Susan
Hole: 14
Original score: 6
New score: 5
Changed by: Primary Scorer
Reason: Verifier query
Resolved by: Verifier / Organiser
```

This is required for event-day trust and troubleshooting but does not need enterprise audit infrastructure.

---

## 18. Group / Scorecard Progress States

### Provisional state model

Operational group progress may include:

```text
not_started
playing
finished_playing
review_required
ready_to_finalize
finalized
```

Possible semantics:

### `not_started`

No scoring activity yet.

### `playing`

Round in progress.

### `finished_playing`

All required hole results captured, but verification may remain outstanding.

### `review_required`

Missing resolution, dispute, or exceptional condition requires attention.

### `ready_to_finalize`

All required results present, queries resolved, verification conditions satisfied.

### `finalized`

Results locked for official event outcome.

Exact transition guards and reopening rules remain open for formal domain modelling.

---

## 19. Live Leaderboard

### Accepted

The live leaderboard should update from recorded scores as players progress.

Results are **provisional** until the round/event is finalised.

A score under query may remain reflected in the live leaderboard, but the system should retain internal query state.

Final event results must not be finalised while unresolved score queries or required missing results remain.

---

## 20. Competition Scoring Principles

### Accepted

Do not conflate:

- actual gross score;
- competition score;
- handicap-adjusted score.

These may differ.

Do not overwrite the player's actual golf result merely to satisfy handicap or format calculations.

### Important

Competition-format rules determine which outcomes are valid.

For example, a Stableford/IPS event may permit a player to pick up once no points can be scored, whereas Medal/stroke play has different rules.

A generic `"No Score"` button should therefore **not** exist without format-specific meaning.

---

## 21. Maximum Scores / Pickups

### Accepted principle

The scoring engine must support competition-format-specific maximum/pickup rules.

For Stableford/IPS, the system may allow an explicit action such as:

```text
Picked Up / No Points
```

rather than forcing the player/scorer to invent a numeric gross score.

### Open

Exact first-format scoring rules, handicap application, and limits will be defined after the initial competition format is selected.

---

## 22. Plausibility Validation

### Accepted principle

The system may detect highly unusual entries and require confirmation.

Examples:

- hole-in-one on a Par 4 or Par 5;
- unusually high or low score;
- unusual retroactive correction;
- exceptional result inconsistent with normal format flow.

### Critical rule

Plausibility checks should normally **warn and require confirmation**, not prohibit a technically possible golf score.

Example:

```text
Unusual score

You entered a hole-in-one on this Par 5.
Please confirm this score is correct.

[Go Back] [Confirm]
```

Do not hard-code brittle assumptions such as:

```text
distance > 320 m => hole-in-one impossible
```

---

## 23. Notifications / Event Messaging

### Accepted

Event/player notifications are part of MVP scope.

The organiser needs to be able to send:

- manual messages to everyone;
- targeted or progress-triggered messages;
- halfway/meal instructions;
- clubhouse/turn instructions;
- final-hole/round-complete instructions;
- prizegiving information.

### Trigger concepts

Initial triggers may include:

```text
manual
physical_hole_reached
physical_hole_completed
holes_completed
holes_remaining
round_completed
```

### Important shotgun distinction

These are different conditions:

```text
physical_hole == 18
holes_completed == 9
holes_remaining == 0
```

A player starting on Hole 14 reaches Hole 18 after only five holes.

Notification rules must therefore be based on the intended event condition rather than assuming Hole 9 or Hole 18 always represents halfway.

---

## 24. Connectivity and Device Failure

### Accepted requirement

Temporary connectivity failure must not cause score loss.

The eventual implementation should provide sufficient local resilience for short outages and show clear score state such as:

- Saved
- Pending sync
- Conflict / Attention required

### Device ownership principle

Scores belong to the server-side round/scorecard resources, not to one device.

If a scorer's phone dies, another authorised device should be able to continue from current state.

### Emergency fallback

If no digital device remains available, organisers must be able to recover/enter results later from another source such as a paper card.

---

## 25. Performance / Infrastructure Boundary

### Accepted

This system does **not** initially require EventSales-scale infrastructure.

Expected scale is approximately:

- 144 golfers;
- roughly 36 groups at full fourballs;
- a modest number of organisers and leaderboard spectators.

Preferred initial architecture direction:

- Postgres as durable source of truth;
- Phoenix PubSub for real-time score/leaderboard updates;
- Phoenix LiveView for scoring and administration where appropriate;
- optimistic concurrency/versioning for score integrity;
- browser-side local persistence/offline queue for temporary connectivity resilience.

### Deferred unless evidence justifies it

- Redis;
- distributed event processing;
- large-scale caching layers;
- complex queue infrastructure;
- 100k-concurrent-user architecture.

Correctness and event-day resilience matter more than premature scale engineering.

---

## 26. Product Principles

### Accepted

1. **Golfers should spend seconds entering scores, not minutes operating software.**
2. **A functioning smartphone must not be required for every player.**
3. **A missing value is never silently converted into a golf result.**
4. **The system must distinguish playing progress from score verification.**
5. **Live results may be provisional; official results must be internally consistent.**
6. **Competition-format behavior must be explicit rather than cosmetic dropdown options.**
7. **Reuse future-friendly domain boundaries where they prevent expensive rewrites.**
8. **Do not build speculative commercial/SaaS infrastructure.**
9. **Do not over-engineer infrastructure for 144 golfers.**
10. **Event-day usability and correctness take priority over architectural sophistication.**

---

## 27. Legacy Repository Guidance

### Accepted

The current repository should be treated as **Legacy V0 / reference implementation**.

Useful work may be reused, especially:

- Phoenix LiveView foundation;
- existing UI concepts;
- course editor concepts;
- mobile scoring UX experiments;
- leaderboard presentation;
- fixtures and useful tests;
- PubSub concepts;
- scoring helper patterns where mathematically correct.

Do **not** blindly preserve:

- current database schema;
- Event → Scorecard ownership;
- missing/NR/completed semantics;
- current competition-format abstraction;
- current permission model;
- current leaderboard rules;
- current broad Golf context structure.

The V2 product/domain specification should be the higher authority.

---


## 28. Preferred MVP Competition Format

### Provisional — strong preference

The first real event is expected to be a **shotgun Four-Ball Better-Ball** competition.

The domain must distinguish:

```text
Playing Group
└── up to 4 players

Scoring Side / Team
└── exactly 2 partners for Four-Ball Better-Ball
```

Normal 4-player group:

```text
Playing Group
├── Team A
│   ├── Player A1
│   └── Player A2
└── Team B
    ├── Player B1
    └── Player B2
```

The four players may all know and play together, but the competition scoring relationship is between the two-person sides.

The system must not use `Group` and `Team/Side` as interchangeable concepts.

### Base scoring direction

The likely MVP implementation should use **Four-Ball Better-Ball Stableford / IPS** semantics:

1. capture each player's actual gross hole result or valid pickup outcome;
2. apply the player's handicap allocation for the hole;
3. calculate the player's individual Stableford/IPS points;
4. calculate the team's hole result from the two partners' points.

For normal better-ball Stableford:

```text
team_hole_points = max(player_a_points, player_b_points)
```

The exact South African handicap allowance and Playing Handicap calculation must be verified and explicitly specified before implementation.

### Important

The raw player result remains authoritative input.

Team scoring is a derived calculation and must never overwrite the player's actual hole result.

---

## 29. Optional Mystery Hole Scoring

### Provisional — recommended as an optional competition modifier

The product may support a distinctive **Mystery Hole Scoring** option on top of the normal Four-Ball Better-Ball Stableford format.

This should **not** be implemented as a second independent scoring engine.

Preferred model:

```text
Base Format
Four-Ball Better-Ball Stableford
        +
Optional Mystery Hole Modifier
```

With the modifier disabled, the event behaves as ordinary better-ball.

With the modifier enabled, selected holes may use a hidden team aggregation rule.

### Initial rule types

Keep V1 deliberately small.

Possible per-hole team rules:

```text
BEST
team_points = max(partner_a_points, partner_b_points)

WORST
team_points = min(partner_a_points, partner_b_points)

BOTH
team_points = partner_a_points + partner_b_points
```

Do not build a generic rules-programming language for MVP.

Additional rule types should only be added after the first event proves they are useful.

### Selected holes

Mystery scoring may be configured:

- on every hole; or
- only on selected holes.

Holes without a special rule use normal `BEST` better-ball scoring.

### Secret rule integrity

The rule for a mystery hole must be:

1. configured before play;
2. hidden from players before score submission;
3. locked once the round starts;
4. revealed only after all active players in the playing group have resolved results for that hole.

This prevents players from changing how they play or deciding whether to pick up based on knowing which team calculation will count.

### Reveal flow

Example:

```text
Hole 7
All four player results submitted
        ↓
Hole submission is locked
        ↓
Mystery rule revealed
        ↓
"WORST SCORE COUNTS"
        ↓
Team points calculated
        ↓
Leaderboard updates
        ↓
Verifier reviews player results
```

The reveal should be a clear event moment in the mobile UI.

### Editing after reveal

After the secret rule is revealed, the primary scorer must not be able to silently rewrite the hole.

Legitimate corrections remain possible, but they must use the existing verification/query/correction flow and audit trail.

Examples:

- verifier raises query;
- scorer corrects with recorded revision;
- organiser resolves dispute.

This preserves correction capability without allowing unrestricted post-reveal manipulation.

### Scoring basis

For the MVP, mystery rules should operate on **individual Stableford/IPS points**, not directly on raw strokes.

This keeps the rule model consistent:

- `BEST` = higher partner points;
- `WORST` = lower partner points;
- `BOTH` = sum of partner points.

It also allows a valid Stableford pickup/no-points outcome to participate cleanly as `0` points.

Raw gross scores remain stored separately for audit, handicap and correctness.

### Naming

The public/event-facing name can be playful and decided later.

Internally, avoid ambiguous names such as `"secret_format"`.

Recommended conceptual naming:

- base format: `four_ball_stableford`;
- optional feature: `mystery_hole_scoring`;
- per-hole aggregation: `best`, `worst`, `both`.

Exact implementation names remain open until architecture planning.

---

## 30. Competition Integrity Rules for Mystery Scoring

### Provisional

Mystery scoring introduces a few additional invariants:

1. The hidden scoring rule must exist before the hole is played.
2. Players may not see the hidden rule before the hole's score submission is complete.
3. A rule may not be changed after the round starts without an organiser override and audit record.
4. The reveal occurs from **submitted player results**, not from verifier completion.
5. Verification remains asynchronous and may happen after reveal.
6. A legitimate corrected player score must automatically recalculate the derived team result and leaderboard.
7. The historical rule used for that hole must remain recorded permanently.
8. The system must clearly distinguish the normal golf result from the event's novelty team calculation.

### Product boundary

This feature is intended as a lightweight, fun event mechanic.

It must not turn V1 into a general-purpose competition-rules engine.


## 31. Current Open Questions

These remain intentionally unresolved.

### Competition format details

The preferred first format is now **Four-Ball Better-Ball**, likely using Stableford/IPS points.

Accepted:
- handicap allowance is configurable per event;
- expected casual-event setting is 100%;
- mixed tees are required and assigned per Round Entry.

Still to settle:

- exact source/verification workflow for Handicap Index and Course Handicap inputs;
- tee-assignment policy and whether organisers assign tees or players confirm/request them;
- tie-breaking rules;
- whether the Mystery Hole Scoring modifier is enabled for the first live event;
- which holes receive mystery rules;
- whether any additional mystery rule beyond `best`, `worst`, and `both` is genuinely required.

### Authentication/access details

Need to decide the exact balance between:

- personal player links;
- group QR links;
- scorer role assignment;
- fallback access recovery.

### Notification delivery channel

Need to determine which delivery mechanisms are required for MVP, for example:

- in-app LiveView messaging;
- browser push;
- WhatsApp/SMS integration;
- email;
- combination.

### Offline model

Need to define the minimum acceptable offline period and conflict behavior.

### Finalisation/reopening

Need explicit rules for:

- closing scoring;
- resolving late disputes;
- organiser override;
- reopening a finalised group/round if truly necessary.

---

## 32. Deferred Questions

These are intentionally not blocking the MVP:

- SaaS multi-tenancy;
- organisations/tenant isolation;
- billing;
- commercial onboarding;
- white-label branding;
- native mobile app;
- advanced player analytics;
- full historical handicap integration;
- club-system integration;
- public tournament marketplace;
- every golf competition format.

---

## 33. Decision Log

### Accepted so far

- Internal-use product first.
- Do not build SaaS multi-tenancy.
- Keep future-friendly domain boundaries.
- Model Round from V1.
- Model Course → Tee Set → Holes rather than storing all rating information directly on Course.
- Support shotgun starts from V1.
- Groups may contain 2–4 players, never more than 4.
- Starting hole belongs to group/round assignment.
- Scorecard UI follows actual shotgun playing order.
- Prefer preloaded player details.
- Avoid mandatory username/password accounts for every player.
- A player must be able to participate without their own functioning smartphone.
- Two designated scoring roles per group where practical.
- Primary Scorer enters results for all active players.
- Verifier reviews rather than independently re-entering all scores.
- Verification is asynchronous.
- Current hole must be resolved for all active players before score-entry progression.
- Missing is a data-integrity state, not a golf outcome.
- Withdrawal and disqualification are round-participation states.
- Pickup/no-points is a format-specific hole outcome.
- Score queries are per player/hole.
- Live leaderboard may use provisional recorded scores.
- Finalisation requires no unresolved required results/queries.
- Organiser may resolve disputes.
- Lightweight score audit trail required.
- Notifications are MVP scope.
- Notification logic must understand shotgun playing order/progress.
- Temporary connectivity resilience is required.
- Plausibility checks warn/confirm rather than prohibit possible scores.
- Players may enter actual gross scores above Net Double Bogey; the actual gross result must be preserved.
- Handicap-adjusted strokes are derived separately and may be capped at Net Double Bogey for established-handicap players.
- Stableford pickup is allowed only once the player can no longer score a point; under that constrained V1 flow the handicap-adjusted value may resolve to Net Double Bogey.
- The product may calculate handicap-ready adjusted totals but must not claim official handicap acceptance or submission without satisfying external handicapping requirements.
- Postgres + Phoenix PubSub + LiveView are sufficient initial infrastructure unless later evidence shows otherwise.
- Preferred first competition format is Four-Ball Better-Ball, likely Stableford/IPS.
- Playing Group and Scoring Team/Side are separate domain concepts.
- A normal 4-player playing group contains two 2-player scoring sides.
- Optional Mystery Hole Scoring should be a modifier on the base format, not a separate scoring engine.
- Initial mystery aggregation rules should be limited to `best`, `worst`, and `both`.
- Mystery rules operate on derived individual Stableford/IPS points, while raw player scores remain authoritative.
- Mystery rules must be configured before play, hidden until hole submission, and locked once the round starts.
- Corrections after mystery-rule reveal require the normal audited verification/query flow.
- Domain boundaries should be designed for long-term expansion even when V1 implements only one concrete path.
- Separate raw authoritative scoring facts from derived competition calculations.
- Prefer enterprise-compatible domain structure with MVP-grade implementation; do not implement speculative generic engines.
- Handicap allowance is event-configurable; expected internal-event default is 100% Course Handicap rather than a hard-coded 85%.
- Mixed tees are required from V1.
- Tee assignment belongs to each player's Round Entry, not the playing group.
- Physical Tee Set, tee rating data, competition category/division, and round tee assignment are separate concepts.
- Do not hard-code men/women/senior/junior directly to specific tee colours.
- Snapshot scoring-relevant handicap and tee inputs for historical reproducibility.
- Handicap details should be collected beforehand where possible but may be confirmed or entered on event day.
- Handicap source/provenance must be retained in the Round Entry handicap snapshot.
- A player without an official Handicap Index must use an explicit event-defined policy rather than an unexplained fallback value.
- Current GolfRSA no-HI guidance is accepted as the default policy: deemed Handicap Index 14.0 for men and 20.0 for women, with organiser/committee discretion to reduce it for known stronger players.
- Players choose their competition partners before the round; side membership locks when scoring opens.
- Players may not switch sides/partners during play for competitive reasons.
- A partner's withdrawal changes Round Participation, not historical Side membership.
- A remaining partner may continue and remain eligible while independent score verification remains available.
- A 3-player playing group may contain one 2-player side and one event-authorized solo side.
- A player may never self-verify their own score.
- Intentional solo sides and two-person sides later reduced to one active player must remain distinguishable.
- The same authoritative player scores must support parallel derived leaderboards.
- V1 should expose a primary Mystery Leaderboard and a secondary Standard Better-Ball Leaderboard.
- Leaderboard differences must come from scoring definitions/projections, not duplicate score entry or duplicate scorecards.
- Because Mystery scoring is the main competition, solo participants should not simply be knowingly disadvantaged on `BOTH` holes; a transparent normalization rule should be used if solos are eligible.
- Solo normalization is accepted as `[P, max(P - 1, 0)]` for Mystery calculations.
- The same solo normalization applies to intentional solo sides and sides reduced to one active player after withdrawal.
- Mystery leaderboard volatility is an intentional product feature.
- Completed Mystery effects may be shown, but future hidden rules must remain secret server-side.
- Tie-breaking is an explicit locked competition policy, not hard-coded leaderboard behavior.
- V1 supports `MYSTERY_HOLES_THEN_COUNTBACK` and `STANDARD_COUNTBACK`.
- Mystery leaderboard should default to Mystery-hole subtotal first, then standard countback.
- Standard Better-Ball leaderboard should default directly to standard countback.
- For shotgun/multiple-tee starts, classic countback uses fixed course holes (10–18, 13–18, 16–18, 18), not each side's chronological final holes.
- Physical completion, verification readiness, and official finalization are separate lifecycle states.
- Finalized scores are protected from ordinary editing but remain correctable through an audited organiser reopen flow.
- Prizegiving readiness should be derived from finalized eligible sides, resolved queries, resolved eligibility, and current tie-break/leaderboard projections.
- The designated verifier must explicitly verify the completed scorecard before `ready_to_finalize`.
- Organiser verification override is allowed only as an audited exception and must not impersonate the verifier.
- End-of-round UX must explicitly show completion, blockers, responsible actor, and next operational instructions.
- Every player should receive a personal event link where possible; the same link acts as pre-event portal, scoring access, and post-round view.
- Scoring availability is controlled server-side by the event/round lifecycle and configured opening time.
- Organisers must be able to resend/reissue player access on the day.
- All players in a group can view the full group scorecard.
- The Primary Scorer is the only ordinary role that enters all group scores.
- The Designated Verifier verifies the complete card and may query any player/hole.
- Ordinary players may query their own submitted score but cannot edit or verify other players' results.
- Event-level and hole-level sponsorship are MVP domain concepts.
- Side Competitions are first-class competition resources and may have their own sponsor/prize.
- V1 implements Closest to the Pin and Longest Drive; future concrete types may include Longest Putt, Hole-in-One, Jackpot Hole, and Sponsor Challenge.
- Sponsor content must never block or materially degrade score entry.

---

## 34. Next Pressure-Test Topic

**Four-Ball Better-Ball Handicap and Team Rules**

The next domain decision should define:

- exact Stableford/IPS scoring semantics;
- handicap allowance and Playing Handicap calculation;
- stroke allocation by hole;
- pickup/no-points behavior;
- team leaderboard ordering;
- tie-breaking;
- how incomplete 2-player sides are handled;
- whether the Mystery Hole Scoring option is enabled for the first event.

---

## 35. Spec Maintenance Rules

As the design discussion continues:

- settled decisions move into **Accepted** sections;
- likely but unconfirmed decisions remain **Provisional**;
- unresolved matters stay under **Open Questions**;
- intentionally excluded features remain **Deferred**;
- contradictions must be resolved explicitly rather than silently overwritten;
- major decisions should be reflected in the Decision Log;
- implementation tickets should not be generated until the product/domain model is sufficiently stable.

## 36. Architecture Principle — Enterprise-Grade Domain Shape, MVP-Grade Implementation

### Accepted

The system should be designed with **long-term domain boundaries and separation of concerns from the start**, even though the first implementation is intentionally small.

The goal is:

> **Use the same domain shape we would expect in a larger competition platform, but only implement the capabilities required by the internal MVP.**

This means the architecture should leave clean expansion paths for future capabilities such as:

- additional competition formats;
- multi-round events;
- multi-course events;
- more advanced handicap rules;
- richer scoring policies;
- alternate team/side structures;
- tournament/tour series;
- player rankings;
- stronger certification workflows;
- external club/handicap integrations;
- advanced leaderboards and projections;
- more sophisticated scoring modifiers;
- richer notification/event orchestration;
- optional multi-tenancy if a real business need appears later.

### Critical boundary

Future expansion should influence:

- domain boundaries;
- ownership;
- resource relationships;
- lifecycle design;
- naming;
- interfaces between contexts/domains;
- separation between raw facts and derived results.

Future expansion should **not** cause MVP implementation of:

- generic formula engines;
- arbitrary rules DSLs;
- plugin systems;
- dynamic workflow engines;
- tenant infrastructure;
- unnecessary queues/caches;
- generic enterprise configuration frameworks.

### Design rule

Prefer:

```text
stable domain interface
        +
small concrete V1 implementation
```

over:

```text
V1-specific schema and logic
that must later be replaced
```

But also prefer:

```text
small concrete V1 implementation
```

over:

```text
generic abstraction whose future requirements are not yet known
```

### Example — Competition Rules

The domain should model a clear scoring/rules boundary from V1.

Conceptually:

```text
Raw Player Result
        ↓
Player Scoring / Handicap Rules
        ↓
Individual Competition Result
        ↓
Team / Side Aggregation
        ↓
Optional Competition Modifier
        ↓
Leaderboard Projection
```

For the first event, those stages may have only one concrete implementation:

```text
Four-Ball Better-Ball Stableford
+
optional Mystery Hole modifier
```

A generic formula language is **not** required.

Future formats should be added by introducing new concrete rule implementations behind the existing domain boundary rather than rewriting raw score storage or event structure.

### Example — Raw Facts vs Derived Results

Authoritative raw facts should be kept separate from calculated outputs.

Examples of raw facts:

- player identity;
- round participation;
- tee set;
- hole;
- gross strokes or explicit hole outcome;
- handicap snapshot;
- score revision history.

Examples of derived values:

- Playing Handicap;
- strokes received on a hole;
- Stableford points;
- team hole points;
- cumulative team score;
- leaderboard position.

Derived values may be recalculated as rules evolve, while raw scoring facts remain stable and auditable.

### Example — Group vs Team vs Scorecard

Do not collapse these concepts merely because the MVP often has one simple shape:

```text
Playing Group
  = who plays together operationally

Side / Team
  = who competes together

Round Entry
  = a player's participation in a specific round

Scorecard
  = scoring record for that round participation

Hole Result
  = authoritative player outcome on one hole
```

This separation provides future breathing room without requiring future features to be implemented now.

### Example — Event vs Round

Even though MVP uses one course and one round:

```text
Event
└── Round
```

remains the correct domain shape.

Future expansion can then support:

```text
Event
├── Round 1 — Course A
├── Round 2 — Course B
└── Aggregate standings
```

without changing the meaning of existing scorecards.

### Architectural test

Before accepting a domain shortcut, ask:

> Would this resource still mean the same thing if we later added another format, round, course, or scoring policy?

If the answer is no, the boundary is probably too MVP-specific.

Before accepting an abstraction, also ask:

> Do we have at least one concrete current use case that needs this abstraction boundary?

If the answer is no, define the conceptual boundary but defer the generic implementation.

### Anti-overengineering rule

The project should aim for **enterprise-compatible structure, not enterprise-complete infrastructure**.

That distinction is mandatory.

## 37. Handicap Allowance and Mixed-Tee Architecture

### Accepted

The event must **not hard-code a specific handicap allowance such as 85%**.

Handicap allowance is an event/competition-rule setting.

For the expected casual internal event, the normal configuration is:

```text
handicap_allowance_percent = 100
```

This means players ordinarily compete using their full Course Handicap, subject to the applicable rules for the selected tees and competition format.

The system should permit the organiser to explicitly configure another percentage for a future event.

Examples:

```text
100%  ← expected internal-event default
85%
90%
95%
```

The percentage is configuration, not a new competition format.

### Handicap calculation separation

Keep these concepts separate:

```text
Handicap Index
        ↓
Course Handicap
        ↓
Competition Handicap Allowance
        ↓
Playing Handicap
        ↓
Hole Stroke Allocation
        ↓
Individual Stableford / IPS Points
```

Do not store only one generic `"handicap"` value and reuse it for every purpose.

For a 100% allowance, Playing Handicap will normally equal the rounded Course Handicap for the selected tee/rating context.

### Mixed tees are required from V1

A single playing group may contain players using different tees.

Examples include a group containing:

- adult men;
- adult women;
- seniors;
- juniors.

Therefore:

> **Tee assignment belongs to the player's Round Entry, not to the Group and not globally to the Round.**

Conceptually:

```text
Round
└── Playing Group
    ├── Round Entry A → Tee Assignment A
    ├── Round Entry B → Tee Assignment B
    ├── Round Entry C → Tee Assignment C
    └── Round Entry D → Tee Assignment D
```

Players in the same fourball may therefore use different physical tee sets while remaining part of the same playing group and scoring sides.

### Physical tee vs rating data vs participant category

Do not collapse these concepts.

Preferred conceptual separation:

```text
Course
└── Tee Set
    ├── physical identity / colour / name
    ├── hole distances
    └── Tee Rating Profile(s)
        ├── Course Rating
        ├── Slope Rating
        ├── par / rated par context
        └── applicable rating classification

Player / Round Entry
├── competition category / division where applicable
└── assigned Tee Rating Profile
```

The exact final resource names should be determined during domain modelling.

The architecture must support a physical tee set having the rating information required for the applicable player/rating classification.

### Do not encode social labels as scoring logic

Avoid domain rules such as:

```text
male => white
female => red
senior => forward
junior => forward
```

These are event policies, not universal golf truths.

Instead, an event may define a tee-assignment policy or organisers may explicitly assign the applicable tee/rating profile to each Round Entry.

This supports:

- mixed gender;
- mixed age/ability;
- different tee policies at different events;
- courses with different tee naming/colour conventions;
- future competition divisions.

### Stableford and multiple tees

The handicap/scoring engine must use the correct Course Rating, Slope Rating, par and Stroke Index data for each player's assigned tee/rating context.

For Stableford, multi-tee competition handling must follow the applicable handicapping rules. The architecture must not assume that all players share the same course par, rating or slope merely because they are in the same playing group.

### Round snapshot requirement

When a Round Entry is activated for play, the scoring-relevant handicap inputs should be snapshotted so historical results do not silently change if course/tee or player handicap data is edited later.

Expected snapshot inputs include:

- Handicap Index used for the event;
- assigned Tee Set / Tee Rating Profile;
- Course Rating;
- Slope Rating;
- applicable par;
- configured handicap allowance;
- resulting Course Handicap / Playing Handicap;
- hole Stroke Index allocation required for scoring.

Exact persistence vs derivation choices remain for implementation architecture, but historical reproducibility is required.

## 38. Handicap Capture, Confirmation, and Players Without an Official Handicap

### Accepted direction

The organiser should try to collect Handicap Index information before the event, but the system must support event-day confirmation and entry.

A player's handicap information must be attached to their **Round Entry / Handicap Snapshot**, not treated as a permanently trusted value on the Player record.

### Event-day confirmation flow

When opening their event access, a player should see the handicap information currently prepared for the round.

Example:

```text
Handicap Index: 12.4
Assigned Tee: Blue
Calculated Course Handicap: 14

[Confirm]
[My Handicap Index is different]
[I do not have an official Handicap Index]
```

A player may enter/correct their Handicap Index before scoring begins.

Once the player's round is active, changes to handicap inputs should require an explicit organiser-authorised correction and audit trail, because changing handicap inputs can recalculate previous hole points and leaderboard results.

### Handicap source

The scoring snapshot should retain how the value was obtained.

Conceptual source types:

```text
official_or_preloaded
player_declared
committee_deemed
committee_override
```

The exact naming is not final.

The system should retain:

- Handicap Index or deemed Handicap Index used;
- source;
- who confirmed/assigned it;
- timestamp;
- assigned tee/rating context;
- calculated Course Handicap;
- Playing Handicap used for the competition.

This keeps a self-declared event-day value distinguishable from a preloaded/committee-assigned value without building an external handicap-verification integration for MVP.

### Players without an official Handicap Index

The event's Terms / Competition Rules must define whether a player without an official Handicap Index may participate and how their Playing Handicap is determined.

Current GolfRSA 2024 local guidance recommends, where such players are allowed:

```text
deemed Handicap Index:
Men   = 14.0
Women = 20.0
```

The committee may assign a lower Playing Handicap where the player's known ability warrants it.

GolfRSA further notes that a handicap allowance is not applied to an issued Playing Handicap for this case.

### Accepted MVP policy

For the first internal event:

1. players with a Handicap Index use the confirmed/snapshotted index and normal event handicap configuration;
2. players without a Handicap Index remain eligible to play;
3. the event applies a clearly published default no-HI policy;
4. default policy should follow the current GolfRSA recommendation unless the organiser deliberately chooses a house rule;
5. organisers may override the resulting handicap downward for known ability;
6. every committee/deemed assignment is stored explicitly and auditable;
7. players are told the handicap they will play from before their round begins.

### Avoid arbitrary hidden defaults

Do not silently assign:

- scratch;
- 9;
- 18;
- 24;
- or any other number

without an explicit event rule.

Older South African guidance used different values (including a 24-course-handicap convention for some women without a South African Handicap Index), so the system must not embed historic conventions as universal business logic.

### Architecture rule

The domain must not represent `"has no Handicap Index"` as though the player suddenly owns a genuine Handicap Index.

Keep separate:

```text
Official / declared Handicap Index
            vs
Competition-assigned/deemed handicap basis
            vs
Playing Handicap actually used
```

This preserves semantic correctness and leaves room for future integrations with official handicap providers without changing historical competition records.

## 39. Side Membership, Solo Continuation, and Verification Eligibility

### Accepted

Players may choose their own two-person competition partners before the round.

The system must explicitly persist the resulting **Side / Partnership membership**.

A normal four-player playing group therefore contains:

```text
Playing Group
├── Side A
│   ├── Player A1
│   └── Player A2
└── Side B
    ├── Player B1
    └── Player B2
```

### Side membership lock

Side membership must be locked when competitive scoring opens.

Players may not switch partners during the round because:

- one partner is playing badly;
- another player is playing well;
- a mystery-hole rule has been revealed;
- leaderboard position changes.

Preferred lifecycle:

```text
draft
  ↓
locked
  ↓
completed
```

The `Side` membership itself does not change when a partner later withdraws. Instead, the player's **Round Participation** changes state.

### Clerical correction

Before competitive scoring begins, organisers may correct an incorrectly captured partnership.

After scoring has begun, partnership replacement/swapping is not permitted as an ordinary action.

Any exceptional administrative correction must be explicit, privileged and audited. The implementation should not provide a casual `"change partner"` action during play.

### One partner may continue

If one member of an originally valid two-person side:

- withdraws;
- becomes unable to continue; or
- is otherwise no longer active,

the remaining partner may continue representing that side and remain prize/competition eligible **provided independent score verification remains available**.

This is consistent with the Four-Ball concept that one partner may represent a side for all or part of a round.

The withdrawn player's future holes are not populated with fake scores. Their Round Participation records the withdrawal, while the Side retains its original membership history.

### Verification requirement

A solo continuing player must have at least one other eligible person in the playing group who can independently verify/mark their scores.

The player may never self-verify their own hole results.

If the playing group eventually contains only that one active golfer and no independent verifier/marker is available:

```text
competitive eligibility = blocked / review required
```

The golfer may still finish the round recreationally, but the result should not silently remain prize-eligible without organiser resolution.

The exact organiser exception policy remains to be finalized.

### Three-player playing groups

A 3-player playing group is valid operationally.

The intended internal-event policy is:

```text
3 players
├── one 2-player Side
└── one Solo Side
```

The Solo Side may compete provided:

- the event permits solo-side participation;
- the solo player has independent score verification from another active player in the group;
- the solo player may not later join or replace a member of the existing two-person side;
- the solo player's side membership/solo status is locked once scoring begins.

### Rules distinction

A deliberately created Solo Side is an **internal event variation**, not ordinary standard Four-Ball partnership structure.

The application must preserve that distinction rather than pretending the solo competitor is a normal two-partner Four-Ball side.

Conceptually:

```text
Side Type
├── partnership   # normal two-player side
└── solo          # event-authorized house-rule side
```

Exact resource representation should be chosen during domain modelling; an enum is not mandated at this stage.

### Reduced partnership vs intentional solo

These are different historical facts:

```text
A. Intentional Solo Side
   started round with one competitor

B. Partnership Side
   started with two partners
   one later withdrew
```

The domain must preserve this distinction even if both later have only one active golfer contributing scores.

### Mystery-hole aggregation with one active competitor

Mystery-hole behavior for a one-active-player side must be explicit.

Current preferred semantic model is:

```text
eligible_contributors = active competitors on the side for that hole

BEST  = max(eligible contributor points)
WORST = min(eligible contributor points)
BOTH  = sum(eligible contributor points)
```

For one eligible contributor:

```text
BEST  = that player's points
WORST = that player's points
BOTH  = that player's points
```

This is simple and deterministic, but `BOTH` naturally gives a one-player side less scoring potential than a two-player side.

**This fairness rule remains provisional and requires explicit owner acceptance before implementation.**

Do not invent a synthetic second score or duplicate the solo player's points unless the competition terms explicitly choose that behavior.

## 40. Parallel Leaderboards and Solo Normalization for Mystery Scoring

### Accepted direction

The system must be able to calculate more than one leaderboard from the **same authoritative player hole results**.

For the first event, support two scoring views:

```text
1. Standard Better-Ball Leaderboard
   - treats every hole as normal BEST Better-Ball Stableford
   - ignores Mystery modifiers

2. Mystery Leaderboard
   - uses normal BEST scoring on ordinary holes
   - applies the configured hidden Mystery aggregation rule on Mystery holes
```

The Mystery Leaderboard is intended to be the **primary/main event leaderboard** for the novelty competition.

The Standard Better-Ball Leaderboard remains available as a secondary comparison / conventional result.

### Architecture rule

Do not duplicate score entry or store separate scorecards for each leaderboard.

Preferred calculation shape:

```text
Authoritative Player Hole Results
        ↓
Individual Stableford Points
        ↓
Leaderboard Definition / Scoring Track
        ├── Standard Better-Ball
        └── Mystery Better-Ball
        ↓
Derived Side Hole Results
        ↓
Leaderboard Projection
```

The exact implementation may use concrete modules/configuration rather than a generic formula engine.

This creates future room for additional leaderboard views without changing raw scoring storage.

### Leaderboard naming

Avoid ambiguous UI labels such as:

- `"Main without Mystery"`
- `"Other leaderboard"`

Preferred public naming:

```text
Mystery Leaderboard      # primary
Standard Better-Ball     # secondary
```

The event may designate one leaderboard as the primary/public default.

### Solo fairness problem

If the Mystery Leaderboard is the main competition, intentionally leaving a Solo Side with only one scoring opportunity on a `BOTH` hole is considered materially disadvantageous.

A transparent normalization rule is therefore preferred over simply warning the solo player that they are disadvantaged.

### Accepted solo-normalization rule

A possible house rule is to derive a **normalized companion contribution** from the solo player's individual Stableford points:

```text
solo_points = P

normalized_companion_points = max(P - 1, 0)
```

Mystery aggregation then behaves as though the solo side has:

```text
[P, max(P - 1, 0)]
```

Examples:

```text
Solo scores 0 points
normalized pair = [0, 0]

Solo scores 1 point
normalized pair = [1, 0]

Solo scores 2 points
normalized pair = [2, 1]

Solo scores 3 points
normalized pair = [3, 2]

Solo scores 4 points
normalized pair = [4, 3]
```

This yields:

```text
BEST  = P
WORST = max(P - 1, 0)
BOTH  = P + max(P - 1, 0)
```

For positive scores, `BOTH` is effectively:

```text
(2 × P) - 1
```

but modelling it as a normalized companion contribution keeps all Mystery aggregation rules consistent.

### Important semantic rule

The normalized companion contribution is **not a player score** and must never be stored as a fake Hole Result.

It is only a derived team-scoring value used by the Mystery calculation.

The authoritative facts remain:

- one real player;
- one real individual Stableford score;
- one competition normalization rule.

### Status

The `P + max(P - 1, 0)` solo normalization is **accepted** for the internal event competition.

It must be clearly disclosed in the competition terms if adopted.

### Accepted fairness rule

Solo normalization applies to:

- intentional Solo Sides from the start of the round; and
- two-player sides reduced to one active player after withdrawal.

For a side reduced to one active player during the round, normalization applies from the first hole on which only one eligible contributor remains.

## 41. Mystery Leaderboard Experience and Volatility

### Accepted

The Mystery Leaderboard is intentionally designed to remain volatile and suspenseful.

Because selected holes may use `WORST` or `BOTH` aggregation instead of normal `BEST` Better-Ball scoring, teams can gain or lose ground quickly even late in the round.

This is a feature of the event format.

### UX principle

The leaderboard should explain **what has already happened** without revealing **what will happen next**.

Players may see:

- current Mystery position;
- current Mystery total;
- completed-hole Mystery rule results;
- movement up/down the leaderboard;
- completed mystery-hole impact.

Players must not see:

- future Mystery rule assignments;
- which upcoming holes are Mystery holes if the event configuration intends those to remain secret;
- unrevealed aggregation rules.

### Standard vs Mystery leaderboard

The application should expose both:

```text
Mystery Leaderboard
- primary event leaderboard
- uses completed Mystery modifiers
- intended to create suspense and score swings

Standard Better-Ball Leaderboard
- secondary reference leaderboard
- treats every hole as normal BEST Better-Ball
```

The Standard leaderboard provides a useful baseline while the Mystery leaderboard determines the main competition outcome.

### Leaderboard recomputation

When a verified/corrected player result changes:

1. recalculate that player's individual Stableford result;
2. recalculate affected Standard side result;
3. recalculate affected Mystery side result using the historically locked hole rule;
4. update both leaderboard projections;
5. broadcast the changed projections in real time;
6. retain the score revision/audit history.

No leaderboard owns authoritative score data.

### Reveal integrity

Leaderboard calculations may only use a Mystery rule after that rule has become reveal-eligible for the group/hole according to the competition rules.

Future hidden rules must not leak through APIs, client payloads, HTML attributes, browser storage, or preloaded LiveView assigns accessible to the player interface.

The implementation must therefore enforce secrecy server-side, not merely hide the rule visually with CSS/JavaScript.

## 42. Hole Result Semantics for Stableford / IPS

### Accepted

For the initial Four-Ball Better-Ball Stableford event, each active player must resolve every played hole with one of two ordinary outcomes:

```text
1. HOLED_OUT
   - actual gross strokes recorded

2. PICKED_UP
   - player did not hole out once no Stableford points remained available
   - competition points = 0
```

A blank value is never treated as either outcome.

### `HOLED_OUT`

When the player completes the hole by holing out:

```text
outcome = holed_out
gross_strokes = actual strokes including applicable penalties
```

The scoring engine then derives:

- net score for competition purposes;
- Stableford / IPS points;
- side contribution;
- Standard Better-Ball result;
- Mystery result.

If the actual gross score produces zero Stableford points, the actual gross score may still be retained.

Do not silently replace it with a lower capped value.

### `PICKED_UP`

When the player stops playing because they can no longer score a Stableford point:

```text
outcome = picked_up
gross_strokes = nil unless an actual completed gross score exists
competition_points = 0
```

The UI should provide an explicit action such as:

```text
[ Picked Up / No Points ]
```

rather than forcing a fabricated numeric score.


### High gross scores are preserved

The scorer may enter a gross score higher than the player's Net Double Bogey.

Example:

```text
Actual gross score = 11
Stableford points = 0
Handicap maximum for the hole = 7
```

Persist:

```text
competition_gross_strokes = 11
competition_points = 0
handicap_adjusted_strokes = 7
```

Do not overwrite `11` with `7`.

This preserves the actual competition history while still allowing an adjusted score to be derived for handicap purposes.

The UI may warn on highly unusual scores, but it should not impose an arbitrary competition maximum merely to simplify handicap calculations.

### Handicap-adjusted hole value

For a player with an established Handicap Index who holes out:

```text
handicap_adjusted_strokes =
  min(actual_gross_strokes, net_double_bogey_for_hole)
```

Net Double Bogey must be calculated using the player's **full Course Handicap**, not a reduced competition Playing Handicap.

For a player establishing an initial Handicap Index, current WHS rules use a different maximum (`par + 5`) and this must remain a separate policy if the product later supports official handicap submission for such players.

### Picked-up holes and handicap adjustment

The MVP permits `PICKED_UP` only when the player's own Stableford result can no longer produce a point.

Because Net Double Bogey is the lowest score that yields zero Stableford points, this restriction allows the handicap-adjusted hole value to resolve to the applicable Net Double Bogey cap for an established-handicap player.

This deliberately avoids requiring golfers to enter artificial high gross scores simply to produce a handicap-adjusted total.

If the application later permits pickup for other reasons (for example because a partner's score makes the player's result irrelevant), it must implement the applicable **Most Likely Score** rules rather than automatically treating every pickup as Net Double Bogey.

### Handicap output is derived, not authoritative external posting

The application may calculate and display/export an adjusted gross score suitable for possible handicap entry.

However, it must not claim that a round is officially acceptable for handicap purposes merely because 18 holes were completed.

Official acceptability also depends on applicable Rules of Handicapping requirements such as:

- authorized format;
- rated course/tees;
- sufficient holes;
- playing in the company of another person / marker;
- compliance with the Rules of Golf;
- any local GolfRSA / Authorized Association requirements.

MVP does not need direct handicap-system submission integration.


### Stableford progression

A picked-up result counts as a **resolved hole result**.

Therefore the group may advance once every active player has either:

- a valid holed-out result; or
- an explicit picked-up result.

Example:

```text
Hole 7

John    5
Susan   4
Peter   Picked Up / 0 pts
Mary    6

[Submit Hole]
```

This is complete.

### Partner performance must not determine pickup eligibility

For the Mystery competition, a golfer must not pick up merely because their partner already has a strong Better-Ball result.

The player's own Stableford result may still matter under:

- `WORST`;
- `BOTH`.

The player should only pick up once **that player's own hole can no longer produce a Stableford point**.

This rule should be explained clearly in the event instructions.

### Competition score vs handicap adjustment

Keep these concepts separate:

```text
actual gross hole result
        ↓
competition Stableford result
        ↓
handicap-adjusted score for handicap purposes
```

For a player with an established Handicap Index, WHS Net Double Bogey is the maximum score used for handicap purposes and corresponds to the lowest score producing zero Stableford points.

Do not overwrite the authoritative competition hole result with Net Double Bogey.

If future integration requires submission of handicap-adjusted scores, derive that value separately from the stored hole result and handicap snapshot.

### Future Medal / Stroke Play

Do not reuse Stableford pickup semantics for Medal / regular stroke play.

Future competition formats must define their own valid hole outcomes and maximum-score behavior.

The initial scoring UI should only expose outcomes valid for the active competition definition.

### Plausibility validation

Plausibility checks remain warnings, not golf-rule prohibitions.

Examples:

- score of 1 on a Par 4 or Par 5 → explicit confirmation;
- unusually high entered gross score → optional confirmation;
- correction after Mystery rule reveal → audited correction path.

The system should never reject a technically possible score merely because it is unlikely.

### Hole submission boundary

For the initial event, the preferred workflow is:

```text
Enter/resolve all active player results
        ↓
Review hole
        ↓
Submit Hole
        ↓
Hole results become recorded
        ↓
Mystery rule becomes reveal-eligible
        ↓
Team projections + leaderboards update
        ↓
Verifier may verify/query asynchronously
```

Before `Submit Hole`, the primary scorer may freely correct entries for the current hole.

After submission/reveal, changes must use the audited correction/query path.

## 43. Tie-Break Policies

### Accepted architecture

Tie-breaking must be an explicit **competition policy**, not hard-coded into the leaderboard.

V1 should support exactly two concrete tie-break strategies:

```text
1. MYSTERY_HOLES_THEN_COUNTBACK
2. STANDARD_COUNTBACK
```

The organiser selects the policy before competitive scoring opens.

The selected policy is part of the competition terms and becomes locked with the round scoring configuration.

Do not build a generic tie-break DSL or arbitrary policy engine for MVP.

### Strategy 1 — Mystery Holes Then Countback

Recommended for the novelty competition.

When two or more sides finish with the same total Mystery Leaderboard points:

```text
Step 1
Compare total Mystery Leaderboard points earned on holes
configured as Mystery holes only.

Higher subtotal wins.
```

If still tied:

```text
Step 2
Apply the Standard Countback policy.
```

This makes the special holes meaningful without requiring a separate playoff.

Important:

- use the actual Mystery scoring rule applied on each Mystery hole;
- do not recalculate those holes as ordinary `BEST` holes for the mystery tie-break subtotal;
- use only holes explicitly configured as Mystery holes;
- corrected hole results automatically recalculate the mystery-hole subtotal.

### Strategy 2 — Standard Countback

Classic scorecard countback should follow the competition's published Terms.

For a single 18-hole round, the default V1 implementation should compare:

```text
holes 10–18
then holes 13–18
then holes 16–18
then hole 18
```

If still tied, continue using:

```text
holes 4–9
then holes 7–9
then hole 9
```

If still tied after the configured countback sequence, the competition terms must define the final fallback, for example:

- shared placing;
- organiser-approved random draw;
- another explicit house rule.

V1 should prefer shared placing unless the event explicitly configures another final fallback.

### Shotgun-start rule

For shotgun starts, "last nine", "last six", "last three", and "last hole" in classic countback refer to the fixed **course hole numbers**, not the final holes personally played by each side.

Therefore a side starting on Hole 14 does **not** use its chronological final nine holes for standard countback.

This follows the R&A recommendation for competitions with multiple-tee starts and guarantees all tied sides are compared over the same course holes.

### Leaderboard-specific tie-break policy

Each leaderboard definition may own its tie-break policy.

Recommended first-event configuration:

```text
Mystery Leaderboard
tie_break = MYSTERY_HOLES_THEN_COUNTBACK

Standard Better-Ball Leaderboard
tie_break = STANDARD_COUNTBACK
```

This preserves conventional ordering on the Standard leaderboard while letting the Mystery competition emphasize its distinguishing feature.

### Derived, reproducible result

Tie-break results are derived from:

- authoritative player hole results;
- locked Mystery-hole configuration;
- leaderboard definition;
- locked tie-break policy.

Do not persist an unexplained manual rank as the source of truth.

If underlying scores are corrected before finalization, tie-break ordering must recalculate automatically.

Once the competition is finalized, the inputs and policy used to determine the final placing must remain historically reproducible.

## 44. Round Completion, Verification, and Finalization

### Accepted

The system must distinguish physical completion of play from competitive finalization.

A Side / Group may therefore move through:

```text
not_started
    ↓
playing
    ↓
finished_playing
    ↓
review_required OR ready_to_finalize
    ↓
finalized
```

### `finished_playing`

A group is `finished_playing` when:

- every active player's final scheduled hole has a resolved Hole Result;
- withdrawn/disqualified players have explicit Round Participation states;
- no required hole is blank.

This means the players are physically done with the round.

It does **not** mean their competition result is official.

### `review_required`

A completed group/side enters `review_required` when any blocking issue remains, for example:

- one or more player/hole results are queried;
- required verification is outstanding;
- a late score correction is pending;
- an exceptional participation/eligibility issue requires organiser resolution;
- a solo player lacks the required independent verification;
- another explicitly modelled scoring integrity issue exists.

### `ready_to_finalize`

A side/group may become `ready_to_finalize` when:

- all required hole results are resolved;
- no score query remains open;
- the required verification policy is satisfied;
- no eligibility blocker remains;
- all derived team/leaderboard calculations can be reproduced.

### `finalized`

Finalization means:

- the competition result is accepted for prize/results purposes;
- the side/group's current score inputs are locked against ordinary player/scorer editing;
- all leaderboards recalculate from the finalized authoritative result set;
- subsequent changes require privileged organiser action and an audit trail.

Finalization is not deletion of edit capability. It changes the correction path.

### Verification threshold — provisional

For the internal event, the recommended MVP rule is:

- the designated verifier should verify the hole results;
- verification may happen asynchronously during the round;
- a group should not be `ready_to_finalize` while any submitted score remains unverified or queried;
- organiser resolution may satisfy the verification requirement for exceptional cases.

The implementation should make bulk review easy so the verifier can verify many clean results quickly rather than tapping every score individually if unnecessary.

### Finalization authority

Recommended MVP:

```text
Players / scorers
- can finish playing
- can review/query
- cannot finalize official competition result

Organiser
- can see readiness
- can resolve exceptions
- can finalize side/group or round
```

A later version may support automatic side finalization after all conditions pass, but manual organiser control is preferred for the first real event.

### Round-level finalization

The overall Round may be finalized only when all competition-eligible sides are in a terminal competition state:

```text
finalized
or
explicitly withdrawn / disqualified / excluded
```

No unresolved score queries may remain.

Before round finalization, the organiser should see a concise readiness summary such as:

```text
36 sides/groups

30 finalized
3 ready to finalize
2 review required
1 still playing
```

### Reopening a finalized result

A finalized side/result may be reopened only by an organiser with an explicit reason.

Example lifecycle:

```text
finalized
    ↓ organiser reopen + reason
review_required
    ↓ correction / verification
ready_to_finalize
    ↓
finalized
```

Reopening must:

- retain the prior finalized values in audit history;
- record who reopened it;
- record why;
- unlock only the affected result scope;
- recalculate affected Standard and Mystery leaderboard projections after correction;
- preserve the locked Mystery rule originally used for each hole.

### Final round lock

Once the entire Round is finalized:

- ordinary score editing is disabled;
- leaderboard standings become official/final;
- Mystery and Standard leaderboard outcomes are frozen from the finalized source data;
- any later exceptional correction requires an explicit Round reopen process.

The application should avoid irreversible database-level destruction. "Finalized" means protected and audited, not impossible to correct.

### Prizegiving readiness

The system should expose a dedicated organiser state:

```text
PRIZEGIVING_READY = true
```

only when:

- all eligible sides are finalized;
- no unresolved score queries remain;
- no unresolved eligibility issue remains;
- tie-break calculations are complete;
- primary and secondary leaderboard projections are current.

This is a derived readiness condition, not a manually typed boolean.

## 45. End-of-Round UX and Responsibility Handoff

### Accepted

The end-of-round experience must clearly explain:

- whether all required hole results are captured;
- whether verification is complete;
- whether any query/dispute remains;
- who must act next;
- whether the group may leave the scoring workflow;
- whether organiser attention is required;
- whether the result is finalized;
- what happens next operationally, including clubhouse/prizegiving instructions.

The UI must not reduce these states to a generic `"Finished"` message.

### Primary Scorer end-of-round flow

After the final scheduled hole is submitted:

```text
FINAL HOLE SUBMITTED
        ↓
Check:
- all active players resolved on every required hole?
- any queries?
- verifier complete?
        ↓
Show exact next action
```

Example when scoring is complete but verification remains:

```text
Your scoring is complete.

18 / 18 holes captured
0 missing scores
0 open queries

Waiting for:
Peter — final scorecard verification

You may return to the clubhouse.
Prizegiving instructions: [event message]
```

### Verifier end-of-round flow

The verifier should receive a dedicated review summary rather than being forced to reopen 18 holes manually.

Example:

```text
SCORECARD REVIEW

72 player-hole results
68 already verified
4 need your review

[Review outstanding]
```

Where appropriate, the UI may offer efficient actions such as:

```text
[Verify all clean results]
```

provided queried/changed/unusual results still receive individual attention.

After completion:

```text
Verification complete.
No queries outstanding.

This group is ready for organiser finalization.
```

### Query state

If a disagreement remains:

```text
REVIEW REQUIRED

Susan — Hole 14
Recorded: 6
Verifier query: expected 5

Action required:
Primary scorer and verifier should resolve this score.
If unresolved, ask an organiser.
```

The UI must identify the exact player/hole and next responsible actor.

### Organiser end-of-round workflow

The organiser dashboard must support rapid prizegiving preparation.

At minimum show:

```text
Still playing
Finished — verifier outstanding
Review required
Ready to finalize
Finalized
```

For every blocked group, show the blocking reason.

Examples:

```text
Group 12
BLOCKED: verifier outstanding

Group 18
BLOCKED: Hole 7 query

Group 23
BLOCKED: solo-player verification exception

Group 31
READY TO FINALIZE
```

The organiser should not need to inspect every scorecard to determine readiness.

### Verification requirement

Every competition-relevant player/hole result must be independently verified by someone other than the player whose score it is.

Operationally:

- the Designated Verifier verifies the Primary Scorer and all other players except themselves;
- the Primary Scorer verifies the Designated Verifier's own results;
- no player may self-verify.

The completed scorecard cannot become `ready_to_finalize` until this independent-verification requirement is satisfied for all required results.

Organiser override is permitted only for a genuine exception and must:

- require an explicit reason;
- identify the organiser;
- be recorded in the audit history;
- satisfy the verification blocker for finalization without pretending the original verifier performed the action.

### Player-facing completion state

After all player responsibilities are complete, the player-facing experience should clearly transition away from score entry.

Example:

```text
ROUND COMPLETE ✓

Scoring complete
Verification complete
Result submitted for finalization

Current Mystery position: 4th
Current Standard Better-Ball position: 2nd

Next:
Return to the clubhouse.
Prizegiving starts at 17:30.
```

Exact leaderboard visibility depends on event configuration.

### Finalized state

After organiser finalization:

```text
RESULT FINALIZED ✓
```

The UI may show:

- final Mystery position;
- final Standard Better-Ball position;
- total points;
- mystery-hole impact summary;
- handicap-adjusted round summary where appropriate;
- event/prizegiving instructions.

Ordinary player/scorer editing is disabled.

### UX principle

At every end-of-round state, answer these four questions:

```text
1. Are we finished playing?
2. Is our scoring complete?
3. Does anyone still need to do something?
4. Can we leave / what happens next?
```

If the interface cannot answer those four questions immediately, the end-of-round UX is incomplete.

## 46. Player Access, Pre-Event Portal, and Scoring Roles

### Accepted direction

Every player should receive a **personal event access link** where possible before the event.

The same link remains useful before, during, and after the round.

The player should not need a traditional username/password account for ordinary event participation.

### Personal event access lifecycle

Conceptually:

```text
INVITED
   ↓
PRE_EVENT
   ↓
SCORING_OPEN
   ↓
PLAYING / REVIEWING
   ↓
ROUND_COMPLETE
   ↓
FINALIZED
```

The access link itself remains stable; the capabilities and content shown change according to event/round state and the player's role.

### Pre-event portal

Before scoring opens, the personal link should show a useful event page rather than an inaccessible scorecard.

Expected content:

- event name;
- date;
- venue/course;
- countdown to scoring/event start;
- player's name;
- fourball / playing group;
- partner / side assignment where already known;
- starting hole;
- assigned tee;
- Handicap Index / Course Handicap confirmation;
- competition rules / quick instructions;
- contact/help information;
- event sponsors;
- important organiser messages.

Example:

```text
GOLF DAY 2026

Starts in:
02:14:37

JC Schoeman
Group 12
Start: Hole 14
Tee: Blue
Handicap Index: 12.4

Your scorecard unlocks when scoring opens.

[Confirm my details]
[View event rules]
```

### Scoring availability

Scoring must be gated server-side by the Round/Event lifecycle.

Preferred configuration:

```text
scoring_opens_at
scoring_closes_at (optional operational boundary)
manual_open / organiser override
```

For a shotgun event, one scheduled scoring-open time is expected to be sufficient.

The client must not receive hidden scoring capabilities or Mystery data merely because buttons are visually disabled before the opening time.

### Day-of access

The organiser must also be able to provide access on the day for players who:

- ignored the earlier message;
- did not receive the link;
- changed phones;
- joined late;
- need their access resent.

Supported operational methods may include:

- resend personal link;
- display/share personal QR;
- search player and open/reissue access;
- group recovery QR/link where appropriate.

Do not require access to the original email/WhatsApp message in order to recover scoring access.

### Player visibility inside the group

All active players in a playing group may view:

- all active players in the group;
- all submitted hole results for the group;
- current hole;
- group progress;
- their side/partner;
- revealed Mystery rules for completed holes;
- live leaderboard(s), subject to event visibility settings.

This transparency is intentional.

### Write and verification permissions

Recommended V1 role model:

```text
Primary Scorer
- enter results for all active players
- submit the hole
- respond to score queries
- request/correct audited changes after submission

Designated Verifier
- view all results
- verify all players' results
- query any player/hole result
- complete final scorecard verification

Ordinary Player
- view all group results
- query their own hole result
- cannot edit another player's score
- cannot verify the whole card
```

A player may therefore protect their own result without creating multiple concurrent score editors.

### Own-score query

An ordinary player who sees an incorrect submitted score should be able to:

```text
[Query my score]
```

The query must identify:

- player;
- hole;
- currently recorded result;
- optional short reason/comment.

The query enters the same score-resolution flow used by verifier queries.

### Other-player discrepancies

Ordinary players should not have a formal authority to verify or modify another player's result.

If they notice an obvious mistake in another player's score, they can tell the scorer/verifier or use a lightweight `"Report issue"` action if later required.

Do not make four players independent verifiers of all four scores in V1.

### Role assignment

The group should have:

- one Primary Scorer;
- one Designated Verifier where possible.

These roles may be selected before play or confirmed at the start of the round.

Role changes during play should require an explicit handover/recovery action and be auditable.

This supports dead-phone/device-replacement scenarios without permitting silent role switching.

---

## 47. Sponsor Domain and Event/Hole Sponsorship

### Accepted

Sponsors are part of the event experience and should be modelled as first-class event content rather than hard-coded images/text in individual screens.

The MVP should support:

- event-level sponsors;
- hole-level sponsors;
- sponsor branding on the pre-event/countdown page;
- sponsor content in the hole-scoring experience;
- optional external sponsor link / `"More info"` action.

### Recommended domain shape

Conceptually:

```text
Sponsor
├── name
├── logo / image asset
├── short description
└── website / destination URL

Event Sponsorship
├── event
├── sponsor
├── placement / role
└── display content

Hole Sponsorship
├── round / course hole
├── sponsor
└── display content
```

Exact resource names remain for formal domain modelling.

Do not build a generic advertising platform or campaign engine for MVP.

### Pre-event sponsor placement

The countdown / event portal may show:

- primary event sponsor;
- supporting sponsors;
- sponsor logos;
- short sponsor message;
- optional link.

Sponsor content should complement, not obscure, critical golfer information.

### Hole sponsor placement

Each hole-scoring screen should have a dedicated sponsor area when configured.

Example:

```text
HOLE 7 — PAR 4

This hole is sponsored by XYZ

[logo]
Short sponsor message

[More info]

----------------
Score entry
----------------
```

The sponsor area must never interfere with score entry.

### Mobile usability rule

Sponsor content must not:

- push score controls excessively below the fold;
- autoplay video/audio;
- block scoring with interstitials;
- require dismissal before entering scores;
- create large network dependency on poor golf-course connectivity.

Prefer lightweight cached image/text content.

### Offline behavior

Sponsor content should be treated as non-critical presentation data.

If sponsor media cannot load because of poor connectivity:

- score entry must continue normally;
- cached sponsor content may be shown;
- a missing sponsor image must not block the hole workflow.

### Future extensibility

The domain should leave room for future placements such as:

- leaderboard sponsor;
- prize sponsor;
- halfway-house sponsor;
- event message sponsor;
- prizegiving sponsor.

Do not implement all of these in V1 unless needed.

### Analytics

Sponsor click/impression analytics are **deferred** unless explicitly required for the first event.

If later added, they should be lightweight derived/event data and must not sit in the critical scoring write path.

---

## 48. Access and Sponsor Security/Integrity Rules

### Accepted

Personal access links and QR codes are credentials and must be treated accordingly.

Requirements:

- use unguessable event-scoped tokens;
- do not expose sequential player IDs as authorization;
- support revoking/reissuing a compromised link;
- scope access to the relevant event/player/group capabilities;
- organiser accounts remain separately authenticated;
- never embed future hidden Mystery rules in pre-event or player-access payloads.

Sponsor URLs/content are organiser-controlled event data.

Do not allow sponsor HTML/JavaScript injection in MVP. Use structured content fields and safe URL validation/rendering.

## 49. Messaging and Notification Delivery Strategy

### Provisional — recommended for acceptance

Use a **multi-channel communication domain with a deliberately small V1 channel set**.

V1 should separate:

```text
Event Message
        ↓
Audience
        ↓
Trigger
        ↓
Delivery Policy
        ├── In-App
        ├── WhatsApp
        └── Email (primarily pre-event/fallback)
```

Do not build browser push, SMS, or a generic enterprise notification platform for MVP unless a concrete operational gap appears.

### Channel 1 — In-App Event Messages

In-app delivery is the primary channel while players are actively using the scoring experience.

Use it for contextual messages such as:

- halfway meal instructions;
- clubhouse/turn instructions;
- final-hole instructions;
- next-step/prizegiving instructions;
- revealed operational notices;
- scorer/verifier workflow messages.

Triggered in-app messages should be delivered at the relevant workflow boundary, for example immediately after a hole is submitted.

Example:

```text
Hole 9 submitted ✓

HALFWAY INFORMATION

Please collect your meal at the halfway house.
Your next hole is Hole 10.

[Continue]
```

### In-app persistence

A triggered message should not disappear merely because the player was not actively viewing the page at the exact trigger moment.

The system should retain the player's/group's message delivery state so the message can be shown on the next relevant interaction.

Important operational messages may require acknowledgement.

Do not require acknowledgement for every sponsor/promotional message.

### Channel 2 — WhatsApp

WhatsApp is the recommended external reach channel for:

- sending the personal event access link before the golf day;
- start-time / access reminders;
- major event-wide operational updates;
- weather/delay/tee-off changes;
- urgent organiser messages;
- prizegiving changes;
- selected important triggered messages where players may no longer have the app open.

Do **not** send every hole-triggered in-app message again over WhatsApp by default.

That would create noise, cost and message fatigue.

### WhatsApp Business Platform constraints

Business-initiated WhatsApp messages may require approved message templates and applicable pricing.

The event onboarding flow should clearly set the expectation/obtain the required consent for event-related WhatsApp communications.

Required templates should be prepared and approved before event day rather than created under time pressure.

V1 implementation should treat WhatsApp as a delivery adapter behind the communication domain rather than embed Meta-specific logic into scoring resources.

### Channel 3 — Email

Email is useful for:

- initial event invitation;
- personal scorecard/access link;
- event rules;
- sponsor/event information;
- fallback when a mobile number is unavailable.

Email should not be relied upon for time-sensitive on-course instructions.

### Browser Push

Browser push is deferred for V1.

Reasons include:

- permission friction;
- varying browser/platform behavior;
- on iPhone/iPad, Web Push is tied to installed Home Screen web-app behavior rather than ordinary Safari-tab usage;
- it adds service-worker/subscription lifecycle complexity that is unnecessary if in-app + WhatsApp already solve the event need.

The domain may leave room for a future push adapter without implementing it now.

### SMS

SMS is deferred.

It may later be useful as an emergency fallback for critical announcements, but V1 should not add a second paid realtime messaging integration without evidence that WhatsApp coverage is insufficient.

### Delivery policy per message

Messages should not all behave identically.

Recommended concrete V1 delivery policies:

```text
IN_APP_ONLY

IN_APP_AND_WHATSAPP

WHATSAPP_ONLY

EMAIL_PRE_EVENT

IN_APP_AND_EMAIL
```

Exact enum names are not final.

Examples:

```text
Halfway meal instruction
→ IN_APP_ONLY

Prizegiving time changed urgently
→ IN_APP_AND_WHATSAPP

Personal access link before event
→ WhatsApp + Email where available

Sponsor message
→ IN_APP_ONLY
```

### Audience targeting

V1 should support a small, explicit audience set:

```text
all_event_players
playing_group
side
specific_player
organisers
```

Do not build a generic audience query language.

### Trigger targeting

V1 should support the concrete triggers already identified:

```text
manual
scheduled_time
physical_hole_reached
physical_hole_completed
holes_completed
holes_remaining
round_completed
```

The trigger event should create a durable communication intent rather than relying on a browser being connected at that instant.

### Message lifecycle

Recommended conceptual lifecycle:

```text
draft
  ↓
scheduled / armed
  ↓
triggered
  ↓
delivery_pending
  ↓
delivered / partially_delivered / failed
```

For in-app player presentation, also track where useful:

```text
unseen
seen
acknowledged
```

Do not force the communication domain to pretend that external-delivery success means the player actually read the message.

### Critical scoring boundary

Messaging delivery must never block score persistence.

A WhatsApp outage, email failure, or sponsor-content failure must not fail the hole submission transaction.

External deliveries should occur asynchronously after the authoritative scoring event is committed.

### Recommended V1 implementation boundary

Implement:

- durable in-app messages;
- manual + progress/hole/round triggers;
- WhatsApp delivery adapter;
- email for pre-event/fallback communication;
- delivery/status tracking sufficient for organiser operations.

Defer:

- browser push;
- SMS;
- generic notification orchestration DSL;
- marketing automation;
- campaign analytics;
- sophisticated retry/routing engines.

## 50. Native Wrapper / Capacitor Strategy

### Provisional — recommended direction

Capacitor is a valid **future native delivery shell**, especially for:

- native push notifications;
- app icon / installed-app experience;
- deep links;
- future native device integrations;
- optional stronger offline support.

However, a Capacitor/native app must **not become a dependency for V1 scoring**.

### Critical architectural rule

The canonical product remains the web application.

Players must still be able to:

- open their personal secure link in a normal mobile browser;
- score the round;
- verify/query scores;
- view leaderboards;
- receive in-app messages;

without installing a native application.

The native shell is an optional enhancement.

### Why not simply wrap the remote Phoenix URL

Capacitor's production model expects bundled web assets. Its `server.url` option for loading an external URL is documented as intended for live-reload/development rather than production.

Therefore, do not plan the production architecture around:

```text
Capacitor WebView
    ↓
remote Phoenix LiveView URL via server.url
```

as the long-term production design.

A proper native shell may eventually require:

- a small bundled client shell;
- native push registration;
- deep-link handling;
- explicit integration with the Phoenix backend;
- careful treatment of LiveView/session/auth state.

That work should be estimated separately rather than assumed to be free simply because Capacitor exists.

### Push notifications

Capacitor's Push Notifications plugin can register native iOS/Android devices for push notifications.

Current implementation considerations include:

- iOS requires Push Notification capability and Apple Developer/APNs setup;
- Android uses Firebase Cloud Messaging;
- users must grant notification permission where required;
- delivery is still subject to OS/device/network behavior;
- push must not be required for the scoring app to function.

Push is therefore an **additional delivery adapter**, not the authoritative messaging system.

### Recommended V1 hierarchy

```text
Canonical scoring/access
→ Mobile web / Phoenix application

Primary in-round messaging
→ Durable in-app messages

External reach
→ WhatsApp

Pre-event/fallback
→ Email

Optional native enhancement
→ Capacitor push notifications
```

### Distribution friction

A native app adds event-day onboarding work:

- iOS App Store/TestFlight distribution;
- Android store/testing distribution;
- install step;
- notification permission;
- app updates;
- Apple/Google signing and release processes.

For an internal once-or-few-times-per-year event, this friction may cost more than it saves.

TestFlight can be used for beta distribution, but golfers would still need the TestFlight app and an invite/install flow. A public App Store app must also satisfy App Review requirements, including Apple's minimum-functionality rule that an app should provide value beyond a repackaged website.

### Recommended decision gate

Do not make Capacitor part of the critical MVP path unless one of these becomes true:

1. WhatsApp delivery is operationally unacceptable;
2. players will use the product repeatedly enough that installing the app is reasonable;
3. stronger native offline/device capability becomes necessary;
4. the native app provides enough distinct utility to justify distribution/review overhead.

Otherwise:

```text
V1
Web + WhatsApp + Email

V1.x / V2
Optional Capacitor native client
```

### Architecture preparation now

Even if Capacitor is deferred, the communication domain should support a future channel:

```text
PUSH
```

without changing Event Message, Audience, Trigger, or Delivery Policy semantics.

Likewise, player access tokens/deep links should be designed so a future native app can open the same player/event context.

### No duplicated business logic

A future Capacitor client must not reimplement:

- scoring rules;
- Mystery rules;
- handicap calculations;
- verification state machines;
- leaderboard calculations.

Those remain authoritative on the server/domain layer.

The native client should primarily provide:

- presentation;
- local/offline interaction;
- native push/device integration;
- synchronization with the same backend authority.

### Offline architecture alignment

The browser MVP and any future Capacitor client should follow the same sync contract:

- server remains authoritative;
- local writes are queued with idempotency keys;
- optimistic revisions protect against stale overwrites;
- conflicts are explicit and auditable;
- Mystery rules are never preloaded merely to enable offline reveal.
- Players may continue scoring subsequent holes while offline once the current hole is durably queued locally.
- Mystery reveals and authoritative leaderboard changes wait until queued hole submissions are accepted by the server.

## 51. Offline Scoring, Reconnection, and Conflict Safety

### Accepted

The MVP must tolerate **short and intermittent mobile connectivity loss** without losing a group's scores.

The goal is not to build a fully offline tournament platform capable of operating an entire event without the server.

The initial resilience target is:

```text
brief outage / weak signal
→ continue entering scores
→ persist locally
→ sync automatically when connectivity returns
```

### Canonical source of truth

The server remains authoritative.

```text
Browser/device
= temporary local working copy + pending queue

Postgres/server
= durable competition authority
```

Local data must never silently become authoritative merely because it was entered while offline.

### Local persistence

Use durable browser storage such as IndexedDB for:

- current scoring context;
- unsent hole submissions;
- locally acknowledged event state;
- cached non-critical event/course/sponsor content where useful.

Do not rely only on in-memory LiveView state or `localStorage` for pending competition scores.

### Atomic hole submission

A hole should sync as one logical command containing all resolved player results for that group/hole.

Conceptually:

```text
HoleSubmission
├── client_submission_id
├── round_id
├── group_id
├── hole_id
├── expected_revision
├── results[]
└── captured_at
```

The exact implementation resource/command name is not final.

The server validates and commits the complete hole submission atomically.

Avoid syncing four unrelated player-score writes that can leave a partially persisted hole.

### Idempotency

Every locally queued submission must carry a client-generated unique submission ID.

If the same submission is retried because of:

- reconnect;
- browser refresh;
- network timeout;
- uncertain response;

the server must process it **at most once**.

A retry of an already accepted `client_submission_id` should return the existing accepted result rather than create duplicate revisions.

### Optimistic concurrency

Hole/scorecard writes must use an explicit revision/version.

A queued submission includes the revision it was based on.

If server state changed while the device was offline:

```text
expected revision != current revision
→ do not silently overwrite
→ return conflict
```

The client then enters an attention/reconciliation flow.

### Player-visible sync states

The scoring UI must always make sync state understandable.

Recommended states:

```text
SAVED
- committed on server

PENDING SYNC
- safely stored on this device but not yet committed

SYNCING
- reconnect in progress

CONFLICT
- server changed; organiser/scorer review required
```

Do not show a generic green `"Saved"` for data that exists only locally.

### Offline progression

A group may continue to the next hole while offline only after all active players have a locally resolved result for the current hole and that complete hole submission has been durably queued.

Example:

```text
Hole 7 complete locally
→ PENDING SYNC
→ Hole 8 becomes available
```

The app should clearly indicate that one or more holes are still pending server confirmation.

### Mystery rules while offline

Future Mystery rules must remain server-side secret.

Therefore:

```text
offline hole submission
→ queue locally
→ player may continue
→ Mystery rule remains unrevealed

reconnect
→ server accepts queued hole
→ rule becomes reveal-eligible
→ reveal + leaderboard update
```

Do not preload encrypted/obfuscated/hidden future Mystery rules onto the player device merely to support offline reveal.

Secrecy is more important than immediate reveal during a temporary outage.

### Leaderboards while offline

While disconnected:

- show the last known leaderboard as stale/cached where useful;
- clearly label it as not current;
- do not fabricate leaderboard movement from uncommitted local scores.

After sync:

- recalculate affected Standard and Mystery projections server-side;
- broadcast updated standings.

### Verification while offline

The Primary Scorer may continue capturing holes offline.

Verifier actions should also be locally queueable where practical, but V1 may prioritize offline score capture over full offline verification.

A verifier must never be shown a result as server-final merely because it exists on another device's unsynced local queue.

### Role handover and stale devices

If scorer authority is handed to another device/person while the original scoring device is offline:

1. record a new scorer-role/assignment version server-side;
2. new scorer continues from current authoritative state;
3. when the old device reconnects, stale queued writes must not silently overwrite newer server data;
4. stale submissions enter conflict/review or are rejected with a clear reason.

This protects against the common case:

```text
Phone A loses signal / battery
→ scoring continues on Phone B
→ Phone A later reconnects
```

### Conflict policy

Do not attempt automatic merge when the same player/hole has changed on both server and offline device.

Preferred V1:

```text
no overlapping change
→ accept

same logical result already accepted
→ idempotent success

different result / stale revision
→ conflict
→ scorer/organiser review
```

The conflict UI should show:

```text
Hole 7 — Susan

Server: 5
Offline device: 6

[Keep server result]
[Request correction to 6]
```

Ordinary scorers should not bypass the audited correction flow merely because a conflict came from offline sync.

### Score submission ordering

Shotgun play order may be sequential for the group, but network delivery can be delayed.

The server should validate logical hole progression using the group's configured playing sequence and accepted/queued history, while allowing delayed sync of earlier legitimately completed holes.

Do not rely solely on arrival timestamp to determine playing order.

### Messaging while offline

In-app messages that require server triggers cannot be guaranteed during an outage.

On reconnect:

- pending triggered messages should become available;
- critical messages should retain delivery state;
- obsolete messages may be suppressed if their relevance window has passed, according to message policy.

WhatsApp/email remain independent external channels but should not be assumed to work when the golfer has no data connection.

### Sponsor/content caching

Static event rules, course data, and lightweight sponsor content may be cached locally for resilience.

Failure to refresh sponsor content must never block scoring or sync.

### STOP condition for V1 offline scope

Do **not** expand V1 into full all-day disconnected operation unless testing at the actual course shows that normal mobile connectivity is insufficient.

The MVP requirement is resilient intermittent connectivity, not serverless tournament operation.

## 52. Pre-Round Setup, Late Changes, and Configuration Locking

### Accepted

Organisers must be able to make practical event-day adjustments freely **before competitive scoring opens**.

This includes common situations such as:

- player does not arrive;
- replacement player arrives;
- player needs to move to another playing group;
- team/side pairing changes before play;
- starting hole changes;
- tee assignment changes;
- Handicap Index correction;
- scorer/verifier assignment changes;
- incorrect player details are fixed.

### Pre-round lifecycle

Preferred conceptual lifecycle:

```text
draft
  ↓
ready
  ↓
scoring_open
  ↓
scoring_closed
  ↓
finalized
```

The exact resource/state-machine implementation remains for formal domain modelling.

### `draft`

Configuration is still actively being built.

Examples:

- import players;
- create groups;
- assign sides;
- assign tees;
- assign starting holes;
- configure Mystery holes;
- configure sponsors/messages;
- set scoring rules.

### `ready`

The round has passed setup validation and is operationally ready to start, but organisers may still make permitted pre-start changes.

`ready` is not immutable.

This allows real-world event-morning adjustments without forcing an artificial reopen/unlock cycle.

### `scoring_open`

Competitive play has begun.

At this transition, competition-affecting configuration becomes locked.

At minimum lock:

- course / hole configuration used for the round;
- tee rating profiles used for scoring;
- competition format;
- handicap allowance;
- Mystery-hole schedule;
- hidden Mystery aggregation rules;
- tie-break policy;
- side/team membership;
- primary leaderboard definition;
- solo-normalization policy.

### Pre-open editable assignments

Until `scoring_open`, organisers may change:

- playing-group membership;
- side/team partnership;
- starting hole;
- tee assignment;
- player participation;
- primary scorer;
- designated verifier;
- Handicap Index / deemed handicap input;
- player contact/access information.

Changes should be reflected in the player's event portal immediately.

### No-show handling

A player who does not arrive should not simply be deleted.

Recommended pre-start outcomes include:

```text
withdrawn_before_start
replaced_before_start
```

The exact participation states remain for formal lifecycle design.

Historical event setup should retain enough information to explain who was originally expected and who actually started where useful.

### Replacement player

Before scoring opens, an organiser may replace a non-starting player.

The replacement receives:

- their own Round Entry;
- their own handicap snapshot;
- assigned tee;
- group membership;
- side membership;
- personal event access link.

Do not mutate the original player's identity into the replacement player.

### Rebalancing groups

Before scoring opens, organisers may move players between groups to handle no-shows or operational needs.

All related assignments must be revalidated:

- group size remains 2–4;
- side/team composition is valid;
- solo-side rules remain explicit;
- scorer/verifier coverage remains valid;
- starting-hole capacity/assignment remains valid.

### Locking after scoring opens

Once `scoring_open`:

Ordinary edits to these are prohibited:

```text
team/side membership
Mystery schedule/rules
competition format
tie-break policy
handicap allowance
course/hole definition
```

Operational changes must use explicit actions instead of generic edit forms.

Examples:

```text
withdraw player
disqualify player
handover scorer role
handover verifier role
reissue access
correct handicap with organiser authority
correct erroneous tee assignment under strict guard
```

### Tee / starting-hole correction after open

A genuine setup error discovered after scoring opens requires special handling.

Preferred guard:

```text
if player has no accepted Hole Result yet:
    organiser may correct tee / starting assignment with audit
else:
    block ordinary correction
    require organiser review / exceptional reopen flow
```

The system should not silently recalculate a partially played round under a different tee/rating context.

### Team/side changes after open

No competitive partner swapping is permitted once scoring opens.

If a partnership was genuinely captured incorrectly and discovered only after scoring begins, the organiser must use an exceptional audited correction path.

The system should make this difficult and visible rather than offering a normal `"Edit Team"` action.

### Scorer/verifier role changes after open

These remain operationally changeable through explicit handover actions because device failure or player availability may require it.

Role changes must not alter side membership or competition eligibility automatically.

### Opening gate

Before allowing `ready → scoring_open`, validate at minimum:

- every active Round Entry has a valid player;
- every active player has a valid tee/rating assignment;
- handicap policy has resolved to a usable Playing Handicap;
- every playing group has 2–4 players;
- side/team structure is valid;
- starting holes are assigned;
- scoring rules are complete;
- Mystery configuration is complete and locked;
- tie-break policy exists;
- no duplicate player participation exists within the round.

Warnings may be allowed for non-critical items such as:

- missing phone/email;
- missing sponsor image;
- unavailable secondary communication channel.

### STOP condition

Do not allow scoring to open if a competition-critical setup invariant is invalid.

Operational inconvenience should generate warnings; competitive ambiguity should block opening.

## 53. Admin Backend, Registration, and Event-Day Check-In

### Accepted

The MVP requires an authenticated **organiser/admin backend** and a dedicated **event-day registration/check-in workflow**.

This is not optional operational tooling; it is part of the core product.

### Admin backend responsibilities

The organiser/admin area should provide, at minimum:

```text
Event setup
Player/import management
Course / tee configuration
Round configuration
Group/fourball management
Side/team assignment
Starting-hole assignment
Scorer/verifier assignment
Check-in / registration
Access-link/QR recovery
Handicap confirmation/correction
Sponsor configuration
Message/notification management
Live scoring oversight
Verification/query resolution
Leaderboard monitoring
Finalization / prizegiving readiness
Audit/revision history
```

The first implementation should remain operationally focused and avoid unnecessary enterprise administration features.

### Check-in lifecycle

A player's Round Entry should expose an event-day participation/check-in lifecycle distinct from competitive scoring state.

Conceptually:

```text
expected
   ↓
checked_in
   ↓
started
   ↓
completed / withdrawn / disqualified
```

Pre-start terminal/exception states may include:

```text
withdrawn_before_start
replaced_before_start
no_show
```

Exact final state names/transitions remain for formal domain modelling.

### `expected`

Player is on the event roster but has not yet been confirmed as present on the day.

### `checked_in`

An organiser has confirmed the player is present/registered.

Check-in may also include confirmation of:

- name/identity;
- Handicap Index or no-HI policy;
- tee assignment;
- group;
- side/team partner;
- starting hole;
- personal access link;
- scoring role where applicable.

### `started`

Competitive play has begun for that Round Entry.

The system should not infer `started` merely from check-in.

A player may check in well before scoring opens.

### Check-in methods

V1 may support:

- organiser search + manual check-in;
- scan/open player's QR/access record;
- group/fourball check-in view;
- optional self-confirmation from personal event link.

Admin confirmation remains authoritative for roster/readiness status.

### Group readiness

The admin backend should derive a readiness status for each playing group.

Example:

```text
Group 12
4 / 4 players checked in
Primary scorer assigned
Verifier assigned
Starting hole: 14
Tee assignments valid
Status: READY
```

or:

```text
Group 18
3 / 4 players checked in
Missing: Peter Smith
Status: ACTION REQUIRED
```

This should immediately support morning reshuffling.

### Round readiness dashboard

Before scoring opens, organisers should see a concise event overview such as:

```text
144 expected

136 checked in
4 withdrawn before start
2 replacements pending
2 not arrived

36 groups
31 ready
5 action required
```

The dashboard should expose blockers rather than forcing organisers to inspect each player individually.

### No-show handling

At the relevant event cutoff, an organiser may mark:

```text
no_show
```

or:

```text
withdrawn_before_start
```

depending on event semantics.

The player should not be deleted from event history.

If replaced, create a new Round Entry for the replacement player and preserve the original record.

### Registration corrections

Before scoring opens, the check-in workflow may correct:

- player identity/details;
- Handicap Index;
- no-HI/deemed-handicap status;
- tee assignment;
- group;
- side/team partner;
- starting hole;
- scorer/verifier role;
- contact/access details.

All competition-critical corrections remain subject to the pre-round setup rules already defined.

### Access support at registration

Organisers must be able to:

```text
Show player QR
Copy personal link
Resend WhatsApp/email
Reissue compromised/lost access token
Open group/fourball access support
```

This should be designed for fast use at a registration desk.

### Check-in and scoring-open guard

Recommended opening policy:

The Round should warn/block scoring open if unresolved registration issues create competition ambiguity.

Examples of blockers:

- invalid group size;
- active player has no valid tee;
- active player has no usable handicap resolution;
- side/team structure invalid;
- starting hole missing;
- duplicate Round Entry.

Examples of warnings:

- player not checked in but organiser intentionally allows late arrival;
- missing email/phone;
- secondary sponsor content missing.

The organiser may explicitly override selected operational warnings, but not hard competition invariants.

### Admin permissions

V1 does not require enterprise RBAC.

Minimum authenticated admin roles may simply be:

```text
organiser
admin
```

or even one organiser role initially, provided the domain/policy boundary leaves room for more granular roles later.

Do not expose admin mutation routes publicly.

### Operational UX principle

The admin backend should prioritize:

```text
What is wrong?
Who needs attention?
What can I fix now?
Is the round ready to start?
```

over generic CRUD screens.

The admin backend is an event-operations console, not just a database editor.

## 54. Admin Roles and Operational Permissions

### Accepted direction

The MVP requires multiple authenticated staff users working concurrently with **role-based operational limits**.

Do not implement enterprise RBAC, arbitrary permission builders, or tenant-level policy administration.

Use a small set of explicit roles with clear boundaries.

### Recommended V1 roles

```text
EVENT_ADMIN
COMPETITION_MANAGER
REGISTRATION_STAFF
SCORING_SUPPORT
```

The exact code names may change during implementation, but the permission boundaries should remain.

---

### `EVENT_ADMIN`

Highest operational authority for the event.

May:

- create/edit the event before lock;
- configure rounds, course, tees and scoring rules;
- configure Mystery holes/rules;
- configure tie-break policy;
- configure sponsors;
- manage staff roles;
- import/manage players;
- manage groups, sides and starting holes;
- manage scorer/verifier assignments;
- manage check-in;
- correct handicap/tee details;
- send event-wide communications;
- resolve score queries;
- reopen finalized results;
- finalize sides/groups;
- finalize the Round;
- perform audited exceptional overrides.

Should be limited to a small number of trusted organisers.

---

### `COMPETITION_MANAGER`

Runs competitive operations without full system administration.

May:

- manage player/group/side assignments before scoring opens;
- manage check-in and no-shows;
- correct tee/handicap assignments under allowed guards;
- hand over scorer/verifier roles;
- monitor live scoring;
- resolve score queries;
- correct scores through audited workflows;
- mark withdrawals/disqualifications where authorised;
- finalize ready sides/groups;
- monitor prizegiving readiness;
- send approved operational event messages.

May **not** normally:

- change competition format after configuration lock;
- alter Mystery rules after scoring opens;
- alter tie-break policy after scoring opens;
- manage administrator accounts/roles;
- perform unrestricted system-level configuration.

---

### `REGISTRATION_STAFF`

Focused on the registration desk.

May:

- search players;
- check players in;
- confirm/update basic contact details;
- resend/show/reissue access links or QR codes;
- mark no-show / withdrawn-before-start subject to event policy;
- flag a replacement request;
- view group/start/tee assignments;
- view handicap status;
- make explicitly permitted pre-start corrections if delegated.

Should **not**:

- change competition rules;
- edit Mystery configuration;
- modify finalized scores;
- resolve score disputes;
- finalize competition results;
- send event-wide broadcasts;
- reopen finalized results.

---

### `SCORING_SUPPORT`

Focused on on-course/player support.

May:

- view live group progress;
- view score sync state;
- help with access/device replacement;
- hand over Primary Scorer / Verifier roles under allowed workflow;
- view missing/pending/queried scores;
- assist a scorer with navigation;
- escalate a score dispute to Competition Manager;
- view connectivity/sync problems.

Should **not**:

- directly alter competition rules;
- change side/team membership after lock;
- silently edit scores;
- resolve disputes without authority;
- finalize competition results;
- send event-wide messages.

---

## Permission principles

### 1. Permissions follow actions, not screens

Do not create a single `"Admin"` page where every authenticated staff user can mutate everything.

Policies should be enforced at the domain/action boundary.

Examples:

```text
check_in_player
assign_round_tee
change_side_membership
submit_score_correction
resolve_score_query
finalize_side
reopen_finalized_side
send_event_broadcast
```

Each action must explicitly authorize the acting staff role.

### 2. Lifecycle guards still apply

A powerful role does not bypass normal state rules automatically.

Example:

```text
Registration Staff
may change group before scoring_open
may not change group after scoring_open
```

`EVENT_ADMIN` may have an exceptional override action, but that is distinct from normal edit permission and must be audited.

### 3. Least privilege

Staff should receive the smallest role required for their job.

A volunteer helping at registration should not be able to:

- alter Mystery rules;
- change leaderboard results;
- finalize the event.

### 4. Concurrent staff safety

Multiple organisers may work at the same time.

Admin actions that mutate competitive data must use the same optimistic concurrency / revision protections as player scoring where relevant.

The UI should surface stale updates instead of silently overwriting another organiser's change.

### 5. Audit high-impact actions

At minimum audit:

- role changes;
- handicap overrides;
- tee changes after readiness;
- side/group corrections after readiness;
- score corrections;
- score-query resolutions;
- withdrawals/disqualifications;
- verifier overrides;
- result reopen;
- result finalization;
- round finalization;
- event-wide message sends;
- locked-configuration override.

Routine read access and ordinary check-in do not require a heavy audit trail.

### 6. Staff authentication

Staff/admin users require normal authenticated accounts.

Player event links are **not** valid admin credentials.

Do not reuse player event tokens for staff access.

---

## Recommended role matrix

| Action | Event Admin | Competition Manager | Registration Staff | Scoring Support |
|---|---:|---:|---:|---:|
| Check in player | ✓ | ✓ | ✓ | View |
| Reissue player access | ✓ | ✓ | ✓ | ✓ |
| Edit contact details | ✓ | ✓ | ✓ | Limited |
| Move player before scoring opens | ✓ | ✓ | Limited | — |
| Change tee/handicap before scoring opens | ✓ | ✓ | Limited | — |
| Change team/side before scoring opens | ✓ | ✓ | — | — |
| Configure Mystery rules | ✓ | Before lock | — | — |
| Change locked competition configuration | Exceptional only | — | — | — |
| Resolve score query | ✓ | ✓ | — | Escalate |
| Correct submitted score | ✓ | ✓ | — | — |
| Handover scorer/verifier | ✓ | ✓ | — | ✓ |
| Finalize side/group | ✓ | ✓ | — | — |
| Reopen finalized result | ✓ | Limited/explicit | — | — |
| Finalize round | ✓ | ✓ if delegated | — | — |
| Send event-wide operational message | ✓ | ✓ | — | — |
| Manage staff roles | ✓ | — | — | — |

Exact permissions should be encoded as policies/actions during formal domain modelling, not inferred from this table alone.

---

## Role architecture boundary

The role system should be designed so future roles can be added without rewriting domain actions, for example:

```text
Content/Sponsor Manager
Course Marshal
Rules Official
Read-Only Observer
```

Do not implement those roles until a real use case requires them.

The stable architectural boundary is:

```text
Authenticated Staff User
        ↓
Event Staff Assignment
        ↓
Role
        ↓
Action Policy
```

This provides future breathing room without enterprise permission machinery.

## 55. Side Competitions / Hole Challenges

### Accepted

The product must model **Side Competitions** as a first-class competition concept separate from:

- the main Mystery leaderboard;
- the Standard Better-Ball leaderboard;
- ordinary hole sponsorship;
- player Hole Results.

Side competitions may be attached to one or more specific holes and may have their own winner, eligibility, verification, sponsor, and prize.

### Initial V1 side competition types

Implement support for:

```text
CLOSEST_TO_PIN
LONGEST_DRIVE
```

These are required for the first practical version.

### Future side competition types

The domain must leave room for additional concrete types such as:

```text
LONGEST_PUTT
HOLE_IN_ONE
JACKPOT_HOLE
SPONSOR_CHALLENGE
```

Do not implement all of these in V1 unless the event requires them.

Do not build a generic formula/rules DSL merely to support future side competitions.

### Domain separation

Preferred conceptual model:

```text
Event / Round
└── Side Competition
    ├── competition type
    ├── target hole(s)
    ├── eligibility
    ├── division/category
    ├── sponsor (optional)
    ├── prize / description (optional)
    ├── status
    └── entries / attempts
```

Each entry/attempt is separate from the player's normal golf score.

Example:

```text
Side Competition: Closest to the Pin
Hole: 7
Sponsor: XYZ Motors

Entry:
Player: Susan
Distance: 1.82 m
Verified by: Peter
```

### Side competition lifecycle

Recommended conceptual lifecycle:

```text
draft
  ↓
armed
  ↓
open
  ↓
closed
  ↓
finalized
```

#### `draft`

Configuration incomplete or still editable.

#### `armed`

Competition is valid and ready for the round.

#### `open`

Attempts may be recorded.

#### `closed`

No new attempts are accepted, but organiser review/finalization may remain.

#### `finalized`

Winner/result is official.

Exact transition implementation remains for formal domain modelling.

### Configuration locking

Once the Round opens for scoring, competition-critical side-competition configuration should lock:

- competition type;
- target hole;
- eligibility;
- division/category structure;
- comparison rule;
- sponsor/prize association where it affects published terms.

Operational corrections remain auditable.

### Closest to the Pin

V1 semantics:

- normally attached to a Par 3 hole, but do not hard-code Par 3 as a universal requirement;
- measurement is a distance from the hole/cup;
- lower valid distance wins;
- only a valid qualifying attempt is eligible;
- measurement units must be explicit.

Preferred canonical storage:

```text
distance_mm
```

or another single normalized metric, with the UI able to display metres/centimetres.

Do not store free-text values such as `"1.8m"` as the authoritative measurement.

### Longest Drive

V1 semantics:

- attached to a configured hole;
- higher valid measured distance wins;
- the event may define qualifying conditions such as the ball needing to finish on the fairway;
- qualifying conditions must be explicit event rules, not inferred from golfer expectations.

Preferred canonical storage uses one normalized distance unit.

### Divisions / categories

A side competition may have one overall winner or multiple divisions.

Examples:

```text
Overall
Men
Women
Senior
Junior
```

Do not hard-code gender/age categories into the side-competition engine.

Instead, the event configures competition divisions and eligibility.

This allows future sponsor-specific categories without changing the core resource.

### Player eligibility

Eligibility should derive from the player's Round Entry / configured competition division, not from arbitrary client-side input.

Examples:

```text
all active players
women only
juniors only
specific tee/rating category
specific event division
```

V1 should use explicit configured eligibility rules rather than a generic expression language.

### Entry capture

Side-competition entries may be recorded by:

- the Primary Scorer;
- Designated Verifier;
- authorised event staff;
- potentially the player themselves for provisional capture.

A winning or leading attempt should not rely solely on self-attestation.

### Verification

Recommended V1:

```text
recorded
  ↓
verified
  ↓
eligible for final result
```

A verifier/marker or authorised staff member should confirm the measurement/qualifying attempt.

An unverified attempt may appear as provisional but should not become the official winner.

### Live leader / leaderboard

The application may show:

```text
Closest to Pin — Hole 7
Current leader: Susan — 1.82 m
```

or:

```text
Longest Drive — Hole 12
Current leader: John — 287 m
```

Visibility is configurable.

For suspense or sponsor activations, an event may choose:

```text
live
organiser_only
reveal_after_round
```

### Interaction with normal hole scoring

Side-competition capture must not block the player's normal hole score submission.

If a group forgets to capture a side-competition measurement, normal scoring continues.

The side competition is an optional parallel workflow.

### Operational UX

When a player reaches a hole with an active side competition, the hole screen may display:

```text
HOLE 7 — CLOSEST TO THE PIN

Sponsored by XYZ Motors

Current leader:
Susan — 1.82 m

[Record attempt]
```

The side-competition UI must remain subordinate to normal score entry.

### Sponsorship

A Side Competition may have its own sponsor independent of the hole's general sponsor.

Example:

```text
Hole 7 Sponsor
ABC Bank

Closest to Pin Sponsor
XYZ Motors
```

The domain must therefore permit sponsorship to attach directly to the Side Competition.

### Prize support

V1 may store lightweight prize information:

- title;
- description;
- sponsor;
- display text.

Do not build a full prize/inventory/redemption system for MVP.

### Hole-in-One / Jackpot future support

Future types such as Hole-in-One or Jackpot challenges may require different result semantics:

- boolean achievement;
- multiple winners;
- qualifying tee/division;
- prize limits;
- organiser verification;
- sponsor terms.

The `Side Competition` boundary should support new concrete calculation/validation policies later without changing the main scoring domain.

### Architecture principle

Side competitions should follow:

```text
stable SideCompetition resource
        +
type-specific policy/validation
```

rather than:

```text
one giant generic challenge formula engine
```

V1 concrete policies:

```text
ClosestToPin
LongestDrive
```

Future policies are added only when required.

## 56. Physical Side-Competition Boards as V1 Source of Truth

### Accepted

For V1, Closest to the Pin and Longest Drive are expected to use **physical on-course boards/markers** as the primary measurement and competition record during play.

Players do not need to measure distances or enter side-competition attempts into the app.

### V1 app responsibility

On a hole with a Side Competition, the player-facing app should primarily:

- show that the challenge exists;
- explain the challenge briefly;
- show the sponsor/prize;
- optionally remind players where/how to record the physical result;
- continue normal score entry without extra required fields.

Example:

```text
HOLE 7 — CLOSEST TO THE PIN

Sponsored by XYZ Motors

Use the marker board on the green to record the closest shot.

Prize:
Weekend vehicle experience
```

### Authoritative result capture

The physical board/marker is the event-day source of truth for the side competition.

At or after the round, an authorised staff member may enter the final result into the admin system:

```text
Side Competition
├── winner
├── final measurement (optional)
├── verified_by
└── finalized_at
```

The exact measurement may be omitted if the event only needs the winner's name.

### Admin workflow

Recommended V1:

```text
open
  ↓
physical board used during play
  ↓
staff reads board
  ↓
record winner / final result
  ↓
verify
  ↓
finalize
```

The admin backend should allow organisers to record:

- winner;
- optional runner-up(s);
- optional measurement;
- notes;
- sponsor/prize;
- verification status.

### Player-side capture deferred

Do not build:

- player measurement entry;
- live side-competition leaderboards;
- measurement conflict resolution;
- per-attempt verification;
- GPS/rangefinder integration;

for V1 unless a concrete event requirement appears.

These remain future extensions behind the existing Side Competition boundary.

### Sponsor placement remains

Even though measurement capture is physical, the app should still show:

- challenge name;
- sponsor;
- prize/message;
- instructions.

This keeps the digital experience commercially useful without increasing scoring friction.

## 57. Formal Domain Model v0.1

### Status

**Working formal model.**  
This section translates the accepted product decisions into explicit domain boundaries, resources, relationships, invariants, policies, and lifecycles.

It is intentionally:

- enterprise-compatible in structure;
- MVP-sized in implementation;
- free of generic formula/workflow/plugin engines;
- independent of the legacy V0 schema.

No implementation tickets should be derived until this model has been pressure-tested and accepted.

---

## 57.1 Domain Map

```text
Accounts & Access
├── StaffUser
├── EventStaffAssignment
└── PlayerAccessGrant

Golf Catalog
├── Course
├── CourseHole
├── TeeSet
└── TeeRatingProfile

Competition
├── Event
├── Round
├── RoundHole
├── RoundTeeProfileSnapshot
├── RoundTeeHoleSnapshot
├── Player
├── RoundEntry
├── CompetitionCategory
├── RoundEntryCategoryMembership
├── PlayingGroup
├── CompetitionSide
├── CompetitionSideMembership
├── CompetitionSideResult
├── GroupRoleAssignment
├── RoundCompetition
├── ScoringTrack
├── MysteryHoleRule
└── MysteryReveal

Scoring
├── HandicapSnapshot
├── CompetitionHandicap
├── Scorecard
├── HoleResult
├── HoleSubmission
├── ScoreVerification
├── ScoreQuery
└── ScoreRevision

Communications
├── EventMessage
├── MessageDispatch
└── MessageDelivery

Sponsorship
├── Sponsor
└── SponsorPlacement

Side Competitions
├── SideCompetition
└── SideCompetitionResult

Operations / Audit
└── AuditEvent
```

### Domain boundary principle

Resources belong where their **business meaning** lives, not where a screen happens to edit them.

Examples:

- `RoundEntry` belongs to Competition even though registration staff edit it.
- `HoleResult` belongs to Scoring even though it appears on a player's scorecard.
- `SponsorPlacement` belongs to Sponsorship even though it renders on a scoring hole.
- `MessageDelivery` belongs to Communications even when triggered by a scoring event.

---

# 57.2 Accounts & Access Domain

## `StaffUser`

Represents an authenticated organiser/staff identity.

### Owns

- login/authentication identity;
- staff profile;
- account status.

### Does not own

- event permissions directly;
- player scoring identity;
- competition participation.

Event-specific authority is granted through `EventStaffAssignment`.

### Lifecycle

```text
active
  ↓
suspended
  ↓
active

active/suspended
  ↓
disabled
```

`disabled` is terminal for normal authentication.

### Guards

- only authorised Event Admin/system administration may disable staff;
- disabling a staff account must invalidate active sessions/tokens as appropriate.

---

## `EventStaffAssignment`

Associates a `StaffUser` with an `Event` and one explicit operational role.

### Roles

```text
event_admin
competition_manager
registration_staff
scoring_support
```

A user may have multiple assignments if future needs require it, but V1 should prefer one effective event role unless a real case requires combined roles.

### Lifecycle

```text
active
  ↓
revoked
```

A replacement assignment is created rather than rewriting historical audit records.

### Invariants

- assignment belongs to exactly one Event;
- only active assignments grant event authority;
- player access links never grant staff authority.

---

## `PlayerAccessGrant`

Represents a secure, event-scoped player credential used by personal links/QR codes.

### Scope

Grant is tied primarily to:

- Event;
- Player;
- allowed player-facing capabilities.

The stable personal event link should remain usable across multiple Rounds in the same Event. Effective round/scoring capabilities are resolved through that Player's current `RoundEntry` records rather than binding the credential itself to one RoundEntry.

### Lifecycle

```text
issued
  ↓
active
  ├── revoked
  ├── superseded
  └── expired
```

Terminal states:

- `revoked`
- `superseded`
- `expired`

### Invariants

- token material must be unguessable;
- sequential IDs are never authorization;
- reissuing access supersedes/revokes the previous active grant as policy requires;
- access grant never exposes admin capabilities;
- scoring capabilities remain subject to Round lifecycle and role assignment.

---

# 57.3 Golf Catalog Domain

## `Course`

Canonical reusable golf course identity.

### Attributes / concepts

- name;
- location;
- active/archived status;
- stable relationship to physical holes.

### Lifecycle

No competition lifecycle.

Operational state:

```text
active ↔ archived
```

Archiving prevents new use but does not alter historical rounds.

---

## `CourseHole`

Represents a physical hole on a Course.

### Invariants

- physical hole identity is stable within the Course;
- a course may contain more than 18 physical holes in future;
- the reusable catalog must not make `1..18` a universal database invariant.

The MVP Round configuration validates an 18-hole playing layout, while `RoundHole` determines which holes and order are actually used.

Do not store round-specific scoring results here.

---

## `TeeSet`

Represents a physical set of tee markers.

Examples:

- Blue;
- White;
- Red;
- Forward.

### Important

`TeeSet` is not equivalent to:

- gender;
- age category;
- competition division;
- rating profile.

---

## `TeeRatingProfile`

Represents the handicap/scoring rating context associated with a physical `TeeSet`.

Expected data:

- Course Rating;
- Slope Rating;
- applicable total par;
- per-hole par;
- per-hole Stroke Index;
- per-hole distance where relevant;
- rating/classification label where required.

### Invariants

- a profile belongs to one Course/TeeSet;
- profile may not be mutated in a way that changes historical round calculations;
- historical rounds use snapshots, not live catalog values.

### Reason for separation

The same physical tee set may require different rating data for different recognized rating contexts.

Do not encode:

```text
male => tee
female => tee
```

as domain logic.

---

# 57.4 Competition Domain

## `Event`

Represents the overall golf-day event.

An Event may contain one or more Rounds in the future.

### Lifecycle

```text
draft
  ↓
published
  ↓
live
  ↓
completed
  ↓
archived
```

Alternative terminal branch:

```text
draft/published
  ↓
cancelled
```

### State meaning

#### `draft`

Internal setup only.

#### `published`

Player portal/invitations may be live; scoring not yet active.

#### `live`

At least one Round is operational/live.

#### `completed`

All required Rounds are finalized and event results are complete.

#### `archived`

Historical read-only event.

#### `cancelled`

Event will not proceed.

### Guards

`published` requires at least:

- basic event identity;
- date/course/round setup sufficient for player communication.

`completed` requires:

- all non-cancelled Rounds finalized.

### Side effects

- `published`: player event portal may become externally accessible;
- `completed`: event results can be treated as final;
- `archived`: normal mutation disabled.

---

## `Round`

Represents one competitive playing round.

MVP:

```text
Event
└── Round 1
```

Future:

```text
Event
├── Round 1
├── Round 2
└── Round 3
```

### Lifecycle

```text
draft
  ↓
ready
  ↓
scoring_open
  ↓
scoring_closed
  ↓
finalized
```

Branches:

```text
draft/ready
  ↓
cancelled
```

Exceptional reopen:

```text
finalized
  ↓ organiser reopen
scoring_closed / review state
  ↓
finalized
```

### `draft`

Competition configuration incomplete.

### `ready`

Opening-gate validation passes, but pre-start operational edits remain allowed.

### `scoring_open`

Competitive scoring is open.

This transition locks competition-affecting configuration.

### `scoring_closed`

New ordinary scoring submissions are closed; review/correction/finalization may continue.

### `finalized`

Official round result state.

Guard: all required `CompetitionSideResult` records are terminal (`finalized` or explicitly `excluded`), no blocking score/query/eligibility review remains, and all official ScoringTrack projections are reproducible from current source data.

### Guards for `ready → scoring_open`

At minimum:

- valid course snapshot;
- valid active Round Entries;
- every active Round Entry has a tee/rating snapshot;
- every active Round Entry has a usable Handicap Snapshot;
- every Playing Group contains 2–4 active players;
- side structure is valid;
- starting holes configured;
- scoring competition configured;
- Mystery rules complete/locked;
- tie-break policy configured;
- no duplicate player Round Entry;
- no critical setup ambiguity.

### Side effects of `scoring_open`

Lock:

- competition format;
- handicap allowance;
- Mystery rule schedule;
- tie-break policy;
- side membership;
- primary scoring track;
- solo normalization policy;
- round course/rating snapshots.

---

## `RoundHole`

Represents the round's stable physical hole sequence.

### Purpose

Provides a round-local hole identity independent of later Course edits.

Expected:

```text
round_id
course_hole_id
play_order
display_hole_number / label
```

For the MVP, the Round must contain exactly 18 playable `RoundHole` records.

`play_order` is the authoritative round sequence; `display_hole_number` is what golfers see. This leaves room for 9-hole, 27-hole, composite-nine, or alternate-routing events later without changing the meaning of `CourseHole`.

Starting-hole assignments reference `RoundHole`, not an unvalidated integer.

Scoring references `RoundHole`, not live `CourseHole` data alone.

---

## `RoundTeeProfileSnapshot`

Immutable round snapshot of one Tee Rating Profile.

### Stores / snapshots

- source TeeSet/Profile identity;
- Course Rating;
- Slope Rating;
- total/applicable par;
- source/version metadata.

### Relationship

```text
Round
└── RoundTeeProfileSnapshot
    └── RoundTeeHoleSnapshot × holes
```

Multiple players may reference the same snapshot.

### Invariant

Once `Round.scoring_open`, snapshot data is immutable except through exceptional audited round-repair workflow.

---

## `RoundTeeHoleSnapshot`

Per-hole scoring/rating snapshot for a `RoundTeeProfileSnapshot`.

Expected:

- RoundHole;
- par;
- Stroke Index;
- distance where relevant.

### Purpose

Mixed-tee players may share a physical RoundHole while using different per-hole rating/scoring values.

---

## `Player`

Canonical reusable golfer identity.

### Owns

- name;
- contact information;
- optional convenience/latest-known handicap information;
- non-authoritative profile data.

### Does not own

- event participation;
- round tee;
- competition side;
- event handicap truth;
- check-in state.

Those belong to `RoundEntry`.

### Lifecycle

No competition lifecycle.

May be:

```text
active ↔ inactive/archived
```

Historical Round Entries remain intact.

---

## `CompetitionCategory`

Optional event/round category used for:

- tee policy;
- prizes;
- side-competition eligibility;
- reporting;
- event-specific classification.

Examples may include:

- Open Men;
- Open Women;
- Senior;
- Junior.

### Important

Categories are event configuration, not universal demographic/scoring logic.

A player may legitimately belong to more than one category (for example, Senior + Women), so the model must not force one mutually exclusive `division_id` onto `RoundEntry`.


---

## `RoundEntryCategoryMembership`

Associates one `RoundEntry` with one `CompetitionCategory`.

### Invariants

- unique per `(round_entry_id, competition_category_id)`;
- category membership is event/round-scoped;
- categories do not directly determine a tee unless the Event has an explicit tee-assignment policy.

For the MVP this can remain a very small join resource. It exists to avoid a future rewrite caused by assuming categories are mutually exclusive.

---

## `RoundEntry`

Central resource representing **one Player participating in one Round**.

This is intentionally separate from `Player`.

### Owns round-specific facts

- Player;
- Round;
- Playing Group;
- Competition Category memberships where applicable;
- tee assignment;
- handicap snapshot;
- check-in/registration status;
- participation status.

Competition-side membership is intentionally **not** a direct field on RoundEntry; it is modelled by `CompetitionSideMembership` so future concurrent competitions may group the same golfer differently.

### Unique invariant

```text
one active RoundEntry per Player per Round
```

unless a future explicit re-entry model is added.

### Registration lifecycle

This is separate from competitive participation and must not duplicate `"started"`.

```text
expected
  ├── checked_in
  ├── withdrawn_before_start
  ├── no_show
  └── replaced_before_start
```

`checked_in` means registration/arrival is complete. Whether play has started belongs only to the competitive participation lifecycle below.

`replaced_before_start`, `withdrawn_before_start`, and `no_show` are terminal for that RoundEntry's start eligibility.

A replacement player receives a **new RoundEntry**; the original entry remains historical.

### Competitive participation lifecycle

```text
not_started
  ↓
active
  ├── completed
  ├── withdrawn
  └── disqualified
```

Terminal:

- `completed`
- `withdrawn`
- `disqualified`

### Guards

`not_started → active` requires:

- Round scoring open;
- entry eligible;
- valid tee snapshot;
- valid Handicap Snapshot;
- valid group/side membership.

### Side effects

`withdrawn`:

- preserves Side membership history;
- future holes become not applicable;
- existing valid scores remain historical.

`disqualified`:

- means this RoundEntry/player has been disqualified from continuing/competing under an explicit organiser/rules decision;
- does not by itself imply that the entire CompetitionSide is excluded;
- side-level effect is determined separately by the RoundCompetition/rules decision;
- does not delete scoring history.

---

## `PlayingGroup`

Operational group of golfers physically playing together.

### Invariants

V1:

```text
minimum active starting size = 2
maximum size = 4
```

Group and Side are not interchangeable.

### Owns / references

- Round;
- members via RoundEntry;
- starting `RoundHole`;
- operational playing/progress state.

### Operational lifecycle

```text
not_started
  ↓
playing
  ↓
finished_playing
```

Exception branch:

```text
playing / finished_playing
  ↓
attention_required
  ↓
finished_playing
```

`attention_required` is operational: for example unresolved sync/recovery or a group-level scoring support issue.

### `finished_playing` guard

Every active player's final scheduled hole has a resolved HoleResult, or their RoundEntry has an explicit terminal participation state that makes future holes not applicable.

### Critical boundary

`PlayingGroup` does **not** own official competition finalization.

A group can contain two competing Sides, and one Side may be ready while the other still has a query. Official result readiness/finalization therefore belongs to `CompetitionSideResult`.

The organiser dashboard may still expose a **derived group readiness summary** for operational convenience.

---

## `CompetitionSide`

Represents one competitive entry grouping within a specific `RoundCompetition`.

### Formation metadata

The resource itself must not hard-code a universal team size.

For the V1 Better-Ball policy, the permitted starting formations are:

```text
partnership = 2 members
solo        = 1 member
```

Future RoundCompetition policies may permit other team sizes without changing CompetitionSide itself.

### Normal examples

4-player group:

```text
Side A = 2 players
Side B = 2 players
```

3-player group:

```text
Side A = 2 players
Side B = 1 intentional solo
```

### Relationship

A Side belongs to exactly one `RoundCompetition`.

This is important for future expansion: the same RoundEntry may eventually compete individually in one competition and as part of a team in another.

### Membership lock

Side membership is editable before `Round.scoring_open`.

At scoring open it becomes locked for the active RoundCompetition.

### Important

If one partner later withdraws:

- Side remains the original partnership;
- withdrawing RoundEntry changes participation state;
- remaining player may continue representing the Side if the competition policy and independent-verification requirements allow it.

Do not mutate the Side into a new Solo Side.

The Side retains its initial `formation_type`, which preserves the distinction between:

```text
intentional Solo Side
vs
partnership reduced to one active contributor
```


---

## `CompetitionSideMembership`

Associates a `RoundEntry` with a `CompetitionSide`.

### Invariants

- Side and RoundEntry must belong to the same Round;
- Side belongs to the relevant RoundCompetition;
- one RoundEntry may belong to at most one Side **per RoundCompetition**;
- member-count validity is defined by the owning RoundCompetition policy;
- V1 Better-Ball validates partnership = 2 starting members and intentional solo = 1 starting member;
- ordinary membership changes are prohibited after `Round.scoring_open`.

This join resource is intentionally explicit rather than storing one `competition_side_id` on RoundEntry. That prevents a future rewrite when a Round supports multiple competitions with different team structures.


---

## `CompetitionSideResult`

Owns the official competitive readiness/finalization state for one `CompetitionSide`.

It does **not** own raw scores or manually stored leaderboard totals.

### Lifecycle

```text
provisional
  ├── review_required
  └── ready_to_finalize
          ↓
      finalized
```

Exceptional branch:

```text
finalized
  ↓ organiser reopen + reason
review_required
```

Optional terminal competition-policy outcome:

```text
provisional / review_required
  ↓
excluded
```

where `excluded` represents a Side no longer eligible for the competition under an explicit rules/organiser decision.

### `ready_to_finalize` guard

At minimum:

- all required member Scorecards are complete as applicable;
- every current competition-relevant HoleResult revision has valid independent verification or audited organiser override;
- no open ScoreQuery can affect the Side;
- no unresolved eligibility blocker remains;
- all ScoringTrack projections are reproducible from current authoritative results.

### `finalized`

- protects ordinary score mutation for that Side;
- makes its ScoringTrack standings official subject to overall Round finalization;
- remains reopenable only through privileged audited action.

### Why this is not PlayingGroup state

A PlayingGroup may contain two Sides. Their competitive readiness can differ. Finalization therefore cannot correctly belong to the group.

---

## `GroupRoleAssignment`

Tracks scoring responsibility within a PlayingGroup.

### Roles

```text
primary_scorer
designated_verifier
```

### Why this is a resource

Roles may legitimately change during play due to:

- dead battery;
- lost phone;
- player availability;
- organiser intervention.

We need assignment history.

### Lifecycle

```text
active
  ↓
handed_over / revoked
```

A new active assignment is created for the replacement actor.

### Invariants

- at most one active Primary Scorer per group;
- at most one active Designated Verifier per group;
- role holder must belong to the PlayingGroup unless organiser exception policy explicitly permits staff assistance.

---

## `RoundCompetition`

Defines the actual competition rules for the Round.

For MVP:

```text
Four-Ball Better-Ball Stableford / IPS
```

### Stores configuration such as

- scoring policy identifier/version;
- handicap allowance percentage;
- solo normalization policy;
- pickup policy;
- eligible Side structure;
- competition terms reference.

### Invariants

- the MVP has one primary RoundCompetition;
- the model permits multiple RoundCompetitions per Round in future;
- CompetitionSides belong to a RoundCompetition;
- ScoringTracks belong to a RoundCompetition;
- configuration is locked at `Round.scoring_open`;
- raw HoleResult data never depends on mutating competition configuration after open.

### No generic formula engine

V1 concrete policy:

```text
four_ball_stableford_v1
```

Future formats add concrete implementations behind the same boundary.

---

## `ScoringTrack`

Defines one derived leaderboard/scoring view over the same authoritative results.

A ScoringTrack belongs to one `RoundCompetition`.

### V1 tracks

```text
mystery
standard_better_ball
```

### Expected configuration

- name;
- primary flag;
- visibility;
- aggregation/scoring policy;
- tie-break policy.

### V1 recommendation

```text
Mystery
primary = true
tie_break = mystery_holes_then_countback

Standard Better-Ball
primary = false
tie_break = standard_countback
```

### Lifecycle

Configuration:

```text
draft
  ↓
locked
```

Results themselves are derived/provisional until Round finalization.

---

## `MysteryHoleRule`

Represents a hidden Mystery aggregation rule for one `ScoringTrack` + `RoundHole`.

This prevents Mystery configuration from becoming a global Round concern and leaves room for future tracks with different per-hole modifiers.

### V1 rule values

```text
best
worst
both
```

### Invariants

- configured before Round scoring opens;
- immutable after Round scoring opens except exceptional audited override;
- never sent to a player client before reveal eligibility;
- ordinary holes need no MysteryHoleRule;
- uniqueness is `(scoring_track_id, round_hole_id)`.

### No independent runtime lifecycle

Configuration is:

```text
draft → locked
```

controlled by Round lifecycle.

---

## `MysteryReveal`

Tracks reveal state **per PlayingGroup and MysteryHoleRule**.

This is required because shotgun groups reach holes at different times.

### Lifecycle

```text
hidden
  ↓
revealed
```

`revealed` is terminal.

### Guard

May reveal only after:

- the group's complete HoleSubmission for that RoundHole has been accepted by the server.

### Side effects

- player-facing reveal becomes available;
- Mystery track result for that group/hole may be published;
- leaderboard projection updates/broadcasts.

### Important

Future rules are never preloaded to the client.

---

# 57.5 Scoring Domain

## `HandicapSnapshot`

Immutable round-specific **base handicap input** for one RoundEntry.

### Stores

- source Handicap Index or deemed basis;
- handicap source/provenance;
- RoundTeeProfileSnapshot;
- unrounded/rounded Course Handicap;
- source inputs required to reproduce Course Handicap.

### Source values

Conceptually:

```text
preloaded_or_official
player_declared
committee_deemed
committee_override
```

### No-HI policy

Accepted V1 default:

```text
men   deemed HI = 14.0
women deemed HI = 20.0
```

with organiser/committee discretion to reduce for known stronger ability.

The snapshot stores the actual deemed value/basis used; it must not pretend a deemed value is an official Handicap Index.

### Invariant

Base handicap facts are competition-independent.

The snapshot becomes immutable when the RoundEntry starts. A later exceptional correction creates audited revision/recalculation rather than silently rewriting history.


---

## `CompetitionHandicap`

Represents the handicap actually used for one `RoundEntry` in one `RoundCompetition`.

### Why this is separate

`HandicapSnapshot` answers:

> What was this golfer's round/tee handicap basis?

`CompetitionHandicap` answers:

> What Playing Handicap applies under this competition's allowance/rules?

Future concurrent competitions may use different allowances without changing the player's base HandicapSnapshot.

### Stores / derives

- RoundEntry;
- RoundCompetition;
- HandicapSnapshot;
- handicap allowance percentage;
- unrounded allowed handicap where required;
- final Playing Handicap;
- policy/version used.

### Invariants

- unique per `(round_entry_id, round_competition_id)`;
- derived from the locked HandicapSnapshot + RoundCompetition policy;
- immutable for ordinary play once the RoundEntry becomes active;
- exceptional changes are audited and force dependent scoring/verification/projection recalculation.

---

## `Scorecard`

One player's authoritative round scoring container for one RoundEntry.

### Cardinality

```text
RoundEntry 1 ── 1 Scorecard
```

### Purpose

Container/aggregate for the player's HoleResults across the Round.

### Lifecycle

```text
not_started
  ↓
in_progress
  ↓
complete
  ↓
verified
```

Possible branch:

```text
in_progress / complete
  ↓
review_required
  ↓
complete / verified
```

### Meaning

#### `not_started`

No accepted HoleResult.

#### `in_progress`

At least one accepted HoleResult; required round outcomes are incomplete.

#### `complete`

Every required hole is resolved or properly not-applicable due to participation state.

#### `verified`

Every **current** competition-relevant HoleResult revision has valid independent verification or explicit organiser override.

### Critical boundary

Scorecard verification and competition finalization are separate.

A Scorecard does not become `"finalized"` merely because one competition result is finalized; future Rounds may have multiple RoundCompetitions. Ordinary mutation is ultimately constrained by HoleResult verification rules, CompetitionSideResult state, and Round lifecycle.

The Scorecard does not own leaderboard totals as authoritative truth.

---

## `HoleResult`

Authoritative player outcome for one Scorecard + RoundHole.

### Unique invariant

```text
one current HoleResult per Scorecard per RoundHole
```

Historical changes live in ScoreRevision.

### Ordinary V1 outcomes

```text
holed_out
picked_up
```

### `holed_out`

Stores actual gross strokes including applicable penalties.

### `picked_up`

- no fabricated gross value required;
- Stableford points = 0;
- only allowed once the player's own hole can no longer earn a Stableford point.

### Derived values

Do not treat these as replacement raw facts:

- individual Stableford points;
- net competition score;
- handicap-adjusted strokes;
- Side contribution;
- Standard track result;
- Mystery track result.

### Server lifecycle

```text
recorded
  ↓
amended
```

Verification/query state is intentionally held by `ScoreVerification` / `ScoreQuery`, not duplicated onto HoleResult.

Client-side offline drafts/queues are synchronization state, not server HoleResult lifecycle state.

Every accepted mutation increments the HoleResult revision/version.

### Guard

No `recorded` result may be blank/ambiguous.

---

## `HoleSubmission`

Immutable server receipt/command record for one PlayingGroup + RoundHole submission.

### Purpose

Supports:

- atomic group hole submission;
- offline retry;
- idempotency;
- logical sequence tracking;
- audit/reconciliation.

### Expected fields

Conceptually:

```text
client_submission_id
playing_group_id
round_hole_id
expected_revision
submitted_by
captured_at
accepted_at
```

and the submitted player result payload/receipt reference.

### Invariants

- `client_submission_id` unique;
- retry of accepted ID returns idempotent success;
- accepted submission applies all group player HoleResults atomically;
- stale conflicting revision never silently overwrites current server state.

### State separation

Client synchronization state may be:

```text
queued → syncing → accepted
```

or:

```text
syncing → conflict / rejected
```

Those are **client sync states**, not the lifecycle of the authoritative server receipt.

Server-side HoleSubmission records an immutable outcome such as:

```text
accepted
conflict
rejected
```

with the idempotency key and relevant revision evidence.

---

## `ScoreVerification`

Independent confirmation of a HoleResult by someone other than the subject player.

### Critical invariants

```text
verifier_round_entry_id != hole_result.player_round_entry_id
```

No self-verification.

Verification must also identify the exact `hole_result_revision` it certifies. If the HoleResult is later amended, verification of the prior revision is no longer valid for finalization and the new current revision must be verified again.

### Corrected two-person verification workflow

Because the Designated Verifier is also a player:

- Designated Verifier verifies the Primary Scorer and all other players **except themselves**;
- Primary Scorer verifies the Designated Verifier's own HoleResults;
- ordinary players may query their own result;
- organiser may override verification only as an audited exception.

This preserves full independent verification with two operational roles.

### Lifecycle

```text
pending
  ↓
verified
```

Organiser exception:

```text
pending
  ↓
overridden
```

A score query is a separate `ScoreQuery` resource; verification does not duplicate a `queried` state.

If the certified HoleResult revision is amended:

```text
verified / overridden
  ↓
superseded
```

The new revision receives a new pending verification.

`overridden` records organiser identity/reason and must never pretend the player verifier performed the verification.

---

## `ScoreQuery`

Represents a disagreement/question about one HoleResult.

### May be raised by

- Designated Verifier;
- player about their own score;
- authorised organiser/staff.

### Lifecycle

```text
open
  ↓
resolved
```

or:

```text
open
  ↓
escalated
  ↓
resolved
```

Possible terminal administrative outcome:

```text
dismissed
```

only with an actor/reason.

### Invariants

- no group can become ready_to_finalize with an open query;
- resolving a query may create a ScoreRevision;
- leaderboard projections recalculate after accepted correction.

---

## `ScoreRevision`

Immutable history of a HoleResult change after initial recording.

### Stores

- original value/outcome;
- new value/outcome;
- actor;
- reason;
- source query/conflict where applicable;
- timestamp;
- resulting revision number.

### Invariant

Never delete revision history to make the current result look as though it was always correct.

---

# 57.6 Scoring Rules / Domain Services

These are domain policies/services, not necessarily database resources.

## Player scoring pipeline

```text
HoleResult
  ↓
HandicapSnapshot + RoundTeeHoleSnapshot
  ↓
strokes received
  ↓
individual Stableford points
```

### Important

- actual gross score is preserved;
- handicap-adjusted value is derived separately;
- Net Double Bogey uses the appropriate Course Handicap basis;
- competition points use the competition's Playing Handicap/stroke allocation policy.

---

## Side aggregation

Input:

```text
eligible contributor Stableford points
```

Policies:

```text
best
worst
both
```

### Solo normalization

Accepted:

```text
P
companion = max(P - 1, 0)

normalized contributors =
[P, companion]
```

Applies to:

- intentional Solo Side;
- partnership reduced to one active contributor after withdrawal.

Never create a fake player or fake HoleResult for the companion contribution.

---

## Standard scoring track

Every hole:

```text
best
```

---

## Mystery scoring track

Ordinary hole:

```text
best
```

Mystery hole:

```text
best / worst / both
```

using the locked MysteryHoleRule.

---

## Tie-break policies

Concrete V1 policies only:

```text
mystery_holes_then_countback
standard_countback
```

No generic tie-break DSL.

---

# 57.7 Leaderboard Projection Model

Leaderboard is a **derived read model**, not an authoritative scoring resource.

Conceptually:

```text
Authoritative HoleResults
        ↓
ScoringTrack policy
        ↓
Side hole results
        ↓
cumulative points
        ↓
tie-break evaluation
        ↓
LeaderboardProjection
```

### Projection states

```text
provisional
  ↓
final
```

Round finalization changes the official status, not the underlying meaning of score facts.

### Requirements

- Standard and Mystery projections derive from the same HoleResults;
- score correction recalculates affected projections;
- hidden future Mystery rules are never exposed through projection payloads;
- stale offline clients may display only clearly labelled cached projections.

### Suggested implementation characteristic

Projection may be:

- query-derived;
- cached/materialized;
- incrementally updated;

but must always be reproducible from authoritative source data.

---

# 57.8 Communications Domain

## `EventMessage`

Represents one reusable organiser-defined communication **definition**.

### Owns

- content/template;
- intended audience rule;
- trigger rule;
- delivery policy;
- relevance/acknowledgement rules.

### Lifecycle

```text
draft
  ↓
armed / scheduled
  ↓
closed
```

Branch:

```text
draft / armed / scheduled
  ↓
cancelled
```

### Important cardinality rule

A single message definition may trigger many times.

Example:

> "Halfway meal instructions" fires separately as each PlayingGroup reaches its halfway point.

Therefore `EventMessage` itself must not transition to a one-time `triggered` state after the first group.

Each actual trigger occurrence creates a `MessageDispatch`.

### Trigger types

V1 should use deterministic workflow triggers:

```text
manual
scheduled_time
round_started
hole_completed
next_hole_ready
holes_completed
holes_remaining
round_completed
```

`physical_hole_reached` is deliberately deferred because the server cannot know true physical arrival without an explicit check-in/GPS signal. `next_hole_ready` is derived after the previous accepted HoleSubmission (or from `round_started` for the starting hole) and is idempotent.

### Invariant

Message dispatch/delivery may never block authoritative score persistence.


---

## `MessageDispatch`

Represents one concrete trigger occurrence + resolved audience for an EventMessage.

Examples:

- one manual broadcast to all players;
- the halfway message for Group 12;
- the round-complete message for Player X.

### Lifecycle

```text
pending
  ↓
dispatching
  ↓
completed
```

Branches:

```text
pending / dispatching
  ↓
partially_completed
  ↓
completed
```

or:

```text
pending / dispatching
  ↓
failed
```

### Idempotency

Triggered dispatches require a deterministic idempotency identity, conceptually:

```text
event_message_id
+ trigger_type
+ trigger_subject
+ trigger_occurrence
```

so score retries/recalculation cannot send duplicate halfway or finish messages.

One MessageDispatch creates one or more MessageDelivery records.

---

## `MessageDelivery`

One recipient/channel delivery attempt/state.

### Channels

V1:

```text
in_app
whatsapp
email
```

Future:

```text
push
sms
```

### Lifecycle

```text
pending
  ↓
sent
  ↓
delivered
```

Branches:

```text
pending/sent
  ↓
failed
```

Optional player-facing state:

```text
unseen
  ↓
seen
  ↓
acknowledged
```

External provider "delivered" does not imply "read".

---

# 57.9 Sponsorship Domain

## `Sponsor`

Reusable sponsor identity/content.

Expected:

- name;
- logo/media reference;
- short description;
- destination URL;
- active/archive state.

### Lifecycle

```text
active ↔ archived
```

---

## `SponsorPlacement`

Associates Sponsor content with an event surface.

### Initial placement scopes

```text
event
round_hole
side_competition
```

Future placements may include leaderboard/prizegiving/message surfaces.

### Invariants

- structured safe content only;
- no arbitrary sponsor HTML/JavaScript;
- sponsor rendering never blocks scoring;
- missing media never blocks competition workflow.

### Lifecycle

Configuration:

```text
draft
  ↓
published
  ↓
archived
```

---

# 57.10 Side Competitions Domain

## `SideCompetition`

Independent challenge parallel to the main scoring competition.

### V1 concrete types

```text
closest_to_pin
longest_drive
```

Future concrete types:

```text
longest_putt
hole_in_one
jackpot_hole
sponsor_challenge
```

### Lifecycle

```text
draft
  ↓
armed
  ↓
open
  ↓
closed
  ↓
finalized
```

Branch:

```text
draft/armed/open
  ↓
cancelled
```

### Configuration

- Round;
- target RoundHole(s);
- type;
- eligibility/division;
- sponsor/prize;
- display instructions;
- visibility.

### V1 operational truth

Physical on-course board/marker is authoritative during play.

Player-side measurement capture is deferred.

---

## `SideCompetitionResult`

Admin-entered final result from the physical board.

### Stores

- winner Player/RoundEntry;
- optional measurement;
- optional runner-up/notes;
- verified by;
- finalized at.

### Lifecycle

```text
draft
  ↓
verified
  ↓
finalized
```

### Invariant

Side competition result never modifies normal HoleResult or leaderboard scoring unless a future explicitly designed format says otherwise.

---

# 57.11 Operations / Audit Domain

## `AuditEvent`

Immutable record of high-impact operational actions.

### Required audit examples

- staff role assignment/revocation;
- handicap override;
- tee correction after readiness;
- side/group correction after readiness;
- score revision;
- query resolution;
- withdrawal/disqualification;
- verifier override;
- finalized result reopen;
- group/round finalization;
- event-wide broadcast;
- locked competition configuration override;
- access grant revocation/reissue where security-relevant.

### Invariant

AuditEvent is append-only for ordinary application behavior.

Do not rely on free-text logs as the only audit source for competition-critical changes.

---

# 57.12 Core Relationship Map

```text
Event
├── EventStaffAssignment ── StaffUser
├── PlayerAccessGrant ── Player
├── Round
│   ├── RoundHole
│   ├── RoundTeeProfileSnapshot
│   │   └── RoundTeeHoleSnapshot
│   ├── RoundEntry ── Player
│   │   ├── RoundEntryCategoryMembership ── CompetitionCategory
│   │   ├── HandicapSnapshot
│   │   ├── CompetitionHandicap ── RoundCompetition
│   │   └── Scorecard
│   │       └── HoleResult
│   │           ├── ScoreVerification
│   │           ├── ScoreQuery
│   │           └── ScoreRevision
│   ├── PlayingGroup
│   │   ├── RoundEntry
│   │   ├── GroupRoleAssignment
│   │   └── HoleSubmission
│   ├── RoundCompetition
│   │   ├── CompetitionSide
│   │   │   ├── CompetitionSideMembership ── RoundEntry
│   │   │   └── CompetitionSideResult
│   │   └── ScoringTrack
│   │       └── MysteryHoleRule
│   │           └── MysteryReveal ── PlayingGroup
│   └── SideCompetition
│       └── SideCompetitionResult
├── EventMessage
│   └── MessageDispatch
│       └── MessageDelivery
└── SponsorPlacement ── Sponsor
```

---

# 57.13 Mandatory Domain Invariants

These are architectural constraints, not optional implementation details.

1. A Player and a RoundEntry are different concepts.
2. A RoundEntry belongs to exactly one Round.
3. A Player has at most one RoundEntry per Round.
4. Registration/check-in state and competitive participation state are separate.
5. A PlayingGroup contains 2–4 starting participants in V1.
6. A PlayingGroup and CompetitionSide are different concepts.
7. A CompetitionSide belongs to one RoundCompetition.
8. RoundEntry-to-Side membership is represented by CompetitionSideMembership, not a single global side field.
9. A RoundEntry belongs to at most one CompetitionSide per RoundCompetition.
10. Side membership locks when Round scoring opens.
11. Withdrawal changes RoundEntry participation, not Side history.
12. A replacement player receives a new RoundEntry.
13. Tee assignment belongs to RoundEntry, not PlayingGroup.
14. Scoring uses immutable Round course/tee snapshots, not mutable live catalog values.
15. RoundHole owns round play order; the catalog does not universally assume exactly 18 physical holes.
16. HandicapSnapshot contains competition-independent round/tee handicap facts.
17. CompetitionHandicap contains competition-specific allowance/Playing Handicap.
18. One Scorecard exists per RoundEntry.
19. One current HoleResult exists per Scorecard + RoundHole.
20. A resolved HoleResult is never blank/ambiguous.
21. `picked_up` is valid only under explicit scoring policy.
22. Actual gross score is never overwritten by handicap-adjusted score.
23. HoleResult verification/query state is not duplicated on HoleResult itself.
24. Every HoleResult mutation increments its revision.
25. Verification certifies an exact HoleResult revision.
26. Amendment invalidates/supersedes verification of the previous revision.
27. No player may verify their own HoleResult.
28. Every current competition-relevant HoleResult requires independent verification or audited organiser override before finalization.
29. An open ScoreQuery blocks affected CompetitionSideResult finalization.
30. Score corrections create immutable revision/audit history.
31. Hole submission is atomic across the group's required player results.
32. Offline submission retries are idempotent.
33. Stale revision conflicts never silently overwrite current scores.
34. Scoring-role handover never changes Side membership.
35. Official competition finalization belongs to CompetitionSideResult, not PlayingGroup.
36. Standard and Mystery tracks derive from the same authoritative HoleResults.
37. ScoringTracks belong to RoundCompetition.
38. MysteryHoleRule belongs to a ScoringTrack + RoundHole.
39. Mystery rules lock before scoring opens.
40. Mystery rules remain server-secret until group-specific reveal eligibility.
41. Leaderboards are derived read models, never authoritative score data.
42. PlayerAccessGrant is event/player scoped and may span multiple RoundEntries.
43. One EventMessage definition may create many MessageDispatch occurrences.
44. Triggered messaging is idempotent; score retries must not duplicate dispatches.
45. External message delivery never blocks score persistence.
46. Sponsor/media failure never blocks scoring.
47. SideCompetition capture never blocks main competition scoring.
48. Round finalization requires all required CompetitionSideResults terminal/resolved and all blocking review conditions cleared.
49. Prizegiving readiness is derived, not manually asserted.
50. Competition categories may overlap; RoundEntry is not limited to one mutually exclusive division.

---

# 57.14 Persistence Constraints / Index Candidates

Exact migrations remain implementation work, but the eventual schema should enforce critical invariants at the database layer where practical.

Recommended uniqueness/index intent:

```text
RoundEntry
UNIQUE(round_id, player_id)

CourseHole
UNIQUE(course_id, hole_number)

RoundHole
UNIQUE(round_id, hole_number)

RoundTeeHoleSnapshot
UNIQUE(round_tee_profile_snapshot_id, round_hole_id)

Scorecard
UNIQUE(round_entry_id)

HoleResult
UNIQUE(scorecard_id, round_hole_id)

CompetitionSideMembership
UNIQUE(round_competition_id, round_entry_id)

CompetitionHandicap
UNIQUE(round_entry_id, round_competition_id)

RoundEntryCategoryMembership
UNIQUE(round_entry_id, competition_category_id)

HoleSubmission
UNIQUE(client_submission_id)

MysteryHoleRule
UNIQUE(scoring_track_id, round_hole_id)

MysteryReveal
UNIQUE(mystery_hole_rule_id, playing_group_id)

MessageDispatch
UNIQUE(event_message_id, trigger_identity)
```

Additional indexes should cover:

- RoundEntry by group/status;
- HoleResult by round/group/hole;
- ScoreQuery open-state lookup;
- MessageDelivery pending/failed work;
- audit lookups by event/resource;
- leaderboard source queries.

Avoid large-table scans in live leaderboard/admin operations even though MVP scale is small.

---

# 57.15 Permission Boundary Summary

### Player-facing

#### Ordinary Player

May:

- view full PlayingGroup scorecard;
- view permitted leaderboards;
- view revealed Mystery rules;
- query own HoleResult;
- confirm own event/handicap details before lock.

May not:

- edit other player's score;
- verify own score;
- alter team/side;
- access admin actions.

#### Primary Scorer

May:

- enter/submit all active group player results;
- verify Designated Verifier's HoleResults;
- respond to queries/corrections through allowed workflow.

May not:

- verify own HoleResult;
- change locked competition configuration.

#### Designated Verifier

May:

- verify all other players' HoleResults;
- query any player result;
- complete their assigned portion of final card review.

They cannot independently certify their own HoleResults; those require another eligible verifier/marker (normally the Primary Scorer in V1).

May not:

- verify own HoleResult.

### Staff

Use the accepted role policy matrix:

- Event Admin;
- Competition Manager;
- Registration Staff;
- Scoring Support.

Policies are enforced on actions, not only UI visibility.

---

# 57.16 Separation-of-Concern Rules

### Competition owns

- participation;
- grouping;
- sides;
- round lifecycle;
- competition configuration.

### Scoring owns

- handicap snapshot;
- scorecards;
- hole results;
- verification;
- queries;
- revisions;
- scoring calculations.

### Communications owns

- message intent;
- audience/trigger;
- channel delivery.

### Sponsorship owns

- sponsor identity/content/placement.

### Side Competitions own

- closest-to-pin / longest-drive configuration and results.

### Audit owns

- immutable high-impact action history.

### Catalog owns

- reusable course/tee knowledge.

No domain may reach into another domain's persistence and mutate its records directly as an implementation shortcut. Cross-domain changes should occur through explicit domain actions/services.

---

# 57.17 Recommended Code/Folder Boundaries

Exact framework layout will be decided during `/wayfinder`, but the architecture should preserve boundaries resembling:

```text
lib/<app>/accounts/
lib/<app>/golf_catalog/
lib/<app>/competition/
lib/<app>/scoring/
lib/<app>/communications/
lib/<app>/sponsorship/
lib/<app>/side_competitions/
lib/<app>/audit/
```

Web/UI remains separate:

```text
lib/<app>_web/
├── admin/
├── player/
├── scoring/
└── leaderboard/
```

Scoring policy implementations should live behind a narrow scoring interface, for example conceptually:

```text
scoring/policies/
├── four_ball_stableford
├── mystery_aggregation
├── solo_normalization
└── tie_break
```

Do not create a `utils` or `misc` dumping ground for domain logic.

---

# 57.18 Performance & Scaling Review

### MVP reality

Expected live scale:

- ~144 players;
- ~36 groups;
- modest spectator/admin load.

Postgres + Phoenix + PubSub are sufficient.

### Hot / warm / cold assessment

For this product, do **not** import EventSales' Redis/Cachex architecture wholesale.

Recommended:

```text
Hot
- current LiveView state
- lightweight in-process read caches only if proven useful

Warm
- Postgres-backed recent scoring state
- optional browser IndexedDB for pending local writes

Cold / durable
- Postgres
```

### High-concurrency safety

Still required despite low scale:

- atomic hole submission;
- optimistic revision checks;
- idempotency keys;
- critical uniqueness indexes;
- server-authoritative results;
- PubSub push rather than polling.

### Analytics

No large analytics system required.

Leaderboard and admin readiness should use bounded indexed queries or small derived projections.

### STOP condition

Do not introduce Redis, distributed locks, read replicas, generic event buses, or complex caching unless actual load/testing demonstrates a need.

---

# 57.19 Domain Model Success Criteria

This model is ready to hand to implementation planning only when:

1. every accepted product behavior maps cleanly to a resource/action/policy;
2. no resource has two conflicting meanings;
3. every meaningful lifecycle has states, transitions, guards, and terminal conditions;
4. raw golf facts remain separate from derived scoring;
5. the model supports the MVP without generic engines;
6. future formats/rounds/courses can be added without changing the meaning of existing resources;
7. player/staff permissions are enforceable at action boundaries;
8. offline/retry/conflict behavior has a clear authority model;
9. Mystery secrecy cannot be bypassed by client payload design;
10. database invariants can enforce critical uniqueness/integrity.

## 58. Domain-Model Pressure Test v0.2

### Verdict

**PASS WITH MATERIAL REFINEMENTS.**

The v0.1 model had the right broad domain boundaries, but several details would have created avoidable future rewrites or ambiguous authority. The amendments below are now incorporated into Section 57.

### Critical findings corrected

#### 1. PlayingGroup was incorrectly carrying competition finalization

**Problem**

A PlayingGroup is operational: golfers physically play together.

A 4-player group can contain two competing Sides. One Side may be clean and finalizable while the other has a disputed score.

Therefore:

```text
PlayingGroup.finalized
```

was the wrong ownership boundary.

**Correction**

Added:

```text
CompetitionSideResult
```

Official readiness/finalization now belongs to the competitive Side. PlayingGroup ends at operational `finished_playing` / `attention_required`.

---

#### 2. Direct RoundEntry → CompetitionSide would block future concurrent competitions

**Problem**

A single `competition_side_id` on RoundEntry works only while a Round has one team structure.

Future examples may include:

- team Better-Ball;
- concurrent individual prize;
- another competition with different teams.

**Correction**

Added:

```text
CompetitionSideMembership
```

Sides belong to `RoundCompetition`, and membership is unique per RoundEntry + RoundCompetition.

This is a small V1 join table with significant future value.

---

#### 3. HandicapSnapshot mixed base handicap facts with competition-specific allowance

**Problem**

Course Handicap is based on the player's round/tee context.

Playing Handicap may differ by competition allowance.

Putting both into one round-global snapshot would fail if a future Round runs multiple competitions with different allowances.

**Correction**

Split:

```text
HandicapSnapshot
= round/tee/base handicap facts

CompetitionHandicap
= allowance + Playing Handicap for RoundEntry × RoundCompetition
```

---

#### 4. Registration lifecycle duplicated competitive `started`

**Problem**

`checked_in → started` overlapped with `RoundEntry.participation = active`.

That creates two sources of truth for whether somebody has begun play.

**Correction**

Registration now ends at states such as:

```text
expected
checked_in
no_show
withdrawn_before_start
replaced_before_start
```

Competitive participation alone owns:

```text
not_started → active → completed/withdrawn/disqualified
```

---

#### 5. Course model was unnecessarily locked to 18 physical holes

**Problem**

A universal `CourseHole = 1..18` invariant blocks:

- 9-hole venues;
- 27-hole facilities;
- composite nines;
- alternate round routing.

**Correction**

`CourseHole` is a physical catalog identity.

`RoundHole` now owns:

```text
play_order
display_hole_number / label
```

The **MVP Round** validates exactly 18 holes; the reusable Course domain does not.

---

#### 6. Mystery rules were scoped too globally

**Problem**

`MysteryHoleRule` attached only to Round + Hole assumes one mystery rule universe.

**Correction**

MysteryHoleRule now belongs to:

```text
ScoringTrack + RoundHole
```

This keeps the hidden modifier where it actually belongs and avoids future conflict between scoring tracks.

---

#### 7. Verification did not bind to the score revision being certified

**Problem**

A score could be verified, later corrected, and incorrectly remain `verified`.

**Correction**

Verification certifies an exact:

```text
HoleResult revision
```

Any amendment supersedes old verification and requires the new current revision to be verified again.

`ScoreQuery` remains separate rather than duplicating a `queried` HoleResult/verification state.

---

#### 8. Server domain state and offline client sync state were mixed together

**Problem**

States such as:

```text
draft/local
queued
syncing
```

are browser/client synchronization states, not server scoring-domain states.

**Correction**

The model now keeps:

```text
client sync state
```

separate from:

```text
server HoleResult / HoleSubmission outcome
```

This will make offline implementation and conflict recovery substantially clearer.

---

#### 9. EventMessage lifecycle failed for per-group triggered messages

**Problem**

One message definition such as `Halfway Meal` may trigger 36 different times as shotgun groups reach halfway.

A one-time:

```text
EventMessage → triggered
```

state cannot represent that correctly.

**Correction**

Added:

```text
EventMessage
    ↓
MessageDispatch
    ↓
MessageDelivery
```

EventMessage is the reusable rule/template. MessageDispatch is one concrete trigger occurrence. Dispatches must be idempotent.

---

#### 10. Player access was too closely tied to RoundEntry

**Problem**

The accepted UX says the same personal event link should work before, during and after the event. Future multi-round events should not require a new link for each Round.

**Correction**

`PlayerAccessGrant` is now primarily:

```text
Event + Player
```

and effective Round capabilities are resolved through RoundEntry.

---

#### 11. One CompetitionDivision per RoundEntry was too restrictive

**Problem**

Categories can overlap:

```text
Senior + Women
Junior + another prize category
```

A single division field would force false mutual exclusion.

**Correction**

Added:

```text
CompetitionCategory
RoundEntryCategoryMembership
```

V1 can keep this extremely small while preserving correct semantics.

---

## 58.1 Pressure-Test Result: Competition Core

The following core boundaries are now considered **strong enough to proceed**:

```text
Event
  ↓
Round
  ↓
RoundEntry
  ↓
PlayingGroup        # operational
  ↓
RoundCompetition
  ↓
CompetitionSide     # competitive grouping
  ↓
CompetitionSideResult
```

with memberships explicitly separated:

```text
RoundEntry ── PlayingGroup
RoundEntry ── CompetitionSideMembership ── CompetitionSide
```

### Why this survives future expansion

It can support later:

- multiple Rounds;
- multiple courses;
- mixed tees;
- multiple concurrent RoundCompetitions;
- individual or team structures;
- multiple leaderboard ScoringTracks;
- future scoring policies;

without changing what `Player`, `RoundEntry`, `PlayingGroup`, `CompetitionSide`, or `HoleResult` fundamentally mean.

---

## 58.2 Remaining Domain Questions Before Final Acceptance

The model is substantially stronger, but the following still need explicit pressure testing before handoff:

1. **Disqualification semantics**
   - when one player is DQ'd, does their Side always continue, sometimes continue, or become excluded according to format-specific policy?

2. **CompetitionSide formation generality**
   - V1 supports one/two-member Better-Ball sides; confirm how much future team-size flexibility belongs in the resource versus the scoring policy.

3. **Round reopen scope**
   - decide whether reopening one finalized Side requires Round-level reopen or can be a controlled Side-level correction while Round remains not-finalized.

4. **Projection consistency**
   - decide whether leaderboard projections are calculated synchronously in the score transaction or updated immediately after commit through a deterministic projection step.

5. **Messaging trigger semantics**
   - define exact subject identity for `physical_hole_reached` versus `physical_hole_completed` so shotgun/offline retries cannot duplicate notifications.

6. **Staff vs player actor identity**
   - implementation needs one clear audit/action actor abstraction capable of identifying either authenticated StaffUser or event-scoped Player/RoundEntry without conflating their credentials.

### STOP condition

Do **not** generate implementation tickets yet.

Proceed only after the remaining six questions are resolved or deliberately deferred with an explicit policy.

## 59. Remaining Pressure-Test Decisions v0.3

### Status

**RECOMMENDED ARCHITECTURAL RESOLUTIONS — pending owner acceptance as a bundle.**

The six unresolved items from Section 58 have now been pressure-tested.

---

## 59.1 Disqualification and Rules Decisions

### Finding

Do not encode:

```text
player DQ => side DQ
```

or:

```text
player DQ => side always continues
```

as a universal rule.

Formal Four-Ball rules contain multiple disqualification effects:

- some breaches by one partner disqualify the whole side;
- some breaches only make that player's score unable to count for a hole;
- some side disqualifications occur only when both partners breach specified rules.

### Recommended domain policy

Keep the scoring engine out of the business of automatically interpreting every Rule of Golf breach in V1.

Provide explicit competition/rules actions such as conceptually:

```text
disqualify_round_entry
exclude_competition_side
```

and leave room for a future action/policy such as:

```text
mark_hole_result_not_countable
```

Every such action must record:

- acting Competition Manager/Event Admin;
- reason;
- optional rule/reference note;
- effective hole/time where relevant;
- affected player/side;
- resulting eligibility state.

### V1 behavior

`RoundEntry.disqualified` affects the player.

It does **not** automatically mutate `CompetitionSideResult` to `excluded`.

If the applicable ruling disqualifies the whole side, an authorised organiser explicitly applies the side exclusion as part of the same resolution workflow.

This gives correct scope without building a full automated Rules-of-Golf adjudication engine.

---

## 59.2 CompetitionSide Team Size

### Finding

Do not make `CompetitionSide` structurally mean "exactly two golfers".

That would require a rewrite for future:

- Scramble teams;
- larger team formats;
- individual competition entries;
- tour/team events.

### Recommended rule

`CompetitionSide` is a stable competitive grouping.

Its owning `RoundCompetition` policy defines valid starting member counts.

For V1 Four-Ball Better-Ball:

```text
partnership => exactly 2 starting members
solo        => exactly 1 starting member
```

The resource itself remains capable of other sizes under future concrete competition policies.

No generic team-builder engine is required.

---

## 59.3 Reopening Finalized Results

### Recommended rule

There are two distinct cases.

### A. Side finalized, Round not yet finalized

An Event Admin / authorised Competition Manager may:

```text
CompetitionSideResult.finalized
    ↓ reopen + mandatory reason
review_required
    ↓ correct / reverify
ready_to_finalize
    ↓
finalized
```

The Round itself does not need to reopen because it was never finalized.

### B. Round already finalized

No Side or score may be altered while the Round remains finalized.

Required workflow:

```text
Round.finalized
    ↓ Event Admin reopen + reason
Round.scoring_closed / review state
    ↓ reopen affected Side
    ↓ correction / re-verification
    ↓ re-finalize affected Side
    ↓ re-finalize Round
```

This preserves a clear official-results boundary.

### STOP condition

Never provide a hidden "edit finalized score" shortcut that bypasses the reopen lifecycle.

---

## 59.4 Leaderboard Projection Consistency

### Recommendation for V1

Do **not** persist a complex leaderboard projection pipeline yet.

At ~144 players, calculate leaderboard views deterministically from authoritative indexed data.

Preferred V1 flow:

```text
HoleSubmission transaction
  ↓
commit HoleResults / revisions / reveal eligibility
  ↓
transaction succeeds
  ↓
Phoenix PubSub invalidation/update signal
  ↓
leaderboard clients recompute/read current derived standings
```

### Why

This avoids:

- projection drift;
- outbox/projector infrastructure;
- replay/rebuild complexity;
- another source of truth.

The read path is tiny at MVP scale.

If later load requires it, the same `ScoringTrack` boundary can gain cached/materialized projections without changing authoritative scoring resources.

### Critical rule

PubSub broadcast occurs only **after commit**.

Clients never receive a leaderboard event for a transaction that later rolls back.

---

## 59.5 Messaging Trigger Semantics

### Finding

`physical_hole_reached` sounds useful but is not objectively knowable by the server in the web MVP.

Using it without GPS or an explicit arrival action would create fake precision.

### V1 deterministic triggers

Use:

```text
round_started
hole_completed
next_hole_ready
holes_completed
holes_remaining
round_completed
manual
scheduled_time
```

### `hole_completed`

Occurs exactly once when the server accepts the group's HoleSubmission for that RoundHole.

### `next_hole_ready`

Occurs from the accepted playing sequence after `hole_completed`.

For the starting hole, it is derived from `round_started`.

This is suitable for messages such as:

> "Your next hole is Hole 18 — halfway instructions apply after completion."

or:

> "As you head to Hole 9, collect meals at the halfway house."

### Idempotency identity

A dispatch trigger should include conceptually:

```text
event_message_id
playing_group_id / round_entry_id
trigger_type
round_hole_id or progress milestone
```

so offline retries and score corrections do not resend the same operational message accidentally.

True physical-arrival triggers may be added later if a native/GPS/manual arrival signal becomes worthwhile.

---

## 59.6 Staff vs Player Actor Identity

### Recommendation

Do not create one shared "User" login model just to make auditing convenient.

Staff and players have fundamentally different credentials:

```text
StaffUser
= authenticated staff account

Player/RoundEntry
= event-scoped player identity via PlayerAccessGrant
```

Use a small domain value concept such as:

```text
ActionActor
├── staff_user_id
└── round_entry_id
```

with exactly one populated for a given action.

This actor concept may be embedded in action context/audit structures rather than becoming its own database resource.

### Persistence pattern

Where an immutable audit/revision row needs actor identity, use explicit nullable foreign keys plus a database check that exactly one actor type is set.

Do not store only free-text names.

### Benefits

- preserves real credential boundaries;
- gives strong foreign-key auditability;
- avoids polymorphic identity magic;
- leaves room for future system/service actors if genuinely needed.

---

## 59.7 Pressure-Test Verdict After These Resolutions

If the six recommendations above are accepted, the **domain model is ready for final consolidation**.

The next stage would be:

```text
1. consolidate accepted v0.3 domain model
2. produce explicit action/policy catalogue
3. produce final state-machine transition tables
4. run security/concurrency/data-integrity review
5. freeze Product + Domain Spec v1.0
6. hand v1.0 to local /wayfinder for repository reconciliation
```

### STOP condition

Do not produce implementation phases/tickets before the consolidated v1.0 spec passes the final security/concurrency/integrity review.

# 60. Accepted Domain Model v0.3 — Consolidation

### Status

**Accepted for final security/concurrency/integrity review.**

Sections 57–59 remain useful design history. Where an earlier provisional statement conflicts with Sections 60–61, **Sections 60–61 are authoritative**.

The six v0.3 pressure-test recommendations are accepted:

1. disqualification is a rules/organiser action and does not automatically imply Side exclusion;
2. CompetitionSide size is constrained by the active competition policy, not hard-coded globally;
3. a finalized Side may be reopened while the Round is still unfinalized; a finalized Round must be reopened before any underlying official result changes;
4. V1 leaderboards are deterministic derived reads with post-commit PubSub invalidation, not a complex persistent projection pipeline;
5. V1 messaging uses deterministic workflow triggers rather than pretending the server knows physical golfer location;
6. staff and player identities remain separate credential models, joined only by an explicit action/audit actor abstraction.

### Core authority chain

```text
Course / Tee Catalog
        ↓ snapshot
Round
        ↓
RoundEntry
        ├── PlayingGroup              # physical/operational grouping
        ├── HandicapSnapshot          # base handicap facts
        └── Scorecard
                ↓
           HoleResult                 # raw authoritative golf result

RoundCompetition
        ├── CompetitionHandicap       # competition-specific Playing Handicap
        ├── CompetitionSide
        │       ├── CompetitionSideMembership
        │       └── CompetitionSideResult
        └── ScoringTrack
                ├── Standard Better-Ball
                └── Mystery
                        └── MysteryHoleRule / MysteryReveal
```

### Non-negotiable ownership rules

- `PlayingGroup` owns **who physically plays together**, not official placing/finalization.
- `CompetitionSide` owns **who competes together** inside one `RoundCompetition`.
- `CompetitionSideResult` owns **competitive readiness/finalization**.
- `RoundEntry` owns **one player's participation in one Round**.
- `Scorecard` owns **one player's round scoring container**, not team totals or leaderboard rank.
- `HoleResult` owns **the player's actual resolved hole outcome**, not Stableford/team/leaderboard truth.
- `HandicapSnapshot` owns base round/tee handicap facts; `CompetitionHandicap` owns competition-specific allowance/Playing Handicap.
- `ScoringTrack` owns one derived scoring view; it never owns raw score data.
- `EventMessage` is a reusable communication definition; `MessageDispatch` is one actual trigger occurrence.

---

# 61. Domain Action & Policy Catalogue

## 61.1 Action design rules

Every mutation must be implemented as an explicit domain action with:

```text
actor
resource / target
preconditions
state guard
authorization policy
validation
atomic side effects
audit requirement (where applicable)
```

Do not expose generic CRUD mutation APIs for competition-critical resources after their lifecycle has begun.

Examples to avoid:

```text
update_round(params)
update_side(params)
update_hole_result(params)
```

for state-sensitive operations.

Prefer explicit actions such as:

```text
open_scoring
withdraw_round_entry
handover_primary_scorer
submit_group_hole
resolve_score_query
reopen_side_result
```

Read operations may remain conventional queries/read actions.

---

## 61.2 Actor model

### Staff actors

```text
Event Admin
Competition Manager
Registration Staff
Scoring Support
```

Authenticated through `StaffUser` + active `EventStaffAssignment`.

### Player actors

Authenticated through an active event-scoped `PlayerAccessGrant`, resolving to the relevant `Player` / `RoundEntry`.

Player operational roles are separate from credentials:

```text
Primary Scorer
Designated Verifier
Ordinary Player
```

### System actor

Background/system-triggered actions may use an explicit system actor identity where needed for auditability.

Do not silently attribute automated actions to a human user.

---

## 61.3 Accounts & Access actions

| Action | Who | Guards | Side effects / audit |
|---|---|---|---|
| `assign_event_staff_role` | Event Admin | Event not archived; target StaffUser active | Create active EventStaffAssignment; audit |
| `revoke_event_staff_role` | Event Admin | Assignment active; cannot remove final required admin without safe replacement policy | Revoke assignment; audit |
| `issue_player_access` | Event Admin, Competition Manager, Registration Staff | Player belongs to Event | Create secure PlayerAccessGrant |
| `reissue_player_access` | Event Admin, Competition Manager, Registration Staff, Scoring Support | Existing player/event identity confirmed | Supersede/revoke prior active grant as policy requires; issue new token; audit if security-relevant |
| `revoke_player_access` | Event Admin, Competition Manager | Active grant exists | Revoke grant; audit |

### Access policy

- Player token never grants staff/admin actions.
- A player token may span multiple RoundEntries within the same Event.
- Revoked/superseded/expired grants cannot authorize further actions.

---

## 61.4 Golf Catalog actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `create_course` | Event Admin | Valid course identity | Create Course |
| `update_course` | Event Admin | Course not archived | Update reusable catalog only; historical Round snapshots unaffected |
| `archive_course` | Event Admin | No requirement to delete history | Prevent new use; historical references remain |
| `configure_course_hole` | Event Admin | Valid physical hole identity | Create/update CourseHole |
| `configure_tee_set` | Event Admin | Course active | Create/update TeeSet |
| `configure_tee_rating_profile` | Event Admin | Valid Course/TeeSet | Create/update current catalog profile; never rewrite Round snapshots |

### Catalog rule

No edit to Course/Tee catalog may retroactively alter an already snapshotted Round.

---

## 61.5 Event actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `create_event` | Event Admin | — | Event=`draft` |
| `publish_event` | Event Admin | Basic event/player-portal configuration valid | Event=`published`; permit invitations/portal |
| `mark_event_live` | System/Event Admin | At least one Round operational/live | Event=`live` |
| `complete_event` | Event Admin | All required Rounds finalized/cancelled | Event=`completed`; publish final event state |
| `archive_event` | Event Admin | Event completed/cancelled | Event=`archived`; disable ordinary mutation |
| `cancel_event` | Event Admin | Not completed/archived | Event=`cancelled`; cancel dependent future operations/messages as policy requires |

---

## 61.6 Round setup and lifecycle actions

| Action | Who | Guards | Side effects / audit |
|---|---|---|---|
| `create_round` | Event Admin | Event mutable | Round=`draft` |
| `configure_round_layout` | Event Admin, Competition Manager before lock | Round=`draft/ready`; no scoring accepted | Define ordered RoundHoles; MVP requires exactly 18 before ready |
| `snapshot_round_tee_profiles` | Event Admin/Competition Manager | Catalog inputs valid; before scoring open | Create immutable RoundTeeProfileSnapshot + RoundTeeHoleSnapshot |
| `mark_round_ready` | Event Admin, Competition Manager | Opening-gate validation passes | Round=`ready` |
| `open_scoring` | Event Admin, Competition Manager | Round=`ready`; all hard invariants pass | Round=`scoring_open`; lock competition-critical config; broadcast post-commit; audit |
| `close_scoring` | Event Admin, Competition Manager | Round=`scoring_open`; policy allows closure | Round=`scoring_closed`; ordinary new score submission disabled except permitted review/correction paths; audit |
| `finalize_round` | Event Admin or delegated Competition Manager | Round=`scoring_closed`; all required SideResults terminal; no blockers; official tracks reproducible | Round=`finalized`; freeze official results; audit |
| `reopen_round` | Event Admin | Round=`finalized`; mandatory reason | Round returns to controlled review/scoring-closed state; official final flag withdrawn; audit |
| `cancel_round` | Event Admin | Round not finalized | Round=`cancelled`; audit |

### Round opening STOP conditions

`open_scoring` MUST fail if any hard condition is false:

- invalid RoundHole layout;
- duplicate active player RoundEntry;
- missing/invalid tee snapshot;
- unresolved handicap basis;
- invalid PlayingGroup size;
- invalid Side membership for active competition;
- missing starting RoundHole;
- incomplete scoring-track configuration;
- missing/invalid Mystery rule configuration;
- missing tie-break policy;
- competition-critical ambiguity.

Warnings such as missing email or sponsor artwork do not block opening.

---

## 61.7 RoundEntry registration actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `add_round_entry` | Event Admin, Competition Manager | Before scoring open; Player not already entered in Round | RoundEntry registration=`expected`, participation=`not_started` |
| `check_in_round_entry` | Event Admin, Competition Manager, Registration Staff | registration=`expected` | registration=`checked_in`; record actor/time |
| `mark_no_show` | Event Admin, Competition Manager, Registration Staff | before participation starts | registration=`no_show`; remove from starting readiness calculations |
| `withdraw_before_start` | Event Admin, Competition Manager, Registration Staff | participation=`not_started` | registration=`withdrawn_before_start`; not eligible to start |
| `replace_before_start` | Event Admin, Competition Manager | original not active; before scoring/entry start | original=`replaced_before_start`; create NEW RoundEntry for replacement; never mutate player identity |
| `update_round_entry_contact` | Event Admin, Competition Manager, Registration Staff | Event mutable | Update contact/access support data |
| `assign_round_entry_categories` | Event Admin, Competition Manager | Before scoring open | Replace category memberships with validated set |

---

## 61.8 RoundEntry competition-participation actions

| Action | Who | Guards | Side effects / audit |
|---|---|---|---|
| `start_round_entry` | System via accepted first score / explicit round start policy | Round scoring open; entry eligible; tee/handicap/group valid | participation=`active`; freeze ordinary handicap/tee mutation |
| `complete_round_entry` | System | All required holes resolved/not-applicable | participation=`completed` |
| `withdraw_round_entry` | Event Admin, Competition Manager; player/scorer may request | participation=`active`; explicit reason | participation=`withdrawn`; future holes N/A; preserve existing results; recalc dependent Side results; audit |
| `disqualify_round_entry` | Event Admin, Competition Manager | explicit ruling/reason | participation=`disqualified`; preserve scores; evaluate Side eligibility separately; audit |

### DQ policy

`disqualify_round_entry` does **not** automatically call `exclude_competition_side`.

The Competition Manager/Event Admin must separately apply the competition/rules consequence where required.

---

## 61.9 PlayingGroup actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `create_playing_group` | Event Admin, Competition Manager | Before scoring open | Create group |
| `assign_entry_to_group` | Event Admin, Competition Manager; limited Registration Staff pre-start if delegated | Before scoring open; result group size 2–4 | Move RoundEntry; revalidate Side/scoring-role assignments |
| `assign_starting_hole` | Event Admin, Competition Manager | Before scoring open; valid RoundHole | Set group starting RoundHole |
| `mark_group_playing` | System | First accepted group HoleSubmission / explicit start | Group=`playing` |
| `mark_group_finished` | System | All active entries completed/terminal and required outcomes resolved | Group=`finished_playing` |
| `flag_group_attention` | System/Scoring Support/Competition Manager | Operational issue exists | Group=`attention_required`; expose blocker |
| `clear_group_attention` | System/authorized staff | Blocker resolved | Return to `playing` or `finished_playing` as derived |

### Group boundary

No `finalize_group` action exists. Official finalization belongs to each `CompetitionSideResult`.

---

## 61.10 CompetitionSide actions

| Action | Who | Guards | Side effects / audit |
|---|---|---|---|
| `create_competition_side` | Event Admin, Competition Manager | Before scoring open; valid RoundCompetition | Create Side |
| `set_side_membership` | Event Admin, Competition Manager | Before scoring open; active competition policy validates member count | Replace Side memberships; audit if after Round ready |
| `exclude_competition_side` | Event Admin, Competition Manager | Explicit competition/rules reason | SideResult=`excluded`; preserve all raw scoring history; audit |
| `mark_side_ready_to_finalize` | System | All guards satisfied | SideResult=`ready_to_finalize` |
| `finalize_side_result` | Event Admin, Competition Manager | SideResult=`ready_to_finalize`; Round not finalized | SideResult=`finalized`; audit |
| `reopen_side_result` | Event Admin; Competition Manager if delegated | SideResult=`finalized`; Round NOT finalized; mandatory reason | SideResult=`review_required`; invalidate official readiness; audit |

### Side-size rule

`CompetitionSide` itself is not globally restricted to one or two members.

The active V1 `four_ball_stableford_v1` policy enforces:

```text
partnership = exactly 2 starting members
solo        = exactly 1 starting member
```

Future competition policies may enforce other sizes.

---

## 61.11 Scoring-role actions

| Action | Who | Guards | Side effects / audit |
|---|---|---|---|
| `assign_primary_scorer` | Event Admin, Competition Manager; self-selection pre-start if permitted | Actor belongs to PlayingGroup; no other active primary | Create active GroupRoleAssignment |
| `assign_designated_verifier` | Event Admin, Competition Manager; group selection pre-start if permitted | Actor belongs to group; preferably different from primary | Create active GroupRoleAssignment |
| `handover_primary_scorer` | Event Admin, Competition Manager, Scoring Support | Existing assignment active; replacement eligible | Old assignment=`handed_over`; create new active; increment role-assignment version; audit |
| `handover_designated_verifier` | Event Admin, Competition Manager, Scoring Support | Same | Same; audit |

### Role safety

Role handover never changes CompetitionSide membership.

Offline submissions from a stale prior scorer must fail optimistic/role-version validation rather than overwrite newer state.

---

## 61.12 Tee and handicap actions

| Action | Who | Guards | Side effects / audit |
|---|---|---|---|
| `assign_round_tee` | Event Admin, Competition Manager; limited Registration Staff pre-open if delegated | Before entry active | Associate RoundEntry with valid RoundTeeProfileSnapshot |
| `confirm_handicap_input` | Player pre-start; Event Admin/Competition Manager | RoundEntry not active | Record declared/preloaded basis provenance |
| `apply_no_hi_policy` | Event Admin, Competition Manager | Player has no official HI; RoundEntry not active | Store deemed basis (default 14.0 men / 20.0 women unless explicit committee override) |
| `override_handicap_basis` | Event Admin, Competition Manager | Mandatory reason; before active OR exceptional correction | Audit; recalc HandicapSnapshot/CompetitionHandicap and dependent scoring as guarded |
| `build_handicap_snapshot` | System | Tee profile + handicap basis valid | Freeze base Course Handicap inputs |
| `build_competition_handicap` | System | HandicapSnapshot + RoundCompetition locked | Derive allowance/Playing Handicap |

### Post-start tee/handicap correction

If no accepted HoleResult exists, Event Admin/Competition Manager may correct with audit.

If scoring already exists, ordinary correction is blocked; use an exceptional reviewed correction path that recalculates dependent results, supersedes affected verification, and refreshes leaderboard reads.

---

## 61.13 RoundCompetition / ScoringTrack actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `configure_round_competition` | Event Admin, Competition Manager | Round=`draft/ready` | Configure concrete policy/version, allowance, solo normalization |
| `configure_scoring_track` | Event Admin, Competition Manager | Before scoring open | Create Standard/Mystery track; set primary/visibility/tie-break |
| `configure_mystery_hole_rule` | Event Admin, Competition Manager | Before scoring open; track supports Mystery | Set `best/worst/both` for target RoundHole |
| `lock_competition_configuration` | System via `open_scoring` | opening gate passes | Immutable ordinary config for Round |
| `reveal_mystery_rule` | System only | Group's accepted complete HoleSubmission for that Mystery RoundHole | Create/transition MysteryReveal; expose completed rule; post-commit broadcast |

### Mystery secrecy STOP condition

No player-facing read/action may return an unrevealed future Mystery rule, including hidden fields, JSON payloads, LiveView assigns, offline cache, or preloaded client state.

---

## 61.14 Hole scoring actions

### `submit_group_hole`

**Actor:** active Primary Scorer (or authorized competition staff emergency entry).

**Input concept:**

```text
client_submission_id
playing_group_id
round_hole_id
expected_group_score_revision
role_assignment_version
results for every currently-required active player
captured_at
```

**Guards:**

- Round=`scoring_open`;
- group actor is current Primary Scorer, unless staff emergency authority;
- correct logical current/queued RoundHole for the group;
- all required active players have a valid `holed_out` or allowed `picked_up` outcome;
- no unexplained blank;
- group membership/role revision current;
- idempotency key valid;
- optimistic revision current;
- competition policy validates pickup/result semantics.

**Atomic side effects:**

1. create immutable accepted HoleSubmission receipt;
2. create/update each required HoleResult revision atomically;
3. mark previous verification superseded where an amended result is involved;
4. advance operational group progress;
5. if Mystery hole, create group-specific MysteryReveal eligibility/reveal;
6. derive any new completion/readiness states;
7. commit;
8. **after commit only**, broadcast PubSub invalidation/update signals and enqueue external message deliveries as required.

**Failure behavior:**

- duplicate accepted idempotency key => return prior accepted result;
- stale revision/role => explicit conflict;
- invalid result set => reject entire hole; no partial write.

### `correct_hole_result`

**Actors:** Competition Manager/Event Admin; Primary Scorer only where allowed by current review workflow.

**Guards:** recorded HoleResult exists; reason required after submission/reveal; Round not finalized unless reopened.

**Side effects:** create ScoreRevision/new HoleResult revision; supersede old verification; recalc derived scoring; audit; post-commit PubSub.

---

## 61.15 Verification/query actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `verify_hole_result` | Eligible player marker/verifier | Cannot verify own result; current revision only | ScoreVerification=`verified` for exact revision |
| `override_hole_verification` | Event Admin, Competition Manager | Genuine exception; mandatory reason | ScoreVerification=`overridden`; audit |
| `query_hole_result` | Designated Verifier; player for own result; Competition Manager/Event Admin | Current HoleResult exists; query not already resolved | Create ScoreQuery=`open`; SideResult becomes/remains `review_required` if competition-impacting |
| `escalate_score_query` | Primary/Verifier/Competition staff | Query=`open` | Query=`escalated`; expose admin attention |
| `resolve_score_query_no_change` | Competition Manager/Event Admin or authorized scorer/verifier agreement | Query open/escalated; current score accepted | Query=`resolved`; retain current result; verification still required where applicable |
| `resolve_score_query_with_correction` | Competition Manager/Event Admin or allowed scorer flow | Query open/escalated; reason/target value valid | Correct HoleResult via ScoreRevision; query=`resolved`; new revision requires fresh verification |
| `dismiss_score_query` | Competition Manager/Event Admin | Explicit reason | Query=`dismissed`; audit |

### Verification invariant

Every **current competition-relevant HoleResult revision** must have one valid independent verification or explicit organiser override before affected SideResult can become ready to finalize.

---

## 61.16 Side-result readiness and leaderboard reads

### Read model

V1 does not persist a second authoritative leaderboard state.

Leaderboard query:

```text
current HoleResults
+ CompetitionHandicaps
+ RoundCompetition policy
+ ScoringTrack policy
+ locked Mystery rules/reveal eligibility
+ tie-break policy
→ current standings
```

### Status

- while Round not finalized => `provisional` standings;
- after Round finalized => `official/final` standings.

### Update path

Score transaction commits first, then Phoenix PubSub tells subscribed LiveViews/clients to re-read the deterministic standings.

No polling required.

---

## 61.17 Messaging actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `create_event_message` | Event Admin, Competition Manager | Event mutable | Message=`draft` |
| `arm_event_message` | Event Admin, Competition Manager | Trigger/audience/delivery valid | Message=`armed` |
| `schedule_event_message` | Event Admin, Competition Manager | Valid future schedule | Message=`scheduled` |
| `cancel_event_message` | Event Admin, Competition Manager | Not closed/cancelled | Message=`cancelled` |
| `trigger_manual_dispatch` | Event Admin, Competition Manager | Message permits manual use | Create idempotent MessageDispatch |
| `trigger_workflow_dispatch` | System | Deterministic workflow event + trigger rule match | Create idempotent MessageDispatch |
| `deliver_message` | System async worker/adapter | Dispatch pending; channel configured | Create/update MessageDelivery; never inside scoring transaction |
| `acknowledge_in_app_message` | Player | Delivery requires/permits acknowledgement | Mark delivery acknowledged |

### Deterministic workflow triggers

V1:

```text
round_started
hole_completed
next_hole_ready
holes_completed
holes_remaining
round_completed
manual
scheduled_time
```

No fake `physical_hole_reached` trigger without an actual location/arrival signal.

---

## 61.18 Sponsorship actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `create_sponsor` | Event Admin | Valid safe structured content | Sponsor active |
| `update_sponsor` | Event Admin | Sponsor not archived | Update reusable content |
| `archive_sponsor` | Event Admin | — | Prevent new placement; history remains |
| `create_sponsor_placement` | Event Admin | Valid event/hole/side-competition scope | Placement=`draft/published` |
| `publish_sponsor_placement` | Event Admin | Safe content/assets | Placement=`published` |
| `archive_sponsor_placement` | Event Admin | — | Placement=`archived` |

Sponsor failure never blocks scoring.

---

## 61.19 SideCompetition actions

| Action | Who | Guards | Side effects |
|---|---|---|---|
| `create_side_competition` | Event Admin, Competition Manager | Round mutable | SideCompetition=`draft` |
| `arm_side_competition` | Event Admin, Competition Manager | type/hole/eligibility valid | `armed` |
| `open_side_competition` | System/Event Admin | Round active | `open` |
| `close_side_competition` | Event Admin, Competition Manager/System | Round/competition ended | `closed` |
| `record_side_competition_result` | Event Admin, Competition Manager | Physical board/result available | Result=`draft` |
| `verify_side_competition_result` | Event Admin, Competition Manager | Winner/result checked | Result=`verified` |
| `finalize_side_competition_result` | Event Admin, Competition Manager | Result verified | Result=`finalized`; SideCompetition may finalize |
| `cancel_side_competition` | Event Admin, Competition Manager | Not finalized | `cancelled` |

Player-side distance entry is not V1.

---

## 61.20 Audit requirements

The following actions MUST create structured AuditEvents:

- staff role assignment/revocation;
- access revoke/reissue where security-relevant;
- Round open/close/finalize/reopen;
- handicap/tee exceptional correction;
- Side membership correction after Round ready;
- scorer/verifier handover during play;
- withdrawal/DQ/Side exclusion;
- submitted score correction;
- score-query resolution/dismissal;
- verification override;
- Side result finalize/reopen;
- locked config override;
- event-wide manual broadcast;
- Round finalization.

Audit rows should identify:

```text
actor type + FK
resource/action
event/round context
before/after or structured change reference
reason where required
timestamp
```

---

# 62. Authoritative State-Transition Tables

## 62.1 Event

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | `create_event` | `draft` | — | Create event | No |
| `draft` | `publish_event` | `published` | Portal-ready config | Permit player invitations/portal | No |
| `published` | `mark_event_live` | `live` | Round operational | Live event status | No |
| `live` | `complete_event` | `completed` | All required Rounds finalized/cancelled | Final event state | No |
| `completed` | `archive_event` | `archived` | — | Disable ordinary mutation | **Yes** |
| `draft/published` | `cancel_event` | `cancelled` | Not completed | Cancel future operation/messages as policy | **Yes** |

---

## 62.2 Round

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | `create_round` | `draft` | — | Create Round | No |
| `draft` | `mark_round_ready` | `ready` | Opening-gate validation | Mark operationally ready | No |
| `ready` | `open_scoring` | `scoring_open` | All hard invariants valid | Lock competition config/snapshots; post-commit broadcast | No |
| `scoring_open` | `close_scoring` | `scoring_closed` | Authorized closure | Stop ordinary new submissions | No |
| `scoring_closed` | `finalize_round` | `finalized` | All SideResults terminal/resolved; no blockers | Official result lock; audit | Normally yes |
| `finalized` | `reopen_round` | `scoring_closed` | Event Admin + reason | Withdraw final status; allow controlled review | No |
| `draft/ready` | `cancel_round` | `cancelled` | Not finalized | Cancel Round | **Yes** |

`finalized` is protected, not irreversible.

---

## 62.3 RoundEntry registration

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | `add_round_entry` | `expected` | Unique Player/Round | Create entry | No |
| `expected` | `check_in_round_entry` | `checked_in` | Player present | Record check-in | No |
| `expected/checked_in` | `withdraw_before_start` | `withdrawn_before_start` | Participation not active | Remove from start readiness | **Yes** for registration/start |
| `expected/checked_in` | `mark_no_show` | `no_show` | Before start | Remove from start readiness | **Yes** |
| `expected/checked_in` | `replace_before_start` | `replaced_before_start` | Before active | Create separate replacement RoundEntry | **Yes** |

`checked_in` does not mean competitive play has started.

---

## 62.4 RoundEntry participation

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| `not_started` | `start_round_entry` | `active` | Round open; eligible; tee/handicap/group valid | Freeze ordinary tee/handicap mutation | No |
| `active` | `complete_round_entry` | `completed` | All required holes resolved/N/A | Complete player round | **Yes** |
| `active` | `withdraw_round_entry` | `withdrawn` | Reason | Future holes N/A; recalc Side | **Yes** |
| `active` | `disqualify_round_entry` | `disqualified` | Explicit ruling/reason | Preserve scores; Side consequence separate | **Yes** |

---

## 62.5 PlayingGroup operational state

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| `not_started` | first accepted hole/start | `playing` | Round open | Group active | No |
| `playing` | `flag_group_attention` | `attention_required` | Operational blocker | Admin/support visibility | No |
| `attention_required` | `clear_group_attention` | `playing` or `finished_playing` | Blocker resolved | Derived return state | No |
| `playing` | `mark_group_finished` | `finished_playing` | All active entries complete/terminal | End physical play | **Yes operationally** |

No competition-finalization state exists here.

---

## 62.6 CompetitionSideResult

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| `provisional` | blocker detected | `review_required` | Query/verification/eligibility blocker | Expose review reason | No |
| `review_required` | blockers cleared | `ready_to_finalize` | Full readiness guards pass | Mark ready | No |
| `provisional` | readiness evaluation | `ready_to_finalize` | Full readiness guards pass | Mark ready | No |
| `ready_to_finalize` | `finalize_side_result` | `finalized` | Round not finalized; actor authorized | Protect ordinary mutation; audit | Normally yes |
| `finalized` | `reopen_side_result` | `review_required` | Round NOT finalized; reason | Withdraw Side final status; audit | No |
| `provisional/review_required` | `exclude_competition_side` | `excluded` | Explicit competition/rules decision | Remove from eligible placing; preserve history | **Yes** |

Once Round is finalized, SideResult cannot reopen until `reopen_round`.

---

## 62.7 Scorecard

| From | Trigger | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| `not_started` | first accepted HoleResult | `in_progress` | — | — | No |
| `in_progress` | all required results resolved | `complete` | Participation accounted for | — | No |
| `in_progress/complete` | blocking query/integrity issue | `review_required` | — | Surface blocker | No |
| `review_required` | blocker resolved, still complete | `complete` | — | — | No |
| `complete` | all current revisions independently verified/overridden | `verified` | No open blocking query | Enables Side readiness | **Yes for scorecard verification** |
| `verified` | HoleResult amended | `review_required/complete` | New revision exists | Prior verification superseded | No |

Scorecard has no competition `finalized` state.

---

## 62.8 HoleResult

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | accepted `submit_group_hole` | `recorded` revision N | Valid resolved outcome | Create current revision | No |
| `recorded` | `correct_hole_result` | `recorded` revision N+1 | Authorized + reason | Create ScoreRevision; supersede old verification | No |

`holed_out` / `picked_up` are result outcomes, not lifecycle states.

---

## 62.9 ScoreVerification

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | verification required | `pending` | Current HoleResult revision exists | — | No |
| `pending` | `verify_hole_result` | `verified` | Independent eligible verifier; exact current revision | Certification | Yes for that revision |
| `pending` | `override_hole_verification` | `overridden` | Authorized staff + reason | Audit exception | Yes for that revision |
| `verified/overridden` | HoleResult amended | `superseded` | Certified revision no longer current | New pending verification created | **Yes** |

---

## 62.10 ScoreQuery

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | `query_hole_result` | `open` | Current HoleResult | Block affected readiness | No |
| `open` | `escalate_score_query` | `escalated` | — | Admin attention | No |
| `open/escalated` | resolve accepted/no change | `resolved` | Decision recorded | Unblock if verification complete | **Yes** |
| `open/escalated` | resolve with correction | `resolved` | Correction accepted | New HoleResult revision; fresh verification required | **Yes** |
| `open/escalated` | `dismiss_score_query` | `dismissed` | Staff reason | Audit | **Yes** |

---

## 62.11 PlayerAccessGrant

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | `issue_player_access` | `active` | Valid Event/Player | Issue secure token | No |
| `active` | `reissue_player_access` | `superseded` | Identity confirmed | New active grant created | **Yes** |
| `active` | `revoke_player_access` | `revoked` | Authorized staff | Token invalid | **Yes** |
| `active` | expiry policy | `expired` | Expiry reached | Token invalid | **Yes** |

---

## 62.12 GroupRoleAssignment

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | assign role | `active` | Eligible group member; unique active role | Increment assignment/version context | No |
| `active` | handover | `handed_over` | Replacement eligible | Create new active assignment; audit | **Yes** |
| `active` | revoke | `revoked` | Authorized reason | No active holder until replacement | **Yes** |

---

## 62.13 MysteryReveal

| From | Trigger | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| `hidden` | accepted group HoleSubmission | `revealed` | Matching MysteryHoleRule + complete accepted submission | Expose rule/result; post-commit broadcast | **Yes** |

No transition back to hidden.

---

## 62.14 EventMessage

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | create | `draft` | — | — | No |
| `draft` | arm | `armed` | Valid trigger/audience/delivery | Eligible for workflow trigger | No |
| `draft` | schedule | `scheduled` | Valid schedule | Eligible at time | No |
| `armed/scheduled` | close | `closed` | No more dispatches desired | Disable future dispatch creation | **Yes** |
| `draft/armed/scheduled` | cancel | `cancelled` | — | Disable future dispatch creation | **Yes** |

A message may produce many MessageDispatch records while armed/scheduled.

---

## 62.15 MessageDispatch

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | deterministic trigger/manual send | `pending` | Unique trigger identity | Create recipient deliveries | No |
| `pending` | delivery processing | `dispatching` | — | Async channel sends | No |
| `dispatching` | all required deliveries terminal-success/acceptable | `completed` | — | — | **Yes** |
| `dispatching` | mixed success/failure | `partially_completed` | Retry policy may remain | Surface status | Maybe |
| `pending/dispatching` | unrecoverable failure | `failed` | — | Surface organizer status | **Yes** |

---

## 62.16 SideCompetition

| From | Action | To | Guard | Side effects | Terminal? |
|---|---|---|---|---|---|
| — | create | `draft` | — | — | No |
| `draft` | arm | `armed` | Type/hole/eligibility valid | Ready | No |
| `armed` | open | `open` | Round active | Challenge live | No |
| `open` | close | `closed` | Challenge complete | Stop new competition activity | No |
| `closed` | finalize result | `finalized` | Verified result exists | Official side prize | **Yes** |
| `draft/armed/open` | cancel | `cancelled` | Not finalized | Cancel challenge | **Yes** |

---

## 62.17 StaffUser / EventStaffAssignment

### StaffUser

```text
active ↔ suspended
active/suspended → disabled
```

`disabled` is terminal for ordinary auth.

### EventStaffAssignment

```text
active → revoked
```

`revoked` is terminal; create a new assignment if authority is restored.

---

# 63. Domain Action/State Review — Success Criteria

This stage is accepted only if all of the following remain true during implementation planning:

1. no competition-critical mutation requires generic unrestricted CRUD;
2. every lifecycle transition has one named action/trigger;
3. actor authority is enforceable at the action boundary;
4. no state is duplicated across two resources as competing sources of truth;
5. correction actions preserve immutable history rather than rewriting evidence;
6. post-commit side effects cannot cause the authoritative score transaction to fail after commit;
7. future formats can add concrete policies without changing raw score/resource meaning;
8. V1 remains small enough to deliver without enterprise framework work.

### STOP condition

Do **not** create implementation phases, TOON prompts, or `/wayfinder` tickets yet.

Next mandatory review:

```text
Security
Concurrency
Data integrity
Offline conflict integrity
Mystery secrecy
Messaging idempotency
Authorization bypass risk
```

Only after that review passes should the Product + Domain Spec be frozen as v1.0 for local `/wayfinder` repository reconciliation.

# 64. Final Security, Concurrency, and Data-Integrity Pressure Test

### Status

**PASS WITH REQUIRED HARDENING RULES.**

The accepted domain model does not require enterprise infrastructure, but several integrity rules must be made explicit before implementation planning. Sections 64–65 override any earlier statement that conflicts with these hardening rules.

The chosen V1 strategy is:

```text
Postgres transactions + row locks
+ explicit revisions
+ idempotency keys
+ server-side authorization
+ durable local message intents
+ post-commit PubSub / async delivery
```

Do **not** add distributed locks, event sourcing, Redis coordination, or a generic event bus for the MVP.

---

## 64.1 Player Access-Link Security

### Finding

A personal event link is effectively a credential. Leaving the credential in the browser URL creates a real leak risk when the player clicks a sponsor/external link because browser referrer information may expose the source URL.

### Required V1 pattern

The personal link must use a high-entropy opaque token and behave conceptually as:

```text
/open/<opaque-token>
        ↓
server validates token
        ↓
create event-scoped player session
        ↓
redirect immediately to token-free URL
        ↓
/event/<public-id>/...
```

### Requirements

- store only a cryptographic digest/hash of the opaque token where practical;
- tokens must be unguessable and never sequential;
- one active grant per Event + Player is preferred for V1;
- reissue supersedes/revokes the prior active grant;
- revoked/superseded/expired grants cannot create new sessions;
- existing sessions must be revocable when security/support requires it;
- player session capability is resolved server-side from current RoundEntry and role state;
- player URLs must never encode authorization by predictable database ID alone.

### External links

Sponsor/external links must use a no-referrer policy (`noreferrer` / equivalent response policy) so event/player URL context is not leaked externally.

### Privacy boundary

Player-facing/public views may expose competition-relevant display information only.

Never expose another player's:

- email;
- mobile number;
- access token/grant;
- private staff/support notes.

Leaderboard display fields should be explicit configuration, not accidental schema serialization.

---

## 64.2 Server-Side Authorization Is Mandatory

UI hiding is not authorization.

Every mutation re-resolves the actor's current authority on the server at execution time.

### Player actions

A scoring request must derive, not trust from client payload:

- Event;
- Player/RoundEntry identity;
- current PlayingGroup;
- current active GroupRoleAssignment;
- Round state;
- requested capability.

The client must never be able to become scorer/verifier by sending a role name or another RoundEntry ID.

### Staff actions

Every staff mutation requires:

```text
StaffUser
+ active EventStaffAssignment
+ role policy
+ lifecycle guard
```

Admin routes/actions are never authorized by PlayerAccessGrant.

### Mystery authorization

Before reveal, hidden Mystery rules may be read only by the minimum staff roles that operationally require them:

```text
event_admin
competition_manager
```

Registration Staff, Scoring Support, ordinary players, scorer/verifier clients, public leaderboard clients, and sponsor surfaces must not receive unrevealed rule data.

---

## 64.3 Scorer/Verifier Handover Must Invalidate Stale Devices

### Finding

A HoleResult revision check alone is insufficient.

Example:

```text
Phone A = Primary Scorer, goes offline before Hole 10
Phone B = receives scorer handover
Phone B scores Hole 10–12
Phone A later reconnects with queued Hole 13
```

If Hole 13 had never been written, a pure HoleResult revision check could allow the stale Phone A submission even though that device no longer has scoring authority.

### Required rule

Every score submission/verification command must identify the **specific active GroupRoleAssignment** under which it was captured.

At acceptance time the server verifies that assignment is still active and belongs to the acting RoundEntry.

A handover:

1. revokes/ends the old active assignment;
2. creates the new active assignment;
3. causes queued commands tied to the old assignment to fail with `stale_authority` rather than being silently accepted.

### Database constraint

Use a partial/conditional unique constraint so there can be at most:

```text
1 active primary_scorer per PlayingGroup
1 active designated_verifier per PlayingGroup
```

The Primary Scorer and Designated Verifier must be different active RoundEntries in V1.

---

## 64.4 Atomic Hole-Submission Transaction

Each accepted group hole submission must be one transaction.

### Recommended transaction order

Conceptually:

```text
BEGIN

1. authorize current actor + active scorer assignment
2. lock PlayingGroup scoring row/state FOR UPDATE
3. verify Round == scoring_open
4. resolve group's expected next RoundHole
5. check idempotency key
6. check expected group scoring revision
7. validate every required active-player outcome
8. write/revise all affected HoleResults atomically
9. write immutable HoleSubmission receipt
10. advance group scoring sequence/revision
11. create any deterministic local MessageDispatch intents
12. create MysteryReveal when eligibility is satisfied

COMMIT

13. PubSub broadcast
14. async external-message processing
```

No external HTTP/API call occurs inside this transaction.

### Why lock PlayingGroup

The group is the natural serialization boundary for normal score capture: only one hole is submitted at a time for that group.

This avoids global/database-wide serialization while preventing two devices from concurrently advancing the same group.

---

## 64.5 Idempotency Must Detect Key Reuse With Different Payloads

`client_submission_id` is not enough by itself.

Store or derive a stable payload fingerprint for the accepted command.

Rules:

```text
same idempotency key + same logical payload
→ return prior result / success

same idempotency key + different payload
→ reject as idempotency misuse / integrity error
```

Never reinterpret a reused key as a correction.

Corrections use the explicit audited correction action.

---

## 64.6 Offline Queue Ordering

A group's offline queue is synchronized in the group's **logical playing order**, not arbitrary network arrival order.

### Required behavior

- client sends pending hole submissions in sequence;
- server verifies the requested RoundHole is the next valid progression step for ordinary scoring;
- if an earlier queued hole conflicts/rejects, later queued holes stop syncing until the conflict is resolved;
- correction workflows are separate and may address an earlier hole without rewinding normal progression.

This prevents an offline client from creating unexplained gaps such as Hole 9 accepted while Hole 8 is unresolved.

### Client trust boundary

IndexedDB/local queue contents are untrusted input.

The server revalidates:

- identity;
- role authority;
- Round state;
- group membership;
- hole sequence;
- score/outcome validity;
- revision;
- idempotency.

Client `captured_at` is useful evidence but never authoritative ordering/security truth.

---

## 64.7 Verification Race Safety

Verification certifies **one exact HoleResult revision**.

### Required acceptance guard

The verification action must confirm in one transaction that:

```text
requested_revision == current_hole_result_revision
```

and that the verifier is currently eligible and is not the player whose result is being verified.

### Concurrent correction case

If:

```text
Verifier views revision 3
Scorer corrects result → revision 4
Verifier submits verification for revision 3
```

then revision-3 verification may remain historical evidence but **must not satisfy current finalization**.

Revision 4 requires fresh verification.

### Query race

Creating/resolving ScoreQuery and amending HoleResult must use expected revisions so a stale query resolution cannot overwrite a newer correction.

---

## 64.8 Handicap Corrections Do Not Rewrite Golf Facts

A post-start handicap correction affects derived competition calculations, not the player's raw HoleResult.

### Required behavior

When HandicapSnapshot / CompetitionHandicap is exceptionally corrected after play begins:

- preserve all raw gross/pickup HoleResults;
- record audit/revision evidence for the handicap correction;
- recompute affected individual Stableford points;
- recompute Standard/Mystery Side results and leaderboard reads;
- move any affected finalized Side back through the required reopen/review path.

Raw-score verification remains valid because it certifies the golf result, not the calculated points.

### Tee correction is stricter

Changing tee/rating context after any accepted HoleResult is **not** an ordinary correction because it can change:

- par;
- stroke index;
- handicap allocation;
- pickup validity.

Required rule:

```text
no accepted HoleResult
→ audited organiser tee correction permitted

accepted HoleResult exists
→ block ordinary action
→ require exceptional Event Admin repair/ruling workflow
```

That repair must re-evaluate every existing hole outcome. Any `picked_up` result whose validity becomes uncertain enters `review_required`; it is not silently accepted under the new tee context.

---

## 64.9 Mystery Rule Secrecy and Post-Reveal Immutability

### Server secrecy

Before reveal eligibility, unrevealed Mystery information must not appear in:

- rendered HTML;
- LiveView assigns sent to the client;
- JSON/API payloads;
- IndexedDB/localStorage;
- client JavaScript configuration;
- public leaderboard payloads;
- predictable resource endpoints that expose rule content.

Authorization must fail server-side.

### Rule mutation after scoring opens

Ordinary mutation is prohibited after `Round.scoring_open`.

Exceptional Event Admin repair before **any group has revealed the affected rule** may be allowed only through an explicit audited locked-configuration repair action.

Once any PlayingGroup has revealed a Mystery rule for that RoundHole:

> **STOP: the rule cannot be silently changed.**

A material mistake then requires an explicit competition ruling (for example excluding/neutralizing that Mystery hole for everyone) recorded as an audited competition amendment. Do not rewrite history for only some groups.

This protects competitive fairness.

---

## 64.10 Finalization Must Recheck Guards Under Lock

Never implement finalization as:

```text
if ready?(side), do: update(side, finalized: true)
```

where `ready?` was calculated outside the final transaction.

### Side finalization

In one transaction:

1. lock CompetitionSideResult;
2. re-read current member/score/query/verification state;
3. ensure every required current HoleResult revision is verified/overridden;
4. ensure no open ScoreQuery can affect the Side;
5. ensure eligibility remains valid;
6. set `finalized`.

### Round finalization

In one transaction:

1. lock Round;
2. ensure every required CompetitionSideResult is terminal (`finalized` or explicit `excluded`);
3. ensure no blocking review/query remains;
4. ensure official ScoringTracks are reproducible;
5. set Round `finalized`.

No score/side mutation action is authorized while Round remains finalized.

This prevents finalization racing with a last-second query or correction.

---

## 64.11 Prizegiving Readiness Must Include Required Side Competitions

The accepted derived readiness rule is extended to include configured prize challenges.

Conceptually:

```text
PRIZEGIVING_READY =
  round finalized
  AND official leaderboard/tie-break complete
  AND no unresolved competition review
  AND every SideCompetition marked prizegiving_required is finalized
```

Closest-to-Pin / Longest-Drive competitions that are not yet finalized should therefore appear as explicit prizegiving blockers when configured as prize-bearing event results.

---

## 64.12 Messaging Idempotency and Durable Delivery

### Durable intent, async delivery

Triggered score/progress actions may create the local `MessageDispatch` intent as part of the authoritative database transaction because this is only a local durable write.

External delivery happens after commit through a durable background mechanism.

For Phoenix/Elixir, **Oban is the preferred V1 implementation mechanism** for WhatsApp/email delivery jobs if a durable job queue is needed.

Do not use fire-and-forget process tasks as the only delivery guarantee.

### Uniqueness

At minimum enforce:

```text
MessageDispatch
UNIQUE(event_message_id, trigger_identity)

MessageDelivery
UNIQUE(message_dispatch_id, recipient_identity, channel)
```

A retry of scoring, PubSub, or job processing must not create duplicate external messages.

A deliberate second manual broadcast creates a new explicit dispatch identity and is therefore allowed.

---

## 64.13 PubSub Is Notification, Not Authority

Phoenix PubSub is used to tell connected clients:

> authoritative data changed; read/recompute current state.

Do not treat a PubSub event as the durable record of a score, reveal, message, or finalization.

### Required order

```text
DB transaction commits
        ↓
PubSub broadcast
```

Never broadcast a success state before the transaction is known to have committed.

If PubSub delivery is missed, reconnecting clients recover from Postgres.

---

## 64.14 Public/Player Data Exposure

### Player group view

Players may see the accepted competition data for their PlayingGroup, but private profile/contact fields remain excluded.

### Public leaderboard

Default public payload should contain only what the event needs, for example:

- display name / team name;
- points;
- position;
- holes completed;
- revealed Mystery impact where enabled.

Do not serialize entire Player/RoundEntry records into public responses.

### Staff-only fields

Examples that remain staff-only unless a concrete reason says otherwise:

- email/mobile;
- access-grant state;
- audit notes;
- staff support notes;
- unrevealed Mystery rules;
- provider delivery metadata.

---

## 64.15 Web Security Baseline

Use Phoenix/framework security mechanisms rather than custom crypto/session code.

Required baseline:

- secure, HttpOnly session cookies where applicable;
- appropriate SameSite policy;
- CSRF protection on state-changing browser actions;
- signed/authenticated LiveView session context;
- no client-trusted role/permission fields;
- safe structured sponsor/message content, not arbitrary HTML/JS;
- URL scheme allowlist for sponsor links (`https` preferred; reject script/data schemes);
- basic rate limiting on repeated invalid staff-login/access-token redemption attempts if abuse is observed or easy to add without complexity.

MFA is **not mandatory for V1** unless the chosen staff authentication provider already supports it cheaply.

---

## 64.16 Database Constraints Required for Integrity

In addition to earlier uniqueness/index intent, the implementation should enforce where practical:

```text
PlayerAccessGrant
UNIQUE active grant per (event_id, player_id)
UNIQUE token_digest

CompetitionSideResult
UNIQUE(competition_side_id)

GroupRoleAssignment
UNIQUE active (playing_group_id, role)

CompetitionSideMembership
UNIQUE(round_competition_id, round_entry_id)

CompetitionHandicap
UNIQUE(round_entry_id, round_competition_id)

HoleResult
UNIQUE(scorecard_id, round_hole_id)
CHECK outcome/gross-strokes consistency

HoleSubmission
UNIQUE(client_submission_id)
store payload_fingerprint

ScoreQuery
at most one open query per current HoleResult revision where practical

MysteryHoleRule
UNIQUE(scoring_track_id, round_hole_id)

MysteryReveal
UNIQUE(mystery_hole_rule_id, playing_group_id)

MessageDispatch
UNIQUE(event_message_id, trigger_identity)

MessageDelivery
UNIQUE(message_dispatch_id, recipient_identity, channel)
```

### HoleResult checks

Conceptually:

```text
outcome = holed_out
→ gross_strokes IS NOT NULL AND gross_strokes >= 1

outcome = picked_up
→ gross_strokes IS NULL
```

Do not depend only on LiveView validation for these invariants.

---

## 64.17 Concurrency Strategy — Explicit Non-Goals

At MVP scale, do **not** introduce:

- Redis distributed locks;
- Redlock;
- global serializable isolation;
- event sourcing;
- Kafka/general event bus;
- custom distributed consensus;
- multi-node in-memory ownership of authoritative score state.

Postgres remains authoritative.

Use short row-level locks only for narrow critical transitions such as:

- group hole submission;
- scorer/verifier handover;
- Side finalization;
- Round finalization;
- exceptional competition configuration repair.

This remains safe if Phoenix later runs on multiple nodes because lock/revision authority is in Postgres, not local process memory.

---

## 64.18 Security/Integrity Test Matrix — Mandatory

Before production use, implementation must have tests covering at minimum:

### Authorization

- ordinary player cannot submit group scores unless current Primary Scorer;
- ordinary player cannot verify someone else's score unless authorized verifier role;
- nobody can verify their own HoleResult;
- Registration Staff cannot change Mystery rules/finalize results;
- Scoring Support cannot silently correct scores;
- player token cannot access admin actions;
- unrevealed Mystery rules are absent from player/public payloads.

### Concurrency

- simultaneous submissions for same group/hole result in one accepted progression;
- reused idempotency key with identical payload is safe;
- reused idempotency key with different payload is rejected;
- scorer handover rejects old offline scorer queue;
- stale verification cannot verify newer score revision;
- query/correction race cannot lose latest data;
- finalization racing with new query/correction cannot finalize invalid state.

### Offline

- queued holes sync in logical order;
- first conflict stops later queue progression;
- refresh/reconnect does not duplicate submissions;
- revoked access/role prevents stale offline acceptance;
- no future Mystery rule exists in offline storage.

### Finalization

- Side with open query cannot finalize;
- Round with unfinalized required Side cannot finalize;
- finalized Round blocks underlying ordinary mutations;
- reopen workflow preserves audit history;
- prizegiving readiness remains false when required side competition is unfinished.

### Messaging

- score retry does not duplicate MessageDispatch;
- delivery retry does not duplicate MessageDelivery record;
- external provider failure cannot roll back score;
- missed PubSub can recover from database state.

### Privacy/security

- access token removed from post-redemption browser URL;
- sponsor external navigation does not leak credential URL/referrer;
- public leaderboard excludes contact/token/audit fields;
- revoked/superseded access grant cannot establish a new session.

---

## 64.19 Final Pressure-Test Verdict

### Security

**PASS** with the access-link/session, server-policy, secrecy, and privacy rules above.

### Concurrency

**PASS** using Postgres row-level serialization at the PlayingGroup/Side/Round boundaries plus optimistic revisions and role-assignment validation.

### Offline integrity

**PASS** with ordered queue replay, role-authority checks, idempotency, and explicit conflicts.

### Mystery integrity

**PASS** with server-only unrevealed data and post-reveal immutability/competition-amendment rules.

### Messaging integrity

**PASS** with deterministic MessageDispatch idempotency and durable post-commit delivery.

### Data integrity

**PASS** provided database uniqueness/check constraints back the critical application invariants.

### Scale/performance

**PASS** for the intended 144-player event without Redis/distributed infrastructure.

---

# 65. Product + Domain Specification v1.0 Release Candidate

### Status

**READY FOR OWNER ACCEPTANCE / FREEZE.**

The specification has now passed:

1. product grilling;
2. golf/scoring-rules pressure testing;
3. future-expansion boundary review;
4. formal resource/domain modelling;
5. lifecycle/state-machine modelling;
6. action/policy modelling;
7. security review;
8. concurrency review;
9. offline/replay review;
10. data-integrity review.

### Architecture position

The v1.0 candidate intentionally uses:

```text
enterprise-compatible domain boundaries
+
MVP-sized concrete implementation
```

It deliberately does **not** implement:

- multi-tenancy;
- generic formula/rules engines;
- generic workflow engines;
- every golf format;
- native-app dependency;
- Redis/distributed scoring infrastructure;
- event sourcing;
- enterprise IAM.

### MVP authority

The target remains:

```text
Internal golf day
~144 players
single day
single course
single Round
shotgun start
2–4 player PlayingGroups
Four-Ball Better-Ball Stableford
primary Mystery leaderboard
secondary Standard Better-Ball leaderboard
mixed tees
full Course Handicap by default (100% allowance)
individual score facts + side aggregation
independent score verification
admin check-in/operations
in-app + WhatsApp/email communications
hole/event sponsorship
Closest-to-Pin + Longest-Drive physical-board side competitions
intermittent-offline resilience
```

### Handoff authority order for `/wayfinder`

When frozen, the local agent should be instructed to use this authority order:

```text
1. Frozen Golf Live Scoring V2 Product + Domain Spec v1.0
2. Explicit decisions made during /wayfinder reconciliation
3. Current repository evidence
4. Legacy V0 architecture/implementation assumptions
```

The legacy repository is evidence and reusable implementation material, **not product/domain authority**.

### Repository-reconciliation goal

`/wayfinder` should next determine:

- what legacy code is reusable unchanged;
- what can be adapted behind the v1.0 boundaries;
- what must be removed/replaced;
- final Ash/Phoenix resource/module structure;
- migrations/data-reset strategy;
- implementation phases;
- ticket breakdown.

It must not silently redesign accepted product semantics merely to fit the old schema.

### Final STOP condition before tickets

Do **not** generate implementation tickets from this chat until the owner accepts the v1.0 release candidate as frozen.

After acceptance, the next artifact should be a concise **local `/wayfinder` handoff prompt** referencing the frozen spec, not a duplicate implementation plan.

