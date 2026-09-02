#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pygments==2.21.0"]
# [tool.uv]
# exclude-newer = "2026-09-02T00:00:00Z"
# ///
"""Build a self-contained concept page for the explore skill.

Deterministic converter, no LLM: wraps the briefing HTML fragment in the
page template (Rose Pine dark), highlights fenced code at build time
with Pygments, and opens the result in the browser. The output stays
one file with no external resource.

The fragment is model-written from fetched pages and the result opens
in a browser, so the page carries a Content Security Policy that blocks
scripts and remote resources, the build accepts only an allowlist of
tags and attributes, and the output path must stay inside the project.
"""

import argparse
import html
import os
import pathlib
import re
import shutil
import subprocess
import sys
from html.parser import HTMLParser

from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexers import get_lexer_by_name
from pygments.util import ClassNotFound

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  :root {{
    --base: #191724; --surface: #1f1d2e; --overlay: #26233a;
    --text: #e0def4; --muted: #908caa; --rose: #ebbcba;
    --pine: #31748f; --foam: #9ccfd8; --gold: #f6c177; --iris: #c4a7e7;
  }}
  body {{ margin: 0; background: var(--base); color: var(--text);
         font-family: system-ui, sans-serif; line-height: 1.65; }}
  main {{ max-width: 44rem; margin: 0 auto; padding: 3rem 1.5rem 5rem; }}
  h1 {{ color: var(--rose); font-size: 2rem;
       border-bottom: 2px solid var(--pine); padding-bottom: .4rem; }}
  h2 {{ color: var(--foam); margin-top: 2.2rem; }}
  a {{ color: var(--iris); }}
  code {{ background: var(--overlay); color: var(--gold);
          padding: .1rem .35rem; border-radius: 4px; }}
  pre {{ background: var(--surface); padding: 1rem; border-radius: 8px;
         overflow-x: auto; }}
  pre code {{ background: none; padding: 0; color: var(--text); }}
  .insight {{ border-left: 4px solid var(--pine); background: var(--surface);
              color: var(--text); padding: .7rem 1rem; margin: 1.2rem 0;
              border-radius: 0 8px 8px 0; }}
  .insight::before {{ content: "Insight"; display: block; color: var(--foam);
                      font-weight: 600; font-size: .85rem;
                      text-transform: uppercase; letter-spacing: .05em; }}
  details {{ background: var(--surface); border: 1px solid var(--overlay);
             border-radius: 8px; padding: .6rem 1rem; margin: .8rem 0; }}
  summary {{ cursor: pointer; font-weight: 600; color: var(--gold); }}
  details[open] summary {{ color: var(--muted); }}
  .source {{ color: var(--muted); font-size: .9rem; margin-top: 3rem;
             border-top: 1px solid var(--overlay); padding-top: 1rem; }}
  /* Pygments token classes, scoped to pre so short names cannot
     collide with page classes. Rose Pine mapping: keys foam,
     strings gold, numbers iris, keywords pine, comments muted. */
  pre .nt, pre .no, pre .nb, pre .nv, pre .bp {{ color: var(--foam); }}
  pre .s, pre .s1, pre .s2, pre .sb, pre .sd,
  pre .se {{ color: var(--gold); }}
  pre .m, pre .mi, pre .mf, pre .mh {{ color: var(--iris); }}
  pre .k, pre .kd, pre .kn, pre .kt, pre .kc,
  pre .ow {{ color: var(--pine); }}
  pre .nf, pre .na, pre .nd {{ color: var(--rose); }}
  pre .c, pre .c1, pre .cm, pre .cs {{ color: var(--muted);
                                       font-style: italic; }}
  /* YAML block-scalar bodies and constants are scalar values, so they
     read as strings, not as names. */
  pre code.language-yaml .no {{ color: var(--gold); }}
  pre .p, pre .o {{ color: var(--muted); }}
  pre [class^="l-"], pre .l {{ color: var(--text); }}
</style>
</head>
<body>
<main>
<h1>{title}</h1>
{briefing}
</main>
</body>
</html>
"""


CODE_BLOCK = re.compile(
    r'<pre><code class="language-([A-Za-z0-9_+-]+)">(.*?)</code></pre>',
    re.DOTALL,
)

# The briefing may use only these tags. Attributes are limited per tag;
# href must be http(s). Everything else is refused, including any
# on* handler, style, script, and media. Code samples are HTML-escaped
# inside <pre><code>, so real markup never needs more than this.
ALLOWED_TAGS = {
    "h2",
    "h3",
    "p",
    "pre",
    "code",
    "div",
    "details",
    "summary",
    "a",
    "ul",
    "ol",
    "li",
    "em",
    "strong",
    "br",
    "blockquote",
    "span",
    "table",
    "thead",
    "tbody",
    "tr",
    "th",
    "td",
}
ALLOWED_ATTRS = {"class": ALLOWED_TAGS, "href": {"a"}, "open": {"details"}}
HREF = re.compile(r"^https?://", re.IGNORECASE)


class FragmentCheck(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.problems: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag not in ALLOWED_TAGS:
            self.problems.append(f"tag <{tag}>")
            return
        for name, value in attrs:
            if tag not in ALLOWED_ATTRS.get(name, set()):
                self.problems.append(f"attribute {name} on <{tag}>")
            elif name == "href" and not HREF.match(value or ""):
                self.problems.append(f"href {value!r} is not http(s)")

    handle_startendtag = handle_starttag


def check_fragment(briefing: str) -> None:
    parser = FragmentCheck()
    parser.feed(briefing)
    parser.close()
    if parser.problems:
        sys.exit("refused: " + "; ".join(parser.problems[:5]))


def resolve_out(raw: str) -> pathlib.Path:
    """The page lands inside the project, as a new or replaced .html file."""
    root = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()).resolve()
    out = pathlib.Path(raw)
    if out.is_symlink():
        sys.exit("refused: --out is a symlink")
    out = out.resolve()
    if root not in out.parents or out.suffix != ".html":
        sys.exit(f"refused: --out must be an .html file inside {root}")
    return out


def _highlight_block(match: re.Match) -> str:
    lang, escaped = match.group(1), match.group(2)
    try:
        lexer = get_lexer_by_name(lang)
    except ClassNotFound:
        print(f"no lexer for {lang!r}, block left plain")
        return match.group(0)
    spans = highlight(html.unescape(escaped), lexer, HtmlFormatter(nowrap=True))
    return f'<pre><code class="language-{lang}">{spans.rstrip()}\n</code></pre>'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--briefing", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-open", action="store_true", help="do not open a browser")
    args = ap.parse_args()

    out = resolve_out(args.out)
    briefing = pathlib.Path(args.briefing).read_text(encoding="utf-8")
    check_fragment(briefing)
    briefing = CODE_BLOCK.sub(_highlight_block, briefing)
    out.parent.mkdir(parents=True, exist_ok=True)
    page = PAGE.format(title=html.escape(args.title), briefing=briefing)
    out.write_text(page, encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size} bytes)")

    if args.no_open:
        return
    # wslview covers WSL, xdg-open Linux, open macOS; silently skip when
    # no opener exists (CI, headless).
    for opener in ("wslview", "xdg-open", "open"):
        if shutil.which(opener):
            subprocess.Popen(
                [opener, str(out.resolve())],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            print(f"opened with {opener}")
            break


if __name__ == "__main__":
    main()
