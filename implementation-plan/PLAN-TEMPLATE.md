# Implementation Plan Template

Use this exact structure. Section order matters — a fresh agent should be able to read top-to-bottom and have what they need by the time they hit "Step-by-step plan".

---

# <Plan title>

> One-sentence summary of what this plan accomplishes. Written for someone who has never heard of this work.

## Source

Link to the originating material. One or more of:
- GitHub issue: `#NNN — Title (URL)`
- Design doc / RFC: `path/to/doc.md` or external URL
- Conversation context: a short paraphrase only if no durable source exists (and note this — it's a weakness)

## Context

Why does this work exist? What problem does it solve, and for whom? Include only the background a fresh agent needs to make good decisions. Link out to longer material rather than restating it. **Don't assume the reader has been part of any prior discussion.**

If domain terms are used here, either link to `CONTEXT.md` (preferred) or define them inline.

## Goals

Numbered list. What "done" looks like, in concrete terms.

1. …
2. …

## Non-goals

Numbered list. Things explicitly out of scope, especially things a reasonable reader might assume are in scope. This section prevents scope creep and helps a fresh agent push back if asked to do more.

1. …
2. …

## Relevant prior decisions

Bulleted list of ADRs, prior plans, or existing patterns this work must respect. Reference by number/title and link.

- ADR-0004 — Soft delete users ([docs/adr/0004-soft-delete-users.md](../adr/0004-soft-delete-users.md))
- …

If any ADRs were created during the grilling session for this plan, list them here too and note "(new, created with this plan)".

## Relevant files and code

Bulleted list of the files a fresh agent will need to read or modify, with a one-line note on each. Use real paths verified to exist. Include line numbers for specific functions when helpful.

- `backend/src/services/tasks.ts` — task mutation logic; version bumping lives here
- `backend/src/db/schema.ts:42` — `tasks` table definition
- …

## Approach

A few paragraphs (not a step list) describing the shape of the solution. The "what" and "why" at a design level, before you get into "how". This is where you explain the key choices that came out of grilling: what was considered, what was picked, and why.

If there are diagrams worth drawing (sequence, state, data flow), include them as Mermaid blocks here.

## Step-by-step plan

Numbered, ordered list of concrete steps. Each step should be:

- **Verifiable** — when you finish the step, you can point to a specific outcome (file exists, test passes, endpoint returns X).
- **Atomic enough to review** — roughly one logical change. A step that says "implement the feature" is too big.
- **Specific** — name files, functions, table columns, endpoints. Not "update the service layer".

Example:

1. **Add `claimed_by` column to `tasks` table.** Edit `backend/src/db/schema.ts` to add `claimed_by: text('claimed_by')` (nullable, FK to `users.id`). Run `npm run db:generate` in `backend/` to create the migration. Verify the migration file appears under `backend/migrations/`.

2. **Expose `claimed_by` in the Task type.** Add `claimed_by: string | null` to the `Task` interface in `shared/src/types.ts`. Run `npm run build` from the root to confirm the shared workspace still compiles.

3. …

## Demo seed data

> **Skip this section if** the plan is a bugfix, pure refactor, or UI-only change. Include it for any plan that adds or changes backend data structures, new entity types, new relationships, or new API capabilities.

If this plan introduces new backend features, update `backend/demo/seed.sql` so that demo mode illustrates the new capability. The seed file is the authoritative fixture for demo resets — a feature that isn't seeded effectively doesn't exist in demo.

What to include:
- Representative rows for any new tables or columns
- At least one example of each new entity type or relationship in a realistic state
- Any new enum values or role assignments exercised by a realistic actor

One step in the step-by-step plan above should explicitly say: "Update `backend/demo/seed.sql` to include [specific rows/examples]." Add a corresponding acceptance criterion below.

If there is genuinely nothing to seed (e.g., the feature only affects runtime behavior with no persistent state), write one sentence explaining why.

## Testing strategy

How will you know it works? Be specific:

- Unit tests to add/update: list them by file and what they cover
- Integration tests (`backend/tests/`): list by file and scenario
- Manual checks (especially for frontend, where there are no component tests): list the user flows to walk through in the browser
- Regression risk: which existing tests must continue to pass

## Acceptance criteria

A checklist a reviewer can run through to confirm the work is done.

- [ ] …
- [ ] …
- [ ] All existing tests pass (`npm test` from root)
- [ ] Typechecks clean (`npm run typecheck` in both `backend/` and `frontend/`)

## Open questions

Anything that didn't get resolved during grilling. Be honest — a fresh agent who hits one of these needs to know it's an open question, not a decided thing. For each, note what the executor should do: ask the user, pick a default, or block.

- **Q: Should claimed tasks auto-release after N hours of inactivity?** Not decided. Default for now: no auto-release. Revisit after we see usage.
- …

If there are no open questions, write "None — all design decisions resolved during grilling."

## Out-of-band work (optional)

Anything the executor should know about but that isn't part of this plan: parallel work happening elsewhere, dependencies on other teams, deploy-time considerations, follow-up tickets to file. Omit this section if not applicable.
