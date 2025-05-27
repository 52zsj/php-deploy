#!/bin/bash

# 设置严格模式
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 保存脚本文件所在目录
SCRIPT_DIR=$(cd $(dirname "$0") && pwd)

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
    echo -e "${YELLOW}检查依赖...${NC}"
    
    command -v git >/dev/null 2>&1 || { echo -e "${RED}错误：git 未安装${NC}"; exit 1; }
    command -v rsync >/dev/null 2>&1 || { echo -e "${RED}错误：rsync 未安装${NC}"; exit 1; }
    command -v yq >/dev/null 2>&1 || { echo -e "${RED}警告：yq 未安装，将尝试使用Python处理YAML文件${NC}"; }
    command -v sshpass >/dev/null 2>&1 || { echo -e "${YELLOW}警告：sshpass 未安装，将无法使用密码认证进行SSH连接${NC}"; }
    
    if ! command -v yq >/dev/null 2>&1; then
        command -v python3 >/dev/null 2>&1 || { echo -e "${RED}错误：既没有安装yq也没有安装python3，无法解析YAML文件${NC}"; exit 1; }
        python3 -c "import yaml" 2>/dev/null || { echo -e "${RED}错误：python3 的 PyYAML 包未安装，请执行 'pip3 install pyyaml'${NC}"; exit 1; }
    fi
    
    echo -e "${GREEN}所有依赖检查通过${NC}"
}

# 列出并选择配置文件
select_config_file() {
    echo -e "${YELLOW}查找可用的配置文件...${NC}"
    
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
        echo -e "${RED}错误：未找到任何.yml配置文件${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}找到以下配置文件:${NC}"
    
    # 显示找到的配置文件列表
    for i in "${!CONFIG_FILES[@]}"; do
        echo -e "  ${BLUE}[$((i+1))]${NC} ${CONFIG_FILES[$i]}"
    done
    
    # 请求用户选择
    read -p "请输入要使用的配置文件编号 (1-${#CONFIG_FILES[@]}): " choice
    
    # 验证用户输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#CONFIG_FILES[@]} ]; then
        echo -e "${RED}错误：无效的选择${NC}"
        exit 1
    fi
    
    # 设置选择的配置文件
    CONFIG_FILE="${CONFIG_FILES[$((choice-1))]}"
    # 使用绝对路径
    CONFIG_FILE="$SCRIPT_DIR/$CONFIG_FILE"
    echo -e "${GREEN}已选择配置文件: $CONFIG_FILE${NC}"
}

# 解析YAML配置文件
parse_config() {
    echo -e "${YELLOW}解析配置文件...${NC}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误：配置文件 $CONFIG_FILE 不存在${NC}"
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
        echo -e "${RED}错误：Gitee认证类型必须为'ssh'或'password'${NC}"
        exit 1
    fi
    
    # 如果是SSH认证，检查SSH密钥
    if [ "$GIT_AUTH_TYPE" = "ssh" ] && [ -z "$GIT_SSH_KEY" ]; then
        echo -e "${RED}错误：使用SSH认证时，必须设置SSH密钥路径${NC}"
        exit 1
    fi
    
    # 如果是密码认证，检查用户名和密码
    if [ "$GIT_AUTH_TYPE" = "password" ] && { [ -z "$GIT_USERNAME" ] || [ -z "$GIT_PASSWORD" ]; }; then
        echo -e "${RED}错误：使用密码认证时，必须设置用户名和密码${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}配置解析完成${NC}"
}

