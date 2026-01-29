#!/bin/zsh

# SMB 文本文件修改测试

# 加载配置和函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib.sh"

test_modify() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        error "文件不存在: $file"
        return 1
    fi
    
    echo ""
    info "测试: $(basename "$file")"
    
    # 挂载 SMB
    if ! mount_smb; then
        return 1
    fi
    
    local remote_file="$mount_point/$(basename "$file")"
    
    # 上传文件到 SMB
    info "上传文件到 SMB"
    if ! upload_file "$file" "$mount_point"; then
        error "上传失败"
        umount_smb "$mount_point"
        return 1
    fi
    
    local original_md5=$(calculate_md5 "$remote_file")
    echo "  上传后 MD5: $original_md5"
    
    # 在 SMB 上直接修改文件
    info "在 SMB 上修改文件"
    echo "" >> "$remote_file"
    echo "# 修改时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$remote_file"
    
    if [[ $? -ne 0 ]]; then
        error "修改 SMB 文件失败"
        umount_smb "$mount_point"
        return 1
    fi
    
    local modified_md5=$(calculate_md5 "$remote_file")
    echo "  修改后 MD5: $modified_md5"
    
    # 从 SMB 下载到本地验证
    info "下载修改后的文件验证"
    local temp_file=$(mktemp)
    cp "$remote_file" "$temp_file" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        error "下载文件失败"
        rm -f "$temp_file"
        umount_smb "$mount_point"
        return 1
    fi
    
    # 验证文件完整性
    info "验证文件完整性"
    if ! verify_file_integrity "$temp_file"; then
        error "文件损坏或无法读取"
        rm -f "$temp_file"
        umount_smb "$mount_point"
        return 1
    fi
    echo "  文件类型: $(file -b "$temp_file")"
    
    # 验证 MD5 一致性
    local downloaded_md5=$(calculate_md5 "$temp_file")
    echo "  下载后 MD5: $downloaded_md5"
    
    rm -f "$temp_file"
    umount_smb "$mount_point"
    
    if [[ "$downloaded_md5" == "$modified_md5" ]] && [[ "$modified_md5" != "$original_md5" ]]; then
        success "$(basename "$file") - 修改测试通过，文件完好"
        return 0
    else
        error "$(basename "$file") - 文件验证失败"
        return 1
    fi
}

# 主程序
echo "SMB 文本文件修改测试"
echo "服务器: //$SMB_USER@$SMB_HOST/$SMB_SHARE"
echo "文件数: ${#MODIFY_FILES[@]}"

success_count=0
fail_count=0

for file in "${MODIFY_FILES[@]}"; do
    if test_modify "$file"; then
        ((success_count++))
    else
        ((fail_count++))
    fi
done

echo ""
echo "================================"
echo "完成: $success_count 成功, $fail_count 失败"
echo "================================"

[[ $fail_count -eq 0 ]] && exit 0 || exit 1
