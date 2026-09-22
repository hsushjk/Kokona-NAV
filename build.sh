#!/usr/bin/env bash
# ============================================================
#  Kokona-NAV 构建脚本（菜单式）
#
#  用法：
#     chmod +x build.sh
#     ./build.sh
#
#  功能：
#     1) 修改网页信息        -> 生成 site.config.json
#     2) 生成 manifest 和 sw -> 生成 manifest.json、sw.js
#     3) 更新 card           -> 生成 mark/appcards.mark、mark/othercards.mark
#     4) 更新 notice         -> 生成 mark/notice.mark
#     5) 全部执行
#     0) 退出
#
#  无外部语言依赖：
#     仅使用 bash、sed、awk、sha256sum（macOS 用 shasum -a 256）。
#     不需要 node、python。
# ============================================================

set -euo pipefail

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG_FILE="site.config.json"

# ============================================================
#  工具函数
# ============================================================

# 检查 SHA-256 工具
check_sha256_tool() {
    if command -v sha256sum >/dev/null 2>&1; then
        return 0
    fi
    if command -v shasum >/dev/null 2>&1; then
        return 0
    fi
    echo -e "${C_RED}错误：找不到 sha256sum 或 shasum${C_RESET}" >&2
    echo -e "${C_YELLOW}提示：Linux 一般自带 sha256sum；macOS 自带 shasum；Windows 请用 Git Bash${C_RESET}" >&2
    exit 1
}

# 计算文件 SHA-256（原始字节）
sha256_of_file() {
    local f="$1"
    if [ ! -f "$f" ]; then
        echo ""
        return
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    else
        shasum -a 256 "$f" | awk '{print $1}'
    fi
}

# 从 site.config.json 读取字段（sed 解析，因为 JSON 是脚本自己生成的，格式可控）
read_config() {
    local key="$1"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo ""
        return
    fi
    sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -n 1
}

# 对用户输入做最小转义，防止破坏 JSON
escape_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# 提示输入，带默认值
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local answer
    if [ -n "$default" ]; then
        read -r -p "$prompt [$default]: " answer
        echo "${answer:-$default}"
    else
        read -r -p "$prompt: " answer
        echo "$answer"
    fi
}

press_enter() {
    echo ""
    read -r -p "按回车返回菜单..." _
}

# 生成 manifest.json
write_manifest() {
    local site_name="$1"
    local short_name="$2"
    local description="$3"
    local theme_color="$4"

    site_name=$(escape_json "$site_name")
    short_name=$(escape_json "$short_name")
    description=$(escape_json "$description")
    theme_color=$(escape_json "$theme_color")

    cat > manifest.json <<EOF
{
  "name": "$site_name",
  "short_name": "$short_name",
  "description": "$description",
  "start_url": "./",
  "scope": "./",
  "display": "standalone",
  "orientation": "portrait-primary",
  "background_color": "#1a1a2e",
  "theme_color": "$theme_color",
  "lang": "zh-CN",
  "icons": [
    {
      "src": "favicon.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "favicon.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ]
}
EOF
}

# 生成 sw.js
write_sw() {
    cat > sw.js <<'EOF'
// 由 build.sh 自动生成，请勿手改
const CACHE_NAME = 'kokona-nav-v1';
const CORE_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './site.config.json',
  './favicon.png',
  './bg.webp',
  './network-test.json'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(CORE_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  if (url.pathname.endsWith('.mark') ||
      url.pathname.endsWith('notice.md') ||
      url.pathname.endsWith('first-time.md') ||
      url.pathname.endsWith('.json')) {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) return cached;
      return fetch(event.request).then(response => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(event.request, copy));
        return response;
      });
    })
  );
});
EOF
}