# 选择服务器组
select_server_group() {
    echo -e "${YELLOW}选择要部署的服务器组:${NC}"
    
    # 显示服务器组列表
    if command -v yq >/dev/null 2>&1; then
        for ((i=0; i<$GROUP_COUNT; i++)); do
            GROUP_NAME=$(yq e ".server_groups[$i].name" "$CONFIG_FILE")
            SERVER_COUNT=$(yq e ".server_groups[$i].servers | length" "$CONFIG_FILE")
            echo -e "  ${BLUE}[$((i+1))]${NC} $GROUP_NAME ($SERVER_COUNT 台服务器)"
        done
    else
        echo "$CONFIG_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for i, group in enumerate(data['server_groups']):
    print(f\"  \033[0;34m[{i+1}]\033[0m {group['name']} ({len(group['servers'])} 台服务器)\")
"
    fi
    
    # 请求用户选择
    read -p "请输入要部署的服务器组编号 (1-$GROUP_COUNT): " group_choice
    
    # 验证用户输入
    if ! [[ "$group_choice" =~ ^[0-9]+$ ]] || [ "$group_choice" -lt 1 ] || [ "$group_choice" -gt $GROUP_COUNT ]; then
        echo -e "${RED}错误：无效的选择${NC}"
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
    
    echo -e "${GREEN}已选择服务器组: $SELECTED_GROUP_NAME${NC}"
}

# 设置git凭据
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
            
            echo -e "${GREEN}已配置Git认证信息${NC}"
        else
            echo -e "${RED}错误：使用密码认证时，仓库URL必须是HTTPS格式${NC}"
            exit 1
        fi
        
        # 配置git使用特定于配置文件的凭据存储
        git config --local credential.helper "store --file=$GIT_CREDENTIALS_FILE"
        echo -e "${GREEN}Git凭据将存储在: $GIT_CREDENTIALS_FILE${NC}"
    elif [ "$GIT_AUTH_TYPE" = "ssh" ]; then
        # 确保SSH密钥存在
        if [ ! -f "$GIT_SSH_KEY" ]; then
            echo -e "${RED}错误：SSH密钥 $GIT_SSH_KEY 不存在${NC}"
            echo -e "${YELLOW}请检查配置文件中的SSH密钥路径是否正确${NC}"
            echo -e "${YELLOW}当前用户主目录: $HOME${NC}"
            exit 1
        fi
        
        # 配置git使用特定的SSH密钥
        export GIT_SSH_COMMAND="ssh -i $GIT_SSH_KEY -o StrictHostKeyChecking=no"
    fi
}

# 拉取所有需要的分支
pull_code() {
    echo -e "${YELLOW}拉取代码...${NC}"
    
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
    
    # 检查是否已经是Git仓库
    if [ -d ".git" ]; then
        # 确保使用正确的凭据配置
        if [ "$GIT_AUTH_TYPE" = "password" ]; then
            git config credential.helper "store --file=$GIT_CREDENTIALS_FILE"
        fi
        
        git fetch origin
        
        # 检出并更新每个需要的分支
        for branch in "${REQUIRED_BRANCHES[@]}"; do
            echo -e "${YELLOW}更新分支: $branch${NC}"
            git checkout "$branch" || git checkout -b "$branch" "origin/$branch"
            git pull origin "$branch"
        done
        
        echo -e "${GREEN}代码更新完成${NC}"
    else
        # 克隆默认分支
        git clone --branch "$DEFAULT_BRANCH" "$REPO_URL" .
        
        # 确保使用正确的凭据配置
        if [ "$GIT_AUTH_TYPE" = "password" ]; then
            git config credential.helper "store --file=$GIT_CREDENTIALS_FILE"
        fi
        
        # 获取其他需要的分支
        for branch in "${REQUIRED_BRANCHES[@]}"; do
            if [ "$branch" != "$DEFAULT_BRANCH" ]; then
                echo -e "${YELLOW}获取分支: $branch${NC}"
                git checkout -b "$branch" "origin/$branch"
            fi
        done
        
        echo -e "${GREEN}代码克隆完成${NC}"
    fi
}

