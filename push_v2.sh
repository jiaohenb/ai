#!/system/bin/sh
#
# 用 GitHub Git Data API 推送工程。全程只用 POST，规避 busybox wget 不支持 PUT 的限制。
#
# 流程:
#   1. GET  /user                                    校验 token
#   2. POST /user/repos                              建仓库
#   3. POST /repos/:o/:r/git/blobs                   每个文件建一个 blob，拿 sha
#   4. POST /repos/:o/:r/git/trees                   用 blob sha 建完整目录树
#   5. POST /repos/:o/:r/git/commits                 建 commit
#   6. POST /repos/:o/:r/git/refs                    把 main 指向该 commit
#
# token scope 需要 repo + workflow（workflow 用于写 .github/workflows/build.yml）
#
set -u

BB=/data/adb/ksu/bin/busybox
SRC=/sdcard/KsuAiBridge
API=https://api.github.com

TOKEN="${1:-}"
REPO="${2:-KsuAiBridge}"

if [ -z "$TOKEN" ]; then
  echo "usage: $0 <github_token> [repo_name]"
  exit 1
fi

H_AUTH="Authorization: token $TOKEN"
H_ACC="Accept: application/vnd.github+json"
H_UA="User-Agent: ksu-ai-bridge"
H_CT="Content-Type: application/json"

post() {
  # $1=url  $2=json
  "$BB" wget -q -O- \
    --header="$H_AUTH" --header="$H_ACC" --header="$H_UA" --header="$H_CT" \
    --post-data="$2" "$1" 2>/dev/null
}

get() {
  "$BB" wget -q -O- \
    --header="$H_AUTH" --header="$H_ACC" --header="$H_UA" "$1" 2>/dev/null
}

jget() {
  # 从 JSON 里抠字符串字段: jget <json> <key>
  echo "$1" | "$BB" sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# ---------- 1. 身份 ----------
echo "[1/6] 校验 token ..."
ME=$(get $API/user)
LOGIN=$(jget "$ME" login)
if [ -z "$LOGIN" ]; then
  echo "  token 无效. 响应:"
  echo "$ME" | head -c 300; echo
  exit 2
fi
echo "  用户: $LOGIN"

# ---------- 2. 建仓库 ----------
echo "[2/6] 建仓库 $LOGIN/$REPO ..."
CR=$(post $API/user/repos "{\"name\":\"$REPO\",\"private\":false,\"auto_init\":false}")
if echo "$CR" | "$BB" grep -q '"full_name"'; then
  echo "  已创建"
elif echo "$CR" | "$BB" grep -q 'already exists'; then
  echo "  已存在 复用"
else
  echo "  返回: $(echo "$CR" | head -c 300)"
fi

# ---------- 3. 逐文件建 blob ----------
echo "[3/6] 上传 blob ..."
cd "$SRC" || { echo "  $SRC 不存在"; exit 3; }

# 收集 "路径<TAB>sha" 表
TREE_ENTRIES=""
OK=0; FAIL=0

LIST=$("$BB" find . -type f \
  ! -name 'push_to_github.sh' \
  ! -name 'push_v2.sh' \
  ! -name '*.apk' \
  | "$BB" sed 's|^\./||' | sort)

for REL in $LIST; do
  [ -f "./$REL" ] || continue

  B64=$("$BB" base64 "./$REL" | "$BB" tr -d '\n')
  RB=$(post "$API/repos/$LOGIN/$REPO/git/blobs" \
        "{\"content\":\"$B64\",\"encoding\":\"base64\"}")
  SHA=$(jget "$RB" sha)

  if [ -z "$SHA" ]; then
    echo "  FAIL $REL"
    echo "       $(echo "$RB" | head -c 200)"
    FAIL=$((FAIL+1))
    continue
  fi

  echo "  ok   $REL  ${SHA%????????????????????????????????}"
  OK=$((OK+1))

  ENTRY="{\"path\":\"$REL\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$SHA\"}"
  if [ -z "$TREE_ENTRIES" ]; then
    TREE_ENTRIES="$ENTRY"
  else
    TREE_ENTRIES="$TREE_ENTRIES,$ENTRY"
  fi
done

echo "  blob 成功 $OK / 失败 $FAIL"
if [ "$OK" -eq 0 ]; then
  echo "  没有成功上传任何文件，终止"
  exit 4
fi

# ---------- 4. 建 tree ----------
echo "[4/6] 建目录树 ..."
RT=$(post "$API/repos/$LOGIN/$REPO/git/trees" "{\"tree\":[$TREE_ENTRIES]}")
TSHA=$(jget "$RT" sha)
if [ -z "$TSHA" ]; then
  echo "  tree 失败: $(echo "$RT" | head -c 300)"
  exit 5
fi
echo "  tree $TSHA"

# ---------- 5. 建 commit ----------
echo "[5/6] 建 commit ..."
RC=$(post "$API/repos/$LOGIN/$REPO/git/commits" \
  "{\"message\":\"init: KSU AI Bridge LSPosed module\",\"tree\":\"$TSHA\",\"parents\":[]}")
CSHA=$(jget "$RC" sha)
if [ -z "$CSHA" ]; then
  echo "  commit 失败: $(echo "$RC" | head -c 300)"
  exit 6
fi
echo "  commit $CSHA"

# ---------- 6. 建 ref ----------
echo "[6/6] 建 main 分支 ..."
RR=$(post "$API/repos/$LOGIN/$REPO/git/refs" \
  "{\"ref\":\"refs/heads/main\",\"sha\":\"$CSHA\"}")
if echo "$RR" | "$BB" grep -q 'refs/heads/main'; then
  echo "  main -> $CSHA"
else
  echo "  ref 返回: $(echo "$RR" | head -c 300)"
fi

echo ""
echo "仓库 : https://github.com/$LOGIN/$REPO"
echo "Actions: https://github.com/$LOGIN/$REPO/actions"
echo "失败文件 $FAIL 个。若非 0 且报 workflow，是 token 缺 workflow scope。"
