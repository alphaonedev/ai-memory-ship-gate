#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Generate a self-contained, offline-browsable index.html inside a
# runs/<campaign-id>/ directory. The HTML summarises the campaign
# (pass/fail badges, per-phase JSON dossiers) and loads in any
# browser with no external dependencies.
#
# Usage:
#   ./scripts/generate_run_html.sh runs/v0.6.0.0-final-r19
#
# Or backfill everything:
#   for d in runs/*/; do ./scripts/generate_run_html.sh "$d"; done

set -euo pipefail

DIR="${1:?usage: $0 <run-directory>}"
[ -d "$DIR" ] || { echo "not a directory: $DIR" >&2; exit 1; }
SUMMARY="$DIR/campaign-summary.json"
[ -f "$SUMMARY" ] || { echo "no campaign-summary.json in $DIR — skipping" >&2; exit 0; }

OUT="$DIR/index.html"
NAME=$(basename "$DIR")

# --- pull top-level fields from campaign-summary.json ----------------
REF=$(jq -r '.ai_memory_git_ref // "?"' "$SUMMARY")
COMPLETED=$(jq -r '.completed_at // "?"' "$SUMMARY")
PASS=$(jq -r '.overall_pass // false' "$SUMMARY")
if [ "$PASS" = "true" ]; then
  PASS_CLASS="pass"
  PASS_LABEL="PASS"
else
  PASS_CLASS="fail"
  PASS_LABEL="FAIL"
fi

# --- HTML-escape helper (for safety when inlining JSON) --------------
html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# --- per-phase blocks ------------------------------------------------
phase_block() {
  local phase="$1"
  local files=()
  if [ "$phase" = "1" ]; then
    # Phase 1 is per-node; gather phase1-node-*.json
    for f in "$DIR"/phase1-node-*.json; do [ -e "$f" ] && files+=("$f"); done
  else
    for f in "$DIR"/phase"$phase".json; do [ -e "$f" ] && files+=("$f"); done
  fi
  [ "${#files[@]}" -gt 0 ] || return 0

  # Derive phase pass/fail from the first file's .pass if present.
  local first="${files[0]}"
  local p_pass
  p_pass=$(jq -r '.pass // empty' "$first" 2>/dev/null || true)
  local badge=""
  if [ "$p_pass" = "true" ]; then
    badge='<span class="badge pass">PASS</span>'
  elif [ "$p_pass" = "false" ]; then
    badge='<span class="badge fail">FAIL</span>'
  fi

  printf '      <section class="phase">\n'
  printf '        <h2>Phase %s %s</h2>\n' "$phase" "$badge"
  for f in "${files[@]}"; do
    local label
    label=$(basename "$f" .json)
    printf '        <details>\n'
    printf '          <summary>%s</summary>\n' "$label"
    # Prettified JSON, HTML-escaped, inside <pre>. jq --tab for
    # indentation and then escape the whole thing.
    printf '          <pre>'
    jq --tab . "$f" 2>/dev/null | html_escape
    printf '</pre>\n'
    # Also link to the raw JSON in the same directory for download /
    # machine-readable use.
    printf '          <p><a href="./%s">raw JSON</a></p>\n' "$(basename "$f")"
    printf '        </details>\n'
  done
  printf '      </section>\n'
}

# --- render ----------------------------------------------------------
{
cat <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Campaign ${NAME} — ai-memory ship-gate</title>
  <meta name="description" content="Per-phase evidence for ai-memory-mcp ship-gate campaign ${NAME} (ref ${REF}).">
  <style>
    :root {
      --fg: #1a1a1a; --bg: #fff; --muted: #666;
      --pass: #1a8b3c; --fail: #b32222; --pass-bg: #e6f6ea; --fail-bg: #fceaea;
      --border: #e0e0e0; --code-bg: #f7f7f9;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #eaeaea; --bg: #181818; --muted: #a0a0a0;
        --pass: #4adc76; --fail: #ff6a6a; --pass-bg: #153d23; --fail-bg: #401818;
        --border: #2a2a2a; --code-bg: #202028;
      }
    }
    * { box-sizing: border-box; }
    body { font: 14px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; color: var(--fg); background: var(--bg); margin: 0; padding: 0; }
    main { max-width: 920px; margin: 0 auto; padding: 2rem 1.25rem 4rem; }
    header { border-bottom: 1px solid var(--border); padding-bottom: 1rem; margin-bottom: 1.5rem; }
    header p.crumb { color: var(--muted); font-size: 13px; margin: 0 0 .25rem; }
    h1 { margin: .25rem 0 .75rem; font-size: 1.75rem; }
    h2 { margin: 1.5rem 0 .5rem; font-size: 1.15rem; border-bottom: 1px solid var(--border); padding-bottom: .25rem; }
    dl.meta { display: grid; grid-template-columns: max-content 1fr; gap: .35rem 1rem; margin: 0; }
    dl.meta dt { color: var(--muted); }
    dl.meta dd { margin: 0; }
    .badge { display: inline-block; padding: .15rem .55rem; border-radius: 999px; font-size: 12px; font-weight: 600; letter-spacing: .03em; text-transform: uppercase; margin-left: .4rem; vertical-align: middle; }
    .badge.pass { color: var(--pass); background: var(--pass-bg); }
    .badge.fail { color: var(--fail); background: var(--fail-bg); }
    details { border: 1px solid var(--border); border-radius: 6px; padding: .25rem .75rem; margin: .5rem 0; }
    details[open] { padding-bottom: .5rem; }
    summary { cursor: pointer; padding: .45rem 0; font-weight: 500; }
    pre { background: var(--code-bg); padding: .75rem; border-radius: 6px; overflow-x: auto; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; margin: .5rem 0; }
    a { color: inherit; }
    a:hover { color: var(--pass); }
    footer { color: var(--muted); font-size: 12px; border-top: 1px solid var(--border); padding-top: 1rem; margin-top: 3rem; }
  </style>
</head>
<body>
  <main>
    <header>
      <p class="crumb"><a href="../">../ runs index</a> · <a href="https://alphaonedev.github.io/ai-memory-ship-gate/runs/${NAME}.html">rendered on Pages</a></p>
      <h1>Campaign ${NAME} <span class="badge ${PASS_CLASS}">${PASS_LABEL}</span></h1>
      <dl class="meta">
        <dt>ai-memory ref</dt><dd><code>${REF}</code></dd>
        <dt>Completed at</dt><dd>${COMPLETED}</dd>
        <dt>Overall pass</dt><dd>${PASS}</dd>
      </dl>
    </header>
EOF

for p in 1 2 3 4; do
  phase_block "$p"
done

cat <<EOF
    <section>
      <h2>All artefacts</h2>
      <ul>
EOF
# List every JSON file in the directory so the page is a true index.
for f in "$DIR"/*.json; do
  [ -e "$f" ] || continue
  fn=$(basename "$f")
  printf '        <li><a href="./%s">%s</a></li>\n' "$fn" "$fn"
done
cat <<EOF
      </ul>
    </section>
    <footer>
      Generated by <code>scripts/generate_run_html.sh</code>.
      Repository:
      <a href="https://github.com/alphaonedev/ai-memory-ship-gate/tree/main/runs/${NAME}">
        alphaonedev/ai-memory-ship-gate/runs/${NAME}
      </a>.
      Methodology:
      <a href="https://alphaonedev.github.io/ai-memory-ship-gate/methodology/">
        alphaonedev.github.io/ai-memory-ship-gate/methodology
      </a>.
    </footer>
  </main>
</body>
</html>
EOF
} > "$OUT"

echo "wrote $OUT"