# 替换环境配置文件
replace_configs() {
    echo -e "${YELLOW}替换环境配置文件...${NC}"
    
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
        echo -e "${YELLOW}未配置替换目录或环境标识，跳过配置替换${NC}"
        return
    fi
    
    # 展开替换目录路径
    REPLACE_BASE_DIR=$(expand_path "$REPLACE_BASE_DIR")
    REPLACE_DIR="$REPLACE_BASE_DIR/$ENV_ID"
    
    echo -e "${YELLOW}使用环境: $ENV_ID${NC}"
    echo -e "${YELLOW}替换目录: $REPLACE_DIR${NC}"
    
    # 检查替换目录是否存在
    if [ ! -d "$REPLACE_DIR" ]; then
        echo -e "${YELLOW}替换目录 $REPLACE_DIR 不存在，跳过配置替换${NC}"
        return
    fi
    
    # 切换到正确的分支
    cd "$LOCAL_DIR"
    
    # 获取当前分支
    CURRENT_BRANCH=$(git branch --show-current)
    echo -e "${YELLOW}当前分支: $CURRENT_BRANCH${NC}"
    
    # 递归替换文件
    echo -e "${YELLOW}开始替换配置文件...${NC}"
    
    # 使用find命令查找替换目录中的所有文件
    find "$REPLACE_DIR" -type f -print | while read replace_file; do
        # 计算相对路径
        rel_path="${replace_file#$REPLACE_DIR/}"
        target_file="$LOCAL_DIR/$rel_path"
        target_dir=$(dirname "$target_file")
        
        # 确保目标目录存在
        if [ ! -d "$target_dir" ]; then
            mkdir -p "$target_dir"
        fi
        
        # 替换文件
        cp -f "$replace_file" "$target_file"
        echo -e "${GREEN}替换文件: $rel_path${NC}"
    done
    
    echo -e "${GREEN}配置文件替换完成${NC}"
}

