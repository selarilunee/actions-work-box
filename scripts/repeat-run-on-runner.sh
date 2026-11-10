#!/usr/bin/env bash
# 串行薄壳：按 --count 逐轮调用 run-on-runner.sh，任一轮失败即停止。
set -u

usage() {
  cat <<'EOF'
用法：repeat-run-on-runner.sh --count N --repo OWNER/REPO --ref BRANCH
                              --pat-file FILE --task-dir DIR --output-dir DIR

逐轮串行调用 run-on-runner.sh，每轮返回并确认完成后才开始下一轮，
任一轮非零退出立即停止。不默认无限循环，不并行。

开头自动生成一对临时 SSH 密钥供所有轮次使用，退出时删除，无需传 --ssh-key。
必填：--count --repo --ref --pat-file --task-dir --output-dir
可选：--startup-timeout（默认 600）--cleanup-timeout（默认 180）--help
各参数含义见 run-on-runner.sh --help。
EOF
}

die()  { echo "错误：$*" >&2; usage >&2; exit 2; }
fail() { echo "错误：$*" >&2; exit 1; }
log()  { echo "[$(date '+%H:%M:%S')] $*"; }

COUNT=""; REPO=""; REF=""; PAT_FILE=""; TASK_DIR=""; OUTPUT_DIR=""
STARTUP_TIMEOUT=600; CLEANUP_TIMEOUT=180

# 参数去掉 -- 后大写、连字符转下划线，正好就是上面的变量名
while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --count|--repo|--ref|--pat-file|--task-dir|--output-dir|--startup-timeout|--cleanup-timeout)
      [ $# -ge 2 ] || die "$1 缺少值"
      name=$(printf '%s' "${1#--}" | tr 'a-z-' 'A-Z_')
      printf -v "$name" '%s' "$2"
      shift 2 ;;
    *) die "未知参数 $1" ;;
  esac
done

for v in COUNT REPO REF PAT_FILE TASK_DIR OUTPUT_DIR; do
  [ -n "${!v}" ] || die "缺少必填参数 $v"
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
[ -r "$SCRIPT_DIR/run-on-runner.sh" ] || die "找不到单轮脚本"

# 开头生成一对临时密钥；单轮脚本用私钥登录，公钥由私钥推导后作为 input 传入
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/awb-repeat.XXXXXX") || fail "无法创建临时目录"
trap 'rm -rf "$TMP_DIR"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$TMP_DIR/id_ed25519" || fail "无法生成 SSH 密钥"
log "临时 SSH 私钥：${TMP_DIR}/id_ed25519（脚本退出后删除）"

# 数组传参，不用 eval，路径里的空格和特殊字符保持原样
args=(--repo "$REPO" --ref "$REF" --pat-file "$PAT_FILE"
      --ssh-key "$TMP_DIR/id_ed25519"
      --task-dir "$TASK_DIR" --output-dir "$OUTPUT_DIR"
      --startup-timeout "$STARTUP_TIMEOUT" --cleanup-timeout "$CLEANUP_TIMEOUT")

i=1
while [ "$i" -le "$COUNT" ]; do
  log "开始第 $i/$COUNT 轮"
  "$SCRIPT_DIR/run-on-runner.sh" "${args[@]}"
  rc=$?
  [ "$rc" -eq 0 ] || { log "第 $i/$COUNT 轮失败，退出码=${rc}，停止"; exit "$rc"; }
  log "第 $i/$COUNT 轮完成"
  i=$((i + 1))
done
log "全部 $COUNT 轮完成"
