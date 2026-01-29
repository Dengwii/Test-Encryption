#!/bin/zsh

# SMB 测试通用函数库

# 处理路径列表（支持单文件、多文件、目录）
# 目录会保留原有结构整体上传
# 参数: 路径数组
# 输出: 路径列表，每行一个
expand_paths() {
    local paths=("$@")
    for path in "${paths[@]}"; do
        [[ -z "$path" || "$path" == \#* ]] && continue
        [[ -e "$path" ]] && echo "$path"
    done
}

# 挂载 SMB 共享
# 参数: 无（使用全局配置）
# 返回: mount_point 变量
mount_smb() {
    # 先清理到同一 SMB 服务器的残留挂载
    local existing_mount
    existing_mount=$(mount | grep "$SMB_HOST" | grep "$SMB_SHARE" | awk '{print $3}' | head -1)
    if [[ -n "$existing_mount" ]]; then
        info "发现已有挂载: $existing_mount，直接使用"
        mount_point="$existing_mount"
        return 0
    fi
    
    mount_point=$(mktemp -d)
    local err_msg
    err_msg=$(mount_smbfs "//$SMB_USER:$SMB_PASSWORD@$SMB_HOST/$SMB_SHARE" "$mount_point" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        error "挂载 SMB 失败: $err_msg"
        rmdir "$mount_point" 2>/dev/null
        return 1
    fi
    
    return 0
}

# 卸载 SMB 共享
# 参数: $1 - 挂载点路径
umount_smb() {
    local mount_point="$1"
    umount "$mount_point" 2>/dev/null
    rmdir "$mount_point" 2>/dev/null
}

# 计算文件 MD5
# 参数: $1 - 文件路径
# 输出: MD5 值
calculate_md5() {
    local file="$1"
    md5 -q "$file" 2>&1
}

# ============================================================
# 通用上传入口函数
# 根据 UPLOAD_METHOD 配置调用对应的底层实现
# ============================================================

# 单文件上传（通用入口）
# 参数: $1 - 本地文件路径
#       $2 - 挂载点路径
upload_file() {
    local method="${UPLOAD_METHOD:-applescript}"
    "_upload_single_${method}" "$@"
}

# 批量上传（通用入口）
# 参数: $1 - 挂载点路径
#       $2... - 文件路径列表
upload_files_batch() {
    local method="${UPLOAD_METHOD:-applescript}"
    "_upload_batch_${method}" "$@"
}

# ============================================================
# 方式 1: AppleScript (默认，无需权限)
# 使用 Finder 的 duplicate 命令，自动覆盖已存在的文件
# ============================================================

_upload_single_applescript() {
    local source="$1"
    local mount_point="$2"
    
    [[ ! -e "$source" ]] && { error "文件不存在: $source"; return 1; }
    
    local result=$(osascript 2>&1 <<EOF
tell application "Finder"
    try
        duplicate (POSIX file "$source" as alias) to (POSIX file "$mount_point" as alias) with replacing
        return "SUCCESS"
    on error errMsg
        return "ERROR: " & errMsg
    end try
end tell
EOF
)
    [[ "$result" == "SUCCESS" ]] && return 0
    error "AppleScript 上传失败: $result"
    return 1
}

_upload_batch_applescript() {
    local mount_point="$1"
    shift
    local files=("$@")
    
    [[ ${#files[@]} -eq 0 ]] && { error "没有指定文件"; return 1; }
    
    # 构建文件列表
    local file_list=""
    for f in "${files[@]}"; do
        [[ ! -e "$f" ]] && { error "文件不存在: $f"; return 1; }
        file_list+="POSIX file \"$f\" as alias, "
    done
    file_list="${file_list%, }"
    
    local result=$(osascript 2>&1 <<EOF
tell application "Finder"
    try
        set sourceFiles to {$file_list}
        set targetFolder to POSIX file "$mount_point" as alias
        duplicate sourceFiles to targetFolder with replacing
        return "SUCCESS"
    on error errMsg
        return "ERROR: " & errMsg
    end try
end tell
EOF
)
    [[ "$result" == "SUCCESS" ]] && return 0
    error "AppleScript 批量上传失败: $result"
    return 1
}

# ============================================================
# 方式 2: GUI (System Events，需要辅助功能权限)
# 模拟 Cmd+C/V，会触发系统冲突对话框
# ============================================================

_upload_single_gui() {
    local source="$1"
    local mount_point="$2"
    
    [[ ! -e "$source" ]] && { error "文件不存在: $source"; return 1; }
    
    local result=$(osascript 2>&1 <<EOF
tell application "Finder"
    activate
    set sourceFile to POSIX file "$source" as alias
    set targetFolder to POSIX file "$mount_point" as alias
    reveal sourceFile
    delay 0.5
    select sourceFile
    delay 0.3
end tell
tell application "System Events"
    keystroke "c" using command down
    delay 0.5
end tell
tell application "Finder"
    activate
    set target of front window to targetFolder
    delay 0.5
end tell
tell application "System Events"
    keystroke "v" using command down
    delay 0.5
end tell
return "SUCCESS"
EOF
)
    [[ "$result" == "SUCCESS" ]] && return 0
    error "GUI 上传失败: $result"
    return 1
}

_upload_batch_gui() {
    local mount_point="$1"
    shift
    local files=("$@")
    
    [[ ${#files[@]} -eq 0 ]] && { error "没有指定文件"; return 1; }
    
    # 获取第一个文件的父目录
    local first_dir="${files[1]:h}"
    
    local file_list=""
    for f in "${files[@]}"; do
        [[ ! -e "$f" ]] && { error "文件不存在: $f"; return 1; }
        file_list+="POSIX file \"$f\" as alias, "
    done
    file_list="${file_list%, }"
    
    local result=$(osascript 2>&1 <<EOF
tell application "Finder"
    activate
    set targetFolder to POSIX file "$mount_point" as alias
    set sourceFiles to {$file_list}
    
    -- 先打开源文件所在目录（而不是 reveal 单个文件）
    open folder (POSIX file "$first_dir" as alias)
    delay 0.5
    
    -- 选中所有源文件
    select sourceFiles
    delay 0.5
end tell

tell application "System Events"
    keystroke "c" using command down
    delay 0.5
end tell

tell application "Finder"
    activate
    -- 打开目标文件夹
    open targetFolder
    delay 0.5
end tell

tell application "System Events"
    keystroke "v" using command down
    delay 1
end tell

return "SUCCESS"
EOF
)
    [[ "$result" == "SUCCESS" ]] && return 0
    error "GUI 批量上传失败: $result"
    return 1
}

# ============================================================
# 方式 3: PyAutoGUI (需要安装 pip3 install pyautogui pillow)
# ============================================================

_upload_single_pyautogui() {
    local source="$1"
    local mount_point="$2"
    
    [[ ! -e "$source" ]] && { error "文件不存在: $source"; return 1; }
    command -v python3 &>/dev/null || { error "未找到 python3"; return 1; }
    
    python3 - "$source" "$mount_point" <<'PYTHON_SCRIPT'
import sys, subprocess
source, mount_point = sys.argv[1], sys.argv[2]
try:
    import pyautogui
except ImportError:
    print("ERROR: pip3 install pyautogui pillow")
    sys.exit(1)
result = subprocess.run(['osascript', '-e', f'''
    tell application "Finder"
        duplicate (POSIX file "{source}" as alias) to (POSIX file "{mount_point}" as alias) with replacing
    end tell
'''], capture_output=True, text=True)
print("SUCCESS" if result.returncode == 0 else f"ERROR: {result.stderr}")
sys.exit(result.returncode)
PYTHON_SCRIPT
}

_upload_batch_pyautogui() {
    local mount_point="$1"
    shift
    for f in "$@"; do
        _upload_single_pyautogui "$f" "$mount_point" || return 1
    done
}

# ============================================================
# 方式 4: Quartz (需要安装 pip3 install pyobjc-framework-Quartz)
# ============================================================

_upload_single_quartz() {
    local source="$1"
    local mount_point="$2"
    
    [[ ! -e "$source" ]] && { error "文件不存在: $source"; return 1; }
    command -v python3 &>/dev/null || { error "未找到 python3"; return 1; }
    
    python3 - "$source" "$mount_point" <<'PYTHON_SCRIPT'
import sys, subprocess
source, mount_point = sys.argv[1], sys.argv[2]
try:
    from Quartz import CGEventCreateMouseEvent
except ImportError:
    print("ERROR: pip3 install pyobjc-core pyobjc-framework-Quartz")
    sys.exit(1)
result = subprocess.run(['osascript', '-e', f'''
    tell application "Finder"
        duplicate (POSIX file "{source}" as alias) to (POSIX file "{mount_point}" as alias) with replacing
    end tell
'''], capture_output=True, text=True)
print("SUCCESS" if result.returncode == 0 else f"ERROR: {result.stderr}")
sys.exit(result.returncode)
PYTHON_SCRIPT
}

_upload_batch_quartz() {
    local mount_point="$1"
    shift
    for f in "$@"; do
        _upload_single_quartz "$f" "$mount_point" || return 1
    done
}

# 兼容旧函数名
upload_file_applescript() { _upload_single_applescript "$@"; }
upload_file_gui() { _upload_single_gui "$@"; }
upload_files_batch_gui() { _upload_batch_gui "$@"; }

# 验证上传文件的 MD5
# 参数: $1 - 本地文件路径
#       $2 - 挂载点路径
# 返回: 0 成功，1 失败
verify_upload() {
    local item="$1"
    local mount_point="$2"
    local itemname=$(basename "$item")
    
    if [[ -f "$item" ]]; then
        # 文件：直接比较 MD5
        local local_md5=$(calculate_md5 "$item")
        if [[ $? -ne 0 ]]; then
            error "无法读取文件 (可能需要授权终端访问该文件夹)"
            return 1
        fi
        
        local remote_md5=$(calculate_md5 "$mount_point/$itemname")
        if [[ $? -ne 0 ]]; then
            error "无法读取远程文件"
            return 1
        fi
        
        if [[ "$local_md5" == "$remote_md5" ]]; then
            return 0
        else
            error "MD5 不一致"
            echo "  本地: $local_md5"
            echo "  远程: $remote_md5"
            return 1
        fi
    elif [[ -d "$item" ]]; then
        # 目录：递归验证每个文件
        local fail_count=0
        local total_count=0
        
        echo "  ────────────────────────────────────"
        for f in "$item"/**/*(.N); do
            ((total_count++))
            local rel_path="${f#$item/}"
            local remote_file="$mount_point/$itemname/$rel_path"
            
            if [[ ! -f "$remote_file" ]]; then
                error "  ✗ $rel_path"
                echo "    远程文件不存在"
                ((fail_count++))
                continue
            fi
            
            local local_md5=$(calculate_md5 "$f")
            local remote_md5=$(calculate_md5 "$remote_file")
            
            echo "  • $rel_path"
            echo "    本地: $local_md5"
            echo "    远程: $remote_md5"
            
            if [[ "$local_md5" == "$remote_md5" ]]; then
                echo "    ${GREEN}✓ 匹配${NC}"
            else
                echo "    ${RED}✗ 不匹配${NC}"
                ((fail_count++))
            fi
        done
        echo "  ────────────────────────────────────"
        
        info "目录验证: $total_count 个文件, $fail_count 个失败"
        [[ $fail_count -eq 0 ]]
    else
        error "路径不存在: $item"
        return 1
    fi
}

# 验证文件完整性
# 参数: $1 - 文件路径
# 返回: 0 完好，1 损坏
verify_file_integrity() {
    local file="$1"
    
    # 检查文件是否存在且可读
    if [[ ! -r "$file" ]]; then
        return 1
    fi
    
    # 方法1: 使用 file 命令检测文件类型（最通用）
    local file_type=$(file -b "$file" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$file_type" ]]; then
        return 1
    fi
    
    # 方法2: 尝试读取文件的一部分
    head -c 1024 "$file" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # 根据文件类型进行特定验证
    case "$file_type" in
        *Zip*|*zip*)
            # ZIP 文件：测试压缩包完整性
            unzip -t "$file" > /dev/null 2>&1
            return $?
            ;;
        *PDF*)
            # PDF 文件：检查 PDF 头
            head -c 5 "$file" 2>/dev/null | grep -q "^%PDF"
            return $?
            ;;
        *text*|*ASCII*|*UTF-8*)
            # 文本文件：尝试读取
            cat "$file" > /dev/null 2>&1
            return $?
            ;;
        *image*|*JPEG*|*PNG*|*GIF*)
            # 图片文件：使用 sips（Mac 自带）
            sips -g format "$file" > /dev/null 2>&1
            return $?
            ;;
        *)
            # 其他文件：基本读取测试已通过
            return 0
            ;;
    esac
}

