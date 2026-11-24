# shellcheck shell=bash
# Tests of the plan: the task that writes it, the items that build it.

PLAN=.workflow/plans/p.md

# write_plan <status>: a plan of two items, the second depending on the first.
write_plan() {
  mkdir -p .workflow/plans
  cat >"$PLAN" <<EOF
---
status: $1
inputs: none
---

# Greet by name, with a default

## Requirements

### Greet
- GREET-01. Greet by name. — verify: test
- GREET-02. Greet with a default name. — verify: test; acceptance

## Items
- [ ] 1. Name (S estimated): greet by name; covers GREET-01; depends on —
- [ ] 2. Default (L estimated): the default name; covers GREET-02; depends on 1

## Acceptance
- [ ] GREET-02: a fresh clone; run greet without a name; it says hello, world.
EOF
}

plan_on_main() {
  write_plan "${1:-approved}"
  git add -A && git commit -qm "docs(greet): plan"
}

tick_item() {
  sed -i.bak "s/^- \[ \] $1\./- [x] $1./" "$PLAN" && rm -f "$PLAN.bak"
}

# plan_task: a plan task at its checkpoint, its plan approved and verified.
plan_task() {
  bash "$SCRIPTS/branch.sh" P docs/greet/plan "$(intent)" >/dev/null
  write_plan approved
  bash "$SCRIPTS/journal.sh" set plan "$PLAN"
  bash "$SCRIPTS/journal.sh" set phase p/checkpoint
  bash "$SCRIPTS/verify.sh" >/dev/null
}

# leave_task: back on main, the task's branch deleted with its journal.
leave_task() {
  local branch
  branch="$(git branch --show-current)"
  rm -f .workflow/journal.md
  git switch -q -f main
  git branch -q -D "$branch"
}

open_item() {
  bash "$SCRIPTS/branch.sh" "$1" "$2" "$(intent)" --item "$PLAN" "$3"
}

# item_spec <status> <item> [<chunk mark>]: the journal's spec, of an item.
item_spec() {
  mkdir -p .workflow/specs
  printf -- '---\nstatus: %s\nplan: %s\nitem: %s\n---\n\n# Default\n\n## Chunks\n- [%s] 1. Default (test-first): a.ts\n' \
    "$1" "$PLAN" "$2" "${3:- }" >.workflow/specs/s.md
}

integrate_now() {
  bash "$SCRIPTS/journal.sh" set phase close/integrate
  bash "$SCRIPTS/integrate.sh"
}

verified_change() {
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "$1")" >/dev/null
}

test_branch_opens_a_plan_task_unless_a_plan_is_open() {
  out="$(bash "$SCRIPTS/branch.sh" P docs/greet/plan "$(intent)")"
  [[ "$out" == *"tier P"* ]] || fail "$out"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get tier)" P
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" p/plan
  expect_eq "$(bash "$SCRIPTS/journal.sh" get command)" task
  leave_task
  plan_on_main
  expect_fail "a plan is open already, $PLAN: one plan at a time" bash "$SCRIPTS/branch.sh" P docs/greet/other "$(intent)"
  expect_fail "the tier is S, L, P (a plan) or D (a drop)" bash "$SCRIPTS/branch.sh" X docs/greet/other "$(intent)"
  sed -i.bak 's/^status: approved/status: done/' "$PLAN" && rm "$PLAN.bak"
  git commit -qam "docs(greet): plan done"
  bash "$SCRIPTS/branch.sh" P docs/greet/other "$(intent)" >/dev/null || fail "a done plan blocks a new one"
}

