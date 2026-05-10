# Weiv AST Script Analysis Plan

## Purpose

This document defines the next foundation upgrade for `weiv` script-side state
analysis.

The current default model remains:

- plain TypeScript authoring
- conservative fallback for blurry script cases
- correctness first

The next improvement is not more heuristic source scanning. The next
improvement is AST-backed script analysis from the Rust parser backend.

## Why This Is Next

`weiv` already has:

- compiler-first template lowering
- region planning
- owned-boundary scheduling
- selective region flushing
- direct-vs-fallback inspectability

The weakest remaining area is script-side precision.

Today the blurriest cases rely on text-level analysis for things like:

- local helper dependency extraction
- mutation classification
- alias-sensitive mutation diagnostics
- callback ownership diagnostics

That is acceptable as an interim step, but too fragile as a long-term base.

## Direction

The next step is:

1. extend `weiv_script_analyze`
2. expose structured AST-derived script facts across the FFI boundary
3. consume those facts in Zig for state diagnostics and dependency analysis
4. stop extending text heuristics much further

## Non-Goals

This phase is not:

- full type-checking
- a public state annotation system
- a runtime tracking redesign
- SSR or hydration work
- a general-purpose JS optimizer

The point is to strengthen compiler correctness and precision while keeping the
plain-code + conservative-fallback model.

## The Contract Shift

Current parser-backend output already includes:

- props
- imports
- top-level bindings
- transpiled code
- parse diagnostics

Next, it should grow a second layer of script-state facts.

These facts should be structural summaries, not a full Rust AST over FFI.

## Proposed New Backend Payload

Add a new top-level field such as:

```json
{
  "state_analysis": {
    "helpers": [],
    "mutations": [],
    "aliases": [],
    "callback_registrations": []
  }
}
```

The exact field names can change, but the intent should be stable.

## 1. Helper Records

The compiler needs AST-backed facts about local callable bindings.

Suggested shape:

```json
{
  "name": "visibleTodos",
  "kind": "function",
  "span_start": 210,
  "span_end": 412,
  "reads": ["filter", "todos"],
  "writes": [],
  "calls": ["completedCount"],
  "async": false,
  "returns_expression_only": false,
  "contains_external_reads": false,
  "contains_side_effects": false
}
```

Purpose:

- replace substring-based helper-body scanning
- improve dependency extraction
- support stronger invalidation-graph output
- enable safer future direct-expression compilation

## 2. Mutation Records

The compiler needs AST-backed mutation summaries.

Suggested shape:

```json
{
  "binding": "todos",
  "kind": "assignment",
  "span_start": 512,
  "span_end": 556,
  "statement_position": true,
  "member_path": null,
  "inside_callback": false,
  "inside_async": false
}
```

Possible `kind` values:

- `assignment`
- `update`
- `member_assignment`
- `method`
- `delete`

Purpose:

- replace heuristic mutation classification
- produce stronger diagnostics
- support clearer owned/unowned boundary analysis

## 3. Alias Records

The compiler needs AST-backed same-scope alias facts.

Suggested shape:

```json
{
  "alias": "u",
  "target": "user",
  "kind": "direct_binding_alias",
  "span_start": 140,
  "span_end": 154
}
```

Purpose:

- detect simple same-scope aliases reliably
- distinguish “diagnosed unsupported” from “unknown”
- avoid growing ad hoc alias text scans

This phase does not require full alias escape analysis.

## 4. Callback Registration Records

The compiler needs structured callback-registration summaries.

Suggested shape:

```json
{
  "callee": "externalStore.subscribe",
  "callback_kind": "inline_arrow",
  "callback_span_start": 320,
  "callback_span_end": 356,
  "owned_candidate": false,
  "reason": "unknown_registration"
}
```

Purpose:

- diagnose unowned visible mutations more reliably
- recognize known built-in owned boundaries more cleanly
- prepare future owned-boundary expansion without text hacks

## What Zig Should Consume First

The first Zig consumers should be:

1. invalidation-graph dependency analysis
2. mutation diagnostics
3. alias diagnostics
4. unowned callback diagnostics

Do not start by rewriting the entire emitter around the new payload at once.

## Rollout Plan

### Phase 1: Extend Backend Schema

Add `state_analysis` to the Rust response with empty defaults first.

Verification:

- existing Zig parsing keeps working
- old fields are unchanged
- new field is ignored safely until Zig consumes it

### Phase 2: Helper Dependency Facts

Implement helper records first.

Why first:

- highest immediate value
- lowest conceptual risk
- improves both scheduling and inspectability

Use it to replace the current substring-based helper dependency expansion in:

- direct browser scheduler dependency collection
- invalidation graph helper dependency expansion

### Phase 3: Mutation And Alias Facts

Implement structured mutation and alias records.

Use them to replace:

- expression-position mutation heuristics
- simple alias mutation heuristics

Expected outcome:

- better diagnostics
- fewer fragile false positives/negatives

### Phase 4: Callback Registration Facts

Implement callback registration summaries and callback-contained mutation links.

Use them to strengthen:

- unowned callback diagnostics
- owned-candidate recognition

## Heuristics To Freeze

Do not keep growing text heuristics significantly in these areas:

- helper-body dependency extraction
- alias declaration inference
- callback registration detection
- mutation reasoning that depends on nested JS structure

The current heuristics are acceptable as interim support only.

## Relationship To Authoring Helpers

Explicit authoring syntax is now deferred.

Reason:

- plain code plus conservative fallback is the correct default
- AST-backed script analysis should come first
- only after AST-backed precision lands should `weiv` decide whether explicit
  author syntax is still worth adding

If explicit syntax is ever added later, it should be for precision and
optimization, not correctness.

## Verification Policy

Every backend/schema change should preserve:

```sh
zig build test
zig build component-test
```

New fixture coverage should focus on:

- local helper dependency chains
- same-scope alias mutation
- callback-owned vs unowned mutation
- imported hidden-state helper detection

## Exit Criteria

This phase is successful when:

- helper dependency analysis no longer depends on substring body scans
- alias diagnostics no longer depend on ad hoc declaration matching
- callback diagnostics are based on structured registration facts
- invalidation-graph output becomes more trustworthy for blurry script cases
- current correctness behavior remains conservative where proof is still absent
