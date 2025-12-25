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
FORCE_SYNC=false
for arg in "$@"; do
    case $arg in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--force)
            FORCE_SYNC=true
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
            echo "  -f, --force          强制同步所有 Git 管理的文件"
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

# 注意：不使用 set -e，因为它会导致脚本在复杂场景下意外退出
# 我们使用显式的错误检查来处理关键命令
# set -e

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
    
    # 写入文件日志（去除颜色代码）
    if [ -n "$LOG_FILE" ]; then
        local clean_msg=$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')
        echo "[${ts}] [INFO] $clean_msg" >> "$LOG_FILE"
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
    
    # 写入文件日志（去除颜色代码）
    if [ -n "$LOG_FILE" ]; then
        local clean_msg=$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')
        echo "[${ts}] [SUCCESS] $clean_msg" >> "$LOG_FILE"
    fi
    
    # 控制台输出（精简模式下始终显示成功信息）
    echo -e "[${ts}] ${GREEN}[✓]${NC} $msg"
}

log_warn() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入文件日志（去除颜色代码）
    if [ -n "$LOG_FILE" ]; then
        local clean_msg=$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')
        echo "[${ts}] [WARN] $clean_msg" >> "$LOG_FILE"
    fi
    
    # 控制台输出（始终显示警告）
    echo -e "[${ts}] ${YELLOW}[!]${NC} $msg"
}

