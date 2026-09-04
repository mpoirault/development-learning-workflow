---
name: debrief
description: Learning close-out for a finished task that changed files.
  Use at the end of such a task, before the commit proposal, to walk
  the user through the diff. A guided opener, a concept walk, a teach-back with a
  TODO(human) blank, and a residual note saved only on approval.
---

# debrief

The user learns from the diff before it ships. Ask, do not lecture.
One question per message, then wait for the answer.

## When to run

The `flow` skill asks the user at the end of a novel task, before the
commit proposal, and routes here on yes. The user can also type
/test-lab-learning:debrief at any stopping point.
If the diff teaches nothing (a typo, a rename, a version bump),
say so in one line and continue to the commit hand-off in the `flow` skill.

## Behavior

1. Opener. Ask one guided question: what does the user think the diff
   does, and why is it built this way? The user states their
   half-formed theory before you explain anything.
2. Concept walk. Explain the diff against that theory: rationale
   first, then mechanics. Define each jargon term once, at first use.
   Give a concrete example before the abstract rule. At most one
   "Insight:" callout per concept, and it must be specific to this
   diff, not generic.
3. Teach-back. Ask 2-3 questions, one at a time.
   - At least one is a TODO(human) blank: re-present a small piece of
     the shipped diff (a test assertion, a Jinja condition, a column
     expression) with the gap marked by a literal `TODO(human)`. The
     user fills the gap and defends the choice; fill plus defend
     counts as one question.
   - If an answer is wrong or partial, probe once with a follow-up
     question before you reveal the correction. Then deepen with one
     harder variation.
   - Close with the metacognitive question: "What made you choose this
     approach over the alternative?"
4. Residual note, per the procedure below. Then route back to the
   commit hand-off in the `flow` skill.

## Residual note

- Synthesize the note from what the teach-back revealed: the gaps, the
  corrected misconceptions, the user's own phrasing. A diff summary is
  not a residual note.
- Write it per the `writing` skill when that skill is available.
- Show the note in chat and ask for approval.
- If the user approves and an installed skill's description says it
  stores notes in a knowledge base, save the note with that skill.
  Match it by description, not by name. If no such skill exists, ask the user what to do with the note.
- Never save without showing the note and getting a yes. No silent
  writes.
