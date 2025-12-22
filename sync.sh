#!/bin/bash

# Gitee代码同步工具
# Copyright (c) 2025 zsj-950127
#
# MIT License - 允许商业使用、修改和分发
# 详细信息请参阅 LICENSE 文件

# 解析命令行参数
VERBOSE=false
LOG_FILE=""
QUIET_MODE=false
for arg in "$@"; do
    case $arg in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        --log=*)
            LOG_FILE="${arg#*=}"
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -v, --verbose        显示详细输出"
            echo "  -q, --quiet          精简模式，详细日志写入文件"
            echo "  --log=/path/file     将关键日志额外写入到指定文件"
            echo "  -h, --help           显示帮助信息"
            exit 0
            ;;
        *)
            if [[ "$arg" == -* ]]; then
                echo "未知参数: $arg"
                echo "使用 $0 --help 查看帮助"
                exit 1
            fi
            ;;
    esac
done

# 设置严格模式
set -e

# 颜色定义（统一颜色方案）
RED='\033[0;31m'      # 错误/失败
GREEN='\033[0;32m'    # 成功/完成
YELLOW='\033[0;33m'   # 警告/提示
BLUE='\033[0;34m'     # 信息/普通
CYAN='\033[0;36m'     # 高亮/强调
NC='\033[0m'          # No Color

# 内容高亮辅助函数（用于高亮日志内容中的关键信息）
highlight_path() {
    echo -e "${CYAN}$1${NC}"
}

highlight_server() {
    echo -e "${CYAN}$1${NC}"
}

highlight_branch() {
    echo -e "${CYAN}$1${NC}"
}

highlight_number() {
    echo -e "${CYAN}$1${NC}"
}

highlight_key() {
    echo -e "${CYAN}$1${NC}"
}

# 智能高亮函数：自动识别并高亮常见的关键信息
# 使用简单的 sed 模式，按顺序处理，避免重复高亮
highlight_content() {
    local content="$1"
    local temp_content="$content"
    
    # 使用特殊标记来避免重复高亮（这些标记不会出现在正常文本中）
    local MARK_START="\001"
    local MARK_END="\002"
    
    # 按优先级顺序高亮（从最具体到最通用）
    
    # 1. 高亮键值对（key=value，最具体）
    temp_content=$(echo "$temp_content" | sed -E "s|([a-zA-Z_]+=)([^ ${MARK_START}${MARK_END} ,;:]+)|${MARK_START}\1${MARK_END}${MARK_START}\2${MARK_END}|g")
    
    # 2. 高亮服务器/主机格式（user@host）
    temp_content=$(echo "$temp_content" | sed -E "s|([a-zA-Z0-9_-]+@[0-9a-zA-Z.-]+)|${MARK_START}\1${MARK_END}|g")
    
    # 3. 高亮IP地址
    temp_content=$(echo "$temp_content" | sed -E "s|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})|${MARK_START}\1${MARK_END}|g")
    
    # 4. 高亮绝对路径（以 / 开头）
    temp_content=$(echo "$temp_content" | sed -E "s|([/][^ ${MARK_START}${MARK_END} ]+)|${MARK_START}\1${MARK_END}|g")
    
    # 5. 高亮分支名（在特定关键词后）
    temp_content=$(echo "$temp_content" | sed -E "s|(分支:)([^ ${MARK_START}${MARK_END} ,;:]+)|${MARK_START}\1${MARK_END}${MARK_START}\2${MARK_END}|g")
    
    # 6. 高亮统计信息（数字+中文单位）- 兼容 BSD sed
    temp_content=$(echo "$temp_content" | sed -E "s|[0-9]+ 台|${MARK_START}&${MARK_END}|g")
    temp_content=$(echo "$temp_content" | sed -E "s|[0-9]+ 个|${MARK_START}&${MARK_END}|g")
    temp_content=$(echo "$temp_content" | sed -E "s|[0-9]+ 条|${MARK_START}&${MARK_END}|g")
    temp_content=$(echo "$temp_content" | sed -E "s|索引: [0-9]+|${MARK_START}&${MARK_END}|g")
    temp_content=$(echo "$temp_content" | sed -E "s|错误代码: [0-9]+|${MARK_START}&${MARK_END}|g")
    
    # 替换标记为颜色代码
    temp_content=$(echo "$temp_content" | sed "s|${MARK_START}|${CYAN}|g" | sed "s|${MARK_END}|${NC}|g")
    
    echo "$temp_content"
}

# 日志函数，带时间戳和颜色区分
log_info() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入文件日志
    if [ -n "$LOG_FILE" ]; then
        echo "[${ts}] [INFO] $msg" >> "$LOG_FILE"
    fi
    
    # 控制台输出（精简模式下跳过某些信息）
    if [ "$QUIET_MODE" = false ]; then
        echo -e "[${ts}] ${BLUE}[INFO]${NC} $msg"
    fi
}

log_success() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入文件日志
    if [ -n "$LOG_FILE" ]; then
        echo "[${ts}] [SUCCESS] $msg" >> "$LOG_FILE"
    fi
    
    # 控制台输出（精简模式下始终显示成功信息）
    echo -e "[${ts}] ${GREEN}[✓]${NC} $msg"
}

log_warn() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入文件日志
    if [ -n "$LOG_FILE" ]; then
        echo "[${ts}] [WARN] $msg" >> "$LOG_FILE"
    fi
    
    # 控制台输出（始终显示警告）
    echo -e "[${ts}] ${YELLOW}[!]${NC} $msg"
}

log_error() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入文件日志
    if [ -n "$LOG_FILE" ]; then
        echo "[${ts}] [ERROR] $msg" >> "$LOG_FILE"
    fi
    
    # 控制台输出（始终显示错误）
    echo -e "[${ts}] ${RED}[✗]${NC} $msg"
}