log_error() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入文件日志（去除颜色代码）
    if [ -n "$LOG_FILE" ]; then
        local clean_msg=$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')
        echo "[${ts}] [ERROR] $clean_msg" >> "$LOG_FILE"
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
    
    log_info "同步策略: ${CYAN}Git 为真相源${NC} (只操作 Git 管理的文件)"
    
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
            
            # 记录当前提交，用于检测变更
            local old_commit=""
            if git rev-parse --verify "$branch" >/dev/null 2>&1; then
                old_commit=$(git rev-parse "$branch")
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
            
            # 检测 Git 变更（详细类型：A/M/D）
            local new_commit=$(git rev-parse HEAD)
            if [ -n "$old_commit" ] && [ "$old_commit" != "$new_commit" ]; then
                # 使用 --name-status 获取变更类型
                local git_changes=$(git diff --name-status "$old_commit" "$new_commit")
                
                # 分类存储
                local added_files=()
                local modified_files=()
                local deleted_files=()
                
                while IFS=$'\t' read -r status file; do
                    if [ -n "$file" ]; then
                        case "$status" in
                            A)  added_files+=("$file") ;;
                            M)  modified_files+=("$file") ;;
                            D)  deleted_files+=("$file") ;;
                        esac
                    fi
                done <<< "$git_changes"
                
                # 存储到全局变量（使用变量名拼接，兼容 bash 3.2）
                # 将分支名中的特殊字符替换为下划线
                local branch_var=$(echo "$branch" | sed 's/[^a-zA-Z0-9_]/_/g')
                eval "CHANGED_FILES_${branch_var}_added=\"${added_files[*]}\""
                eval "CHANGED_FILES_${branch_var}_modified=\"${modified_files[*]}\""
                eval "CHANGED_FILES_${branch_var}_deleted=\"${deleted_files[*]}\""
                
                # 显示统计
                echo -e "  ${CYAN}[i]${NC} 分支 ${CYAN}$branch${NC} 变更统计:"
                [ ${#added_files[@]} -gt 0 ] && echo -e "    新增: ${GREEN}${#added_files[@]}${NC} 个文件"
                [ ${#modified_files[@]} -gt 0 ] && echo -e "    修改: ${YELLOW}${#modified_files[@]}${NC} 个文件"
                [ ${#deleted_files[@]} -gt 0 ] && echo -e "    删除: ${RED}${#deleted_files[@]}${NC} 个文件"
                
                # 写入日志
                if [ -n "$LOG_FILE" ]; then
                    echo "  分支 $branch 变更详情:" >> "$LOG_FILE"
                    if [ ${#added_files[@]} -gt 0 ]; then
                        echo "    新增文件:" >> "$LOG_FILE"
                        for file in "${added_files[@]}"; do
                            echo "      + $file" >> "$LOG_FILE"
                        done
                    fi
                    if [ ${#modified_files[@]} -gt 0 ]; then
                        echo "    修改文件:" >> "$LOG_FILE"
                        for file in "${modified_files[@]}"; do
                            echo "      M $file" >> "$LOG_FILE"
                        done
                    fi
                    if [ ${#deleted_files[@]} -gt 0 ]; then
                        echo "    删除文件:" >> "$LOG_FILE"
                        for file in "${deleted_files[@]}"; do
                            echo "      - $file" >> "$LOG_FILE"
                        done
                    fi
                fi
            else
                # 无变更，清空变量
                local branch_var=$(echo "$branch" | sed 's/[^a-zA-Z0-9_]/_/g')
                eval "CHANGED_FILES_${branch_var}_added=\"\""
                eval "CHANGED_FILES_${branch_var}_modified=\"\""
                eval "CHANGED_FILES_${branch_var}_deleted=\"\""
                echo -e "  ${YELLOW}[!]${NC} 分支 $branch 无变更"
            fi
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
            # 首次克隆，标记为首次同步
            local branch_var=$(echo "$branch" | sed 's/[^a-zA-Z0-9_]/_/g')
            eval "CHANGED_FILES_${branch_var}_first_clone=\"true\""
        done

        echo -e "  ${GREEN}[✓]${NC} 代码克隆完成 (${#REQUIRED_BRANCHES[@]} 个分支)"
        echo -e "  ${CYAN}[i]${NC} 首次克隆，将使用智能比对同步文件"
        
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
    
    # 初始化替换文件列表
    REPLACED_FILES=()

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

    # 递归替换文件（只替换有变更的文件）
    if [ "$VERBOSE" = true ]; then
        # 详细模式：滚动显示最近 10 个文件
        local temp_files=$(mktemp)
        local temp_processed=$(mktemp)
        find "$REPLACE_DIR" -type f -print > "$temp_files"
        local total_count=$(wc -l < "$temp_files" | tr -d ' ')
        local current_count=0
        local replaced_count=0
        local skipped_count=0
        local display_lines=10
        
        # 预留显示空间
        local actual_lines=$((total_count < display_lines ? total_count : display_lines))
        for ((j=0; j<$actual_lines; j++)); do
            echo ""
        done
        
        while IFS= read -r replace_file; do
            rel_path="${replace_file#$REPLACE_DIR/}"
            target_file="$LOCAL_DIR/$rel_path"
            target_dir=$(dirname "$target_file")
            current_count=$((current_count + 1))

            if [ ! -d "$target_dir" ]; then
                mkdir -p "$target_dir"
            fi

            # 检查文件是否需要替换（内容比对）
            local need_replace=true
            if [ -f "$target_file" ]; then
                # 使用 cmp 比较文件内容
                if cmp -s "$replace_file" "$target_file"; then
                    need_replace=false
                    skipped_count=$((skipped_count + 1))
                fi
            fi
            
            if [ "$need_replace" = true ]; then
                cp -f "$replace_file" "$target_file"
                REPLACED_FILES+=("$rel_path")
                replaced_count=$((replaced_count + 1))
                echo "✓ $rel_path" >> "$temp_processed"
            else
                echo "→ $rel_path (无变更)" >> "$temp_processed"
            fi
            
            # 向上移动光标到显示区域
            for ((j=0; j<$actual_lines; j++)); do
                printf "\033[1A"
            done
            
            # 显示最近的文件
            tail -n $display_lines "$temp_processed" | while IFS= read -r show_line; do
                if [[ "$show_line" == "✓ "* ]]; then
                    local show_file="${show_line#✓ }"
                    printf "\033[2K  ${GREEN}[✓]${NC} ${GRAY}%s${NC}\n" "$show_file"
                else
                    local show_file="${show_line#→ }"
                    printf "\033[2K  ${YELLOW}[→]${NC} ${GRAY}%s${NC}\n" "$show_file"
                fi
            done
            
            # 补齐空行（如果还没有足够的文件）
            local shown=$(tail -n $display_lines "$temp_processed" | wc -l | tr -d ' ')
            for ((j=$shown; j<$actual_lines; j++)); do
                printf "\033[2K\n"
            done
        done < "$temp_files"
        
        # 清除滚动显示区域
        for ((j=0; j<$actual_lines; j++)); do
            printf "\033[1A\033[2K"
        done
        
        # 显示完成信息
        if [ $skipped_count -gt 0 ]; then
            echo -e "  ${GREEN}[✓]${NC} 替换 ${CYAN}${replaced_count}${NC} 个文件，跳过 ${YELLOW}${skipped_count}${NC} 个无变更文件"
        else
            echo -e "  ${GREEN}[✓]${NC} 已替换 ${CYAN}${replaced_count}${NC} 个文件"
        fi
        rm -f "$temp_files" "$temp_processed"
    else
        # 精简模式：后台执行并显示进度（只替换有变更的文件）
        local temp_replaced_list=$(mktemp)
        local temp_skipped_list=$(mktemp)
        
        replace_config_files_background() {
            find "$REPLACE_DIR" -type f -print | while read replace_file; do
                rel_path="${replace_file#$REPLACE_DIR/}"
                target_file="$LOCAL_DIR/$rel_path"
                target_dir=$(dirname "$target_file")

                if [ ! -d "$target_dir" ]; then
                    mkdir -p "$target_dir"
                fi

                # 检查文件是否需要替换（内容比对）
                local need_replace=true
                if [ -f "$target_file" ]; then
                    if cmp -s "$replace_file" "$target_file"; then
                        need_replace=false
                        echo "$rel_path" >> "$temp_skipped_list"
                    fi
                fi
                
                if [ "$need_replace" = true ]; then
                    cp -f "$replace_file" "$target_file"
                    echo "$rel_path" >> "$temp_replaced_list"
                fi
            done
        }

        # 在后台执行替换
        replace_config_files_background &
        local replace_pid=$!

        # 显示进度
        show_progress "  替换配置文件" "$replace_pid"
        wait "$replace_pid"
        
        # 读取替换文件列表
        while IFS= read -r file; do
            [ -n "$file" ] && REPLACED_FILES+=("$file")
        done < "$temp_replaced_list"
        
        # 统计数量
        local replaced_count=${#REPLACED_FILES[@]}
        local skipped_count=$(wc -l < "$temp_skipped_list" 2>/dev/null | tr -d ' ' || echo "0")
        rm -f "$temp_replaced_list" "$temp_skipped_list"

        # 显示结果
        if [ "$skipped_count" -gt 0 ]; then
            echo -e "  ${GREEN}[✓]${NC} 替换 ${CYAN}${replaced_count}${NC} 个文件，跳过 ${YELLOW}${skipped_count}${NC} 个无变更文件"
        else
            echo -e "  ${GREEN}[✓]${NC} 已替换 ${CYAN}${replaced_count}${NC} 个文件"
        fi
        
        if [ -n "$LOG_FILE" ]; then
            echo "  替换文件数: $replaced_count (跳过: $skipped_count)" >> "$LOG_FILE"
            if [ $replaced_count -gt 0 ]; then
                echo "  替换文件列表:" >> "$LOG_FILE"
                for file in "${REPLACED_FILES[@]}"; do
                    echo "    - $file" >> "$LOG_FILE"
                done
            fi
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
            git checkout "$SERVER_BRANCH" || true  # 忽略错误，避免 set -e 导致退出
        else
            safe_git_command "正在切换到目标分支 $SERVER_BRANCH" "checkout" "$SERVER_BRANCH" || true
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

            # 测试SSH密码连接
            if [ -n "$LOG_FILE" ]; then
                echo "  测试SSH密码连接..." >> "$LOG_FILE"
            fi
            
            # 直接使用 -p 参数传递密码（更可靠）
            if [ "$VERBOSE" = true ]; then
                echo -e "  ${CYAN}[DEBUG]${NC} 测试 SSH 连接到 $SERVER_HOST..."
                echo -e "  ${CYAN}[DEBUG]${NC} 密码长度: ${#AUTH_INFO} 字符"
                echo -e "  ${CYAN}[DEBUG]${NC} 密码前3字符: ${AUTH_INFO:0:3}***"
                sshpass -p "$AUTH_INFO" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SERVER_HOST" "echo 连接成功"
                local ssh_result=$?
                echo -e "  ${CYAN}[DEBUG]${NC} SSH 返回码: $ssh_result"
            else
                sshpass -p "$AUTH_INFO" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SERVER_HOST" "echo 连接成功" >/dev/null 2>&1
                local ssh_result=$?
            fi
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
                    sshpass -f "$temp_debug_pass_file" ssh -v -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SERVER_HOST" "echo 调试模式连接成功" 2>&1
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
            RSYNC_SSH_OPTS="-e \"sshpass -f '$TEMP_RSYNC_PASS_FILE' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null\""
        else
            log_error "服务器 $SERVER_NAME 的认证类型 $AUTH_TYPE 不支持，必须为 'ssh' 或 'password'"
            exit 1
        fi

        # ========================================
        # 智能同步策略：以 Git 为真相源
        # ========================================
        
        # 初始化删除文件列表（避免未定义错误）
        DELETED_FILES_LIST=()
        
        # 1. 获取当前分支的变更（使用变量名拼接，兼容 bash 3.2）
        local branch_var=$(echo "$SERVER_BRANCH" | sed 's/[^a-zA-Z0-9_]/_/g')
        local is_first_clone=""
        local added_files=""
        local modified_files=""
        local deleted_files=""
        
        eval "is_first_clone=\${CHANGED_FILES_${branch_var}_first_clone}"
        eval "added_files=\${CHANGED_FILES_${branch_var}_added}"
        eval "modified_files=\${CHANGED_FILES_${branch_var}_modified}"
        eval "deleted_files=\${CHANGED_FILES_${branch_var}_deleted}"
        
        # 2. 准备需要同步的文件列表（Git 新增/修改 + Replace 替换）
        local files_to_upload=()
        
        if [ "$VERBOSE" = true ]; then
            echo -e "  ${CYAN}[DEBUG]${NC} REPLACED_FILES 数量: ${#REPLACED_FILES[@]}"
            echo -e "  ${CYAN}[DEBUG]${NC} added_files: '$added_files'"
            echo -e "  ${CYAN}[DEBUG]${NC} modified_files: '$modified_files'"
            echo -e "  ${CYAN}[DEBUG]${NC} deleted_files: '$deleted_files'"
            echo -e "  ${CYAN}[DEBUG]${NC} is_first_clone: '$is_first_clone'"
        fi
        
        # 添加 Git 新增的文件
        if [ -n "$added_files" ]; then
            for file in $added_files; do
                [ -n "$file" ] && files_to_upload+=("$file")
            done
        fi
        
        # 添加 Git 修改的文件
        if [ -n "$modified_files" ]; then
            for file in $modified_files; do
                [ -n "$file" ] && files_to_upload+=("$file")
            done
        fi
        
        # 添加 Replace 替换的文件（优先级最高，可能覆盖 Git 变更）
        for replaced_file in "${REPLACED_FILES[@]}"; do
            # 检查是否已在列表中
            local found=false
            for existing_file in "${files_to_upload[@]}"; do
                if [ "$existing_file" = "$replaced_file" ]; then
                    found=true
                    break
                fi
            done
            if [ "$found" = false ]; then
                files_to_upload+=("$replaced_file")
            fi
        done
        
        # 3. 判断同步策略
        if [ "$FORCE_SYNC" = true ]; then
            # 强制同步：使用智能比对同步所有 Git 文件
            echo -e "  ${CYAN}[i]${NC} 强制同步模式，使用智能比对同步所有 Git 管理的文件"
            
            # 切换到本地目录
            cd "$LOCAL_DIR"
            
            # 获取当前分支的所有 Git 文件
            git checkout "$SERVER_BRANCH" >/dev/null 2>&1 || true
            local all_git_files=$(git ls-files)
            
            # 创建文件列表
            local temp_file_list=$(mktemp)
            echo "$all_git_files" > "$temp_file_list"
            
            # 添加 Replace 替换的文件
            for replaced_file in "${REPLACED_FILES[@]}"; do
                echo "$replaced_file" >> "$temp_file_list"
            done
            
            # 使用 rsync --checksum 智能比对，只上传有差异的文件
            echo -e "  ${YELLOW}[→]${NC} 智能比对中..."
            
            if [ -n "$LOG_FILE" ]; then
                echo "  强制同步模式，智能比对同步" >> "$LOG_FILE"
            fi
            
            # 统计文件数量
            local file_count=$(wc -l < "$temp_file_list" | tr -d ' ')
            echo -e "  ${CYAN}[i]${NC} 将检查 ${CYAN}${file_count}${NC} 个文件（使用 checksum 比对）"
            
            # 构建 rsync 命令（使用 --checksum 比对，--files-from 指定文件列表）
            RSYNC_CMD="rsync -azc --files-from=\"$temp_file_list\" $RSYNC_SSH_OPTS \"$LOCAL_DIR/\" \"$SERVER_HOST:$TARGET_DIR/\""
            SYNC_FILES_LIST="$temp_file_list"
            
        elif [ "$is_first_clone" = "true" ]; then
            # 首次克隆：使用智能比对同步所有 Git 文件
            echo -e "  ${CYAN}[i]${NC} 首次克隆，使用智能比对同步 Git 管理的文件"
            
            # 切换到本地目录
            cd "$LOCAL_DIR"
            
            # 获取当前分支的所有 Git 文件
            git checkout "$SERVER_BRANCH" >/dev/null 2>&1
            local all_git_files=$(git ls-files)
            
            # 创建文件列表
            local temp_file_list=$(mktemp)
            echo "$all_git_files" > "$temp_file_list"
            
            # 添加 Replace 替换的文件
            for replaced_file in "${REPLACED_FILES[@]}"; do
                echo "$replaced_file" >> "$temp_file_list"
            done
            
            # 使用 rsync --checksum 智能比对，只上传有差异的文件
            echo -e "  ${YELLOW}[→]${NC} 智能比对中..."
            
            if [ -n "$LOG_FILE" ]; then
                echo "  首次克隆，智能比对同步" >> "$LOG_FILE"
            fi
            
            # 构建 rsync 命令（使用 --checksum 比对，--files-from 指定文件列表）
            RSYNC_CMD="rsync -azc --files-from=\"$temp_file_list\" $RSYNC_SSH_OPTS \"$LOCAL_DIR/\" \"$SERVER_HOST:$TARGET_DIR/\""
            SYNC_FILES_LIST="$temp_file_list"
            
        elif [ ${#files_to_upload[@]} -eq 0 ] && [ -z "$deleted_files" ]; then
            # 无变更
            echo -e "  ${YELLOW}[!]${NC} 无变更，跳过同步"
            if [ -n "$LOG_FILE" ]; then
                echo "  跳过同步: 无变更" >> "$LOG_FILE"
            fi
            continue
            
        else
            # 有变更：智能同步
            echo -e "  ${CYAN}[i]${NC} 检测到变更，准备同步..."
            
            # 切换到正确的分支
            cd "$LOCAL_DIR" || {
                log_error "无法切换到本地目录: $LOCAL_DIR"
                continue
            }
            
            if [ "$VERBOSE" = true ]; then
                git checkout "$SERVER_BRANCH" 2>&1 || true
            else
                git checkout "$SERVER_BRANCH" >/dev/null 2>&1 || true
            fi
            
            # 创建文件列表
            local temp_file_list=$(mktemp)
            for file in "${files_to_upload[@]}"; do
                echo "$file" >> "$temp_file_list"
            done
            
            #智能比对：只上传真正有变化的文件
            if [ ${#files_to_upload[@]} -gt 0 ]; then
                echo -e "  ${YELLOW}[→]${NC} 智能比对 ${CYAN}${#files_to_upload[@]}${NC} 个文件..."
                
                if [ -n "$LOG_FILE" ]; then
                    echo "  待检查文件:" >> "$LOG_FILE"
                    for file in "${files_to_upload[@]}"; do
                        echo "    - $file" >> "$LOG_FILE"
                    done
                fi
                
                # 使用 rsync --checksum 比对
                RSYNC_CMD="rsync -azc --files-from=\"$temp_file_list\" $RSYNC_SSH_OPTS \"$LOCAL_DIR/\" \"$SERVER_HOST:$TARGET_DIR/\""
                SYNC_FILES_LIST="$temp_file_list"
            fi
            
            # 处理删除的文件
            if [ -n "$deleted_files" ]; then
                DELETED_FILES_LIST=()
                for file in $deleted_files; do
                    [ -n "$file" ] && DELETED_FILES_LIST+=("$file")
                done
                echo -e "  ${RED}[!]${NC} 需要删除 ${CYAN}${#DELETED_FILES_LIST[@]}${NC} 个文件"
                
                if [ -n "$LOG_FILE" ]; then
                    echo "  需要删除的文件:" >> "$LOG_FILE"
                    for file in "${DELETED_FILES_LIST[@]}"; do
                        echo "    - $file" >> "$LOG_FILE"
                    done
                fi
            fi
        fi

        # 4. 执行同步
        if [ -n "$RSYNC_CMD" ]; then
            if [ "$VERBOSE" = true ]; then
                echo -e "${CYAN}执行命令:${NC} $RSYNC_CMD"
                eval $RSYNC_CMD
                RSYNC_EXIT_CODE=$?
            else
            # 精简模式：实时滚动显示文件，完成后清除
            # 创建临时文件
            local temp_rsync_output=$(mktemp)
            
            # 添加 -v 参数以获取详细输出
            local rsync_cmd_verbose=$(echo "$RSYNC_CMD" | sed 's/rsync /rsync -v /')
            
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
        else
            RSYNC_EXIT_CODE=0
        fi
        
        # 5. 处理删除操作（如果有）
        if [ $RSYNC_EXIT_CODE -eq 0 ] && [ -n "$DELETED_FILES_LIST" ] && [ ${#DELETED_FILES_LIST[@]} -gt 0 ]; then
            echo -e "  ${RED}[→]${NC} 删除服务器上的文件..."
            
            local delete_success_count=0
            local delete_fail_count=0
            
            for file in "${DELETED_FILES_LIST[@]}"; do
                # 检查文件是否在 exclude 列表中
                local should_skip=false
                for exclude_pattern in $EXCLUDE_OPTS; do
                    local pattern=$(echo "$exclude_pattern" | sed 's/--exclude=//')
                    if [[ "$file" == $pattern* ]]; then
                        should_skip=true
                        break
                    fi
                done
                
                if [ "$should_skip" = true ]; then
                    echo -e "    ${YELLOW}[-]${NC} 跳过 (在排除列表中): $file"
                    if [ -n "$LOG_FILE" ]; then
                        echo "    跳过删除 (excluded): $file" >> "$LOG_FILE"
                    fi
                    continue
                fi
                
                # 删除文件
                if [ "$AUTH_TYPE" = "ssh" ]; then
                    ssh -i "$AUTH_INFO" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SERVER_HOST" "rm -f \"$TARGET_DIR/$file\"" 2>/dev/null
                elif [ "$AUTH_TYPE" = "password" ]; then
                    sshpass -p "$AUTH_INFO" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SERVER_HOST" "rm -f \"$TARGET_DIR/$file\"" 2>/dev/null
                fi
                
                if [ $? -eq 0 ]; then
                    echo -e "    ${RED}[✗]${NC} $file"
                    delete_success_count=$((delete_success_count + 1))
                else
                    echo -e "    ${YELLOW}[!]${NC} 删除失败: $file"
                    delete_fail_count=$((delete_fail_count + 1))
                fi
            done
            
            if [ $delete_success_count -gt 0 ]; then
                echo -e "  ${GREEN}[✓]${NC} 已删除 ${CYAN}${delete_success_count}${NC} 个文件"
            fi
            if [ $delete_fail_count -gt 0 ]; then
                echo -e "  ${YELLOW}[!]${NC} ${delete_fail_count} 个文件删除失败"
            fi
        fi
        
        # 清理临时文件
        if [ -n "$TEMP_RSYNC_PASS_FILE" ] && [ -f "$TEMP_RSYNC_PASS_FILE" ]; then
            rm -f "$TEMP_RSYNC_PASS_FILE"
        fi
        if [ -n "$SYNC_FILES_LIST" ] && [ -f "$SYNC_FILES_LIST" ]; then
            rm -f "$SYNC_FILES_LIST"
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
        COMMAND_SOURCE=""  # 记录命令来源

        # 服务器级别命令
        while IFS= read -r line; do
            [ -n "$line" ] && COMMAND_LIST+=("$line")
        done < <(yq e ".server_groups[$GROUP_INDEX].servers[$server_index].post_sync_commands[]?" "$CONFIG_FILE" 2>/dev/null)
        
        if [ ${#COMMAND_LIST[@]} -gt 0 ]; then
            COMMAND_SOURCE="服务器级别"
        fi

        # 如果服务器级别没有配置，再尝试服务器组级别
        if [ ${#COMMAND_LIST[@]} -eq 0 ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && COMMAND_LIST+=("$line")
            done < <(yq e ".server_groups[$GROUP_INDEX].post_sync_commands[]?" "$CONFIG_FILE" 2>/dev/null)
            
            if [ ${#COMMAND_LIST[@]} -gt 0 ]; then
                COMMAND_SOURCE="服务器组级别"
            fi
        fi

        # 如果服务器组级别也没有，再使用全局默认命令
        if [ ${#COMMAND_LIST[@]} -eq 0 ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && COMMAND_LIST+=("$line")
            done < <(yq e ".default_post_sync_commands[]?" "$CONFIG_FILE" 2>/dev/null)
            
            if [ ${#COMMAND_LIST[@]} -gt 0 ]; then
                COMMAND_SOURCE="全局默认"
            fi
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
    echo -e "${CYAN}━━━━━━ 同步后命令 (${#COMMAND_LIST[@]} 条) [${YELLOW}${COMMAND_SOURCE}${CYAN}] ━━━━━━${NC}"
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
                    ssh -i "$AUTH_INFO" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "$SERVER_HOST" "$processed_command"
                    local cmd_exit_code=$?
                elif [ "$AUTH_TYPE" = "password" ]; then
                    local temp_cmd_pass_file=$(mktemp)
                    echo "$AUTH_INFO" > "$temp_cmd_pass_file"
                    chmod 600 "$temp_cmd_pass_file"
                    sshpass -f "$temp_cmd_pass_file" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "$SERVER_HOST" "$processed_command"
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
                    ssh -i "$AUTH_INFO" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SERVER_HOST" "$processed_command" > "$temp_cmd_output" 2>&1 &
                    local cmd_pid=$!
                elif [ "$AUTH_TYPE" = "password" ]; then
                    local temp_cmd_pass_file=$(mktemp)
                    echo "$AUTH_INFO" > "$temp_cmd_pass_file"
                    chmod 600 "$temp_cmd_pass_file"
                    sshpass -f "$temp_cmd_pass_file" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SERVER_HOST" "$processed_command" > "$temp_cmd_output" 2>&1 &
                    local cmd_pid=$!
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
                
                # 命令完成后清理密码文件（避免竞态条件）
                if [ "$AUTH_TYPE" = "password" ] && [ -n "$temp_cmd_pass_file" ] && [ -f "$temp_cmd_pass_file" ]; then
                    rm -f "$temp_cmd_pass_file"
                fi
                
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