test_plan_check_prints_the_counts_or_each_problem() {
  write_plan draft
  expect_eq "$(bash "$SCRIPTS/plan.sh" check "$PLAN")" "2 requirements, 2 items (0 ticked), 1 acceptance steps (0 passed)"
  sed -i.bak 's/covers GREET-02/covers GREET-03/' "$PLAN" && rm "$PLAN.bak"
  expect_fail "spec.py: $PLAN: item 2 names GREET-03, no requirement of the plan" bash "$SCRIPTS/plan.sh" check "$PLAN"
  expect_fail "GREET-02 is covered by no item" bash "$SCRIPTS/plan.sh" check "$PLAN"
  expect_fail "Usage" bash "$SCRIPTS/plan.sh"
  expect_fail "No such file" bash "$SCRIPTS/plan.sh" check .workflow/plans/none.md
}

test_commit_closes_a_plan_task_once_its_plan_is_approved() {
  plan_task
  sed -i.bak 's/^status: approved/status: draft/' "$PLAN" && rm "$PLAN.bak"
  bash "$SCRIPTS/verify.sh" >/dev/null
  out="$(bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): draft')")"
  [[ "$out" == *"phase stays p/checkpoint: the commit holds no plan with 'status: approved'"* ]] || fail "$out"
  sed -i.bak 's/^status: draft/status: approved/' "$PLAN" && rm "$PLAN.bak"
  tick_item 1
  bash "$SCRIPTS/verify.sh" >/dev/null
  out="$(bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): ticked')")"
  [[ "$out" == *"phase stays p/checkpoint: item 1 is ticked: a plan reaches main with no item ticked"* ]] || fail "$out"
  sed -i.bak 's/^- \[x\] 1\./- [ ] 1./; s/covers GREET-02/covers GREET-03/' "$PLAN" && rm "$PLAN.bak"
  bash "$SCRIPTS/verify.sh" >/dev/null
  out="$(bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): broken')")"
  [[ "$out" == *"phase stays p/checkpoint"*"item 2 names GREET-03"* ]] || fail "$out"
  sed -i.bak 's/covers GREET-03/covers GREET-02/' "$PLAN" && rm "$PLAN.bak"
  bash "$SCRIPTS/verify.sh" >/dev/null
  out="$(bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): plan')")"
  [[ "$out" == *"phase: close/check"* ]] || fail "$out"
}

test_a_plan_task_closes_as_docs_only_and_integrates() {
  slow_check
  mkdir -p docs/adr
  echo "# 0000 template" >docs/adr/0000-template.md
  set_config rules 'CLAUDE.md, docs/adr/'
  git add -A && git commit -qm "chore(repo): decision records"
  plan_task
  echo "# 0001 greet" >docs/adr/0001-greet.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): plan')" >/dev/null
  echo slow-red >>.git/info/exclude
  touch slow-red
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"verify: green"*"docs only"*"phase: close/write"* ]] || fail "$out"
  out="$(integrate_now)"
  [[ "$out" == *"integrated 'docs/greet/plan'"* ]] || fail "$out"
  expect_eq "$(git show "main:$PLAN" | sed -n 2p)" "status: approved"
}

test_integrate_refuses_a_plan_not_approved_ticked_or_beside_another() {
  plan_task
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): plan')" >/dev/null
  sed -i.bak 's/^status: approved/status: draft/' "$PLAN" && rm "$PLAN.bak"
  verified_change 'docs(greet): draft'
  expect_fail "$PLAN is not 'status: approved'" integrate_now
  sed -i.bak 's/^status: draft/status: approved/' "$PLAN" && rm "$PLAN.bak"
  tick_item 1
  verified_change 'docs(greet): ticked'
  expect_fail "item 1 of $PLAN is ticked: a plan reaches main with no item ticked" integrate_now
  sed -i.bak 's/^- \[x\] 1\./- [ ] 1./' "$PLAN" && rm "$PLAN.bak"
  verified_change 'docs(greet): unticked'
  git switch -q main
  mkdir -p .workflow/plans
  git show "docs/greet/plan:$PLAN" >.workflow/plans/other.md
  git add -A && git commit -qm "docs(other): plan"
  git switch -q docs/greet/plan
  bash "$SCRIPTS/sync.sh" >/dev/null
  verified_change "Merge branch 'main'"
  expect_fail "a plan is open on main already, .workflow/plans/other.md: one plan at a time" integrate_now
}

