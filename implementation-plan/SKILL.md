---
name: implementation-plan
description: Produce a self-contained implementation plan for a problem or feature. Phase 1 ingests the problem (free-form description, GitHub issue, URL, or local doc). Phase 2 runs grill-with-docs to stress-test the approach against the project's domain language and prior decisions. Phase 3 writes a structured plan to docs/plans/<slug>.md that a fresh agent with zero prior context can execute. Use this whenever the user wants to plan a feature, design work, refactor, or bug-fix campaign — especially when they mention a GitHub issue, a design doc, a spec, or say things like "let's figure out how to do X", "make a plan for Y", "I want to scope out Z", or hand over a URL/issue without specifying what to do next.
---

<purpose>

The user has a problem and wants a plan that someone else (a fresh agent, a teammate, or future-them) can execute without needing to relive this conversation. Your output is not the implementation — it is a durable, hand-offable document.

Two things tend to go wrong with implementation plans:

1. **Half-baked alignment.** The plan looks fine but the author skipped past terminology disagreements, ignored existing ADRs, or invented new concepts that conflict with the codebase. A fresh agent then has to make the same judgment calls from scratch — badly.

2. **Insufficient self-containment.** The plan reads well to the people who wrote it but assumes context a fresh agent doesn't have: undefined acronyms, "the usual approach", references to "the bug we discussed", file paths that don't exist anymore.

This skill exists to fix both. Grilling fixes #1. The structured template fixes #2.

</purpose>

<workflow>

## Phase 1 — Ingest the problem

Figure out what you're planning. The user might give you any of:

- A free-form description in chat
- A URL (design doc, blog post, RFC) — fetch with WebFetch
- A GitHub issue/PR — fetch with `gh issue view <num>` or `gh pr view <num>` (prefer this to scraping HTML)
- A local file path — read it
- A combination (e.g., "this issue plus the discussion in #42")

Read all of it before grilling. Don't paraphrase back to the user — they wrote it, they know what it says. Just confirm you have the source: "Got it, working from issue #57 plus the linked design doc."

If the source is ambiguous or thin (e.g., a one-line issue title), ask one targeted question to disambiguate scope before grilling. Don't ask "what do you want?" — propose an interpretation and let them correct it.

## Phase 2 — Grill

Invoke the `grill-with-docs` skill via the Skill tool. That skill runs an interactive alignment session: it explores the codebase, challenges terminology against `CONTEXT.md`, surfaces contradictions, and offers ADRs for hard-to-reverse decisions.

Let it run to completion. Do not short-circuit it because the problem "seems clear" — the grilling is where you learn that the user's "user" is the codebase's "actor", that the obvious approach conflicts with ADR-0003, and that the edge case the user dismissed actually drives the whole design.

While grilling is in progress, take notes (mentally or in scratch) on what will end up in the plan: glossary terms, ADRs created or referenced, scenarios resolved, files identified as relevant, decisions made and rejected. You will need all of this when writing the plan.

When grilling ends (shared understanding reached, or the user says "OK, write the plan"), move to Phase 3.

## Phase 3 — Write the plan

Pick a slug: lowercase, hyphenated, derived from the feature/problem (e.g. `agent-task-claiming`, `fix-stale-blocker-cache`). Keep it short — 2–5 words. Check `docs/plans/` for an existing file with that slug; if one exists, ask before overwriting.

Create the file at `docs/plans/<slug>.md` (create the directory if it doesn't exist). Use the template in [PLAN-TEMPLATE.md](./PLAN-TEMPLATE.md). Every section is mandatory unless marked optional — empty sections defeat the purpose of the template, so if you genuinely have nothing to put in one, write a single line explaining why ("No new ADRs — this slots into the existing event-bus pattern from ADR-0002").

After writing, tell the user the path and offer to read it back or open it. Don't paste the whole plan into chat — they can read the file.

</workflow>

<self-containment-test>

Before you finish, audit the plan against this question: **could a fresh agent, given only this file and the repository, execute the work well?**

Specifically check:

- **No dangling pronouns.** "The issue we discussed" → "issue #57 (link)". "The bug" → the specific bug, named.
- **All file paths are real and current.** Don't write `src/auth/middleware.ts` if the file is actually `src/auth/index.ts`. Verify with the Read tool if uncertain.
- **All acronyms and project terms are either defined or linked to CONTEXT.md.**
- **ADRs are referenced by number and title**, not by "the ADR we just made".
- **Steps are concrete and verifiable.** "Refactor the auth layer" is not a step. "Extract `validateToken` from `src/auth/index.ts:42` into a new `src/auth/validate.ts` module, exported as a named function" is a step.
- **Open questions are explicit.** If something wasn't resolved in grilling, name it under "Open questions" rather than papering over it.

If the plan fails this audit, fix it before reporting done. The self-containment test is the whole point of the skill — it is not optional polish.

</self-containment-test>

<notes>

**New backend features must update `backend/demo/seed.sql`.** When writing steps for a plan that adds new tables, columns, entity types, relationships, or API capabilities, include an explicit step to update the demo seed file. Bugfixes, pure refactors, and UI-only changes don't need this. If in doubt, ask: "does demo mode need a row to show this off?" If yes, it needs a seed step.

**Don't implement.** This skill produces a plan, not code. If the user wants you to execute the plan, that's a separate request and should usually be a separate session (often with a fresh agent, which is what the plan is designed for).

**Don't be exhaustive for its own sake.** A good plan is as short as it can be while passing the self-containment test. A 200-line plan for a 5-line bug fix is a smell. Match the depth to the problem.

**The grilling is load-bearing.** If the user pushes to skip it ("just write the plan, I know what I want"), gently push back once: "Grilling usually surfaces terminology mismatches or ADR conflicts I'd otherwise miss. Want to do a 10-minute version, or skip it entirely?" If they still want to skip, write the plan with a prominent "Caveat: this plan was written without a grilling pass" note at the top, so a fresh agent knows the alignment is shallower than usual.

</notes>
