#!/bin/bash
# =============================================
#  三年级学习工作台 · 一键部署到 GitHub Pages
#  双击运行；过程写入本文件夹「部署日志.txt」
#  自动下载独立版 GitHub CLI，无需 Homebrew
# =============================================
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [ -z "$BASH_VERSION" ]; then exec /bin/bash "$0" "$@"; fi
cd "$(dirname "$0")" || exit 1
LOG_FILE="$(pwd)/部署日志.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "=============================================="
echo "  三年级学习工作台 · 一键部署  (开始 $(date '+%H:%M:%S'))"
echo "=============================================="

# ---------- 0) 网络（直连优先，失败才用系统代理；强制 IPv4） ----------
echo ""
echo "→ [0/6] 检查网络…"
# 先探测系统代理（仅当直连失败时作为备用）
PROXY_HOST=""; PROXY_PORT=""; PROXY_TYPE=""
if command -v scutil >/dev/null 2>&1; then
  for PT in HTTPS HTTP; do
    H=$(scutil --proxy | awk "/${PT}Proxy/{print \\$3}" | head -1)
    P=$(scutil --proxy | awk "/${PT}Port/{print \\$3}" | head -1)
    if [ -n "$H" ] && [ -n "$P" ] && ! echo "$H" | grep -q '{'; then PROXY_HOST="$H"; PROXY_PORT="$P"; PROXY_TYPE="$PT"; break; fi
  done
  if [ -z "$PROXY_HOST" ]; then
    H=$(scutil --proxy | awk '/SOCKSProxy/{print $3}' | head -1)
    P=$(scutil --proxy | awk '/SOCKSPort/{print $3}' | head -1)
    if [ -n "$H" ] && [ -n "$P" ] && ! echo "$H" | grep -q '{'; then PROXY_HOST="$H"; PROXY_PORT="$P"; PROXY_TYPE="SOCKS"; fi
  fi
fi
NET_OK=""
echo "  （尝试直连 github.com，最多重试 3 次…）"
for try in 1 2 3; do
  if curl -4 -s -m 15 -o /dev/null https://github.com; then NET_OK=1; break; fi
  echo "  （第 $try 次失败，2 秒后重试…）"
  sleep 2
done
if [ -z "$NET_OK" ] && [ -n "$PROXY_HOST" ]; then
  echo "  直连失败，改用系统代理（$PROXY_TYPE $PROXY_HOST:$PROXY_PORT）…"
  if [ "$PROXY_TYPE" = "SOCKS" ]; then
    export http_proxy="socks5h://$PROXY_HOST:$PROXY_PORT"
    export https_proxy="socks5h://$PROXY_HOST:$PROXY_PORT"
  else
    export http_proxy="http://$PROXY_HOST:$PROXY_PORT"
    export https_proxy="http://$PROXY_HOST:$PROXY_PORT"
  fi
  export HTTP_PROXY="$http_proxy"; export HTTPS_PROXY="$https_proxy"
  for try in 1 2 3; do
    if curl -4 -s -m 15 -o /dev/null https://github.com; then NET_OK=1; break; fi
    sleep 2
  done
fi
if [ -z "$NET_OK" ]; then
  echo "❌ 仍连不上 github.com。你反馈浏览器能打开、且没开代理，"
  echo "   那多半是「首次连接较慢」：请稍等片刻，把本脚本再运行一次（已放宽超时并强制 IPv4）。"
  echo "   如果反复失败，请把下面这行的输出发给我："
  echo "     curl -4 -m 15 -I https://github.com"
  read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
fi
echo "✅ 网络正常"

# ---------- 1) git ----------
echo ""
echo "→ [1/6] 检查 git…"
if ! command -v git >/dev/null 2>&1; then
  echo "❌ 未安装 git。打开「终端」运行： xcode-select --install"
  read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
fi
echo "✅ git: $(git --version)"