test_branch_opens_an_item_of_the_open_plan() {
  plan_on_main
  out="$(open_item S feature/greet/name 1)"
  [[ "$out" == *"item 1 of $PLAN"* ]] || fail "$out"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get plan)" "$PLAN"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get item)" 1
  expect_eq "$(bash "$SCRIPTS/journal.sh" get tier)" S
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" s/implement
  expect_eq "$(cat .git/overload/items/feature/greet/name)" "$PLAN	1	task"
}

test_branch_refuses_an_item_that_cannot_open() {
  expect_fail "$PLAN is not a file on main" open_item S feature/greet/name 1
  plan_on_main draft
  expect_fail "$PLAN is not 'status: approved' but 'draft'" open_item S feature/greet/name 1
  sed -i.bak 's/^status: draft/status: approved/' "$PLAN" && rm "$PLAN.bak"
  git commit -qam "docs(greet): approve"
  expect_fail "item 2 depends on item 1, not ticked yet" open_item L feature/greet/default 2
  expect_fail "item 9 is not in the plan" open_item S feature/greet/name 9
  expect_fail "Usage" bash "$SCRIPTS/branch.sh" S feature/greet/name "$(intent)" --item "$PLAN"
  expect_fail "Usage" bash "$SCRIPTS/branch.sh" P docs/greet/plan "$(intent)" --item "$PLAN" 1
  open_item S feature/greet/name 1 >/dev/null
  rm .workflow/journal.md
  git switch -q main
  expect_fail "item 1 of $PLAN is open on branch feature/greet/name: one item at a time" open_item S feature/greet/again 1
  expect_eq "$(git branch --show-current)" main
  git branch -q -D feature/greet/name
  open_item S feature/greet/again 1 >/dev/null || fail "the record of a deleted branch still counts"
}

test_plan_item_says_whether_a_task_can_open_an_item() {
  plan_on_main
  expect_eq "$(bash "$SCRIPTS/plan.sh" item "$PLAN" 1)" "item 1 (S estimated), Name: a task can open it"
  expect_fail "item 2 depends on item 1, not ticked yet" bash "$SCRIPTS/plan.sh" item "$PLAN" 2
  open_item S feature/greet/name 1 >/dev/null
  rm .workflow/journal.md
  git switch -q main
  expect_fail "item 1 of $PLAN is open on branch feature/greet/name" bash "$SCRIPTS/plan.sh" item "$PLAN" 1
}

test_status_shows_the_open_plan_and_the_command_of_its_next_item() {
  [[ "$(bash "$SCRIPTS/status.sh")" == *"- open plan: none"* ]] || fail "$(bash "$SCRIPTS/status.sh")"
  plan_on_main
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"- open plan: $PLAN, 2 requirements, 2 items (0 ticked), 1 acceptance steps (0 passed)"* ]] || fail "$out"
  [[ "$out" == *"  - next: item 1 (S estimated), Name → /overload:task $PLAN 1"* ]] || fail "$out"
  open_item S feature/greet/name 1 >/dev/null
  rm .workflow/journal.md
  git switch -q main
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"  - next: item 1 (S estimated), Name: open on branch feature/greet/name, where /overload:task resumes it"* ]] || fail "$out"
  git branch -q -D feature/greet/name
  tick_item 1
  item_spec approved 2
  git add -A && git commit -qm "docs(greet): item 2's spec"
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"  - next: item 2 (L estimated), Default: its spec .workflow/specs/s.md is approved → /overload:build .workflow/specs/s.md"* ]] || fail "$out"
  tick_item 2
  git commit -qam "docs(greet): item 2 built"
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"  - every item ticked → its acceptance: /overload:build $PLAN"* ]] || fail "$out"
  sed -i.bak 's/covers GREET-02/covers GREET-03/' "$PLAN" && rm "$PLAN.bak"
  git commit -qam "docs(greet): broken"
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"- open plan: $PLAN, refused:"*"item 2 names GREET-03"* ]] || fail "$out"
}