# 安全验证函数
validate_path() {
    local path="$1"
    local path_type="$2"

    # 检查路径是否包含危险字符
    if [[ "$path" =~ \.\./|\.\.\\ ]]; then
        log_error "路径包含危险的相对路径符号: $path"
        return 1
    fi

    # 检查是否为系统关键目录
    case "$path" in
        /|/bin|/sbin|/usr|/etc|/boot|/dev|/proc|/sys|/run)
            log_error "不允许操作系统关键目录: $path"
            return 1
            ;;
        /bin/*|/sbin/*|/usr/bin/*|/usr/sbin/*|/etc/*)
            log_error "不允许操作系统关键目录下的文件: $path"
            return 1
            ;;
    esac

    return 0
}

# 动态进度提示函数
show_progress() {
    local message="$1"
    local pid="$2"
    local dots=""
    local count=0

    echo -ne "${YELLOW}${message}"

    while kill -0 "$pid" 2>/dev/null; do
        case $((count % 4)) in
            0) echo -ne "\r${YELLOW}${message}   ${NC}" ;;
            1) echo -ne "\r${YELLOW}${message}.  ${NC}" ;;
            2) echo -ne "\r${YELLOW}${message}.. ${NC}" ;;
            3) echo -ne "\r${YELLOW}${message}...${NC}" ;;
        esac
        sleep 0.5
        count=$((count + 1))
    done

    echo -ne "\r${GREEN}${message}完成${NC}\n"
}

# 安全执行Git命令的函数
safe_git_command() {
    local message="$1"
    local git_cmd="$2"
    shift 2
    local args=("$@")

    if [ "$VERBOSE" = true ]; then
        log_info "执行Git命令: git $git_cmd ${args[*]}"
        git "$git_cmd" "${args[@]}"
    else
        # 在后台执行命令
        git "$git_cmd" "${args[@]}" >/dev/null 2>&1 &
        local cmd_pid=$!

        # 显示进度
        show_progress "$message" "$cmd_pid"

        # 等待命令完成并获取退出状态
        wait "$cmd_pid"
        return $?
    fi
}

# 保存脚本文件所在目录
SCRIPT_DIR=$(cd $(dirname "$0") && pwd)

# 初始化日志目录和文件（按日期划分）
init_log_file() {
    local config_name="$1"
    local log_dir="$SCRIPT_DIR/logs/$config_name"
    mkdir -p "$log_dir"
    
    # 按日期生成日志文件名
    local date_str=$(date '+%Y-%m-%d')
    LOG_FILE="$log_dir/sync_${date_str}.log"
    
    # 写入同步开始标记
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "              [$start_time] 启动同步" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "配置文件: $config_name" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# 展开路径中的~为用户主目录，./为脚本目录
expand_path() {
    local path="$1"
    if [[ "$path" == ~* ]]; then
        path="${HOME}${path:1}"
    elif [[ "$path" == ./* ]]; then
        path="$SCRIPT_DIR/${path#./}"
    fi
    echo "$path"
}

# URL编码函数
urlencode() {
    local string="$1"
    local encoded=""
    local pos c o

    for ((pos=0; pos<${#string}; pos++)); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9])
                o="$c" ;;
            *)
                printf -v o '%%%02X' "'$c"
                ;;
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

# 检查依赖
check_dependencies() {
    echo -e "${BLUE}[→]${NC} 检查依赖..."

    command -v git >/dev/null 2>&1 || { log_error "git 未安装"; exit 1; }
    command -v rsync >/dev/null 2>&1 || { log_error "rsync 未安装"; exit 1; }
    command -v yq >/dev/null 2>&1 || { log_warn "yq 未安装，将使用Python处理YAML"; }
    command -v sshpass >/dev/null 2>&1 || { log_warn "sshpass 未安装，密码认证将不可用"; }

    if ! command -v yq >/dev/null 2>&1; then
        command -v python3 >/dev/null 2>&1 || { log_error "需要安装yq或python3"; exit 1; }
        python3 -c "import yaml" 2>/dev/null || { log_error "需要安装 PyYAML: pip3 install pyyaml"; exit 1; }
    fi

    echo -e "  ${GREEN}[✓]${NC} 依赖检查通过"
    echo ""
}

# 列出并选择配置文件
select_config_file() {
    echo -e "${BLUE}[→]${NC} 查找配置文件..."

    # 使用兼容macOS和Linux的方式查找所有.yml文件
    CONFIG_FILES=()
    for file in *.yml; do
        # 检查文件是否存在且不是通配符本身
        if [ -f "$file" ]; then
            CONFIG_FILES+=("$file")
        fi
    done

    # 如果没有找到任何配置文件
    if [ ${#CONFIG_FILES[@]} -eq 0 ]; then
        log_error "未找到任何.yml配置文件"
        exit 1
    fi

    echo ""
    echo -e "${CYAN}可用配置文件:${NC}"
    # 显示找到的配置文件列表
    for i in "${!CONFIG_FILES[@]}"; do
        echo -e "  ${GREEN}[$((i+1))]${NC} ${CONFIG_FILES[$i]}"
    done

    echo ""
    # 请求用户选择
    read -p "请输入配置文件编号 (1-${#CONFIG_FILES[@]}): " choice

    # 验证用户输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#CONFIG_FILES[@]} ]; then
        log_error "无效的选择"
        exit 1
    fi

    # 设置选择的配置文件
    CONFIG_FILE="${CONFIG_FILES[$((choice-1))]}"
    # 使用绝对路径
    CONFIG_FILE="$SCRIPT_DIR/$CONFIG_FILE"
    
    # 初始化日志文件
    CONFIG_FILE_BASE=$(basename "$CONFIG_FILE" .yml)
    init_log_file "$CONFIG_FILE_BASE"
    
    echo ""
    echo -e "${GREEN}[✓]${NC} 配置文件: ${CYAN}$(basename $CONFIG_FILE)${NC}"
    echo -e "${GREEN}[✓]${NC} 日志文件: ${CYAN}$LOG_FILE${NC}"
    echo ""
}

# 解析YAML配置文件
parse_config() {
    echo -e "${BLUE}[→]${NC} 解析配置..."

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件 $CONFIG_FILE 不存在"
        exit 1
    fi

    if command -v yq >/dev/null 2>&1; then
        # 使用yq解析配置
        REPO_URL=$(yq e '.gitee.repo_url' "$CONFIG_FILE")
        DEFAULT_BRANCH=$(yq e '.gitee.default_branch' "$CONFIG_FILE")
        LOCAL_DIR=$(yq e '.gitee.local_dir' "$CONFIG_FILE")
        GIT_AUTH_TYPE=$(yq e '.gitee.auth_type' "$CONFIG_FILE")

        if [ "$GIT_AUTH_TYPE" = "ssh" ]; then
            GIT_SSH_KEY=$(yq e '.gitee.ssh_key' "$CONFIG_FILE")
            GIT_SSH_KEY=$(expand_path "$GIT_SSH_KEY")
        elif [ "$GIT_AUTH_TYPE" = "password" ]; then
            GIT_USERNAME=$(yq e '.gitee.username' "$CONFIG_FILE")
            GIT_PASSWORD=$(yq e '.gitee.password' "$CONFIG_FILE")
        fi

        RSYNC_OPTIONS=$(yq e '.sync.rsync_options' "$CONFIG_FILE")

        # 获取服务器组数量
        GROUP_COUNT=$(yq e '.server_groups | length' "$CONFIG_FILE")

        # 提取排除项
        EXCLUDE_COUNT=$(yq e '.sync.exclude | length' "$CONFIG_FILE")
        EXCLUDE_OPTS=""
        for ((i=0; i<$EXCLUDE_COUNT; i++)); do
            EXCLUDE_ITEM=$(yq e ".sync.exclude[$i]" "$CONFIG_FILE")
            EXCLUDE_OPTS="$EXCLUDE_OPTS --exclude=$EXCLUDE_ITEM"
        done
    else
        # 使用Python解析配置
        CONFIG_PYTHON=$(cat << 'EOF'
import yaml
import sys
import json
import os

with open(sys.argv[1], 'r') as file:
    config = yaml.safe_load(file)

gitee_config = config['gitee']
output = {
    'repo_url': gitee_config['repo_url'],
    'default_branch': gitee_config.get('default_branch', 'master'),
    'local_dir': gitee_config['local_dir'],
    'git_auth_type': gitee_config['auth_type'],
}

if gitee_config['auth_type'] == 'ssh':
    ssh_key = gitee_config.get('ssh_key', '')
    # 展开~为用户主目录
    if ssh_key.startswith('~'):
        ssh_key = os.path.expanduser(ssh_key)
    output['git_ssh_key'] = ssh_key
elif gitee_config['auth_type'] == 'password':
    output['git_username'] = gitee_config.get('username', '')
    output['git_password'] = gitee_config.get('password', '')

output['rsync_options'] = config['sync']['rsync_options']
output['group_count'] = len(config['server_groups'])
output['server_groups'] = config['server_groups']
output['exclude'] = config['sync']['exclude']

print(json.dumps(output))
EOF
)
        CONFIG_JSON=$(python3 -c "$CONFIG_PYTHON" "$CONFIG_FILE")

        REPO_URL=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['repo_url'])")
        DEFAULT_BRANCH=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['default_branch'])")
        LOCAL_DIR=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['local_dir'])")
        GIT_AUTH_TYPE=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['git_auth_type'])")

        if [ "$GIT_AUTH_TYPE" = "ssh" ]; then
            GIT_SSH_KEY=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('git_ssh_key', ''))")
        elif [ "$GIT_AUTH_TYPE" = "password" ]; then
            GIT_USERNAME=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('git_username', ''))")
            GIT_PASSWORD=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('git_password', ''))")
        fi

        RSYNC_OPTIONS=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['rsync_options'])")
        GROUP_COUNT=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['group_count'])")

        # 提取排除项
        EXCLUDE_ITEMS=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(' '.join(['--exclude=' + item for item in json.load(sys.stdin)['exclude']]))")
        EXCLUDE_OPTS="$EXCLUDE_ITEMS"
    fi

    # 验证Git认证类型
    if [ "$GIT_AUTH_TYPE" != "ssh" ] && [ "$GIT_AUTH_TYPE" != "password" ]; then
        log_error "Gitee认证类型必须为'ssh'或'password'"
        exit 1
    fi

    # 如果是SSH认证，检查SSH密钥
    if [ "$GIT_AUTH_TYPE" = "ssh" ] && [ -z "$GIT_SSH_KEY" ]; then
        log_error "使用SSH认证时，必须设置SSH密钥路径"
        exit 1
    fi

    # 如果是密码认证，检查用户名和密码
    if [ "$GIT_AUTH_TYPE" = "password" ] && { [ -z "$GIT_USERNAME" ] || [ -z "$GIT_PASSWORD" ]; }; then
        log_error "使用密码认证时，必须设置用户名和密码"
        exit 1
    fi

    # 写入详细信息到日志文件
    if [ -n "$LOG_FILE" ]; then
        echo "配置详情:" >> "$LOG_FILE"
        echo "  仓库URL: $REPO_URL" >> "$LOG_FILE"
        echo "  本地目录: $LOCAL_DIR" >> "$LOG_FILE"
        echo "  认证类型: $GIT_AUTH_TYPE" >> "$LOG_FILE"
        if [ "$GIT_AUTH_TYPE" = "ssh" ]; then
            echo "  SSH密钥: $GIT_SSH_KEY" >> "$LOG_FILE"
        fi
        echo "" >> "$LOG_FILE"
    fi
    
    echo -e "  ${GREEN}[✓]${NC} 配置解析完成"
    echo ""
}

# 选择服务器组
select_server_group() {
    echo -e "${BLUE}[→]${NC} 选择服务器组..."
    echo ""
    echo -e "${CYAN}可用服务器组:${NC}"
    
    # 显示服务器组列表
    if command -v yq >/dev/null 2>&1; then
        for ((i=0; i<$GROUP_COUNT; i++)); do
            GROUP_NAME=$(yq e ".server_groups[$i].name" "$CONFIG_FILE")
            SERVER_COUNT=$(yq e ".server_groups[$i].servers | length" "$CONFIG_FILE")
            echo -e "  ${GREEN}[$((i+1))]${NC} $GROUP_NAME (${SERVER_COUNT} 台服务器)"
        done
    else
        echo "$CONFIG_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for i, group in enumerate(data['server_groups']):
    print(f\"  [{i+1}] {group['name']} ({len(group['servers'])} 台服务器)\")
"
    fi

    echo ""
    # 请求用户选择
    read -p "请输入服务器组编号 (1-$GROUP_COUNT): " group_choice

    # 验证用户输入
    if ! [[ "$group_choice" =~ ^[0-9]+$ ]] || [ "$group_choice" -lt 1 ] || [ "$group_choice" -gt $GROUP_COUNT ]; then
        log_error "无效的选择"
        exit 1
    fi

    # 设置选择的服务器组
    GROUP_INDEX=$((group_choice-1))

    if command -v yq >/dev/null 2>&1; then
        SELECTED_GROUP_NAME=$(yq e ".server_groups[$GROUP_INDEX].name" "$CONFIG_FILE")
        SERVER_COUNT=$(yq e ".server_groups[$GROUP_INDEX].servers | length" "$CONFIG_FILE")
    else
        SELECTED_GROUP_NAME=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['server_groups'][$GROUP_INDEX]['name'])")
        SERVER_COUNT=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['server_groups'][$GROUP_INDEX]['servers']))")
    fi

    # 写入详细信息到日志文件
    if [ -n "$LOG_FILE" ]; then
        echo "服务器组信息:" >> "$LOG_FILE"
        echo "  组名: $SELECTED_GROUP_NAME" >> "$LOG_FILE"
        echo "  索引: $GROUP_INDEX" >> "$LOG_FILE"
        echo "  服务器数量: $SERVER_COUNT" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
    
    echo ""
    echo -e "${GREEN}[✓]${NC} 服务器组: ${CYAN}$SELECTED_GROUP_NAME${NC} (${CYAN}$SERVER_COUNT${NC} 台)"
    echo ""
}

# 设置git凭据（仅准备凭据文件和URL，不执行git config）
setup_git_credentials() {
    # 从配置文件名中提取基本名称（不含路径和扩展名）
    CONFIG_FILE_BASE=$(basename "$CONFIG_FILE" .yml)
    # 创建一个基于配置文件名的凭据文件路径
    CREDENTIALS_DIR="$SCRIPT_DIR/.credentials"
    mkdir -p "$CREDENTIALS_DIR"
    GIT_CREDENTIALS_FILE="$CREDENTIALS_DIR/$CONFIG_FILE_BASE.git-credentials"

    if [ "$GIT_AUTH_TYPE" = "password" ]; then
        # 修改git URL以包含用户名和密码
        local protocol=$(echo "$REPO_URL" | grep -o -E '^(https?://)')
        if [ -n "$protocol" ]; then
            local repo_path=$(echo "$REPO_URL" | sed -e "s|^$protocol||")

            # URL编码用户名和密码中的特殊字符
            local username_encoded=$(urlencode "$GIT_USERNAME")
            local password_encoded=$(urlencode "$GIT_PASSWORD")

            # 构建带有认证信息的URL
            REPO_URL="${protocol}${username_encoded}:${password_encoded}@${repo_path}"

            log_info "已配置Git HTTPS 认证信息（使用用户名密码）"
        else
            log_error "使用密码认证时，仓库URL必须是HTTPS格式，当前: $REPO_URL"
            exit 1
        fi

        log_info "Git 凭据文件: $GIT_CREDENTIALS_FILE"
    elif [ "$GIT_AUTH_TYPE" = "ssh" ]; then
        # 确保SSH密钥存在
        if [ ! -f "$GIT_SSH_KEY" ]; then
            log_error "SSH密钥 $GIT_SSH_KEY 不存在，请检查配置文件中的 ssh_key 路径；当前 HOME=$HOME"
            exit 1
        fi

        # 配置git使用特定的SSH密钥
        export GIT_SSH_COMMAND="ssh -i $GIT_SSH_KEY -o StrictHostKeyChecking=no"
    fi
}

# 拉取所有需要的分支
pull_code() {
    echo -e "${BLUE}[→]${NC} 拉取代码..."
    
    if [ -n "$LOG_FILE" ]; then
        echo "拉取代码到本地目录: $LOCAL_DIR" >> "$LOG_FILE"
    fi

    # 设置git凭据
    setup_git_credentials

    # 确保本地目录存在
    mkdir -p "$LOCAL_DIR"

    # 收集所有需要的分支
    REQUIRED_BRANCHES=("$DEFAULT_BRANCH")

    if command -v yq >/dev/null 2>&1; then
        for ((i=0; i<$SERVER_COUNT; i++)); do
            SERVER_BRANCH=$(yq e ".server_groups[$GROUP_INDEX].servers[$i].branch // \"$DEFAULT_BRANCH\"" "$CONFIG_FILE")
            # 检查分支是否已在列表中
            if [[ ! " ${REQUIRED_BRANCHES[@]} " =~ " ${SERVER_BRANCH} " ]]; then
                REQUIRED_BRANCHES+=("$SERVER_BRANCH")
            fi
        done
    else
        python3 -c "
import sys, json
data = json.load(sys.stdin)
group = data['server_groups'][$GROUP_INDEX]
branches = set(['$DEFAULT_BRANCH'])
for server in group['servers']:
    branch = server.get('branch', '$DEFAULT_BRANCH')
    branches.add(branch)
print(' '.join(branches))
" <<< "$CONFIG_JSON" | read -r -a REQUIRED_BRANCHES
    fi

    # 切换到本地目录
    cd "$LOCAL_DIR"

    # 检查是否已经是有效的Git仓库
    if [ -d ".git" ] && git rev-parse --git-dir >/dev/null 2>&1; then
        # 确保使用正确的凭据配置
        if [ "$GIT_AUTH_TYPE" = "password" ]; then
            git config credential.helper "store --file=$GIT_CREDENTIALS_FILE"
        fi

        git fetch origin

        # 检出并更新每个需要的分支
        for branch in "${REQUIRED_BRANCHES[@]}"; do
            if [ -n "$LOG_FILE" ]; then
                echo "  更新分支: $branch" >> "$LOG_FILE"
            fi

            # 切换分支
            if [ "$VERBOSE" = true ]; then
                git checkout "$branch" || git checkout -b "$branch" "origin/$branch"
            else
                # 尝试切换到现有分支，如果失败则创建新分支
                if ! safe_git_command "正在切换到分支 $branch" "checkout" "$branch"; then
                    safe_git_command "正在创建分支 $branch" "checkout" "-b" "$branch" "origin/$branch"
                fi
            fi

            # 拉取更新
            safe_git_command "正在拉取分支 $branch 的最新代码" "pull" "origin" "$branch"
        done

        echo -e "  ${GREEN}[✓]${NC} 代码更新完成 (${#REQUIRED_BRANCHES[@]} 个分支)"
        
        if [ -n "$LOG_FILE" ]; then
            echo "更新的分支: ${REQUIRED_BRANCHES[*]}" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
        fi
    else
        # 克隆默认分支
        safe_git_command "正在克隆代码" "clone" "--branch" "$DEFAULT_BRANCH" "$REPO_URL" "."

        # 确保使用正确的凭据配置
        if [ "$GIT_AUTH_TYPE" = "password" ]; then
            git config credential.helper "store --file=$GIT_CREDENTIALS_FILE"
        fi

        # 获取其他需要的分支
        for branch in "${REQUIRED_BRANCHES[@]}"; do
            if [ "$branch" != "$DEFAULT_BRANCH" ]; then
                if [ -n "$LOG_FILE" ]; then
                    echo "  获取分支: $branch" >> "$LOG_FILE"
                fi
                git checkout -b "$branch" "origin/$branch" >> "$LOG_FILE" 2>&1
            fi
        done

        echo -e "  ${GREEN}[✓]${NC} 代码克隆完成 (${#REQUIRED_BRANCHES[@]} 个分支)"
        
        if [ -n "$LOG_FILE" ]; then
            echo "克隆的分支: ${REQUIRED_BRANCHES[*]}" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
        fi
    fi
    echo ""
}

# 替换环境配置文件
replace_configs() {
    echo -e "${BLUE}[→]${NC} 替换环境配置..."

    # 获取替换目录和环境标识
    if command -v yq >/dev/null 2>&1; then
        REPLACE_BASE_DIR=$(yq e '.sync.replace_dir' "$CONFIG_FILE")
        ENV_ID=$(yq e ".server_groups[$GROUP_INDEX].env // \"\"" "$CONFIG_FILE")
    else
        REPLACE_BASE_DIR=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('sync', {}).get('replace_dir', ''))")
        ENV_ID=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['server_groups'][$GROUP_INDEX].get('env', ''))")
    fi

    # 如果没有配置替换目录或环境标识，则跳过
    if [ -z "$REPLACE_BASE_DIR" ] || [ -z "$ENV_ID" ]; then
        echo -e "  ${YELLOW}[!]${NC} 未配置替换目录，跳过"
        echo ""
        return
    fi

    # 展开替换目录路径
    REPLACE_BASE_DIR=$(expand_path "$REPLACE_BASE_DIR")
    REPLACE_DIR="$REPLACE_BASE_DIR/$ENV_ID"

    # 检查替换目录是否存在
    if [ ! -d "$REPLACE_DIR" ]; then
        echo -e "  ${YELLOW}[!]${NC} 替换目录不存在，跳过"
        echo ""
        return
    fi
    
    if [ -n "$LOG_FILE" ]; then
        echo "替换配置:" >> "$LOG_FILE"
        echo "  环境: $ENV_ID" >> "$LOG_FILE"
        echo "  替换目录: $REPLACE_DIR" >> "$LOG_FILE"
    fi

    # 切换到正确的分支
    cd "$LOCAL_DIR"

    # 递归替换文件
    if [ "$VERBOSE" = true ]; then
        # 详细模式：显示每个文件
        find "$REPLACE_DIR" -type f -print | while read replace_file; do
            rel_path="${replace_file#$REPLACE_DIR/}"
            target_file="$LOCAL_DIR/$rel_path"
            target_dir=$(dirname "$target_file")

            if [ ! -d "$target_dir" ]; then
                mkdir -p "$target_dir"
            fi

            cp -f "$replace_file" "$target_file"
            echo -e "  ${GREEN}[✓]${NC} $rel_path"
        done
    else
        # 精简模式：后台执行并显示进度
        replace_config_files_background() {
            find "$REPLACE_DIR" -type f -print | while read replace_file; do
                rel_path="${replace_file#$REPLACE_DIR/}"
                target_file="$LOCAL_DIR/$rel_path"
                target_dir=$(dirname "$target_file")

                if [ ! -d "$target_dir" ]; then
                    mkdir -p "$target_dir"
                fi

                cp -f "$replace_file" "$target_file"
            done
        }

        # 在后台执行替换
        replace_config_files_background &
        local replace_pid=$!

        # 显示进度
        show_progress "  替换配置文件" "$replace_pid"
        wait "$replace_pid"

        # 统计替换的文件数量
        local total_files=$(find "$REPLACE_DIR" -type f | wc -l | tr -d ' ')
        echo -e "  ${GREEN}[✓]${NC} 已替换 ${CYAN}${total_files}${NC} 个文件"
        
        if [ -n "$LOG_FILE" ]; then
            echo "  替换文件数: $total_files" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
        fi
    fi
    echo ""
}

# 同步到服务器
sync_to_servers() {
    echo -e "${BLUE}[→]${NC} 开始同步到服务器..."
    echo ""

    # 检查是否存在代理环境变量
    HAS_PROXY=0
    if env | grep -i proxy > /dev/null; then
        echo -e "${YELLOW}[!]${NC} 检测到代理环境变量"
        if [ -n "$LOG_FILE" ]; then
            env | grep -i proxy >> "$LOG_FILE"
        fi
        HAS_PROXY=1

        # 询问是否为SSH连接临时禁用代理
        read -p "是否为SSH连接临时禁用代理? (y/n): " disable_proxy_choice
        if [ "$disable_proxy_choice" = "y" ] || [ "$disable_proxy_choice" = "Y" ]; then
            # 备份当前代理设置
            export BACKUP_HTTP_PROXY=$http_proxy
            export BACKUP_HTTPS_PROXY=$https_proxy
            export BACKUP_ALL_PROXY=$all_proxy
            export BACKUP_NO_PROXY=$no_proxy

            # 清除所有代理变量
            unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
            echo -e "  ${GREEN}[✓]${NC} 已临时禁用代理"
            echo ""
        fi
    fi

    # 对于选定服务器组中的每个服务器执行同步
    for ((i=0; i<$SERVER_COUNT; i++)); do
        if command -v yq >/dev/null 2>&1; then
            SERVER_NAME=$(yq e ".server_groups[$GROUP_INDEX].servers[$i].name" "$CONFIG_FILE")
            SERVER_HOST=$(yq e ".server_groups[$GROUP_INDEX].servers[$i].host" "$CONFIG_FILE")
            TARGET_DIR=$(yq e ".server_groups[$GROUP_INDEX].servers[$i].target_dir" "$CONFIG_FILE")
            SERVER_BRANCH=$(yq e ".server_groups[$GROUP_INDEX].servers[$i].branch // \"$DEFAULT_BRANCH\"" "$CONFIG_FILE")
            AUTH_TYPE=$(yq e ".server_groups[$GROUP_INDEX].servers[$i].auth_type" "$CONFIG_FILE")
            AUTH_INFO=$(yq e ".server_groups[$GROUP_INDEX].servers[$i].auth_info" "$CONFIG_FILE")
            # 展开路径中的~
            if [[ "$AUTH_TYPE" = "ssh" ]]; then
                AUTH_INFO=$(expand_path "$AUTH_INFO")
            fi
        else
            SERVER_JSON=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin)['server_groups'][$GROUP_INDEX]['servers'][$i]))")
            SERVER_NAME=$(echo "$SERVER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['name'])")
            SERVER_HOST=$(echo "$SERVER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['host'])")
            TARGET_DIR=$(echo "$SERVER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['target_dir'])")
            SERVER_BRANCH=$(echo "$SERVER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('branch', '$DEFAULT_BRANCH'))")
            AUTH_TYPE=$(echo "$SERVER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['auth_type'])")
            AUTH_INFO=$(echo "$SERVER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['auth_info'])")
            # 展开路径中的~
            if [[ "$AUTH_TYPE" = "ssh" ]]; then
                AUTH_INFO=$(expand_path "$AUTH_INFO")
            fi
        fi

        # 验证目标路径安全性
        if ! validate_path "$TARGET_DIR" "target"; then
            log_error "跳过不安全的目标路径: $TARGET_DIR"
            continue
        fi

        # 写入详细信息到日志
        if [ -n "$LOG_FILE" ]; then
            echo "----------------------------------------" >> "$LOG_FILE"
            echo "同步服务器: $SERVER_NAME" >> "$LOG_FILE"
            echo "  主机: $SERVER_HOST" >> "$LOG_FILE"
            echo "  分支: $SERVER_BRANCH" >> "$LOG_FILE"
            echo "  目标目录: $TARGET_DIR" >> "$LOG_FILE"
            echo "  认证类型: $AUTH_TYPE" >> "$LOG_FILE"
        fi
        
        echo -e "${BLUE}[→]${NC} 正在同步到 ${CYAN}$SERVER_NAME${NC} (${CYAN}$SERVER_HOST${NC})"

        # 切换到正确的分支
        cd "$LOCAL_DIR"
        if [ "$VERBOSE" = true ]; then
            git checkout "$SERVER_BRANCH"
        else
            safe_git_command "正在切换到目标分支 $SERVER_BRANCH" "checkout" "$SERVER_BRANCH"
        fi

        # 提取主机名（不包含用户名）用于连接测试
        SERVER_HOSTNAME=$(echo "$SERVER_HOST" | cut -d '@' -f 2)
        if [ -z "$SERVER_HOSTNAME" ]; then
            SERVER_HOSTNAME="$SERVER_HOST"  # 如果没有@符号，则使用整个主机字符串
        fi

        # 写入日志
        if [ -n "$LOG_FILE" ]; then
            echo "  测试SSH连接..." >> "$LOG_FILE"
        fi

        # 根据认证类型构建rsync命令
        RSYNC_SSH_OPTS=""
        if [ "$AUTH_TYPE" = "ssh" ]; then
            if [ ! -f "$AUTH_INFO" ]; then
            log_error "SSH密钥 $AUTH_INFO 不存在，当前 HOME=$HOME"
                exit 1
            fi

            # 测试SSH连接（静默测试，失败时才显示详细信息）
            if [ -n "$LOG_FILE" ]; then
                echo "  测试SSH密钥连接..." >> "$LOG_FILE"
            fi
            ssh -i "$AUTH_INFO" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$SERVER_HOST" "echo 连接成功" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                log_error "SSH 连接测试失败"
                log_warn "请确认以下信息:"
                echo -e "  1. ${CYAN}服务器 $SERVER_HOSTNAME 是否可达${NC}"
                echo -e "  2. ${CYAN}SSH密钥 $AUTH_INFO 是否有效${NC}"
                echo -e "  3. ${CYAN}SSH密钥权限是否正确 (应为600)${NC}"
                echo -e "  4. ${CYAN}服务器SSH配置是否允许密钥认证${NC}"
                echo -e "  5. ${CYAN}是否存在网络代理问题${NC}"

                # 设置SSH密钥权限为600
                log_warn "尝试修复 SSH 密钥权限为 600"
                chmod 600 "$AUTH_INFO"
                log_info "已设置 SSH 密钥权限为 600"

                log_info "再次测试 SSH 连接 (修复权限后)..."
                ssh -i "$AUTH_INFO" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$SERVER_HOST" "echo 连接成功" 2>&1
                if [ $? -ne 0 ]; then
                    log_error "修复权限后 SSH 连接仍然失败"

                    # 询问是否跳过代理
                    read -p "是否尝试使用无代理模式连接? (y/n): " direct_conn_choice
                    if [ "$direct_conn_choice" = "y" ] || [ "$direct_conn_choice" = "Y" ]; then
                        log_info "用户选择尝试无代理模式直接连接"
                        # 确保所有可能的代理变量都被清除
                        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY

                        log_info "使用 -v 调试模式尝试 SSH 连接（密钥）"
                        ssh -v -i "$AUTH_INFO" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SERVER_HOST" "echo 调试模式连接成功" 2>&1

                        # 询问是否跳过此服务器
                        read -p "是否仍然要尝试继续同步? (y/n): " force_sync_choice
                        if [ "$force_sync_choice" != "y" ] && [ "$force_sync_choice" != "Y" ]; then
                            read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                            if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                                log_warn "跳过服务器 $SERVER_NAME"
                                continue
                            else
                                log_error "同步中止"

                                # 恢复代理设置
                                if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                                    log_info "恢复代理设置..."
                                    export http_proxy=$BACKUP_HTTP_PROXY
                                    export https_proxy=$BACKUP_HTTPS_PROXY
                                    export all_proxy=$BACKUP_ALL_PROXY
                                    export no_proxy=$BACKUP_NO_PROXY
                                    log_success "代理设置已恢复"
                                fi

                                exit 1
                            fi
                        else
                            log_warn "强制继续同步..."
                        fi
                    else
                        # 询问是否跳过此服务器
                        read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                        if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                            log_warn "跳过服务器 $SERVER_NAME"
                            continue
                        else
                                log_error "用户选择中止同步"

                            # 恢复代理设置
                            if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                                    log_info "恢复代理设置..."
                                export http_proxy=$BACKUP_HTTP_PROXY
                                export https_proxy=$BACKUP_HTTPS_PROXY
                                export all_proxy=$BACKUP_ALL_PROXY
                                export no_proxy=$BACKUP_NO_PROXY
                                    log_info "代理设置已恢复"
                            fi

                            exit 1
                        fi
                    fi
                else
                    log_success "修复权限后 SSH 连接成功"
                fi
            else
                if [ -n "$LOG_FILE" ]; then
                    echo "  SSH连接测试成功" >> "$LOG_FILE"
                fi
            fi

            # 使用无代理环境变量的SSH命令
            RSYNC_SSH_OPTS="-e \"ssh -i $AUTH_INFO -o StrictHostKeyChecking=no\""
        elif [ "$AUTH_TYPE" = "password" ]; then
            # 检查sshpass是否可用
            if ! command -v sshpass >/dev/null 2>&1; then
                log_error "服务器 $SERVER_NAME 配置为密码认证，但sshpass未安装"
                log_warn "可以使用以下命令安装sshpass:"
                echo -e "  ${CYAN}Debian/Ubuntu:${NC} ${BLUE}sudo apt-get install sshpass${NC}"
                echo -e "  ${CYAN}CentOS/RHEL:${NC} ${BLUE}sudo yum install sshpass${NC}"
                echo -e "  ${CYAN}macOS:${NC} ${BLUE}brew install hudochenkov/sshpass/sshpass${NC}"

                # 询问是否跳过此服务器
                read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                    log_warn "跳过服务器 $SERVER_NAME"
                    continue
                else
                    log_error "同步中止"

                    # 恢复代理设置
                    if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                        log_info "恢复代理设置..."
                        export http_proxy=$BACKUP_HTTP_PROXY
                        export https_proxy=$BACKUP_HTTPS_PROXY
                        export all_proxy=$BACKUP_ALL_PROXY
                        export no_proxy=$BACKUP_NO_PROXY
                        log_success "代理设置已恢复"
                    fi

                    exit 1
                fi
            fi

            # 测试SSH密码连接（静默测试）
            if [ -n "$LOG_FILE" ]; then
                echo "  测试SSH密码连接..." >> "$LOG_FILE"
            fi
            # 使用临时文件存储密码，避免在进程列表中暴露
            local temp_pass_file=$(mktemp)
            echo "$AUTH_INFO" > "$temp_pass_file"
            chmod 600 "$temp_pass_file"
            sshpass -f "$temp_pass_file" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SERVER_HOST" "echo 连接成功" >/dev/null 2>&1
            local ssh_result=$?
            rm -f "$temp_pass_file"
            if [ $ssh_result -ne 0 ]; then
                log_error "SSH 密码连接测试失败"
                log_warn "请确认以下信息:"
                echo -e "  1. ${CYAN}服务器 $SERVER_HOSTNAME 是否可达${NC}"
                echo -e "  2. ${CYAN}密码是否正确${NC}"
                echo -e "  3. ${CYAN}服务器SSH配置是否允许密码认证${NC}"
                echo -e "  4. ${CYAN}是否存在网络代理问题${NC}"

                # 询问是否跳过代理
                read -p "是否尝试使用无代理模式连接? (y/n): " direct_conn_choice
                if [ "$direct_conn_choice" = "y" ] || [ "$direct_conn_choice" = "Y" ]; then
                    log_info "用户选择尝试无代理模式直接连接 (密码认证)"
                    # 确保所有可能的代理变量都被清除
                    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY

                    log_info "使用 -v 调试模式尝试 SSH 密码连接"
                    local temp_debug_pass_file=$(mktemp)
                    echo "$AUTH_INFO" > "$temp_debug_pass_file"
                    chmod 600 "$temp_debug_pass_file"
                    sshpass -f "$temp_debug_pass_file" ssh -v -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SERVER_HOST" "echo 调试模式连接成功" 2>&1
                    rm -f "$temp_debug_pass_file"

                    # 询问是否仍然尝试同步
                    read -p "是否仍然要尝试继续同步? (y/n): " force_sync_choice
                    if [ "$force_sync_choice" != "y" ] && [ "$force_sync_choice" != "Y" ]; then
                        read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                        if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                            log_warn "跳过服务器 $SERVER_NAME"
                            continue
                        else
                            log_error "用户选择中止同步"

                            # 恢复代理设置
                            if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                                log_info "恢复代理设置..."
                                export http_proxy=$BACKUP_HTTP_PROXY
                                export https_proxy=$BACKUP_HTTPS_PROXY
                                export all_proxy=$BACKUP_ALL_PROXY
                                export no_proxy=$BACKUP_NO_PROXY
                                log_info "代理设置已恢复"
                            fi

                            exit 1
                        fi
                    else
                        log_warn "强制继续同步..."
                    fi
                else
                    # 询问是否跳过此服务器
                    read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                    if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                            log_warn "跳过服务器 $SERVER_NAME"
                        continue
                    else
                        log_error "用户选择中止同步"

                        # 恢复代理设置
                        if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                            log_info "恢复代理设置..."
                            export http_proxy=$BACKUP_HTTP_PROXY
                            export https_proxy=$BACKUP_HTTPS_PROXY
                            export all_proxy=$BACKUP_ALL_PROXY
                            export no_proxy=$BACKUP_NO_PROXY
                            log_info "代理设置已恢复"
                        fi

                        exit 1
                    fi
                fi
            else
                if [ -n "$LOG_FILE" ]; then
                    echo "  SSH连接测试成功" >> "$LOG_FILE"
                fi
            fi

            # 创建临时密码文件用于rsync
            TEMP_RSYNC_PASS_FILE=$(mktemp)
            echo "$AUTH_INFO" > "$TEMP_RSYNC_PASS_FILE"
            chmod 600 "$TEMP_RSYNC_PASS_FILE"
            RSYNC_SSH_OPTS="-e \"sshpass -f '$TEMP_RSYNC_PASS_FILE' ssh -o StrictHostKeyChecking=no\""
        else
            log_error "服务器 $SERVER_NAME 的认证类型 $AUTH_TYPE 不支持，必须为 'ssh' 或 'password'"
            exit 1
        fi

        # 使用eval执行rsync命令，以便正确解析引号
        RSYNC_CMD="rsync $RSYNC_OPTIONS $RSYNC_SSH_OPTS $EXCLUDE_OPTS \"$LOCAL_DIR/\" \"$SERVER_HOST:$TARGET_DIR/\""
        
        # 写入简要信息到日志（不包含详细输出）
        if [ -n "$LOG_FILE" ]; then
            echo "  开始rsync同步..." >> "$LOG_FILE"
        fi

        if [ "$VERBOSE" = true ]; then
            echo -e "${CYAN}执行命令:${NC} $RSYNC_CMD"
            eval $RSYNC_CMD
            RSYNC_EXIT_CODE=$?
        else
            # 精简模式：实时滚动显示文件，完成后清除
            # 创建临时文件
            local temp_rsync_output=$(mktemp)
            
            # 在rsync命令中添加 -v 参数以获取详细输出
            local rsync_cmd_verbose
            if [[ "$RSYNC_OPTIONS" != *"-v"* ]]; then
                rsync_cmd_verbose="rsync -v $RSYNC_OPTIONS $RSYNC_SSH_OPTS $EXCLUDE_OPTS \"$LOCAL_DIR/\" \"$SERVER_HOST:$TARGET_DIR/\""
            else
                rsync_cmd_verbose="$RSYNC_CMD"
            fi
            
            # 后台执行rsync
            eval $rsync_cmd_verbose > "$temp_rsync_output" 2>&1 &
            local rsync_pid=$!
            
            # 灰色文字滚动显示配置
            local GRAY='\033[0;90m'
            local display_lines=12
            local last_line_count=0
            
            # 预留空间
            for ((j=0; j<$display_lines; j++)); do
                echo ""
            done
            
            # 实时显示文件列表（滚动效果）
            while kill -0 $rsync_pid 2>/dev/null; do
                # 向上移动光标到显示区域开始
                for ((j=0; j<$display_lines; j++)); do
                    printf "\033[1A"  # 向上移动一行
                done
                
                # 提取最新的文件列表（过滤掉统计和提示信息）
                local files=$(grep "^[a-zA-Z0-9_/.]" "$temp_rsync_output" 2>/dev/null | \
                    grep -v "building file list\|done\|^sent\|^total\|^Number" | \
                    tail -n $display_lines)
                
                # 显示文件列表
                local line_num=0
                while IFS= read -r file && [ $line_num -lt $display_lines ]; do
                    # 清除当前行
                    printf "\033[K"
                    
                    # 截断过长的文件名
                    if [ ${#file} -gt 70 ]; then
                        file="${file:0:67}..."
                    fi
                    
                    # 显示灰色文件名
                    echo -e "${GRAY}  ▸ $file${NC}"
                    line_num=$((line_num + 1))
                done <<< "$files"
                
                # 补充空行（如果文件数不足）
                while [ $line_num -lt $display_lines ]; do
                    printf "\033[K\n"
                    line_num=$((line_num + 1))
                done
                
                sleep 0.15
            done
            
            # 等待rsync完成
            wait $rsync_pid
            RSYNC_EXIT_CODE=$?
            
            # 清除滚动显示区域（向上移动并清除所有行）
            for ((j=0; j<$display_lines; j++)); do
                printf "\033[1A\033[K"
            done
            
            # 显示最终结果
            if [ $RSYNC_EXIT_CODE -eq 0 ]; then
                echo -e "${CYAN}  同步统计:${NC}"
                # 提取统计信息
                grep -E "Number of files:|Total file size:|Total transferred file size:|Literal data:|sent.*bytes.*received" "$temp_rsync_output" 2>/dev/null | while IFS= read -r line; do
                    echo "    $line"
                done
                
                # 如果没有统计信息，显示简单消息
                if ! grep -q "Number of files:" "$temp_rsync_output" 2>/dev/null; then
                    local total_files=$(grep -c "^[a-zA-Z0-9_/.]" "$temp_rsync_output" 2>/dev/null)
                    echo "    已同步 $total_files 个文件"
                fi
            else
                # 如果失败，显示错误信息
                echo -e "${RED}  同步失败，详细信息:${NC}"
                tail -n 20 "$temp_rsync_output" | while IFS= read -r line; do
                    echo "    $line"
                done
            fi
            
            # 清理临时文件
            rm -f "$temp_rsync_output"
        fi

        # 清理rsync密码文件
        if [ -n "$TEMP_RSYNC_PASS_FILE" ] && [ -f "$TEMP_RSYNC_PASS_FILE" ]; then
            rm -f "$TEMP_RSYNC_PASS_FILE"
        fi

        if [ $RSYNC_EXIT_CODE -eq 0 ]; then
            echo -e "  ${GREEN}[✓]${NC} 同步成功"
            
            # 写入日志
            if [ -n "$LOG_FILE" ]; then
                echo "  同步结果: 成功" >> "$LOG_FILE"
                echo "" >> "$LOG_FILE"
            fi

            # 执行同步后命令（权限设置等）
            execute_post_sync_commands "$i"
        else
            log_error "同步失败 (错误代码: $RSYNC_EXIT_CODE)"
            log_warn "rsync错误代码参考:"
            echo -e "  ${YELLOW}1-10:${NC} 通常是文件访问或权限错误"
            echo -e "  ${YELLOW}11-20:${NC} 网络或连接错误"
            echo -e "  ${YELLOW}23-24:${NC} 其他rsync错误"
            echo -e "  ${YELLOW}30+:${NC} SSH或shell错误"

            # 询问是否继续同步其他服务器
            read -p "是否继续同步其他服务器? (y/n): " continue_choice
            if [ "$continue_choice" = "y" ] || [ "$continue_choice" = "Y" ]; then
                log_warn "用户选择在当前错误后继续同步其他服务器"
                continue
            else
                log_error "用户选择中止同步"

                # 恢复代理设置
                if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                    log_info "恢复代理设置..."
                    export http_proxy=$BACKUP_HTTP_PROXY
                    export https_proxy=$BACKUP_HTTPS_PROXY
                    export all_proxy=$BACKUP_ALL_PROXY
                    export no_proxy=$BACKUP_NO_PROXY
                    log_info "代理设置已恢复"
                fi

                exit 1
            fi
        fi
    done

    echo ""
    echo -e "${GREEN}[✓]${NC} 所有服务器同步完成"

    # 恢复代理设置
    if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
        export http_proxy=$BACKUP_HTTP_PROXY
        export https_proxy=$BACKUP_HTTPS_PROXY
        export all_proxy=$BACKUP_ALL_PROXY
        export no_proxy=$BACKUP_NO_PROXY
        echo -e "${GREEN}[✓]${NC} 代理设置已恢复"
    fi
}

# 执行同步后命令（权限设置等）
execute_post_sync_commands() {
    local server_index=$1

    if [ -n "$LOG_FILE" ]; then
        echo "  执行同步后命令..." >> "$LOG_FILE"
    fi

    # 获取服务器信息
    if command -v yq >/dev/null 2>&1; then
        SERVER_NAME=$(yq e ".server_groups[$GROUP_INDEX].servers[$server_index].name" "$CONFIG_FILE")
        SERVER_HOST=$(yq e ".server_groups[$GROUP_INDEX].servers[$server_index].host" "$CONFIG_FILE")
        TARGET_DIR=$(yq e ".server_groups[$GROUP_INDEX].servers[$server_index].target_dir" "$CONFIG_FILE")
        SERVER_BRANCH=$(yq e ".server_groups[$GROUP_INDEX].servers[$server_index].branch // \"$DEFAULT_BRANCH\"" "$CONFIG_FILE")
        AUTH_TYPE=$(yq e ".server_groups[$GROUP_INDEX].servers[$server_index].auth_type" "$CONFIG_FILE")
        AUTH_INFO=$(yq e ".server_groups[$GROUP_INDEX].servers[$server_index].auth_info" "$CONFIG_FILE")

        # 获取命令列表（按优先级：服务器级别 > 服务器组级别 > 全局默认）
        # 这里改为使用数组存储命令，避免某些环境下多行字符串/管道读取导致只执行部分命令
        COMMAND_LIST=()

        # 服务器级别命令
        while IFS= read -r line; do
            [ -n "$line" ] && COMMAND_LIST+=("$line")
        done < <(yq e ".server_groups[$GROUP_INDEX].servers[$server_index].post_sync_commands[]?" "$CONFIG_FILE" 2>/dev/null)

        # 如果服务器级别没有配置，再尝试服务器组级别
        if [ ${#COMMAND_LIST[@]} -eq 0 ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && COMMAND_LIST+=("$line")
            done < <(yq e ".server_groups[$GROUP_INDEX].post_sync_commands[]?" "$CONFIG_FILE" 2>/dev/null)
        fi

        # 如果服务器组级别也没有，再使用全局默认命令
        if [ ${#COMMAND_LIST[@]} -eq 0 ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && COMMAND_LIST+=("$line")
            done < <(yq e ".default_post_sync_commands[]?" "$CONFIG_FILE" 2>/dev/null)
        fi

        # 展开路径中的~
        if [[ "$AUTH_TYPE" = "ssh" ]]; then
            AUTH_INFO=$(expand_path "$AUTH_INFO")
        fi
    else
        # 使用Python解析（简化版本，主要支持yq）
        log_warn "未安装 yq，post_sync_commands 仅部分支持，建议安装 yq"
        return
    fi

    # 如果没有配置任何命令，跳过
    if [ ${#COMMAND_LIST[@]} -eq 0 ]; then
        return
    fi

    if [ -n "$LOG_FILE" ]; then
        echo "  找到 ${#COMMAND_LIST[@]} 条同步后命令" >> "$LOG_FILE"
    fi

    # 预处理命令并显示
    echo ""
    echo -e "${CYAN}━━━━━━ 同步后命令 (${#COMMAND_LIST[@]} 条) ━━━━━━${NC}"
    local cmd_count=0

    for command in "${COMMAND_LIST[@]}"; do
        if [ -n "$command" ]; then
            cmd_count=$((cmd_count + 1))
            # 变量替换
            processed_command=$(echo "$command" | sed "s|{target_dir}|$TARGET_DIR|g" | sed "s|{server_name}|$SERVER_NAME|g" | sed "s|{branch}|$SERVER_BRANCH|g")
            echo -e "${CYAN}[$cmd_count]${NC} $processed_command"
        fi
    done
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # 询问用户执行方式
    echo -e "${YELLOW}请选择执行方式：${NC}"
    echo -e "  ${GREEN}[1]${NC} 执行所有命令"
    echo -e "  ${GREEN}[2]${NC} 逐个确认执行"
    echo -e "  ${GREEN}[3]${NC} 跳过所有命令"
    read -p "请输入选择 (1/2/3): " execute_mode

    case "$execute_mode" in
        1)
            if [ -n "$LOG_FILE" ]; then
                echo "  执行模式: 全部执行" >> "$LOG_FILE"
            fi
            ;;
        2)
            if [ -n "$LOG_FILE" ]; then
                echo "  执行模式: 逐个确认" >> "$LOG_FILE"
            fi
            ;;
        3|*)
            echo -e "${YELLOW}[!]${NC} 跳过所有命令"
            return
            ;;
    esac
    echo ""

    # 执行每个命令
    local cmd_index=0
    local should_break=false

    for command in "${COMMAND_LIST[@]}"; do
        if [ -n "$command" ]; then
            cmd_index=$((cmd_index + 1))
            # 变量替换
            processed_command=$(echo "$command" | sed "s|{target_dir}|$TARGET_DIR|g" | sed "s|{server_name}|$SERVER_NAME|g" | sed "s|{branch}|$SERVER_BRANCH|g")

            # 如果是逐个确认模式，询问用户
            if [ "$execute_mode" = "2" ]; then
                echo -e "${YELLOW}准备执行命令 [${CYAN}$cmd_index${NC}${YELLOW}]:${NC} $processed_command"
                read -p "是否执行此命令? (y/n/q): " cmd_choice
                case "$cmd_choice" in
                    y|Y)
                        ;;
                    q|Q)
                        echo -e "${YELLOW}[!]${NC} 退出执行"
                        should_break=true
                        break
                        ;;
                    *)
                        echo -e "${YELLOW}[!]${NC} 跳过命令 [$cmd_index]"
                        continue
                        ;;
                esac
            fi

            echo -e "${BLUE}[→]${NC} 执行 [$cmd_index]: $processed_command"
            
            # 检测是否为交互式命令
            local is_interactive=false
            local interactive_keywords="mysql|psql|redis-cli|mongo|vim|vi|nano|emacs|less|more|top|htop|sudo -i|su -|passwd|apt-get.*install|yum.*install|npm install|yarn install|read"
            
            if echo "$processed_command" | grep -qE "$interactive_keywords"; then
                is_interactive=true
                echo -e "${YELLOW}  ⚠ 检测到可能的交互式命令${NC}"
                read -p "  是否需要交互? (y/n, 默认n): " need_interactive
                if [ "$need_interactive" = "y" ] || [ "$need_interactive" = "Y" ]; then
                    is_interactive=true
                else
                    is_interactive=false
                fi
            fi

            # 如果是交互式命令，直接执行
            if [ "$is_interactive" = true ]; then
                echo -e "${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                
                # 直接执行，不重定向输出
                if [ "$AUTH_TYPE" = "ssh" ]; then
                    ssh -i "$AUTH_INFO" -o StrictHostKeyChecking=no -t "$SERVER_HOST" "$processed_command"
                    local cmd_exit_code=$?
                elif [ "$AUTH_TYPE" = "password" ]; then
                    local temp_cmd_pass_file=$(mktemp)
                    echo "$AUTH_INFO" > "$temp_cmd_pass_file"
                    chmod 600 "$temp_cmd_pass_file"
                    sshpass -f "$temp_cmd_pass_file" ssh -o StrictHostKeyChecking=no -t "$SERVER_HOST" "$processed_command"
                    local cmd_exit_code=$?
                    rm -f "$temp_cmd_pass_file"
                fi
                
                echo -e "${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            else
                # 非交互式命令，使用滚动显示
                # 创建临时文件存储命令输出
                local temp_cmd_output=$(mktemp)
                
                # 根据认证类型在后台执行远程命令
                if [ "$AUTH_TYPE" = "ssh" ]; then
                    ssh -i "$AUTH_INFO" -o StrictHostKeyChecking=no "$SERVER_HOST" "$processed_command" > "$temp_cmd_output" 2>&1 &
                    local cmd_pid=$!
                elif [ "$AUTH_TYPE" = "password" ]; then
                    local temp_cmd_pass_file=$(mktemp)
                    echo "$AUTH_INFO" > "$temp_cmd_pass_file"
                    chmod 600 "$temp_cmd_pass_file"
                    sshpass -f "$temp_cmd_pass_file" ssh -o StrictHostKeyChecking=no "$SERVER_HOST" "$processed_command" > "$temp_cmd_output" 2>&1 &
                    local cmd_pid=$!
                    # 在后台清理密码文件
                    (sleep 1; rm -f "$temp_cmd_pass_file") &
                fi

                # 灰色文字滚动显示命令输出
                local GRAY='\033[0;90m'
                local display_lines=10
                
                # 预留显示空间
                for ((j=0; j<$display_lines; j++)); do
                    echo ""
                done
                
                # 实时显示命令输出
                while kill -0 $cmd_pid 2>/dev/null; do
                    # 向上移动光标
                    for ((j=0; j<$display_lines; j++)); do
                        printf "\033[1A"
                    done
                    
                    # 获取最新的输出（最后10行）
                    local output_lines=$(tail -n $display_lines "$temp_cmd_output" 2>/dev/null)
                    
                    local line_num=0
                    while IFS= read -r line && [ $line_num -lt $display_lines ]; do
                        printf "\033[K"  # 清除当前行
                        
                        # 截断过长的行
                        if [ ${#line} -gt 75 ]; then
                            line="${line:0:72}..."
                        fi
                        
                        # 显示灰色输出
                        echo -e "${GRAY}  │ $line${NC}"
                        line_num=$((line_num + 1))
                    done <<< "$output_lines"
                    
                    # 补充空行
                    while [ $line_num -lt $display_lines ]; do
                        printf "\033[K\n"
                        line_num=$((line_num + 1))
                    done
                    
                    sleep 0.2
                done
                
                # 等待命令完成
                wait $cmd_pid
                local cmd_exit_code=$?
                
                # 清除滚动显示区域
                for ((j=0; j<$display_lines; j++)); do
                    printf "\033[1A\033[K"
                done
            fi
            
            # 统一的结果显示和错误处理
            if [ $cmd_exit_code -eq 0 ]; then
                echo -e "  ${GREEN}[✓]${NC} 命令 [$cmd_index] 完成"
                if [ -n "$LOG_FILE" ]; then
                    echo "  命令 [$cmd_index] 执行成功" >> "$LOG_FILE"
                fi
            else
                echo -e "  ${RED}[✗]${NC} 命令 [$cmd_index] 失败 (退出码: $cmd_exit_code)"
                
                # 非交互式命令才显示错误输出
                if [ "$is_interactive" = false ] && [ -f "$temp_cmd_output" ]; then
                    # 显示错误信息（最后5行）
                    echo -e "${RED}  错误输出:${NC}"
                    tail -n 5 "$temp_cmd_output" 2>/dev/null | while IFS= read -r line; do
                        echo "    $line"
                    done
                    
                    if [ -n "$LOG_FILE" ]; then
                        echo "  命令 [$cmd_index] 执行失败" >> "$LOG_FILE"
                        echo "  错误输出:" >> "$LOG_FILE"
                        tail -n 10 "$temp_cmd_output" >> "$LOG_FILE" 2>/dev/null
                    fi
                fi
                
                if [ "$execute_mode" = "1" ]; then
                    read -p "是否继续执行其他命令? (y/n): " continue_cmd_choice
                    if [ "$continue_cmd_choice" != "y" ] && [ "$continue_cmd_choice" != "Y" ]; then
                        echo -e "${YELLOW}[!]${NC} 停止执行后续命令"
                        should_break=true
                        [ -f "$temp_cmd_output" ] && rm -f "$temp_cmd_output"
                        break
                    fi
                fi
            fi
            
            # 清理临时文件
            [ -f "$temp_cmd_output" ] && rm -f "$temp_cmd_output"
        fi
    done

    echo ""
}

# 清理敏感凭据
cleanup_credentials() {
    # 清除环境变量中的敏感信息
    if [ "$GIT_AUTH_TYPE" = "password" ]; then
        GIT_PASSWORD=""
        GIT_USERNAME=""
    fi

    # 清除SSH命令中的敏感信息
    unset GIT_SSH_COMMAND
    
    if [ -n "$LOG_FILE" ]; then
        local end_time=$(date '+%Y-%m-%d %H:%M:%S')
        echo "" >> "$LOG_FILE"
        echo "───────────────────────────────────────────────────────────────" >> "$LOG_FILE"
        echo "              [$end_time] 同步完成" >> "$LOG_FILE"
        echo "───────────────────────────────────────────────────────────────" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
}

# 主函数
main() {
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      Gitee 代码同步工具 v1.1         ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""

    check_dependencies
    select_config_file
    parse_config
    select_server_group
    pull_code
    replace_configs
    sync_to_servers
    cleanup_credentials

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ 同步完成！                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    if [ -n "$LOG_FILE" ]; then
        echo -e "${CYAN}详细日志:${NC} $LOG_FILE"
    fi
    echo ""
}

# 执行主函数
main
