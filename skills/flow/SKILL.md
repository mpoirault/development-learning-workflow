---
name: flow
description: Task router and branching workflow. Use at the start of any
  task that touches files, before the first Edit or Write, to create a
  work branch (never edit on main). Use again when the user says the
  task is done, wants to wrap up, commit, push, or open a PR, to route
  that step to the skill that owns it, or to a built-in fallback when
  none is installed.
---

# flow

Main is protected. Every change reaches main through a PR. This skill owns
the branch procedure, the routing map, and the fallbacks below. When an
installed skill owns a routed step, that skill's rules win. The fallbacks
apply only when no such skill is installed. Installed skills appear in the skill list, often namespaced as
`plugin:skill`. Match a companion skill by what its description says
it does, not by its exact name.

## Behavior: start a task

Follow this before the first file edit of any task.

1. Run `git branch --show-current`.
2. If the branch is not main and the task continues that branch's topic,
   stay on it and stop here.
3. If uncommitted changes block a branch switch, ask the user: commit them
   first, or bring them along. Wait for the answer.
4. Run `git fetch origin`.
5. Run `git checkout -b <type>/<slug> origin/main` with a name in the
   branch format below.
6. If the user gave a branch name, use that name instead.

## Routing map

- If the user asks to commit or push, follow the commit hand-off.
- If the task reaches a natural stopping point, follow the `debrief`
  skill first, then the commit hand-off for the end-of-task
  confirmation.
- If the user wants a PR, follow the PR hand-off.
- If a side topic worth studying appears, suggest
  /test-lab-learning:explore. Only the user starts it.

## Commit hand-off

- If an installed skill's description says it handles git commits
  (grouping, message format, or the push), follow that skill.
- If no such skill is installed, use this fallback. At the stopping
  point, propose in one message: the commit split, each commit
  message, and the push. Wait for the user's yes. On yes, stage each
  group with explicit paths. Commit each group. Then run
  `git push -u origin <branch>` and stop. One commit holds one
  meaningful change. The subject is imperative and 65 characters max.
  Never add an attribution trailer.
- Never create a PR from the commit hand-off.

## PR hand-off

- If an installed skill's description says it creates pull requests,
  tell the user to type its command. Only that skill creates the PR.
- If no such skill is installed, draft a title and body, show them
  with the matching `gh pr create` command, and stop. The user runs
  it.

## Branch format

```text
<type>/<kebab-slug>
```

The slug is 2-4 kebab-case words that name the task.

Types:

- feat: new capability
- fix: bug fix
- chore: maintenance, tooling, config
- refactor: restructure without behavior change
- docs: documentation only
- test: tests only

## Example

```text
task:    "add a freshness test to the orders source"
branch:  test/orders-source-freshness
```