test_integrate_an_s_item_needs_its_tick_and_no_other_item_changed() {
  plan_on_main
  open_item S feature/greet/name 1 >/dev/null
  verified_commit "Name."
  expect_fail "item 1 of $PLAN is not ticked: the task's last commit ticks it" integrate_now
  tick_item 1
  tick_item 2
  verified_change 'docs(greet): tick'
  expect_fail "the task changes item 2 of $PLAN: a revision of the plan goes through /overload:task $PLAN" integrate_now
  sed -i.bak 's/^- \[x\] 2\./- [ ] 2./' "$PLAN" && rm "$PLAN.bak"
  verified_change 'docs(greet): untick 2'
  out="$(integrate_now)"
  [[ "$out" == *"integrated"* ]] || fail "$out"
  [[ ! -e .git/overload/items/feature/greet/name ]] || fail "the item's record outlives its branch"
}

test_integrate_an_item_s_spec_task_leaves_the_item_open() {
  plan_on_main
  open_item L feature/greet/name 1 >/dev/null
  item_spec approved 2
  bash "$SCRIPTS/journal.sh" set spec .workflow/specs/s.md
  bash "$SCRIPTS/journal.sh" set phase l/checkpoint
  bash "$SCRIPTS/verify.sh" >/dev/null
  out="$(bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): spec')")"
  [[ "$out" == *"phase: close/check"* ]] || fail "$out"
  expect_fail ".workflow/specs/s.md names item 2 of $PLAN, not the task's: plan: $PLAN and item: 1" integrate_now
  item_spec approved 1
  tick_item 1
  verified_change 'docs(greet): spec of item 1'
  expect_fail "item 1 of $PLAN is ticked: the build of its spec ticks it" integrate_now
  sed -i.bak 's/^- \[x\] 1\. Name (S estimated)/- [ ] 1. Name (L estimated)/' "$PLAN" && rm "$PLAN.bak"
  bash "$SCRIPTS/verify.sh" --integrate >/dev/null
  [[ "$(bash "$SCRIPTS/verify.sh" --integrate)" == *"docs only"* ]] || fail "the tier's correction is a doc of the spec's task"
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): item 1 is L')" >/dev/null
  out="$(integrate_now)"
  [[ "$out" == *"integrated"* ]] || fail "$out"
}

# item_spec_on_main: the plan, and the approved spec of its item 1, on main.
item_spec_on_main() {
  plan_on_main
  item_spec approved 1
  git add -A && git commit -qm "docs(greet): item 1's spec"
}

test_branch_builds_an_item_s_spec_and_watches_its_plan() {
  item_spec_on_main
  bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md >/dev/null
  expect_eq "$(bash "$SCRIPTS/journal.sh" get plan)" "$PLAN"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get item)" 1
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/chunk-1/test
  expect_eq "$(cat .git/overload/items/feature/greet/build)" "$PLAN	1	build"
  leave_task
  sed -i.bak 's/the default name;/the default name, from the config;/' "$PLAN" && rm "$PLAN.bak"
  git commit -qam "docs(greet): revise item 2"
  out="$(bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md)"
  [[ "$out" == *"main changed the spec's files since its approval: $PLAN"* ]] || fail "$out"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/expiry
  leave_task
  open_item S feature/greet/other 1 >/dev/null 2>&1 && fail "an item with its spec approved opened as a task"
  bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md >/dev/null
  rm .workflow/journal.md
  git switch -q main
  expect_fail "item 1 of $PLAN is open on branch feature/greet/build: one item at a time" \
    bash "$SCRIPTS/branch.sh" --build feature/greet/again .workflow/specs/s.md
}