# ============================================================
#  功能 1：修改网页信息
# ============================================================
do_edit_info() {
    echo ""
    echo -e "${C_CYAN}=== 修改网页信息 ===${C_RESET}"
    echo "（直接回车保留括号内的当前值）"
    echo ""

    local cur_site cur_logo cur_title cur_copy cur_theme cur_desc
    cur_site=$(read_config "siteName")
    cur_logo=$(read_config "logoText")
    cur_title=$(read_config "title")
    cur_copy=$(read_config "copyright")
    cur_theme=$(read_config "themeColor")
    cur_desc=$(read_config "description")

    local site_name logo_text page_title copyright theme_color description
    site_name=$(prompt_with_default "站点名称（主标题）" "$cur_site")
    logo_text=$(prompt_with_default "左上角 Logo 文字" "$cur_logo")
    page_title=$(prompt_with_default "浏览器标签标题" "$cur_title")
    copyright=$(prompt_with_default "页脚版权文字" "$cur_copy")
    theme_color=$(prompt_with_default "主题色（如 #3498db）" "$cur_theme")
    description=$(prompt_with_default "站点描述" "$cur_desc")

    site_name=$(escape_json "$site_name")
    logo_text=$(escape_json "$logo_text")
    page_title=$(escape_json "$page_title")
    copyright=$(escape_json "$copyright")
    theme_color=$(escape_json "$theme_color")
    description=$(escape_json "$description")

    cat > "$CONFIG_FILE" <<EOF
{
  "siteName": "$site_name",
  "logoText": "$logo_text",
  "title": "$page_title",
  "copyright": "$copyright",
  "themeColor": "$theme_color",
  "description": "$description",
  "lang": "zh-CN"
}
EOF

    echo ""
    echo -e "${C_GREEN}已写入 $CONFIG_FILE${C_RESET}"
    press_enter
}

# ============================================================
#  功能 2：生成 manifest.json 和 sw.js
# ============================================================
do_build_pwa() {
    echo ""
    echo -e "${C_CYAN}=== 生成 manifest.json 和 sw.js ===${C_RESET}"
    echo ""

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${C_YELLOW}未找到 site.config.json，请先执行功能 1${C_RESET}"
        press_enter
        return
    fi

    local site_name theme_color description short_name
    site_name=$(read_config "siteName")
    theme_color=$(read_config "themeColor")
    description=$(read_config "description")

    if [ -z "$site_name" ]; then
        echo -e "${C_YELLOW}siteName 为空，请先执行功能 1${C_RESET}"
        press_enter
        return
    fi

    short_name=$(prompt_with_default "PWA 短名称（桌面图标下显示）" "$site_name")

    write_manifest "$site_name" "$short_name" "$description" "$theme_color"
    echo -e "${C_GREEN}已生成 manifest.json${C_RESET}"

    write_sw
    echo -e "${C_GREEN}已生成 sw.js${C_RESET}"

    echo ""
    echo -e "${C_YELLOW}提示：修改网站内容后，若想强制刷新缓存，"
    echo -e "请手动把 sw.js 里的 CACHE_NAME 改成 kokona-nav-v2、v3 ...${C_RESET}"

    press_enter
}

# ============================================================
#  功能 3：更新 card
# ============================================================
do_update_card() {
    echo ""
    echo -e "${C_CYAN}=== 更新 card ===${C_RESET}"
    echo ""

    if [ ! -f "cardjson/appcards.json" ]; then
        echo -e "${C_RED}缺少 cardjson/appcards.json${C_RESET}"
        press_enter
        return
    fi
    if [ ! -f "cardjson/othercards.json" ]; then
        echo -e "${C_RED}缺少 cardjson/othercards.json${C_RESET}"
        press_enter
        return
    fi

    mkdir -p mark

    local app_hash other_hash
    app_hash=$(sha256_of_file "cardjson/appcards.json")
    other_hash=$(sha256_of_file "cardjson/othercards.json")

    echo "$app_hash"   > mark/appcards.mark
    echo "$other_hash" > mark/othercards.mark

    echo -e "${C_GREEN}已更新：${C_RESET}"
    echo "  mark/appcards.mark   = $app_hash"
    echo "  mark/othercards.mark = $other_hash"
    echo ""
    echo "下次打开页面时，会自动检测到 card 变化并刷新。"

    press_enter
}

