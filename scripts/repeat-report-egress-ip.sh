#!/usr/bin/env bash
# 循环触发 report-egress-ip：以记录页出现新 run 为准，再启动下一次。
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
  curl -sS --connect-timeout 8 --max-time 12 \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

latest_recorded() {
  curl -fsS --connect-timeout 8 --max-time 12 "$RECORD_API" \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    runs=d.get("runs") or []
    if not runs:
        print("|")
    else:
        r=runs[0]
        print("%s|%s" % (r.get("run_id") or "", r.get("egress_ip") or ""))
except Exception:
    print("|")'
}

ok=0
fail=0
echo "$(date '+%F %T %Z') start COUNT=$COUNT REPO=$REPO wait=record-page" | tee -a "$LOG"

for i in $(seq 1 "$COUNT"); do
  now=$(date '+%F %T')
  echo "$(date '+%H:%M:%S') start $i/$COUNT ok=$ok fail=$fail" | tee -a "$LOG"
  echo "i=$i ok=$ok fail=$fail target=$COUNT ts=$now" > "$PROGRESS"

  before=$(latest_recorded)
  before_rid=${before%%|*}

  code=$(auth_curl -o "$DISPATCH_BODY" -w '%{http_code}' -X POST \
    "${API}/workflows/${WORKFLOW}/dispatches" \
    -d "{\"ref\":\"${BRANCH}\"}" || true)
  if [ "$code" != "204" ]; then
    echo "$(date '+%H:%M:%S') dispatch failed $i http=${code:-none}" | tee -a "$LOG"
    fail=$((fail+1))
    sleep 8
    continue
  fi

  rid=""
  ip=""
  for _ in $(seq 1 40); do
    sleep 2
    rec=$(latest_recorded)
    rid=${rec%%|*}
    ip=${rec#*|}
    if [ -n "$rid" ] && [ "$rid" != "$before_rid" ]; then
      break
    fi
  done

  if [ -n "$rid" ] && [ "$rid" != "$before_rid" ]; then
    echo "$(date '+%H:%M:%S') ok $i run=$rid ip=$ip" | tee -a "$LOG"
    ok=$((ok+1))
  else
    echo "$(date '+%H:%M:%S') FAIL $i no new record before=$before_rid last=$rid" | tee -a "$LOG"
    fail=$((fail+1))
  fi
  sleep 2
done

echo "$(date '+%F %T %Z') done ok=$ok fail=$fail" | tee -a "$LOG"
echo "done ok=$ok fail=$fail ts=$(date '+%F %T')" > "$PROGRESS"