test_integrate_a_build_of_an_item_needs_its_tick() {
  item_spec_on_main
  bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md >/dev/null
  item_spec "done" 1 x
  verified_change 'feat(greet): default'
  expect_fail "item 1 of $PLAN is not ticked: the task's last commit ticks it" integrate_now
  tick_item 1
  verified_change 'docs(greet): tick item 1'
  out="$(integrate_now)"
  [[ "$out" == *"integrated"* ]] || fail "$out"
}

test_restart_keeps_the_item_of_an_s_item_turning_l() {
  plan_on_main
  open_item S feature/greet/name 1 >/dev/null
  verified_commit "Attempt."
  bash "$SCRIPTS/restart.sh" "it is L" >/dev/null
  expect_eq "$(bash "$SCRIPTS/journal.sh" get tier)" L
  expect_eq "$(bash "$SCRIPTS/journal.sh" get plan)" "$PLAN"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get item)" 1
  [[ -f .git/overload/items/feature/greet/name ]] || fail "the item's record is gone"
}

# A change of a decision on main: the plan revised or dropped, a spec dropped.

change_task() {
  bash "$SCRIPTS/branch.sh" "$1" "$2" "$(intent)" --change "$3"
}

# drop_doc <doc> [<reason>]: sets the document dropped, with the reason
# under ## Dropped when one is given.
drop_doc() {
  sed -i.bak 's/^status: approved/status: dropped/' "$1" && rm "$1.bak"
  [[ -z "${2:-}" ]] || printf '\n## Dropped\n%s\n' "$2" >>"$1"
}

# at_checkpoint <phase>: commits the verified tree from a checkpoint, and
# prints commit.sh's output.
at_checkpoint() {
  bash "$SCRIPTS/journal.sh" set phase "$1"
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): change')"
}

# spec_on_main <status> <chunk mark>: a spec of no plan, committed on main.
spec_on_main() {
  mkdir -p .workflow/specs
  printf -- '---\nstatus: %s\n---\n\n# Greet\n\n## Chunks\n- [%s] 1. Greet (test-first): a.ts\n' "$1" "$2" >.workflow/specs/s.md
  git add -A && git commit -qm "docs(greet): spec, $1"
}

close_docs_only() {
  bash "$SCRIPTS/journal.sh" set phase close/check
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"docs only"*"phase: close/write"* ]] || fail "$out"
}

test_branch_opens_a_change_of_the_open_plan_or_of_an_approved_spec() {
  expect_fail "$PLAN is not a file on main" change_task P docs/greet/revise "$PLAN"
  plan_on_main
  out="$(change_task P docs/greet/revise "$PLAN")"
  [[ "$out" == *"tier P"*"It changes $PLAN."* ]] || fail "$out"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" p/plan
  expect_eq "$(bash "$SCRIPTS/journal.sh" get plan)" "$PLAN"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get change)" "$PLAN"
  leave_task
  change_task D docs/greet/drop "$PLAN" >/dev/null
  expect_eq "$(bash "$SCRIPTS/journal.sh" get tier)" D
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" d/drop
  expect_eq "$(bash "$SCRIPTS/journal.sh" get plan)" ""
  leave_task
  expect_fail "Usage" change_task S docs/greet/drop "$PLAN"
  expect_fail "Usage" bash "$SCRIPTS/branch.sh" P docs/greet/x "$(intent)" --item "$PLAN" 1 --change "$PLAN"
  expect_fail "tier D drops a plan or a spec: name it with --change <doc>" bash "$SCRIPTS/branch.sh" D docs/greet/x "$(intent)"
  expect_fail "is neither a plan" change_task D docs/greet/x README.md
  spec_on_main approved " "
  expect_fail "a spec approved on main changes only by its drop" change_task P docs/greet/x .workflow/specs/s.md
  change_task D docs/greet/drop .workflow/specs/s.md >/dev/null || fail "an approved spec is not dropped"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get spec)" ""
  leave_task
  spec_on_main "done" x
  expect_fail ".workflow/specs/s.md is not 'status: approved' but 'done'" change_task D docs/greet/drop .workflow/specs/s.md
  open_item S feature/greet/name 1 >/dev/null
  rm .workflow/journal.md
  git switch -q main
  expect_fail "item 1 of $PLAN is open on branch feature/greet/name: stop that task" change_task D docs/greet/drop "$PLAN"
  change_task P docs/greet/revise "$PLAN" >/dev/null || fail "a revision waits for no item"
}

