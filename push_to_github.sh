#!/system/bin/sh
#
# 一键把本地工程推到 GitHub 并触发 Actions 编译。
# 用法:  push_to_github.sh <github_token> [repo_name]
#
# token 需要两个 scope: repo + workflow
#   没有 workflow scope 时 GitHub 会拒绝写入 .github/workflows/ 下的文件，
#   表现为 404 或 "refusing to allow a Personal Access Token to create or update workflow"。
#
set -u

BB=/data/adb/ksu/bin/busybox
SRC=/sdcard/KsuAiBridge

TOKEN="${1:-}"
REPO="${2:-KsuAiBridge}"

if [ -z "$TOKEN" ]; then
  echo "usage: $0 <github_token> [repo_name]"
  exit 1
fi

API=https://api.github.com
AUTH="Authorization: token $TOKEN"
ACCEPT="Accept: application/vnd.github+json"
UA="User-Agent: ksu-ai-bridge-pusher"

wget() { "$BB" wget "$@"; }

# ---------- 1. 取当前登录用户 ----------
echo "[1/4] 校验 token ..."
ME=$(wget -q -O- --header="$AUTH" --header="$ACCEPT" --header="$UA" $API/user 2>/dev/null)
LOGIN=$(echo "$ME" | "$BB" sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
if [ -z "$LOGIN" ]; then
  echo "  token 无效或网络失败，原始响应:"
  echo "$ME" | head -c 300
  echo
  exit 2
fi
echo "  登录用户: $LOGIN"

# ---------- 2. 建仓库 ----------
echo "[2/4] 创建仓库 $LOGIN/$REPO ..."
CREATE=$(wget -q -O- \
  --header="$AUTH" --header="$ACCEPT" --header="$UA" \
  --header="Content-Type: application/json" \
  --post-data="{\"name\":\"$REPO\",\"private\":false,\"auto_init\":false}" \
  $API/user/repos 2>/dev/null)

if echo "$CREATE" | "$BB" grep -q 'already exists'; then
  echo "  仓库已存在，直接往里写"
elif echo "$CREATE" | "$BB" grep -q '"full_name"'; then
  echo "  创建成功"
else
  echo "  创建返回:"
  echo "$CREATE" | head -c 400
  echo
fi

# ---------- 3. 逐文件上传 ----------
echo "[3/4] 上传文件 ..."
cd "$SRC" || { echo "  $SRC 不存在"; exit 3; }

OK=0
FAIL=0

# 用 find 列出全部普通文件，去掉前导 ./，按稳定顺序
LIST=$("$BB" find . -type f ! -name 'push_to_github.sh' | "$BB" sed 's|^\./||' | sort)

for REL in $LIST; do
  ABS="./$REL"
  if [ ! -f "$ABS" ]; then
    continue
  fi

  B64=$("$BB" base64 "$ABS" | "$BB" tr -d '\n')

  # JSON 里路径不含特殊字符，直接拼安全
  BODY="{\"message\":\"add $REL\",\"content\":\"$B64\",\"branch\":\"main\"}"

  RESP=$(wget -q -O- \
    --header="$AUTH" --header="$ACCEPT" --header="$UA" \
    --header="Content-Type: application/json" \
    --method=PUT \
    --post-data="$BODY" \
    "$API/repos/$LOGIN/$REPO/contents/$REL" 2>/dev/null)

  if echo "$RESP" | "$BB" grep -q '"content"'; then
    echo "  ok   $REL"
    OK=$((OK + 1))
  elif echo "$RESP" | "$BB" grep -q 'workflow'; then
    echo "  FAIL $REL  <- token 缺 workflow scope"
    FAIL=$((FAIL + 1))
  elif echo "$RESP" | "$BB" grep -q '"sha"'; then
    echo "  ok   $REL (已存在, 未覆盖)"
    OK=$((OK + 1))
  else
    echo "  FAIL $REL"
    echo "       $(echo "$RESP" | head -c 160)"
    FAIL=$((FAIL + 1))
  fi
done

echo "  成功 $OK 个, 失败 $FAIL 个"

# ---------- 4. 汇总 ----------
echo "[4/4] 完成"
echo "  仓库地址 : https://github.com/$LOGIN/$REPO"
echo "  Actions  : https://github.com/$LOGIN/$REPO/actions"
if [ "$FAIL" -gt 0 ]; then
  echo "  有文件失败，最可能是 token 没勾 workflow scope，重新生成 token 再跑一次"
  exit 4
fi
echo "  等 Actions 跑完，在 artifact 里下载 KsuAiBridge-debug.zip，解压就是 APK"
