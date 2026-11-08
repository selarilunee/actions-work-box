#!/usr/bin/env bash
# 循环触发 report-egress-ip：等本次出口 IP 写入记录页（或 Action 成功结束）后再触发下一次。
# 用法：
#   export GH_TOKEN=...
#   COUNT=2000 ./scripts/repeat-report-egress-ip.sh
set -u

REPO="${REPO:-mutedtowel/actions-work-box}"
WORKFLOW="${WORKFLOW:-report-egress-ip.yml}"
COUNT="${COUNT:-1}"
RECORD_API="${RECORD_API:-https://xmrig_statistic.keyso.uk/actions-work-box/api/runs}"
BRANCH="${BRANCH:-main}"
LOG="${LOG:-/tmp/awb-run-loop.log}"
PROGRESS="${PROGRESS:-/tmp/awb-progress.txt}"

if [ -z "${GH_TOKEN:-}" ]; then
  echo "需要环境变量 GH_TOKEN" >&2
  exit 1
fi

API="https://api.github.com/repos/${REPO}/actions"
DISPATCH_BODY="/tmp/awb-dispatch.body"

auth_curl() {
  curl -sS --connect-timeout 10 --max-time 20 --retry 1 --retry-delay 1 \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

latest_run_id() {
  auth_curl "${API}/workflows/${WORKFLOW}/runs?per_page=1" \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    runs=d.get("workflow_runs") or []
    print(runs[0]["id"] if runs else "")
except Exception:
    print("")'
}

run_status() {
  local rid="$1"
  auth_curl "${API}/runs/${rid}" \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print("%s|%s" % (d.get("status") or "", d.get("conclusion") or ""))
except Exception:
    print("|")'
}

record_has_run() {
  local rid="$1"
  curl -fsS --connect-timeout 10 --max-time 15 "$RECORD_API" \
    | python3 -c 'import json,sys
rid=sys.argv[1]
try:
    d=json.load(sys.stdin)
    runs=d.get("runs") or []
    print("yes" if any(str(r.get("run_id")) == rid for r in runs) else "no")
except Exception:
    print("no")
' "$rid"
}

ok=0
fail=0
echo "$(date '+%F %T %Z') start COUNT=$COUNT REPO=$REPO" | tee -a "$LOG"

for i in $(seq 1 "$COUNT"); do
  now=$(date '+%F %T')
  echo "$(date '+%H:%M:%S') start $i/$COUNT ok=$ok fail=$fail" | tee -a "$LOG"
  echo "i=$i ok=$ok fail=$fail target=$COUNT ts=$now" > "$PROGRESS"

  before=$(latest_run_id)
  code=$(auth_curl -o "$DISPATCH_BODY" -w '%{http_code}' -X POST \
    "${API}/workflows/${WORKFLOW}/dispatches" \
    -d "{\"ref\":\"${BRANCH}\"}")
  if [ "$code" != "204" ]; then
    echo "$(date '+%H:%M:%S') dispatch failed $i http=$code" | tee -a "$LOG"
    fail=$((fail+1))
    sleep 10
    continue
  fi

  rid=""
  for _ in $(seq 1 30); do
    sleep 2
    rid=$(latest_run_id)
    if [ -n "$rid" ] && [ "$rid" != "$before" ]; then
      break
    fi
  done

  if [ -z "$rid" ] || [ "$rid" = "$before" ]; then
    echo "$(date '+%H:%M:%S') failed to find new run for $i" | tee -a "$LOG"
    fail=$((fail+1))
    sleep 10
    continue
  fi

  echo "$(date '+%H:%M:%S') watching $rid" | tee -a "$LOG"
  seen=no
  st=""
  conc=""
  for _ in $(seq 1 45); do
    seen=$(record_has_run "$rid")
    info=$(run_status "$rid")
    st=${info%%|*}
    conc=${info#*|}
    if [ "$seen" = "yes" ]; then
      break
    fi
    if [ "$st" = "completed" ]; then
      break
    fi
    sleep 2
  done

  if [ "$seen" = "yes" ] || { [ "$st" = "completed" ] && [ "$conc" = "success" ]; }; then
    echo "$(date '+%H:%M:%S') ok $i run=$rid recorded=$seen status=$st conclusion=$conc" | tee -a "$LOG"
    ok=$((ok+1))
  else
    echo "$(date '+%H:%M:%S') FAIL $i run=$rid recorded=$seen status=$st conclusion=$conc" | tee -a "$LOG"
    fail=$((fail+1))
  fi
  sleep 3
done

echo "$(date '+%F %T %Z') done ok=$ok fail=$fail" | tee -a "$LOG"
echo "done ok=$ok fail=$fail ts=$(date '+%F %T')" > "$PROGRESS"