test_a_revision_of_the_plan_commits_and_integrates_as_docs_only() {
  plan_on_main
  tick_item 1
  git commit -qam "feat(greet): item 1"
  change_task P docs/greet/revise "$PLAN" >/dev/null
  sed -i.bak 's/the default name;/the default name, from the config;/' "$PLAN" && rm "$PLAN.bak"
  echo "- [ ] 3. Docs (S estimated): the README; covers GREET-02; depends on 2" >>"$WORK/item"
  sed -i.bak "/^- \[ \] 2\./r $WORK/item" "$PLAN" && rm "$PLAN.bak"
  sed -i.bak 's/covers GREET-02; depends on 1/covers GREET-02; closes GREET-02; depends on 1/' "$PLAN" && rm "$PLAN.bak"
  out="$(at_checkpoint p/checkpoint)"
  [[ "$out" == *"phase: close/check"* ]] || fail "$out"
  close_docs_only
  out="$(integrate_now)"
  [[ "$out" == *"integrated 'docs/greet/revise'"* ]] || fail "$out"
  [[ "$(bash "$SCRIPTS/status.sh")" == *"next: item 2 (L estimated), Default → /overload:task $PLAN 2"* ]] || fail "$(bash "$SCRIPTS/status.sh")"
}

test_integrate_refuses_a_revision_of_an_item_started_or_ticked() {
  plan_on_main
  open_item S feature/greet/name 1 >/dev/null
  rm .workflow/journal.md
  git switch -q main
  change_task P docs/greet/revise "$PLAN" >/dev/null
  sed -i.bak 's/greet by name;/greet by full name;/' "$PLAN" && rm "$PLAN.bak"
  at_checkpoint p/checkpoint >/dev/null
  expect_fail "item 1 of $PLAN is open on branch feature/greet/name: a revision changes no item a task works" integrate_now
  git branch -q -D feature/greet/name
  tick_item 2
  verified_change 'docs(greet): tick 2'
  expect_fail "the revision ticks item 2: the task that ends an item ticks it" integrate_now
  sed -i.bak 's/^- \[x\] 2\./- [ ] 2./' "$PLAN" && rm "$PLAN.bak"
  verified_change 'docs(greet): untick 2'
  integrate_now >/dev/null || fail "a revision of items nobody works is refused"
}

test_a_revision_drops_the_approved_spec_of_an_item_it_removes() {
  plan_on_main
  tick_item 1
  printf -- '- [ ] 3. Docs (S estimated): the README; covers GREET-02; closes GREET-02; depends on 1\n' >"$WORK/item"
  sed -i.bak "/^- \[ \] 2\./r $WORK/item" "$PLAN" && rm "$PLAN.bak"
  item_spec approved 2
  git add -A && git commit -qm "docs(greet): item 2's spec"
  change_task P docs/greet/revise "$PLAN" >/dev/null
  sed -i.bak '/^- \[ \] 2\./d' "$PLAN" && rm "$PLAN.bak"
  at_checkpoint p/checkpoint >/dev/null
  expect_fail "item 2 of $PLAN goes, and main holds its spec .workflow/specs/s.md approved: drop it in this task" integrate_now
  drop_doc .workflow/specs/s.md
  verified_change 'docs(greet): drop the spec'
  expect_fail "the task changes .workflow/specs/s.md, which it may only drop, with its reason" integrate_now
  printf '\n## Dropped\nItem 2 of the plan is gone.\n' >>.workflow/specs/s.md
  verified_change 'docs(greet): why'
  close_docs_only
  integrate_now >/dev/null || fail "a revision that drops its removed item's spec is refused"
}

