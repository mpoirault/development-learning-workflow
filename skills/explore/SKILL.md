---
name: explore
description: >-
  Learning spike for a concept, article, or link. Typed only, as
  /test-lab-learning:explore <topic or url>; never started by the model.
  Produces a grounded briefing in chat, a concept page under
  explorations/, and a forced verdict: implement now, park, or drop.
disable-model-invocation: true
---

# explore

/test-lab-learning:explore starts a learning spike. It always ends in one of three
verdicts. Take no implementation action before the verdict is spoken and
answered.

## Input forms

- `/test-lab-learning:explore <topic>`: a concept, tool, or technique by name.
- `/test-lab-learning:explore <url>`, or a pasted article: read it first, then name the
  core concept back to the user and continue with that concept. The
  article is the seed, not the authority. Verify its checkable facts per
  the retrieval rules, say where it is out of date, and cite it in the
  briefing and on the page.

## Behavior

1. Ground the facts (retrieval rules below).
2. Read the repo context the concept touches: the code, config, and
   CI it changes, and earlier pages in `explorations/`.
3. Give the briefing in chat (briefing shape below).
4. Ask only the 1-2 questions whose answers change the verdict. Discuss.
5. Build the concept page (page procedure below).
6. Force the verdict (verdict rules below).

## Retrieval rules

- Never write a checkable fact from memory. Versions, config keys, API
  shapes, and product names change under you.
- context7 (`resolve-library-id`, then `query-docs`) is the primary source
  for library-shaped facts: config keys, function signatures, runtime
  behavior, schema definitions.
- WebSearch covers conceptual material context7 does not hold.
- If context7 is not installed, tell the user once per session how to
  add it: `/plugin install context7@claude-plugins-official`. Then
  continue with the official docs site via WebFetch and say so in the
  source line.
- If context7 is installed but down, fall back to the official docs
  site via WebFetch and say so in the source line. Ask the user only
  when no official source is reachable.
- If the topic involves a product that renames its features often, do
  a live check even when confident.

## Briefing shape

- Fundamentals first: state the general question the concept answers,
  before any repo specifics.
- Then the fit: how the concept fits this repo and what adopting it
  changes, concretely, naming real files. Describe impact and fit, not
  advocacy. "Why it matters" framing is banned; the verdict can be drop.
- Then one comparison question that ties the concept to something the
  user already built here.
- Define each jargon term once, at first use.
- Give a concrete example before the abstract rule.
- At most one "Insight:" callout per section, for the non-obvious point.
- If an installed skill's description says it shapes writing style,
  invoke it before drafting the briefing and the page fragment. Match
  it by description, not by name.

## Page procedure

1. Write a briefing HTML fragment in the session scratchpad, never in
   the repo: the briefing sections as `<h2>` and
   `<p>` (the sections cover the principle, how the concept fits this
   repo, repo connections naming real files, open questions), at most one
   `<div class="insight">` per section, 2-3 quick-check questions with
   each answer collapsed in `<details><summary>`, and a
   `<p class="source">` line at the bottom. Write every code example as
   `<pre><code class="language-<lang>">` (yaml, sql, python, hcl, ...)
   with the content HTML-escaped; the build script highlights it at
   build time, so an untagged block stays one flat color. The source
   line links every
   source as `<a href="<url>">`, the verified page itself, not a search
   result. Before you link a URL, fetch it and make sure that it
   resolves.
2. Build the page with the script next to this SKILL.md, at
   `scripts/build_page.py`. Use the absolute path of the directory that
   holds this SKILL.md, never a path relative to the repo:

   ```text
   <skill directory>/scripts/build_page.py \
     --briefing <fragment.html> \
     --title "<Concept>" --out explorations/<slug>.html
   ```

   The script declares its own dependency (pygments) in an inline
   block and runs through uv. If uv is missing, tell the user to
   install it and stop. The output path must be an `.html` file
   inside the project; the script refuses anything else.
3. The result is one self-contained file, styled by the script (Rose
   Pine dark). The build script opens it in the browser. If the host has
   no opener (CI, headless), give the user the path instead. The
   fragment source does not get committed. The page is committed only
   when the verdict is park (verdict rules below).

## Verdict

End with exactly one of these. Never end in a hedge. Every verdict adds
an entry to `IDEAS.md`, so the file logs every exploration. If
`IDEAS.md` does not exist, create it from the template at the end of
this skill. The page outlives the exploration only on park.

- Implement now: add a one-line entry with the date under Implemented
  in `IDEAS.md`, remove the exploration page, then follow the `flow`
  skill and start the work.
- Park: add an entry under Parked in `IDEAS.md` with the problem it
  solves, the trigger to reconsider, the source, and the page link.
  The page stays in `explorations/` and gets committed.
- Drop: add a one-line entry with the reason under Discarded in
  `IDEAS.md`, and remove the exploration page.

When the exploration is the whole task (run, verdict, nothing else),
the verdict is the natural stopping point. Skip the `debrief` skill,
the exploration was the learning pass, and follow the commit hand-off
in the `flow` skill: a parked page and its IDEAS.md entry are one
commit, proposed and pushed on the user's yes.

## IDEAS.md template

```markdown
# Ideas

Log of exploration verdicts; every exploration lands here. A parked idea
waits for its trigger and keeps its page in `explorations/`. An
implemented idea records what it added. A discarded idea keeps its
reason, so it is not re-litigated without new evidence.

## Parked

<!-- entry format:
### <title>
- problem: <what it would solve in this repo>
- trigger to reconsider: <event or condition>
- source: <what raised the idea>
- page: explorations/<slug>.html
-->

## Implemented

<!-- format: - <title>: <what it added> (<YYYY-MM-DD>) -->

## Discarded

<!-- format: - <title>: <one-line reason> (<YYYY-MM-DD>) -->
```
