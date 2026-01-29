#!/bin/zsh

# SMB 文件上传 MD5 校验测试（支持多轮上传和报告生成）

# 加载配置和函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib.sh"

# 初始化报告
init_report() {
    mkdir -p "$REPORT_DIR"
    REPORT_TIME=$(date +"%Y%m%d_%H%M%S")
    CSV_FILE="$REPORT_DIR/report_${REPORT_TIME}.csv"
    HTML_FILE="$REPORT_DIR/report_${REPORT_TIME}.html"

    # CSV 表头（大小包含人类可读和字节数）
    local header="文件名"
    for ((i=1; i<=UPLOAD_ROUNDS; i++)); do
        header+=",第${i}次-大小,第${i}次-MD5,第${i}次-通过"
    done
    echo "$header" > "$CSV_FILE"

    # HTML 开头
    cat > "$HTML_FILE" <<'HTML_HEAD'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SMB 上传测试报告</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .info { color: #666; margin-bottom: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f5f5f5; }
        .pass { background-color: #d4edda; color: #155724; }
        .fail { background-color: #f8d7da; color: #721c24; }
        .size { font-size: 0.9em; color: #666; }
        .md5 { font-family: monospace; font-size: 0.85em; }
    </style>
</head>
<body>
HTML_HEAD
    
    echo "<h1>SMB 上传测试报告</h1>" >> "$HTML_FILE"
    echo "<div class='info'>" >> "$HTML_FILE"
    echo "<p>测试时间: $(date '+%Y-%m-%d %H:%M:%S')</p>" >> "$HTML_FILE"
    echo "<p>SMB 服务器: //$SMB_USER@$SMB_HOST/$SMB_SHARE</p>" >> "$HTML_FILE"
    echo "<p>上传方式: $UPLOAD_METHOD | 上传轮数: $UPLOAD_ROUNDS</p>" >> "$HTML_FILE"
    echo "</div>" >> "$HTML_FILE"
    
    # 表格开始
    echo "<table>" >> "$HTML_FILE"
    echo "<tr><th>文件名</th>" >> "$HTML_FILE"
    for ((i=1; i<=UPLOAD_ROUNDS; i++)); do
        echo "<th>第${i}次上传</th>" >> "$HTML_FILE"
    done
    echo "</tr>" >> "$HTML_FILE"
}

# 获取文件大小（人类可读）
get_file_size() {
    local file="$1"
    local size=""
    if [[ -f "$file" ]]; then
        size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
    elif [[ -d "$file" ]]; then
        size=$(du -sh "$file" 2>/dev/null | awk '{print $1}')
    fi
    [[ -z "$size" ]] && size="0B"
    echo "$size"
}

# 获取文件大小（精确字节数）
get_file_size_bytes() {
    local file="$1"
    local size
    if [[ -f "$file" ]]; then
        # macOS 使用 -f%z，Linux 使用 -c%s
        size=$(stat -f%z "$file" 2>/dev/null)
        if [[ -z "$size" ]]; then
            size=$(stat -c%s "$file" 2>/dev/null)
        fi
    elif [[ -d "$file" ]]; then
        # 目录大小
        size=$(du -sk "$file" 2>/dev/null | awk '{print $1 * 1024}')
    fi
    [[ -z "$size" || "$size" == "0" ]] && size="0"
    echo "$size"
}

# 单轮上传并验证，返回结果
# 参数: $1=文件路径, $2=挂载点
# 输出: size_human|size_bytes|md5|pass/fail
upload_and_verify_single() {
    local item="$1"
    local mount_point="$2"
    local itemname=$(basename "$item")

    # 上传
    if ! upload_file "$item" "$mount_point"; then
        echo "0|0|上传失败|fail"
        return 1
    fi

    # 获取远程文件信息
    local remote_path="$mount_point/$itemname"
    local remote_size=$(get_file_size "$remote_path")
    local remote_size_bytes=$(get_file_size_bytes "$remote_path")

    if [[ -f "$item" ]]; then
        # 单文件
        local local_md5=$(calculate_md5 "$item" 2>/dev/null)
        local remote_md5=$(calculate_md5 "$remote_path" 2>/dev/null)

        # 确保 MD5 不为空
        [[ -z "$local_md5" ]] && local_md5="计算失败"
        [[ -z "$remote_md5" ]] && remote_md5="计算失败"

        if [[ "$local_md5" == "$remote_md5" ]] && [[ "$local_md5" != "计算失败" ]]; then
            echo "${remote_size}|${remote_size_bytes}|${remote_md5}|pass"
            return 0
        else
            echo "${remote_size}|${remote_size_bytes}|本地:${local_md5} 远程:${remote_md5}|fail"
            return 1
        fi
    elif [[ -d "$item" ]]; then
        # 目录：验证所有文件
        local fail_count=0
        local total_count=0
        local first_md5=""

        for f in "$item"/**/*(.N); do
            ((total_count++))
            local rel_path="${f#$item/}"
            local remote_file="$mount_point/$itemname/$rel_path"

            local local_md5=$(calculate_md5 "$f" 2>/dev/null)
            local remote_md5=$(calculate_md5 "$remote_file" 2>/dev/null)

            # 保存第一个文件的 MD5 作为代表
            [[ -z "$first_md5" && -n "$local_md5" ]] && first_md5="$local_md5"

            if [[ "$local_md5" != "$remote_md5" ]] || [[ -z "$local_md5" ]]; then
                ((fail_count++))
            fi
        done

        # MD5 显示：目录只显示第一个文件的 MD5（或状态）
        local md5_display=""
        if [[ $total_count -eq 0 ]]; then
            md5_display="空目录"
        elif [[ $fail_count -eq 0 ]]; then
            md5_display="${first_md5}"
        else
            md5_display="${fail_count}/${total_count}不匹配"
        fi

        if [[ $fail_count -eq 0 ]]; then
            echo "${remote_size}|${remote_size_bytes}|${md5_display}|pass"
            return 0
        else
            echo "${remote_size}|${remote_size_bytes}|${md5_display}|fail"
            return 1
        fi
    fi
}

# 执行多轮测试
run_multi_round_test() {
    local items=("$@")

    # 存储所有结果: results[文件名_轮次] = "size|md5|result_status"
    # 使用下划线分隔，避免键名中的特殊字符问题
    typeset -A results

    for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
        echo ""
        echo "========================================"
        echo "第 $round 轮上传 (共 $UPLOAD_ROUNDS 轮)"
        echo "========================================"

        if ! mount_smb; then
            error "挂载失败，跳过本轮"
            for item in "${items[@]}"; do
                local itemname=$(basename "$item")
                local key="${itemname}_${round}"
                results[$key]="0|挂载失败|fail"
            done
            continue
        fi

        for item in "${items[@]}"; do
            local itemname=$(basename "$item")
            local key="${itemname}_${round}"
            info "上传: $itemname"

            local result=$(upload_and_verify_single "$item" "$mount_point")
            results[$key]="$result"

            # 调试：显示结果
            info "结果: $result"

            local result_status="${result##*|}"
            if [[ "$result_status" == "pass" ]]; then
                success "$itemname - 校验通过"
            else
                error "$itemname - 校验失败"
            fi
        done

        umount_smb "$mount_point"

        # 轮次间等待
        if [[ $round -lt $UPLOAD_ROUNDS ]]; then
            info "等待 2 秒后开始下一轮..."
            sleep 2
        fi
    done

    # 生成报告
    echo ""
    info "生成测试报告..."

    for item in "${items[@]}"; do
        local itemname=$(basename "$item")
        local csv_line="$itemname"
        local html_line="<tr><td>$itemname</td>"

        for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
            local key="${itemname}_${round}"
            local result="${results[$key]}"

            # 调试：显示原始结果
            info "解析结果 [$key]: $result"

            # 解析结果: size_human|size_bytes|md5|status
            local size_human="${result%%|*}"
            local rest="${result#*|}"
            local size_bytes="${rest%%|*}"
            rest="${rest#*|}"
            md5="${rest%|*}"
            result_status="${rest##*|}"

            # 调试：显示解析后的值
            info "  解析: size=[$size_human] bytes=[$size_bytes] md5=[$md5] status=[$result_status]"

            # 确保有值
            [[ -z "$size_human" ]] && size_human="未知"
            [[ -z "$size_bytes" ]] && size_bytes="0"
            [[ -z "$md5" ]] && md5="未知"
            [[ -z "$result_status" ]] && result_status="未知"

            # CSV: 大小（含字节数）、MD5、通过（布尔值 TRUE/FALSE）
            local pass_bool="FALSE"
            local status_icon="✗"
            if [[ "$result_status" == "pass" ]]; then
                pass_bool="TRUE"
                status_icon="✓"
            fi
            # 大小格式：人类可读(字节数)
            local size_combined="${size_human}(${size_bytes})"
            csv_line+=",$size_combined,$md5,$pass_bool"

            # HTML: 带颜色和格式（默认为 fail）
            local class="fail"
            [[ "$result_status" == "pass" ]] && class="pass"

            local html_safe_md5="${md5//</&lt;}"
            html_safe_md5="${html_safe_md5//>/&gt;}"

            html_line+="<td class='$class'>"
            html_line+="<div class='size'><strong>大小:</strong> $size_human ($size_bytes 字节)</div>"
            html_line+="<div class='md5'><strong>MD5:</strong> <code>$html_safe_md5</code></div>"
            html_line+="<div><strong>结果:</strong> $status_icon $result_status</div>"
            html_line+="</td>"
        done

        echo "$csv_line" >> "$CSV_FILE"
        echo "$html_line</tr>" >> "$HTML_FILE"
    done

    # HTML 结尾
    echo "</table>" >> "$HTML_FILE"
    echo "<p style='margin-top:20px;color:#666;'>报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>" >> "$HTML_FILE"
    echo "</body></html>" >> "$HTML_FILE"

    echo ""
    echo "========================================"
    success "测试完成！报告已生成："
    echo "  CSV: $CSV_FILE"
    echo "  HTML: $HTML_FILE"
    echo "========================================"

    # 打开 HTML 报告
    open "$HTML_FILE" 2>/dev/null
}

# 主程序
echo "========================================"
echo "SMB 多轮上传测试"
echo "========================================"
echo "服务器: //$SMB_USER@$SMB_HOST/$SMB_SHARE"
echo "上传方式: $UPLOAD_METHOD"
echo "上传轮数: $UPLOAD_ROUNDS"

# 展开路径
expanded_files=()
while IFS= read -r f; do
    expanded_files+=("$f")
done < <(expand_paths "${UPLOAD_FILES[@]}")

echo "文件/目录数: ${#expanded_files[@]}"

if [[ ${#expanded_files[@]} -eq 0 ]]; then
    error "没有要上传的文件，请检查 config.sh 中的 UPLOAD_FILES"
    exit 1
fi

# 初始化报告
init_report

# 执行多轮测试
run_multi_round_test "${expanded_files[@]}"