# ============================================================
#  功能 4：更新 notice
# ============================================================
do_update_notice() {
    echo ""
    echo -e "${C_CYAN}=== 更新 notice ===${C_RESET}"
    echo ""

    if [ ! -f "notice.md" ]; then
        echo -e "${C_RED}缺少 notice.md${C_RESET}"
        press_enter
        return
    fi

    mkdir -p mark

    local notice_hash
    notice_hash=$(sha256_of_file "notice.md")

    echo "$notice_hash" > mark/notice.mark

    echo -e "${C_GREEN}已更新：${C_RESET}"
    echo "  mark/notice.mark = $notice_hash"
    echo ""
    echo "下次打开页面时，如果 notice.md 内容变了，就会弹出通知。"

    press_enter
}

# ============================================================
#  功能 5：全部执行
# ============================================================
do_all() {
    echo ""
    echo -e "${C_CYAN}=== 全部执行 ===${C_RESET}"
    echo ""

    # ---- 1. 站点信息 ----
    do_edit_info

    # ---- 2. manifest + sw ----
    echo -e "${C_CYAN}--- 2/4 生成 manifest 和 sw ---${C_RESET}"
    if [ -f "$CONFIG_FILE" ]; then
        local site_name theme_color description short_name
        site_name=$(read_config "siteName")
        theme_color=$(read_config "themeColor")
        description=$(read_config "description")

        if [ -n "$site_name" ]; then
            short_name=$(prompt_with_default "PWA 短名称" "$site_name")
            write_manifest "$site_name" "$short_name" "$description" "$theme_color"
            write_sw
            echo -e "${C_GREEN}已生成 manifest.json、sw.js${C_RESET}"
        else
            echo -e "${C_YELLOW}siteName 为空，跳过${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}缺少 site.config.json，跳过${C_RESET}"
    fi

    # ---- 3. card ----
    echo -e "${C_CYAN}--- 3/4 更新 card ---${C_RESET}"
    if [ -f "cardjson/appcards.json" ] && [ -f "cardjson/othercards.json" ]; then
        mkdir -p mark
        sha256_of_file "cardjson/appcards.json"   > mark/appcards.mark
        sha256_of_file "cardjson/othercards.json" > mark/othercards.mark
        echo -e "${C_GREEN}已生成 mark/appcards.mark、mark/othercards.mark${C_RESET}"
    else
        echo -e "${C_YELLOW}缺少 cardjson 文件，跳过${C_RESET}"
    fi

    # ---- 4. notice ----
    echo -e "${C_CYAN}--- 4/4 更新 notice ---${C_RESET}"
    if [ -f "notice.md" ]; then
        mkdir -p mark
        sha256_of_file "notice.md" > mark/notice.mark
        echo -e "${C_GREEN}已生成 mark/notice.mark${C_RESET}"
    else
        echo -e "${C_YELLOW}缺少 notice.md，跳过${C_RESET}"
    fi

    echo ""
    echo -e "${C_GREEN}全部完成。${C_RESET}"
    press_enter
}

# ============================================================
#  菜单
# ============================================================
show_menu() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${C_BLUE}========================================${C_RESET}"
    echo -e "${C_BLUE}        Build-Kokona-NAV${C_RESET}"
    echo -e "${C_BLUE}========================================${C_RESET}"
    echo "  1) 修改网页信息"
    echo "  2) 生成 manifest 和 sw"
    echo "  3) 更新 card"
    echo "  4) 更新 notice"
    echo "  5) 全部执行"
    echo "  0) 退出"
    echo -e "${C_BLUE}========================================${C_RESET}"
}

main() {
    check_sha256_tool
    while true; do
        show_menu
        read -r -p "请选择 [0-5]: " choice
        case "$choice" in
            1) do_edit_info ;;
            2) do_build_pwa ;;
            3) do_update_card ;;
            4) do_update_notice ;;
            5) do_all ;;
            0) echo ""; echo "已退出。"; exit 0 ;;
            *) echo -e "${C_RED}无效选项${C_RESET}"; sleep 1 ;;
        esac
    done
}

main