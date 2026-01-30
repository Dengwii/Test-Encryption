#!/bin/zsh

# SMB 文件上传 MD5 校验测试（支持多轮上传和报告生成）

# 加载配置和函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib.sh"

# ============================================================
# 报告生成
# ============================================================

# 全局变量存储测试文件列表
TEST_FILES_LIST=()

init_report() {
    mkdir -p "$REPORT_DIR"
    REPORT_TIME=$(date +"%Y%m%d_%H%M%S")
    CSV_FILE="$REPORT_DIR/${REPORT_TIME}_report.csv"
    HTML_FILE="$REPORT_DIR/${REPORT_TIME}_report.html"
    DIFF_FILE="$REPORT_DIR/${REPORT_TIME}_diff.txt"
}

write_report_header() {
    local total_tests=$1
    local pass_tests=$2
    local fail_tests=$3
    local file_count=$4

    # 计算错误率
    local error_rate="0"
    local pass_rate="0"
    if [[ $total_tests -gt 0 ]]; then
        pass_rate=$(printf "%.2f" $(echo "scale=4; $pass_tests * 100 / $total_tests" | bc))
        error_rate=$(printf "%.2f" $(echo "scale=4; $fail_tests * 100 / $total_tests" | bc))
    fi

    # 配置信息
    local delete_before_upload_str="否"
    local separate_round_folders_str="否"
    [[ "$DELETE_BEFORE_UPLOAD" == "true" ]] && delete_before_upload_str="是"
    [[ "$SEPARATE_ROUND_FOLDERS" == "true" ]] && separate_round_folders_str="是"

    # CSV 头部信息
    echo "# SMB 上传测试报告" > "$CSV_FILE"
    echo "# 测试时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$CSV_FILE"
    echo "# 测试文件:" >> "$CSV_FILE"
    for f in "${TEST_FILES_LIST[@]}"; do
        echo "#   - $f" >> "$CSV_FILE"
    done
    echo "# SMB 服务器: //$SMB_USER@$SMB_HOST/$SMB_SHARE" >> "$CSV_FILE"
    echo "# 上传方式: $UPLOAD_METHOD" >> "$CSV_FILE"
    echo "# 上传前删除同名文件: $delete_before_upload_str" >> "$CSV_FILE"
    echo "# 独立轮次文件夹: $separate_round_folders_str" >> "$CSV_FILE"
    echo "#" >> "$CSV_FILE"
    echo "# 测试统计" >> "$CSV_FILE"
    echo "# 总测试数: $total_tests (${file_count}个文件 × ${UPLOAD_ROUNDS}轮)" >> "$CSV_FILE"
    echo "# 通过数: $pass_tests" >> "$CSV_FILE"
    echo "# 失败数: $fail_tests" >> "$CSV_FILE"
    echo "# 通过率: ${pass_rate}%" >> "$CSV_FILE"
    echo "# 错误率: ${error_rate}%" >> "$CSV_FILE"
    echo "#" >> "$CSV_FILE"

    # CSV 表头
    local header="文件名"
    for ((i=1; i<=UPLOAD_ROUNDS; i++)); do
        header+=",第${i}次-大小,第${i}次-MD5,第${i}次-通过"
    done
    echo "$header" >> "$CSV_FILE"

    # 测试文件列表 HTML
    local test_files_html=""
    for f in "${TEST_FILES_LIST[@]}"; do
        test_files_html+="<li>$f</li>"
    done

    # HTML 头部
    cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SMB 上传测试报告</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; }
        h1 { color: #333; }
        h2 { color: #444; margin-top: 25px; }
        .info { color: #666; margin-bottom: 20px; }
        .info p { margin: 5px 0; }
        .info ul { margin: 5px 0 5px 20px; padding: 0; }
        .info li { margin: 2px 0; }
        .stats { padding: 15px; background-color: #f8f9fa; border-radius: 5px; margin-bottom: 20px; }
        .stats table { width: auto; border: none; }
        .stats td { border: none; padding: 5px 20px 5px 0; }
        table.data { border-collapse: collapse; width: 100%; }
        table.data th, table.data td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        table.data th { background-color: #f5f5f5; }
        .pass { background-color: #d4edda; color: #155724; }
        .fail { background-color: #f8d7da; color: #721c24; }
        .size { font-size: 0.9em; color: #666; }
        .md5 { font-family: monospace; font-size: 0.85em; }
    </style>
</head>
<body>
<h1>SMB 上传测试报告</h1>

<div class='info'>
<p><strong>测试时间:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
<p><strong>测试文件:</strong></p>
<ul>$test_files_html</ul>
<p><strong>SMB 服务器:</strong> //$SMB_USER@$SMB_HOST/$SMB_SHARE</p>
<p><strong>上传方式:</strong> $UPLOAD_METHOD</p>
<p><strong>上传前删除同名文件:</strong> $delete_before_upload_str</p>
<p><strong>独立轮次文件夹:</strong> $separate_round_folders_str</p>
</div>

<div class='stats'>
<h2 style='margin-top:0;'>测试统计</h2>
<table>
    <tr><td><strong>总测试数:</strong></td><td>$total_tests (${file_count}个文件 × ${UPLOAD_ROUNDS}轮)</td></tr>
    <tr><td><strong>通过数:</strong></td><td style='color:#155724;'>$pass_tests</td></tr>
    <tr><td><strong>失败数:</strong></td><td style='color:#721c24;'>$fail_tests</td></tr>
    <tr><td><strong>通过率:</strong></td><td style='color:#155724;'><strong>${pass_rate}%</strong></td></tr>
    <tr><td><strong>错误率:</strong></td><td style='color:#721c24;'><strong>${error_rate}%</strong></td></tr>
</table>
</div>

<h2>测试详情</h2>
<table class='data'>
<tr><th>文件名</th>
EOF

    for ((i=1; i<=UPLOAD_ROUNDS; i++)); do
        echo "<th>第${i}次上传</th>" >> "$HTML_FILE"
    done
    echo "</tr>" >> "$HTML_FILE"
}

finalize_report() {
    cat >> "$HTML_FILE" <<EOF
</table>
<p style='margin-top:20px;color:#666;'>报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
</body></html>
EOF
}

# ============================================================
# 辅助函数
# ============================================================

get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        ls -lh "$file" 2>/dev/null | awk '{print $5}'
    elif [[ -d "$file" ]]; then
        du -sh "$file" 2>/dev/null | awk '{print $1}'
    else
        echo "0B"
    fi
}

get_file_size_bytes() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0"
    elif [[ -d "$file" ]]; then
        du -sk "$file" 2>/dev/null | awk '{print $1 * 1024}'
    else
        echo "0"
    fi
}

# HTML 转义
html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    echo "$s"
}

# ============================================================
# 单轮上传并验证 (返回结果到临时文件)
# ============================================================

# 单文件上传验证，结果写入临时目录
# 格式: size_human|size_bytes|md5_or_status|pass_or_fail|is_dir|file_details_file
upload_and_verify_single() {
    local item="$1"
    local upload_path="$2"
    local result_file="$3"
    local itemname=$(basename "$item")

    # 上传
    if ! upload_file "$item" "$upload_path"; then
        echo "0|0|上传失败|fail|false|" > "$result_file"
        return 1
    fi

    local remote_path="$upload_path/$itemname"
    local remote_size=$(get_file_size "$remote_path")
    local remote_size_bytes=$(get_file_size_bytes "$remote_path")

    if [[ -f "$item" ]]; then
        # 单文件
        local local_md5=$(calculate_md5 "$item" 2>/dev/null)
        local remote_md5=$(calculate_md5 "$remote_path" 2>/dev/null)
        [[ -z "$local_md5" ]] && local_md5="(无法读取)"
        [[ -z "$remote_md5" ]] && remote_md5="(无法读取)"

        if [[ "$local_md5" == "$remote_md5" ]] && [[ "$local_md5" != "(无法读取)" ]]; then
            echo "${remote_size}|${remote_size_bytes}|${remote_md5}|pass|false|" > "$result_file"
        else
            echo "${remote_size}|${remote_size_bytes}|本地:${local_md5} 远程:${remote_md5}|fail|false|" > "$result_file"
        fi

    elif [[ -d "$item" ]]; then
        # 目录: 逐个文件验证，结果写入 details 文件
        local details_file="${result_file}.details"
        touch "$details_file"

        local fail_count=0
        local total_count=0
        local first_md5=""

        for f in "$item"/**/*(.N); do
            ((total_count++))
            local rel_path="${f#$item/}"
            local remote_file="$upload_path/$itemname/$rel_path"
            local f_size_bytes=$(get_file_size_bytes "$f")

            local local_md5=$(calculate_md5 "$f" 2>/dev/null)
            local remote_md5=$(calculate_md5 "$remote_file" 2>/dev/null)
            [[ -z "$local_md5" ]] && local_md5="(无法读取)"
            [[ -z "$remote_md5" ]] && remote_md5="(无法读取)"

            [[ -z "$first_md5" && "$local_md5" != "(无法读取)" ]] && first_md5="$local_md5"

            local matched="false"
            if [[ "$local_md5" == "$remote_md5" ]] && [[ "$local_md5" != "(无法读取)" ]]; then
                matched="true"
            else
                ((fail_count++))
            fi

            # details 格式: rel_path|local_file|remote_file|local_md5|remote_md5|matched|size_bytes
            echo "${rel_path}|${f}|${remote_file}|${local_md5}|${remote_md5}|${matched}|${f_size_bytes}" >> "$details_file"
        done

        local verify_status="pass"
        local md5_display="$first_md5"
        if [[ $fail_count -gt 0 ]]; then
            verify_status="fail"
            md5_display="${fail_count}/${total_count}不匹配"
        fi

        echo "${remote_size}|${remote_size_bytes}|${md5_display}|${verify_status}|true|${details_file}" > "$result_file"
    fi
}

# ============================================================
# 多轮测试
# ============================================================

run_multi_round_test() {
    local items=("$@")

    # 临时目录存储结果
    local tmp_dir=$(mktemp -d)
    local test_timestamp=$(date +"%Y%m%d_%H%M%S")

    for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
        echo ""
        echo "========================================"
        echo "第 $round 轮上传 (共 $UPLOAD_ROUNDS 轮)"
        echo "========================================"

        if ! mount_smb; then
            error "挂载失败，跳过本轮"
            for item in "${items[@]}"; do
                local itemname=$(basename "$item")
                echo "0|0|挂载失败|fail|false|" > "$tmp_dir/${itemname}_${round}"
            done
            continue
        fi

        # 确定本轮上传目标路径
        local upload_path="$mount_point"
        local round_folder_name=""
        if [[ "$SEPARATE_ROUND_FOLDERS" == "true" ]]; then
            round_folder_name="${test_timestamp}_round_${round}"
            upload_path="$mount_point/$round_folder_name"
            if [[ ! -d "$upload_path" ]]; then
                mkdir -p "$upload_path"
                info "创建文件夹: $round_folder_name"
            fi
        fi

        for item in "${items[@]}"; do
            local itemname=$(basename "$item")
            local result_file="$tmp_dir/${itemname}_${round}"
            local remote_item="$upload_path/$itemname"

            # 如果配置了删除，先删除远程已存在的文件/目录
            if [[ "$DELETE_BEFORE_UPLOAD" == "true" ]] && [[ -e "$remote_item" ]]; then
                info "删除远程文件: $itemname"
                rm -rf "$remote_item" 2>/dev/null
            fi

            if [[ -n "$round_folder_name" ]]; then
                info "上传: $itemname -> $round_folder_name/$itemname"
            else
                info "上传: $itemname"
            fi

            upload_and_verify_single "$item" "$upload_path" "$result_file"

            # 读取并显示结果
            if [[ -f "$result_file" ]]; then
                local result_line=$(head -1 "$result_file")
                # 格式: size_human|size_bytes|md5|status|is_dir|details_file
                # 使用 zsh 的分割语法
                local parts=("${(@s:|:)result_line}")
                local r_size="${parts[1]}"
                local r_md5="${parts[3]}"
                local r_status="${parts[4]}"

                info "结果: ${r_size}|${r_md5}|${r_status}"

                if [[ "$r_status" == "pass" ]]; then
                    success "$itemname - 校验通过"
                else
                    error "$itemname - 校验失败"
                fi
            fi
        done

        umount_smb "$mount_point"

        if [[ $round -lt $UPLOAD_ROUNDS ]]; then
            info "等待 2 秒后开始下一轮..."
            sleep 2
        fi
    done

    # ============================================================
    # 生成报告
    # ============================================================
    echo ""
    info "生成测试报告..."

    # 第一遍: 统计通过/失败数和文件数
    local total_tests=0
    local pass_tests=0
    local fail_tests=0
    local file_count=0

    for item in "${items[@]}"; do
        local itemname=$(basename "$item")
        local first_result_file="$tmp_dir/${itemname}_1"
        local first_line=""
        [[ -f "$first_result_file" ]] && first_line=$(head -1 "$first_result_file")

        local first_parts=("${(@s:|:)first_line}")
        local is_dir="${first_parts[5]}"
        local first_details="${first_parts[6]}"

        if [[ "$is_dir" == "true" ]] && [[ -n "$first_details" ]] && [[ -f "$first_details" ]]; then
            # 目录: 统计每个子文件
            while IFS='|' read -r rel_path local_file remote_file local_md5 remote_md5 matched size_bytes; do
                ((file_count++))
                for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
                    local rf="$tmp_dir/${itemname}_${round}"
                    local rl=""
                    [[ -f "$rf" ]] && rl=$(head -1 "$rf")
                    local rp=("${(@s:|:)rl}")
                    local r_details="${rp[6]}"

                    local d_matched="false"
                    if [[ -n "$r_details" ]] && [[ -f "$r_details" ]]; then
                        while IFS='|' read -r d_rp d_lf d_rf d_lm d_rm d_mt d_sb; do
                            if [[ "$d_rp" == "$rel_path" ]]; then
                                d_matched="$d_mt"
                                break
                            fi
                        done < "$r_details"
                    fi

                    ((total_tests++))
                    if [[ "$d_matched" == "true" ]]; then
                        ((pass_tests++))
                    else
                        ((fail_tests++))
                    fi
                done
            done < "$first_details"
        else
            # 单文件
            ((file_count++))
            for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
                local rf="$tmp_dir/${itemname}_${round}"
                local rl=""
                [[ -f "$rf" ]] && rl=$(head -1 "$rf")
                local rp=("${(@s:|:)rl}")
                local r_status="${rp[4]:-fail}"

                ((total_tests++))
                if [[ "$r_status" == "pass" ]]; then
                    ((pass_tests++))
                else
                    ((fail_tests++))
                fi
            done
        fi
    done

    # 写入报告头部 (包含统计信息)
    write_report_header "$total_tests" "$pass_tests" "$fail_tests" "$file_count"

    # 第二遍: 写入详细数据
    for item in "${items[@]}"; do
        local itemname=$(basename "$item")

        # 读取第1轮结果判断是否是目录
        local first_result_file="$tmp_dir/${itemname}_1"
        local first_line=""
        [[ -f "$first_result_file" ]] && first_line=$(head -1 "$first_result_file")

        local first_parts=("${(@s:|:)first_line}")
        local is_dir="${first_parts[5]}"
        local first_details="${first_parts[6]}"

        if [[ "$is_dir" == "true" ]] && [[ -n "$first_details" ]] && [[ -f "$first_details" ]]; then
            # ========== 目录: 汇总行 ==========
            local csv_line="[目录] $itemname"
            local html_line="<tr style='background-color:#eef;'><td><strong>[目录] $itemname</strong></td>"

            for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
                local rf="$tmp_dir/${itemname}_${round}"
                local rl=""
                [[ -f "$rf" ]] && rl=$(head -1 "$rf")
                local rp=("${(@s:|:)rl}")
                local r_size="${rp[1]:-未知}"
                local r_size_bytes="${rp[2]:-0}"
                local r_status="${rp[4]:-fail}"
                local r_details="${rp[6]}"

                # 统计该轮子文件通过/失败
                local round_total=0
                local round_pass=0
                if [[ -n "$r_details" ]] && [[ -f "$r_details" ]]; then
                    while IFS='|' read -r _rp _lf _rf _lm _rm _matched _sb; do
                        ((round_total++))
                        [[ "$_matched" == "true" ]] && ((round_pass++))
                    done < "$r_details"
                fi
                local round_fail=$((round_total - round_pass))

                local pass_bool="FALSE"
                local class="fail"
                local icon="&#10007;"
                if [[ "$r_status" == "pass" ]]; then
                    pass_bool="TRUE"
                    class="pass"
                    icon="&#10003;"
                fi

                csv_line+=",$r_size($r_size_bytes),$round_pass/$round_total 通过,$pass_bool"

                html_line+="<td class='$class'>"
                html_line+="<div class='size'><strong>总大小:</strong> $r_size ($r_size_bytes 字节)</div>"
                html_line+="<div><strong>文件数:</strong> $round_total 个 (通过: $round_pass, 失败: $round_fail)</div>"
                html_line+="<div><strong>结果:</strong> $icon $r_status</div>"
                html_line+="</td>"
            done

            echo "$csv_line" >> "$CSV_FILE"
            echo "$html_line</tr>" >> "$HTML_FILE"

            # ========== 目录: 展开每个子文件 ==========
            # 使用第1轮 details 作为文件列表
            while IFS='|' read -r rel_path local_file remote_file local_md5 remote_md5 matched size_bytes; do
                local csv_sub="  $itemname/$rel_path"
                local html_sub="<tr><td style='padding-left:30px;'>$itemname/$rel_path</td>"

                for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
                    local rf="$tmp_dir/${itemname}_${round}"
                    local rl=""
                    [[ -f "$rf" ]] && rl=$(head -1 "$rf")
                    local rp=("${(@s:|:)rl}")
                    local r_details="${rp[6]}"

                    # 从该轮 details 中找到对应文件
                    local d_size_bytes="0"
                    local d_local_md5="(无法读取)"
                    local d_remote_md5="(无法读取)"
                    local d_matched="false"
                    local found=false

                    if [[ -n "$r_details" ]] && [[ -f "$r_details" ]]; then
                        while IFS='|' read -r d_rp d_lf d_rf d_lm d_rm d_mt d_sb; do
                            if [[ "$d_rp" == "$rel_path" ]]; then
                                d_size_bytes="$d_sb"
                                d_local_md5="$d_lm"
                                d_remote_md5="$d_rm"
                                d_matched="$d_mt"
                                found=true
                                break
                            fi
                        done < "$r_details"
                    fi

                    # 人类可读大小
                    local d_size_human="${d_size_bytes}B"
                    if [[ $d_size_bytes -ge 1073741824 ]]; then
                        d_size_human="$(echo "scale=2; $d_size_bytes/1073741824" | bc)GB"
                    elif [[ $d_size_bytes -ge 1048576 ]]; then
                        d_size_human="$(echo "scale=2; $d_size_bytes/1048576" | bc)MB"
                    elif [[ $d_size_bytes -ge 1024 ]]; then
                        d_size_human="$(echo "scale=2; $d_size_bytes/1024" | bc)KB"
                    fi

                    local md5_display=""
                    local pass_bool="FALSE"
                    local class="fail"
                    local icon="&#10007;"
                    local status_text="fail"

                    if [[ "$found" == "true" ]] && [[ "$d_matched" == "true" ]]; then
                        md5_display="$d_local_md5"
                        pass_bool="TRUE"
                        class="pass"
                        icon="&#10003;"
                        status_text="pass"
                    else
                        if [[ "$found" == "true" ]]; then
                            md5_display="本地:$d_local_md5 远程:$d_remote_md5"
                        else
                            md5_display="未知"
                        fi
                    fi

                    local safe_md5=$(html_escape "$md5_display")
                    csv_sub+=",$d_size_human($d_size_bytes),$md5_display,$pass_bool"

                    html_sub+="<td class='$class'>"
                    html_sub+="<div class='size'><strong>大小:</strong> $d_size_human ($d_size_bytes 字节)</div>"
                    html_sub+="<div class='md5'><strong>MD5:</strong> <code>$safe_md5</code></div>"
                    html_sub+="<div><strong>结果:</strong> $icon $status_text</div>"
                    html_sub+="</td>"
                done

                echo "$csv_sub" >> "$CSV_FILE"
                echo "$html_sub</tr>" >> "$HTML_FILE"
            done < "$first_details"

        else
            # ========== 单文件 ==========
            local csv_line="$itemname"
            local html_line="<tr><td>$itemname</td>"

            for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
                local rf="$tmp_dir/${itemname}_${round}"
                local rl=""
                [[ -f "$rf" ]] && rl=$(head -1 "$rf")

                local rp=("${(@s:|:)rl}")
                local r_size="${rp[1]:-未知}"
                local r_size_bytes="${rp[2]:-0}"
                local r_md5="${rp[3]:-未知}"
                local r_status="${rp[4]:-fail}"

                local pass_bool="FALSE"
                local class="fail"
                local icon="&#10007;"
                if [[ "$r_status" == "pass" ]]; then
                    pass_bool="TRUE"
                    class="pass"
                    icon="&#10003;"
                fi

                local safe_md5=$(html_escape "$r_md5")
                csv_line+=",$r_size($r_size_bytes),$r_md5,$pass_bool"

                html_line+="<td class='$class'>"
                html_line+="<div class='size'><strong>大小:</strong> $r_size ($r_size_bytes 字节)</div>"
                html_line+="<div class='md5'><strong>MD5:</strong> <code>$safe_md5</code></div>"
                html_line+="<div><strong>结果:</strong> $icon $r_status</div>"
                html_line+="</td>"
            done

            echo "$csv_line" >> "$CSV_FILE"
            echo "$html_line</tr>" >> "$HTML_FILE"
        fi
    done

    finalize_report

    # ============================================================
    # 生成字节差异报告 (使用 cmp -l)
    # ============================================================
    info "分析失败文件的字节差异..."
    local diff_content=""
    diff_content+="SMB 上传测试 - 字节差异报告\n"
    diff_content+="生成时间: $(date '+%Y-%m-%d %H:%M:%S')\n"
    diff_content+="SMB 服务器: //$SMB_USER@$SMB_HOST/$SMB_SHARE\n\n"

    local has_diffs=false

    # 重新挂载 SMB
    if mount_smb; then
        for item in "${items[@]}"; do
            local itemname=$(basename "$item")

            for ((round=1; round<=UPLOAD_ROUNDS; round++)); do
                local rf="$tmp_dir/${itemname}_${round}"
                [[ ! -f "$rf" ]] && continue
                local rl=$(head -1 "$rf")
                local rp=("${(@s:|:)rl}")
                local r_status="${rp[4]}"
                local r_is_dir="${rp[5]}"
                local r_details="${rp[6]}"

                [[ "$r_status" == "pass" ]] && continue

                # 确定远程路径
                local diff_upload_path="$mount_point"
                if [[ "$SEPARATE_ROUND_FOLDERS" == "true" ]]; then
                    diff_upload_path="$mount_point/${test_timestamp}_round_${round}"
                fi

                if [[ "$r_is_dir" == "true" ]] && [[ -n "$r_details" ]] && [[ -f "$r_details" ]]; then
                    # 目录: 对比每个失败的子文件
                    while IFS='|' read -r d_rp d_lf d_rf d_lm d_rm d_mt d_sb; do
                        [[ "$d_mt" == "true" ]] && continue
                        local remote_file="$diff_upload_path/$itemname/$d_rp"
                        # 构建 SMB 路径用于显示
                        local smb_display_path="//$SMB_HOST/$SMB_SHARE"
                        if [[ "$SEPARATE_ROUND_FOLDERS" == "true" ]]; then
                            smb_display_path+="/${test_timestamp}_round_${round}"
                        fi
                        smb_display_path+="/$itemname/$d_rp"
                        diff_content+="\n第 $round 轮 - $itemname/$d_rp\n"
                        diff_content+="============================================================\n"
                        diff_content+="源文件: $d_lf\n"
                        diff_content+="目标文件: $smb_display_path\n"
                        if [[ -f "$d_lf" ]] && [[ -f "$remote_file" ]]; then
                            local cmp_output=$(cmp -l "$d_lf" "$remote_file" 2>&1 | head -5)
                            if [[ -n "$cmp_output" ]]; then
                                diff_content+="cmp -l 前5个差异:\n$cmp_output\n"
                            else
                                diff_content+="cmp: 文件相同或无法比较\n"
                            fi
                        else
                            diff_content+="文件不存在，无法比较\n"
                        fi
                        diff_content+="============================================================\n"
                        has_diffs=true
                    done < "$r_details"
                else
                    # 单文件
                    local local_file="$item"
                    local remote_file="$diff_upload_path/$itemname"
                    # 构建 SMB 路径用于显示
                    local smb_display_path="//$SMB_HOST/$SMB_SHARE"
                    if [[ "$SEPARATE_ROUND_FOLDERS" == "true" ]]; then
                        smb_display_path+="/${test_timestamp}_round_${round}"
                    fi
                    smb_display_path+="/$itemname"
                    diff_content+="\n第 $round 轮 - $itemname\n"
                    diff_content+="============================================================\n"
                    diff_content+="源文件: $local_file\n"
                    diff_content+="目标文件: $smb_display_path\n"
                    if [[ -f "$local_file" ]] && [[ -f "$remote_file" ]]; then
                        local cmp_output=$(cmp -l "$local_file" "$remote_file" 2>&1 | head -5)
                        if [[ -n "$cmp_output" ]]; then
                            diff_content+="cmp -l 前5个差异:\n$cmp_output\n"
                        else
                            diff_content+="cmp: 文件相同或无法比较\n"
                        fi
                    else
                        diff_content+="文件不存在，无法比较\n"
                    fi
                    diff_content+="============================================================\n"
                    has_diffs=true
                fi
            done
        done
        umount_smb "$mount_point"
    else
        diff_content+="无法连接 SMB，跳过字节差异分析\n"
    fi

    if [[ "$has_diffs" == "true" ]]; then
        echo -e "$diff_content" > "$DIFF_FILE"
        info "字节差异报告: $DIFF_FILE"
    else
        info "所有文件校验通过，无需生成差异报告"
    fi

    # 清理临时目录
    rm -rf "$tmp_dir"

    echo ""
    echo "========================================"
    success "测试完成！报告已生成："
    echo "  CSV: $CSV_FILE"
    echo "  HTML: $HTML_FILE"
    if [[ "$has_diffs" == "true" ]]; then
        echo "  DIFF: $DIFF_FILE"
    fi
    echo "========================================"

    # 打开 HTML 报告
    open "$HTML_FILE" 2>/dev/null
}

# ============================================================
# 主程序
# ============================================================

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

# 保存测试文件列表供报告使用
TEST_FILES_LIST=("${expanded_files[@]}")

# 初始化报告
init_report

# 执行多轮测试
run_multi_round_test "${expanded_files[@]}"