# 同步到服务器
sync_to_servers() {
    echo -e "${YELLOW}开始同步到服务器...${NC}"
    
    # 检查是否存在代理环境变量
    HAS_PROXY=0
    if env | grep -i proxy > /dev/null; then
        echo -e "${YELLOW}检测到代理环境变量:${NC}"
        env | grep -i proxy
        HAS_PROXY=1
        
        # 询问是否为SSH连接临时禁用代理
        read -p "是否为SSH连接临时禁用代理? (y/n): " disable_proxy_choice
        if [ "$disable_proxy_choice" = "y" ] || [ "$disable_proxy_choice" = "Y" ]; then
            echo -e "${YELLOW}临时禁用所有代理环境变量...${NC}"
            # 备份当前代理设置
            export BACKUP_HTTP_PROXY=$http_proxy
            export BACKUP_HTTPS_PROXY=$https_proxy
            export BACKUP_ALL_PROXY=$all_proxy
            export BACKUP_NO_PROXY=$no_proxy
            
            # 清除所有代理变量
            unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
            echo -e "${GREEN}已临时禁用代理${NC}"
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
        
        echo -e "${YELLOW}同步到服务器: $SERVER_NAME ($SERVER_HOST)${NC}"
        echo -e "${YELLOW}使用分支: $SERVER_BRANCH${NC}"
        
        # 切换到正确的分支
        cd "$LOCAL_DIR"
        git checkout "$SERVER_BRANCH"
        
        # 提取主机名（不包含用户名）用于连接测试
        SERVER_HOSTNAME=$(echo "$SERVER_HOST" | cut -d '@' -f 2)
        if [ -z "$SERVER_HOSTNAME" ]; then
            SERVER_HOSTNAME="$SERVER_HOST"  # 如果没有@符号，则使用整个主机字符串
        fi
        
        # 测试与服务器的连接
        echo -e "${YELLOW}测试与服务器 $SERVER_HOSTNAME 的连接...${NC}"
        
        # 跳过ping测试，直接测试SSH连接
        echo -e "${YELLOW}注意: 跳过ping测试，直接测试SSH连接${NC}"
        
        # 根据认证类型构建rsync命令
        RSYNC_SSH_OPTS=""
        if [ "$AUTH_TYPE" = "ssh" ]; then
            if [ ! -f "$AUTH_INFO" ]; then
                echo -e "${RED}错误：SSH密钥 $AUTH_INFO 不存在${NC}"
                echo -e "${YELLOW}请检查配置文件中的SSH密钥路径是否正确${NC}"
                echo -e "${YELLOW}当前用户主目录: $HOME${NC}"
                exit 1
            fi
            
            # 测试SSH连接
            echo -e "${YELLOW}测试SSH连接...${NC}"
            ssh -i "$AUTH_INFO" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$SERVER_HOST" "echo 连接成功" 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误：SSH连接测试失败${NC}"
                echo -e "${YELLOW}请确认以下信息:${NC}"
                echo -e "1. ${YELLOW}服务器 $SERVER_HOSTNAME 是否可达${NC}"
                echo -e "2. ${YELLOW}SSH密钥 $AUTH_INFO 是否有效${NC}"
                echo -e "3. ${YELLOW}SSH密钥权限是否正确 (应为600)${NC}"
                echo -e "4. ${YELLOW}服务器SSH配置是否允许密钥认证${NC}"
                echo -e "5. ${YELLOW}是否存在网络代理问题${NC}"
                
                # 设置SSH密钥权限为600
                echo -e "${YELLOW}尝试修复SSH密钥权限...${NC}"
                chmod 600 "$AUTH_INFO"
                echo -e "${GREEN}已设置SSH密钥权限为600${NC}"
                
                echo -e "${YELLOW}再次测试SSH连接...${NC}"
                ssh -i "$AUTH_INFO" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$SERVER_HOST" "echo 连接成功" 2>&1
                if [ $? -ne 0 ]; then
                    echo -e "${RED}修复权限后SSH连接仍然失败${NC}"
                    
                    # 询问是否跳过代理
                    read -p "是否尝试使用无代理模式连接? (y/n): " direct_conn_choice
                    if [ "$direct_conn_choice" = "y" ] || [ "$direct_conn_choice" = "Y" ]; then
                        echo -e "${YELLOW}尝试直接连接...${NC}"
                        # 确保所有可能的代理变量都被清除
                        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
                        
                        echo -e "${YELLOW}使用调试模式尝试SSH连接...${NC}"
                        ssh -v -i "$AUTH_INFO" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SERVER_HOST" "echo 调试模式连接成功" 2>&1
                        
                        # 询问是否跳过此服务器
                        read -p "是否仍然要尝试继续同步? (y/n): " force_sync_choice
                        if [ "$force_sync_choice" != "y" ] && [ "$force_sync_choice" != "Y" ]; then
                            read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                            if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                                echo -e "${YELLOW}跳过服务器 $SERVER_NAME${NC}"
                                continue
                            else
                                echo -e "${RED}同步中止${NC}"
                                
                                # 恢复代理设置
                                if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                                    echo -e "${YELLOW}恢复代理设置...${NC}"
                                    export http_proxy=$BACKUP_HTTP_PROXY
                                    export https_proxy=$BACKUP_HTTPS_PROXY
                                    export all_proxy=$BACKUP_ALL_PROXY
                                    export no_proxy=$BACKUP_NO_PROXY
                                    echo -e "${GREEN}代理设置已恢复${NC}"
                                fi
                                
                                exit 1
                            fi
                        else
                            echo -e "${YELLOW}强制继续同步...${NC}"
                        fi
                    else
                        # 询问是否跳过此服务器
                        read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                        if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                            echo -e "${YELLOW}跳过服务器 $SERVER_NAME${NC}"
                            continue
                        else
                            echo -e "${RED}同步中止${NC}"
                            
                            # 恢复代理设置
                            if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                                echo -e "${YELLOW}恢复代理设置...${NC}"
                                export http_proxy=$BACKUP_HTTP_PROXY
                                export https_proxy=$BACKUP_HTTPS_PROXY
                                export all_proxy=$BACKUP_ALL_PROXY
                                export no_proxy=$BACKUP_NO_PROXY
                                echo -e "${GREEN}代理设置已恢复${NC}"
                            fi
                            
                            exit 1
                        fi
                    fi
                else
                    echo -e "${GREEN}修复权限后SSH连接成功${NC}"
                fi
            else
                echo -e "${GREEN}SSH连接测试成功${NC}"
            fi
            
            # 使用无代理环境变量的SSH命令
            RSYNC_SSH_OPTS="-e \"ssh -i $AUTH_INFO -o StrictHostKeyChecking=no\""
        elif [ "$AUTH_TYPE" = "password" ]; then
            # 检查sshpass是否可用
            if ! command -v sshpass >/dev/null 2>&1; then
                echo -e "${RED}错误：服务器 $SERVER_NAME 配置为密码认证，但sshpass未安装${NC}"
                echo -e "${YELLOW}可以使用以下命令安装sshpass:${NC}"
                echo -e "  Debian/Ubuntu: ${BLUE}sudo apt-get install sshpass${NC}"
                echo -e "  CentOS/RHEL: ${BLUE}sudo yum install sshpass${NC}"
                echo -e "  macOS: ${BLUE}brew install hudochenkov/sshpass/sshpass${NC}"
                
                # 询问是否跳过此服务器
                read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                    echo -e "${YELLOW}跳过服务器 $SERVER_NAME${NC}"
                    continue
                else
                    echo -e "${RED}同步中止${NC}"
                    
                    # 恢复代理设置
                    if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                        echo -e "${YELLOW}恢复代理设置...${NC}"
                        export http_proxy=$BACKUP_HTTP_PROXY
                        export https_proxy=$BACKUP_HTTPS_PROXY
                        export all_proxy=$BACKUP_ALL_PROXY
                        export no_proxy=$BACKUP_NO_PROXY
                        echo -e "${GREEN}代理设置已恢复${NC}"
                    fi
                    
                    exit 1
                fi
            fi
            
            # 测试SSH密码连接
            echo -e "${YELLOW}测试SSH密码连接...${NC}"
            sshpass -p "$AUTH_INFO" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SERVER_HOST" "echo 连接成功" 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误：SSH密码连接测试失败${NC}"
                echo -e "${YELLOW}请确认以下信息:${NC}"
                echo -e "1. ${YELLOW}服务器 $SERVER_HOSTNAME 是否可达${NC}"
                echo -e "2. ${YELLOW}密码是否正确${NC}"
                echo -e "3. ${YELLOW}服务器SSH配置是否允许密码认证${NC}"
                echo -e "4. ${YELLOW}是否存在网络代理问题${NC}"
                
                # 询问是否跳过代理
                read -p "是否尝试使用无代理模式连接? (y/n): " direct_conn_choice
                if [ "$direct_conn_choice" = "y" ] || [ "$direct_conn_choice" = "Y" ]; then
                    echo -e "${YELLOW}尝试直接连接...${NC}"
                    # 确保所有可能的代理变量都被清除
                    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
                    
                    echo -e "${YELLOW}使用调试模式尝试SSH密码连接...${NC}"
                    sshpass -p "$AUTH_INFO" ssh -v -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SERVER_HOST" "echo 调试模式连接成功" 2>&1
                    
                    # 询问是否仍然尝试同步
                    read -p "是否仍然要尝试继续同步? (y/n): " force_sync_choice
                    if [ "$force_sync_choice" != "y" ] && [ "$force_sync_choice" != "Y" ]; then
                        read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                        if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                            echo -e "${YELLOW}跳过服务器 $SERVER_NAME${NC}"
                            continue
                        else
                            echo -e "${RED}同步中止${NC}"
                            
                            # 恢复代理设置
                            if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                                echo -e "${YELLOW}恢复代理设置...${NC}"
                                export http_proxy=$BACKUP_HTTP_PROXY
                                export https_proxy=$BACKUP_HTTPS_PROXY
                                export all_proxy=$BACKUP_ALL_PROXY
                                export no_proxy=$BACKUP_NO_PROXY
                                echo -e "${GREEN}代理设置已恢复${NC}"
                            fi
                            
                            exit 1
                        fi
                    else
                        echo -e "${YELLOW}强制继续同步...${NC}"
                    fi
                else
                    # 询问是否跳过此服务器
                    read -p "是否跳过此服务器并继续同步其他服务器? (y/n): " skip_choice
                    if [ "$skip_choice" = "y" ] || [ "$skip_choice" = "Y" ]; then
                        echo -e "${YELLOW}跳过服务器 $SERVER_NAME${NC}"
                        continue
                    else
                        echo -e "${RED}同步中止${NC}"
                        
                        # 恢复代理设置
                        if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                            echo -e "${YELLOW}恢复代理设置...${NC}"
                            export http_proxy=$BACKUP_HTTP_PROXY
                            export https_proxy=$BACKUP_HTTPS_PROXY
                            export all_proxy=$BACKUP_ALL_PROXY
                            export no_proxy=$BACKUP_NO_PROXY
                            echo -e "${GREEN}代理设置已恢复${NC}"
                        fi
                        
                        exit 1
                    fi
                fi
            else
                echo -e "${GREEN}SSH密码连接测试成功${NC}"
            fi
            
            RSYNC_SSH_OPTS="-e \"sshpass -p '$AUTH_INFO' ssh -o StrictHostKeyChecking=no\""
        else
            echo -e "${RED}错误：服务器 $SERVER_NAME 的认证类型 $AUTH_TYPE 不支持，必须为 'ssh' 或 'password'${NC}"
            exit 1
        fi
        
        # 使用eval执行rsync命令，以便正确解析引号
        echo -e "${YELLOW}开始执行rsync同步...${NC}"
        RSYNC_CMD="rsync $RSYNC_OPTIONS $RSYNC_SSH_OPTS $EXCLUDE_OPTS \"$LOCAL_DIR/\" \"$SERVER_HOST:$TARGET_DIR/\""
        echo -e "${BLUE}执行命令: $RSYNC_CMD${NC}"
        
        eval $RSYNC_CMD
        RSYNC_EXIT_CODE=$?
        
        if [ $RSYNC_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}服务器 $SERVER_NAME 同步成功${NC}"
        else
            echo -e "${RED}服务器 $SERVER_NAME 同步失败 (错误代码: $RSYNC_EXIT_CODE)${NC}"
            echo -e "${YELLOW}rsync错误代码参考:${NC}"
            echo -e "${YELLOW}1-10: 通常是文件访问或权限错误${NC}"
            echo -e "${YELLOW}11-20: 网络或连接错误${NC}"
            echo -e "${YELLOW}23-24: 其他rsync错误${NC}"
            echo -e "${YELLOW}30+: SSH或shell错误${NC}"
            
            # 询问是否继续同步其他服务器
            read -p "是否继续同步其他服务器? (y/n): " continue_choice
            if [ "$continue_choice" = "y" ] || [ "$continue_choice" = "Y" ]; then
                echo -e "${YELLOW}继续同步其他服务器...${NC}"
                continue
            else
                echo -e "${RED}同步中止${NC}"
                
                # 恢复代理设置
                if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
                    echo -e "${YELLOW}恢复代理设置...${NC}"
                    export http_proxy=$BACKUP_HTTP_PROXY
                    export https_proxy=$BACKUP_HTTPS_PROXY
                    export all_proxy=$BACKUP_ALL_PROXY
                    export no_proxy=$BACKUP_NO_PROXY
                    echo -e "${GREEN}代理设置已恢复${NC}"
                fi
                
                exit 1
            fi
        fi
    done
    
    echo -e "${GREEN}所有服务器同步完成${NC}"
    
    # 恢复代理设置
    if [ $HAS_PROXY -eq 1 ] && [ "$disable_proxy_choice" = "y" ]; then
        echo -e "${YELLOW}恢复代理设置...${NC}"
        export http_proxy=$BACKUP_HTTP_PROXY
        export https_proxy=$BACKUP_HTTPS_PROXY
        export all_proxy=$BACKUP_ALL_PROXY
        export no_proxy=$BACKUP_NO_PROXY
        echo -e "${GREEN}代理设置已恢复${NC}"
    fi
}

# 清理敏感凭据
cleanup_credentials() {
    echo -e "${YELLOW}清理敏感凭据...${NC}"
    
    # 如果用户希望删除凭据文件，可以取消下面的注释
    # 默认情况下我们保留凭据文件以便下次使用
    # if [ -f "$GIT_CREDENTIALS_FILE" ]; then
    #     rm -f "$GIT_CREDENTIALS_FILE"
    #     echo -e "${GREEN}已删除Git凭据文件${NC}"
    # fi
    
    # 清除环境变量中的敏感信息
    if [ "$GIT_AUTH_TYPE" = "password" ]; then
        GIT_PASSWORD=""
        GIT_USERNAME=""
    fi
    
    # 清除SSH命令中的敏感信息
    unset GIT_SSH_COMMAND
    
    echo -e "${GREEN}凭据清理完成${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}       Gitee代码同步工具 v1.0          ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    check_dependencies
    select_config_file
    parse_config
    select_server_group
    pull_code
    replace_configs
    sync_to_servers
    cleanup_credentials
    
    echo -e "${GREEN}任务完成！所有代码已成功同步到目标服务器${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

# 执行主函数
main 