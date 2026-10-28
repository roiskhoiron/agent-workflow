#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"

# fm FILE KEY -> value of KEY in the leading --- frontmatter block (empty if absent)
fm() { awk -v k="$2" 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1&&index($0,k": ")==1{print substr($0,length(k)+3)}' "$1"; }

for pair in spv:opus validator:opus reviewer:opus release:haiku coder:sonnet qa:sonnet; do
  n=${pair%%:*} m=${pair#*:} f="$REPO/agents/$n.md"
  assert_eq yes "$([ -f "$f" ] && echo yes || echo no)" "agents/$n.md exists"
  [ -f "$f" ] || continue
  assert_eq "$n" "$(fm "$f" name)" "$n: name"
  assert_eq "$m" "$(fm "$f" model)" "$n: model"
  assert_eq yes "$([ -n "$(fm "$f" description)" ] && echo yes || echo no)" "$n: description"
  tools=$(fm "$f" tools)
  case $n in
    coder|qa)
      assert_eq yes "$([ -n "$tools" ] && echo yes || echo no)" "$n: explicit tools"
      assert_eq no "$(printf '%s' "$tools" | grep -qE 'mcp__|Atlassian|Claude_Docs' && echo yes || echo no)" "$n: no MCP tools" ;;
    *) assert_eq "" "$tools" "$n: inherits all tools" ;;
  esac
done

# every shared-doc / script reference must resolve inside the repo
files=$(ls "$REPO"/agents/*.md "$REPO"/skills/*/*.md 2>/dev/null)
for r in $(cat $files | grep -oE '_agent-workflow-shared/[A-Za-z0-9_-]+\.md' | sort -u); do
  assert_eq yes "$([ -f "$REPO/skills/_shared/${r#*/}" ] && echo yes || echo no)" "ref $r exists"
done
for r in $(cat $files | grep -oE 'AGENT_WORKFLOW_DIR/bin/[A-Za-z0-9_.-]+' | sort -u); do
  assert_eq yes "$([ -f "$REPO/bin/${r##*/}" ] && echo yes || echo no)" "ref $r exists"
done
for d in rules devices credentials build-release report-format; do
  assert_eq yes "$([ -f "$REPO/skills/_shared/$d.md" ] && echo yes || echo no)" "_shared/$d.md exists"
done
assert_eq yes "$([ -f "$REPO/templates/qa.local.properties" ] && echo yes || echo no)" "qa template exists"
# public repo: no user paths or private words (extra words: gitignored .private-denylist, one per line)
assert_eq "" "$(grep -lE '/Users/|@gmail' $files "$REPO/templates/qa.local.properties" 2>/dev/null)" "no private identifiers"
if [ -f "$REPO/.private-denylist" ]; then
  assert_eq "" "$(git -C "$REPO" grep -lwFf <(grep -v '^[[:space:]]*$' "$REPO/.private-denylist") -- . ':!.private-denylist' 2>/dev/null)" "no words from .private-denylist in tracked files"
fi

echo "agents_test FAILS=$FAILS"; exit $FAILS