# ---------- 2) GitHub CLI (gh)：没有就自动下载独立版 ----------
echo ""
echo "→ [2/6] 检查 GitHub CLI…"
if ! command -v gh >/dev/null 2>&1; then
  if [ -x "$HOME/.workbench-gh/bin/gh" ]; then
    export PATH="$HOME/.workbench-gh/bin:$PATH"
  else
    echo "  未找到 gh，正在下载独立版（约20MB，只需一次）…"
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then OSARCH="arm64"; else OSARCH="amd64"; fi
    VER=$(curl -4 -s -m 20 https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
    if [ -z "$VER" ]; then
      echo "❌ 获取 gh 版本失败，请检查网络后重试。"
      read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
    fi
    echo "    版本 v$VER · macOS $OSARCH"
    mkdir -p "$HOME/.workbench-gh"
    URL="https://github.com/cli/cli/releases/download/v$VER/gh_${VER}_macOS_${OSARCH}.zip"
    if ! curl -4 -sL -m 300 -o "$HOME/.workbench-gh/gh.zip" "$URL" || [ ! -s "$HOME/.workbench-gh/gh.zip" ]; then
      echo "❌ 下载失败（$URL）"
      echo "   备选：按「部署说明.md」里的手动步骤操作。"
      read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
    fi
    ( cd "$HOME/.workbench-gh" && unzip -oq gh.zip ) || { echo "❌ 解压失败"; read -n 1 -s -r -p "按任意键退出…"; echo; exit 1; }
    GH_PATH=$(find "$HOME/.workbench-gh" -path '*/bin/gh' -type f | head -1)
    if [ -z "$GH_PATH" ]; then
      echo "❌ 解压后未找到 gh 程序"; read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
    fi
    mkdir -p "$HOME/.workbench-gh/bin"
    cp "$GH_PATH" "$HOME/.workbench-gh/bin/gh"
    chmod +x "$HOME/.workbench-gh/bin/gh"
    rm -f "$HOME/.workbench-gh/gh.zip"
    rm -rf "$HOME/.workbench-gh"/gh_*_macOS_*
    export PATH="$HOME/.workbench-gh/bin:$PATH"
  fi
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "❌ GitHub CLI 仍不可用。请把日志发给作者，或用「手动部署」步骤。"
  read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
fi
echo "✅ gh: $(gh --version | head -1)"

# ---------- 3) 登录 ----------
echo ""
echo "→ [3/6] 登录 GitHub…"
if ! gh auth status >/dev/null 2>&1; then
  echo "  按 gh 提示操作：GitHub.com → HTTPS → Login with a web browser"
  echo "  → 复制授权码 → 浏览器打开 https://github.com/login/device 粘贴并授权"
  echo "  （如果还没注册账号，或注册后没去邮箱点验证邮件，请先完成再继续）"
  gh auth login
  if ! gh auth status >/dev/null 2>&1; then
    echo "❌ 登录未成功。请重试，或用「手动部署」方案。"
    read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
  fi
fi
OWNER=$(gh api user -q .login 2>/dev/null)
if [ -z "$OWNER" ]; then
  echo "❌ 无法获取用户名（账号可能未验证邮箱）。请先到邮箱点 GitHub 验证邮件。"
  read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
fi
echo "✅ 已登录：$OWNER"

# ---------- 4) 提交 ----------
echo ""
echo "→ [4/6] 准备文件并提交…"
REPO="study-workbench"
git init -q
git branch -M main
git add -A
if ! git -c user.name="$OWNER" -c user.email="$OWNER@users.noreply.github.com" commit -q -m "部署工作台 $(date '+%Y-%m-%d %H:%M')"; then
  echo "  （没有新更改，继续）"
fi

# ---------- 5) 创建/更新仓库并推送 ----------
echo ""
echo "→ [5/6] 上传到 GitHub…"
if ! gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  echo "  创建公开仓库 $REPO 并推送…"
  if ! gh repo create "$REPO" --public --source=. --push --description "三年级学习工作台（智能排期·计时版）"; then
    echo "❌ 创建仓库/推送失败，请把上方错误信息发给我。"
    read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
  fi
else
  echo "  仓库已存在，推送更新…"
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$OWNER/$REPO.git"
  if ! git push -q -u origin main; then
    echo "❌ 推送失败，请把上方错误信息发给我。"
    read -n 1 -s -r -p "按任意键退出…"; echo; exit 1
  fi
fi

# ---------- 6) 开启 GitHub Pages ----------
echo ""
echo "→ [6/6] 开启 GitHub Pages…"
if ! gh api -X POST "repos/$OWNER/$REPO/pages" -f "source[branch]=main" -f "source[path]=/" >/dev/null 2>&1; then
  echo "  （Pages 可能已开启，忽略）"
fi

URL="https://$OWNER.github.io/$REPO/"
echo ""
echo "🎉 上传完成！等待网站生成（最多约90秒）…"
CODE=""
for i in 1 2 3 4 5 6 7 8 9; do
  CODE=$(curl -4 -s -m 6 -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || true)
  if [ "$CODE" = "200" ]; then break; fi
  sleep 10
done
if [ "$CODE" = "200" ]; then
  echo "✅ 网站已上线：$URL"
else
  echo "   网站仍在生成中，1~2 分钟后刷新即可访问：$URL"
fi
echo ""
echo "  iPad 用 Safari 打开上面的网址 → 分享 → 添加到主屏幕。"
echo "  完整日志：$LOG_FILE"
read -n 1 -s -r -p "按任意键退出…"; echo