test_integrate_refuses_a_change_that_touches_a_spec_it_does_not_drop() {
  plan_on_main
  spec_on_main approved " "
  change_task P docs/greet/revise "$PLAN" >/dev/null
  sed -i.bak 's/greet by name;/greet by full name;/' "$PLAN" && rm "$PLAN.bak"
  drop_doc .workflow/specs/s.md "Not needed."
  at_checkpoint p/checkpoint >/dev/null
  expect_fail "the task changes .workflow/specs/s.md, which is not the spec of an item it changes or removes" integrate_now
}

test_dropping_the_plan_drops_its_unbuilt_item_specs() {
  item_spec_on_main
  change_task D docs/greet/drop "$PLAN" >/dev/null
  drop_doc "$PLAN"
  out="$(at_checkpoint d/checkpoint)"
  [[ "$out" == *"phase stays d/checkpoint: no reason under ## Dropped"* ]] || fail "$out"
  printf '\n## Dropped\nGreeting moves to another service.\n' >>"$PLAN"
  out="$(at_checkpoint d/checkpoint)"
  [[ "$out" == *"phase: close/check"* ]] || fail "$out"
  close_docs_only
  expect_fail "dropping $PLAN drops the approved spec of its item 1, .workflow/specs/s.md: drop it in this task" integrate_now
  drop_doc .workflow/specs/s.md "Its plan is dropped."
  sed -i.bak 's/greet by name;/greet by full name;/' "$PLAN" && rm "$PLAN.bak"
  verified_change 'docs(greet): drop the spec'
  expect_fail "dropping $PLAN changes its item 1: a drop leaves the items as they are" integrate_now
  sed -i.bak 's/greet by full name;/greet by name;/' "$PLAN" && rm "$PLAN.bak"
  verified_change 'docs(greet): item 1 back'
  close_docs_only
  out="$(integrate_now)"
  [[ "$out" == *"integrated"* ]] || fail "$out"
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"- open plan: none"* && "$out" == *"- specs to build: none"* ]] || fail "$out"
  bash "$SCRIPTS/branch.sh" P docs/greet/plan "$(intent)" >/dev/null || fail "a dropped plan blocks a new one"
}

test_dropping_an_approved_spec_reopens_its_item() {
  item_spec_on_main
  change_task D docs/greet/drop .workflow/specs/s.md >/dev/null
  drop_doc .workflow/specs/s.md "The item needs another approach."
  out="$(at_checkpoint d/checkpoint)"
  [[ "$out" == *"phase: close/check"* ]] || fail "$out"
  close_docs_only
  integrate_now >/dev/null || fail "the drop of a spec is refused"
  [[ "$(bash "$SCRIPTS/status.sh")" == *"next: item 1 (S estimated), Name → /overload:task $PLAN 1"* ]] || fail "$(bash "$SCRIPTS/status.sh")"
}

test_integrate_refuses_a_drop_without_its_reason() {
  item_spec_on_main
  change_task D docs/greet/drop .workflow/specs/s.md >/dev/null
  drop_doc .workflow/specs/s.md
  verified_change 'docs(greet): drop'
  expect_fail ".workflow/specs/s.md is not dropped with its reason: no reason under ## Dropped" integrate_now
}

test_a_revision_keeps_a_changed_item_s_spec_for_its_build_to_review() {
  item_spec_on_main
  change_task P docs/greet/revise "$PLAN" >/dev/null
  sed -i.bak 's/greet by name;/greet by full name;/' "$PLAN" && rm "$PLAN.bak"
  at_checkpoint p/checkpoint >/dev/null
  close_docs_only
  integrate_now >/dev/null || fail "a revision of an item whose spec is approved is refused"
  out="$(bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md)"
  [[ "$out" == *"main changed the spec's files since its approval: $PLAN"* ]] || fail "$out"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/expiry
}
