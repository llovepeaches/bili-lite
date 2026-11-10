#!/usr/bin/env bash
# 将本仓库安全发布到 GitHub。
#
# 凭证策略：令牌只从 GH_TOKEN / GITHUB_TOKEN 环境变量读取，由 gh 注入请求头；
# 绝不写入文件、git remote URL、命令行参数、日志或提交历史。
# 本文件自身不包含任何令牌。
set -euo pipefail

REPO="${GITHUB_REPO:-bilibili-apps}"
BRANCH="${GITHUB_BRANCH:-main}"
VISIBILITY="${GITHUB_VISIBILITY:-private}"
OWNER="${GITHUB_OWNER:-}"

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -n "$TOKEN" ]]; then
  # 方式 A：环境变量注入，令牌只存在于当前进程内存
  export GH_TOKEN="$TOKEN"
  unset TOKEN
elif gh auth status >/dev/null 2>&1; then
  # 方式 B：gh 凭证管理器（gh auth login，令牌由 gh/系统钥匙串保管）
  echo "[i] 使用 gh 凭证管理器中已登录的身份"
else
  cat >&2 <<'HINT'
[!] 未检测到凭证，已中止（不会发起任何网络请求）。

    任选一种方式后重新运行：

    A. 环境变量（令牌不进 shell 历史、不落盘）
         read -rsp 'GitHub PAT: ' GH_TOKEN; export GH_TOKEN; echo
         ./push-to-github.sh

    B. 凭证管理器（推荐，浏览器授权，令牌由 gh 保管）
         gh auth login --hostname github.com
         ./push-to-github.sh
HINT
  exit 1
fi

command -v gh >/dev/null 2>&1 || { echo "需要 GitHub CLI: https://cli.github.com" >&2; exit 1; }

case "$VISIBILITY" in
  private) PRIVATE=true ;;
  public)  PRIVATE=false ;;
  *) echo "GITHUB_VISIBILITY 仅支持 private 或 public" >&2; exit 1 ;;
esac

if [[ -z "$OWNER" ]]; then
  OWNER="$(gh api user --jq .login)" || {
    echo "无法获取 GitHub 账号，请检查令牌是否有效" >&2
    exit 1
  }
fi

# remote URL 中绝不含凭证
TARGET_URL="https://github.com/${OWNER}/${REPO}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$TARGET_URL"

echo "[i] 目标: ${OWNER}/${REPO}  分支: ${BRANCH}  可见性: ${VISIBILITY}"

if gh api "repos/${OWNER}/${REPO}" >/dev/null 2>&1; then
  echo "[i] 仓库已存在，跳过创建"
else
  printf '{"name":"%s","private":%s,"description":"Bilibili 第三方客户端：Flutter 六端 + Rust/Python/Next.js 混合架构"}' \
    "$REPO" "$PRIVATE" |
    gh api --method POST /user/repos --input - >/dev/null
  echo "[ok] 已创建仓库 ${OWNER}/${REPO}"
fi

# 让 git 通过 gh 读取凭证，而不是把令牌拼进 URL
gh auth setup-git --hostname github.com -f >/dev/null 2>&1 ||
  git config --local "credential.https://github.com.helper" '!gh auth git-credential'

git branch -M "$BRANCH"
git push -u origin "$BRANCH"

echo "[ok] 推送完成: https://github.com/${OWNER}/${REPO}/tree/${BRANCH}"
