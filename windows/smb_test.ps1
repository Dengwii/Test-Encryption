# SMB 文件上传 MD5 校验测试（支持多轮上传和报告生成）
# Windows PowerShell 版本

# 设置编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

# 加载配置和函数库
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\config.ps1"
. "$ScriptDir\lib.ps1"

# ============================================================
# 报告生成
# ============================================================

function Initialize-Report {
    param([string[]]$TestFiles)

    if (-not (Test-Path $REPORT_DIR)) {
        New-Item -ItemType Directory -Path $REPORT_DIR -Force | Out-Null
    }

    $script:ReportTime = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:CsvFile = Join-Path $REPORT_DIR "${ReportTime}_report.csv"
    $script:HtmlFile = Join-Path $REPORT_DIR "${ReportTime}_report.html"
    $script:DiffFile = Join-Path $REPORT_DIR "${ReportTime}_diff.txt"

    # 保存测试文件列表供后续使用
    $script:TestFilesList = $TestFiles
}

function Write-ReportHeader {
    param(
        [int]$TotalTests = 0,
        [int]$PassTests = 0,
        [int]$FailTests = 0,
        [int]$FileCount = 0
    )

    # 计算错误率
    $errorRate = if ($TotalTests -gt 0) { [math]::Round(($FailTests / $TotalTests) * 100, 2) } else { 0 }
    $passRate = if ($TotalTests -gt 0) { [math]::Round(($PassTests / $TotalTests) * 100, 2) } else { 0 }

    # 配置信息
    $deleteBeforeUploadStr = if ($DELETE_BEFORE_UPLOAD) { "是" } else { "否" }
    $separateRoundFoldersStr = if ($SEPARATE_ROUND_FOLDERS) { "是" } else { "否" }

    # 测试文件列表
    $testFilesStr = ($script:TestFilesList | ForEach-Object { "  - $_" }) -join "`r`n"

    # CSV 头部信息
    $csvHeader = @()
    $csvHeader += "# SMB 上传测试报告"
    $csvHeader += "# 测试时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $csvHeader += "# 测试文件:"
    foreach ($f in $script:TestFilesList) {
        $csvHeader += "#   - $f"
    }
    $csvHeader += "# SMB 服务器: \\$SMB_HOST\$SMB_SHARE"
    $csvHeader += "# 上传方式: $UPLOAD_METHOD"
    $csvHeader += "# 上传前删除同名文件: $deleteBeforeUploadStr"
    $csvHeader += "# 独立轮次文件夹: $separateRoundFoldersStr"
    $csvHeader += "#"
    $csvHeader += "# 测试统计"
    $csvHeader += "# 总测试数: $TotalTests (${FileCount}个文件 × ${UPLOAD_ROUNDS}轮)"
    $csvHeader += "# 通过数: $PassTests"
    $csvHeader += "# 失败数: $FailTests"
    $csvHeader += "# 通过率: $passRate%"
    $csvHeader += "# 错误率: $errorRate%"
    $csvHeader += "#"

    # CSV 表头
    $header = "文件名"
    for ($i = 1; $i -le $UPLOAD_ROUNDS; $i++) {
        $header += ",第${i}次-大小,第${i}次-MD5,第${i}次-通过"
    }
    $csvHeader += $header

    $csvHeader -join "`r`n" | Out-File -FilePath $CsvFile -Encoding utf8

    # HTML 头部
    $testFilesHtml = ($script:TestFilesList | ForEach-Object { "<li>$_</li>" }) -join ""

    $htmlHead = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SMB 上传测试报告</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 20px; }
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
        .md5 { font-family: Consolas, monospace; font-size: 0.85em; }
    </style>
</head>
<body>
<h1>SMB 上传测试报告</h1>

<div class='info'>
<p><strong>测试时间:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>测试文件:</strong></p>
<ul>$testFilesHtml</ul>
<p><strong>SMB 服务器:</strong> \\$SMB_HOST\$SMB_SHARE</p>
<p><strong>上传方式:</strong> $UPLOAD_METHOD</p>
<p><strong>上传前删除同名文件:</strong> $deleteBeforeUploadStr</p>
<p><strong>独立轮次文件夹:</strong> $separateRoundFoldersStr</p>
</div>

<div class='stats'>
<h2 style='margin-top:0;'>测试统计</h2>
<table>
    <tr><td><strong>总测试数:</strong></td><td>$TotalTests (${FileCount}个文件 × ${UPLOAD_ROUNDS}轮)</td></tr>
    <tr><td><strong>通过数:</strong></td><td style='color:#155724;'>$PassTests</td></tr>
    <tr><td><strong>失败数:</strong></td><td style='color:#721c24;'>$FailTests</td></tr>
    <tr><td><strong>通过率:</strong></td><td style='color:#155724;'><strong>$passRate%</strong></td></tr>
    <tr><td><strong>错误率:</strong></td><td style='color:#721c24;'><strong>$errorRate%</strong></td></tr>
</table>
</div>

<h2>测试详情</h2>
<table class='data'>
<tr><th>文件名</th>
"@
    for ($i = 1; $i -le $UPLOAD_ROUNDS; $i++) {
        $htmlHead += "<th>第${i}次上传</th>"
    }
    $htmlHead += "</tr>"

    $htmlHead | Out-File -FilePath $HtmlFile -Encoding utf8
}

function Finalize-Report {
    # HTML 结尾
    $htmlFoot = @"
</table>
<p style='margin-top:20px;color:#666;'>报告生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
</body></html>
"@
    $htmlFoot | Out-File -FilePath $HtmlFile -Append -Encoding utf8
}

# ============================================================
# 单轮上传并验证
# ============================================================

function Upload-AndVerify {
    param(
        [string]$LocalPath,
        [string]$RemotePath
    )

    $itemName = Split-Path $LocalPath -Leaf

    # 上传
    $uploadResult = Upload-File -Source $LocalPath -Destination $RemotePath
    if (-not $uploadResult) {
        return @{
            SizeHuman = "0"
            SizeBytes = 0
            MD5 = "上传失败"
            Status = "fail"
            IsDir = $false
            FileDetails = @()
        }
    }

    # 获取远程文件信息
    $remoteItem = Join-Path $RemotePath $itemName
    $sizeHuman = Get-FileSize -Path $remoteItem
    $sizeBytes = Get-FileSizeBytes -Path $remoteItem

    # 验证
    $verifyResult = Verify-Upload -LocalPath $LocalPath -RemotePath $RemotePath
    $isDir = Test-Path $LocalPath -PathType Container

    if ($verifyResult.Success) {
        return @{
            SizeHuman = $sizeHuman
            SizeBytes = $sizeBytes
            MD5 = $verifyResult.MD5
            Status = "pass"
            IsDir = $isDir
            FileDetails = if ($verifyResult.FileDetails) { $verifyResult.FileDetails } else { @() }
        }
    } else {
        $md5Info = if ($verifyResult.LocalMD5) {
            "本地:$($verifyResult.LocalMD5) 远程:$($verifyResult.RemoteMD5)"
        } else {
            $verifyResult.Message
        }
        return @{
            SizeHuman = $sizeHuman
            SizeBytes = $sizeBytes
            MD5 = $md5Info
            Status = "fail"
            IsDir = $isDir
            FileDetails = if ($verifyResult.FileDetails) { $verifyResult.FileDetails } else { @() }
        }
    }
}

# ============================================================
# 多轮测试
# ============================================================

function Run-MultiRoundTest {
    param([string[]]$Files)

    # 存储所有结果
    $results = @{}

    # 生成本次测试的时间戳前缀 (用于独立文件夹命名)
    $testTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    for ($round = 1; $round -le $UPLOAD_ROUNDS; $round++) {
        Write-Host ""
        Write-Host "========================================"
        Write-Host "第 $round 轮上传 (共 $UPLOAD_ROUNDS 轮)"
        Write-Host "========================================"

        # 连接 SMB
        $driveLetter = Connect-SMB
        if (-not $driveLetter) {
            Write-Error2 "连接失败，跳过本轮"
            foreach ($file in $Files) {
                $key = "$(Split-Path $file -Leaf)_$round"
                $results[$key] = @{
                    SizeHuman = "0"
                    SizeBytes = 0
                    MD5 = "连接失败"
                    Status = "fail"
                }
            }
            continue
        }

        # 确定本轮的上传目标路径
        if ($SEPARATE_ROUND_FOLDERS) {
            $roundFolderName = "${testTimestamp}_round_$round"
            $roundFolder = Join-Path "$driveLetter\" $roundFolderName
            if (-not (Test-Path -LiteralPath $roundFolder)) {
                New-Item -ItemType Directory -Path $roundFolder -Force | Out-Null
                Write-Info "创建文件夹: $roundFolderName"
            }
            $uploadPath = $roundFolder
        } else {
            $roundFolderName = ""
            $uploadPath = "$driveLetter\"
        }

        foreach ($file in $Files) {
            $itemName = Split-Path $file -Leaf
            $key = "${itemName}_$round"
            $remoteItem = Join-Path $uploadPath $itemName

            # 如果配置了删除，先删除远程已存在的文件/目录
            if ($DELETE_BEFORE_UPLOAD -and (Test-Path -LiteralPath $remoteItem)) {
                Write-Info "删除远程文件: $itemName"
                try {
                    Remove-Item -LiteralPath $remoteItem -Recurse -Force -ErrorAction Stop
                } catch {
                    Write-Error2 "删除失败: $_"
                }
            }

            Write-Info "上传: $itemName -> $(if ($roundFolderName) { "$roundFolderName/" } else { '' })$itemName"

            $result = Upload-AndVerify -LocalPath $file -RemotePath $uploadPath
            $results[$key] = $result

            Write-Info "结果: $($result.SizeHuman) | $($result.MD5) | $($result.Status)"

            if ($result.Status -eq "pass") {
                Write-Success "$itemName - 校验通过"
            } else {
                Write-Error2 "$itemName - 校验失败"
            }
        }

        # 断开连接
        Disconnect-SMB -DriveLetter $driveLetter

        # 轮次间等待
        if ($round -lt $UPLOAD_ROUNDS) {
            Write-Info "等待 2 秒后开始下一轮..."
            Start-Sleep -Seconds 2
        }
    }

    # 生成报告
    Write-Host ""
    Write-Info "生成测试报告..."

    # 第一遍: 统计通过/失败数和文件数
    $totalTests = 0
    $passTests = 0
    $failTests = 0
    $fileCount = 0

    foreach ($file in $Files) {
        $itemName = Split-Path $file -Leaf
        $firstKey = "${itemName}_1"
        $firstResult = $results[$firstKey]
        $isDir = $firstResult -and $firstResult.IsDir -and $firstResult.FileDetails.Count -gt 0

        if ($isDir) {
            $fileList = $firstResult.FileDetails
            foreach ($fd in $fileList) {
                $fileCount++
                $relPath = $fd.RelativePath
                for ($round = 1; $round -le $UPLOAD_ROUNDS; $round++) {
                    $roundKey = "${itemName}_$round"
                    $roundResult = $results[$roundKey]
                    $detail = $null
                    if ($roundResult -and $roundResult.FileDetails) {
                        $detail = $roundResult.FileDetails | Where-Object { $_.RelativePath -eq $relPath }
                    }
                    $totalTests++
                    if ($detail -and $detail.Matched) { $passTests++ } else { $failTests++ }
                }
            }
        } else {
            $fileCount++
            for ($round = 1; $round -le $UPLOAD_ROUNDS; $round++) {
                $key = "${itemName}_$round"
                $result = $results[$key]
                $totalTests++
                if ($result -and $result.Status -eq "pass") { $passTests++ } else { $failTests++ }
            }
        }
    }

    # 写入报告头部 (包含统计信息)
    Write-ReportHeader -TotalTests $totalTests -PassTests $passTests -FailTests $failTests -FileCount $fileCount

    # 第二遍: 写入详细数据
    foreach ($file in $Files) {
        $itemName = Split-Path $file -Leaf

        # 检查第1轮结果判断是否是目录
        $firstKey = "${itemName}_1"
        $firstResult = $results[$firstKey]
        $isDir = $firstResult -and $firstResult.IsDir -and $firstResult.FileDetails.Count -gt 0

        if ($isDir) {
            # 目录: 先输出一行汇总行
            $csvLine = "[目录] $itemName"
            $htmlLine = "<tr style='background-color:#eef;'><td><strong>[目录] $itemName</strong></td>"

            for ($round = 1; $round -le $UPLOAD_ROUNDS; $round++) {
                $key = "${itemName}_$round"
                $result = $results[$key]
                if (-not $result) {
                    $result = @{ SizeHuman = "未知"; SizeBytes = 0; MD5 = "未知"; Status = "fail"; FileDetails = @() }
                }

                # 统计通过/失败文件数
                $totalFiles = $result.FileDetails.Count
                $passFiles = ($result.FileDetails | Where-Object { $_.Matched }).Count
                $failFiles = $totalFiles - $passFiles

                $passBool = if ($result.Status -eq "pass") { "TRUE" } else { "FALSE" }
                $sizeCombined = "$($result.SizeHuman)($($result.SizeBytes))"
                $csvLine += ",$sizeCombined,$passFiles/$totalFiles 通过,$passBool"

                $class = if ($result.Status -eq "pass") { "pass" } else { "fail" }
                $icon = if ($result.Status -eq "pass") { "&#10003;" } else { "&#10007;" }

                $htmlLine += "<td class='$class'>"
                $htmlLine += "<div class='size'><strong>总大小:</strong> $($result.SizeHuman) ($($result.SizeBytes) 字节)</div>"
                $htmlLine += "<div><strong>文件数:</strong> $totalFiles 个 (通过: $passFiles, 失败: $failFiles)</div>"
                $htmlLine += "<div><strong>结果:</strong> $icon $($result.Status)</div>"
                $htmlLine += "</td>"
            }

            $csvLine | Out-File -FilePath $CsvFile -Append -Encoding utf8
            $htmlLine += "</tr>"
            $htmlLine | Out-File -FilePath $HtmlFile -Append -Encoding utf8

            # 展开目录下每个子文件
            # 使用第1轮的 FileDetails 作为文件列表参考
            $fileList = $firstResult.FileDetails
            foreach ($fd in $fileList) {
                $relPath = $fd.RelativePath
                $csvSubLine = "  $itemName/$relPath"
                $htmlSubLine = "<tr><td style='padding-left:30px;'>$itemName/$relPath</td>"

                for ($round = 1; $round -le $UPLOAD_ROUNDS; $round++) {
                    $roundKey = "${itemName}_$round"
                    $roundResult = $results[$roundKey]

                    # 从该轮的 FileDetails 中找到对应文件
                    $detail = $null
                    if ($roundResult -and $roundResult.FileDetails) {
                        $detail = $roundResult.FileDetails | Where-Object { $_.RelativePath -eq $relPath }
                    }

                    if ($detail) {
                        $sizeBytes = $detail.SizeBytes
                        $sizeHuman = if ($sizeBytes -ge 1GB) { "{0:N2}GB" -f ($sizeBytes / 1GB) }
                                     elseif ($sizeBytes -ge 1MB) { "{0:N2}MB" -f ($sizeBytes / 1MB) }
                                     elseif ($sizeBytes -ge 1KB) { "{0:N2}KB" -f ($sizeBytes / 1KB) }
                                     else { "${sizeBytes}B" }

                        # 处理 MD5 为 null 的情况 (被杀毒软件拦截)
                        $localMD5Str = if ($null -eq $detail.LocalMD5) { "(无法读取)" } else { $detail.LocalMD5 }
                        $remoteMD5Str = if ($null -eq $detail.RemoteMD5) { "(无法读取)" } else { $detail.RemoteMD5 }

                        $md5Display = if ($detail.Matched) {
                            $localMD5Str
                        } else {
                            "本地:$localMD5Str 远程:$remoteMD5Str"
                        }
                        $passBool = if ($detail.Matched) { "TRUE" } else { "FALSE" }
                        $class = if ($detail.Matched) { "pass" } else { "fail" }
                        $icon = if ($detail.Matched) { "&#10003;" } else { "&#10007;" }
                    } else {
                        $sizeHuman = "未知"
                        $sizeBytes = 0
                        $md5Display = "未知"
                        $passBool = "FALSE"
                        $class = "fail"
                        $icon = "&#10007;"
                    }

                    $csvSubLine += ",$sizeHuman($sizeBytes),$md5Display,$passBool"

                    $safeMD5 = "$md5Display" -replace '<', '&lt;' -replace '>', '&gt;'
                    $htmlSubLine += "<td class='$class'>"
                    $htmlSubLine += "<div class='size'><strong>大小:</strong> $sizeHuman ($sizeBytes 字节)</div>"
                    $htmlSubLine += "<div class='md5'><strong>MD5:</strong> <code>$safeMD5</code></div>"
                    $htmlSubLine += "<div><strong>结果:</strong> $icon $(if ($detail -and $detail.Matched) {'pass'} else {'fail'})</div>"
                    $htmlSubLine += "</td>"
                }

                $csvSubLine | Out-File -FilePath $CsvFile -Append -Encoding utf8
                $htmlSubLine += "</tr>"
                $htmlSubLine | Out-File -FilePath $HtmlFile -Append -Encoding utf8
            }
        } else {
            # 单文件: 保持原逻辑
            $csvLine = $itemName
            $htmlLine = "<tr><td>$itemName</td>"

            for ($round = 1; $round -le $UPLOAD_ROUNDS; $round++) {
                $key = "${itemName}_$round"
                $result = $results[$key]

                if (-not $result) {
                    $result = @{ SizeHuman = "未知"; SizeBytes = 0; MD5 = "未知"; Status = "fail" }
                }

                # CSV
                $passBool = if ($result.Status -eq "pass") { "TRUE" } else { "FALSE" }
                $sizeCombined = "$($result.SizeHuman)($($result.SizeBytes))"
                $csvLine += ",$sizeCombined,$($result.MD5),$passBool"

                # HTML
                $class = if ($result.Status -eq "pass") { "pass" } else { "fail" }
                $icon = if ($result.Status -eq "pass") { "&#10003;" } else { "&#10007;" }
                $safeMD5 = "$($result.MD5)" -replace '<', '&lt;' -replace '>', '&gt;'

                $htmlLine += "<td class='$class'>"
                $htmlLine += "<div class='size'><strong>大小:</strong> $($result.SizeHuman) ($($result.SizeBytes) 字节)</div>"
                $htmlLine += "<div class='md5'><strong>MD5:</strong> <code>$safeMD5</code></div>"
                $htmlLine += "<div><strong>结果:</strong> $icon $($result.Status)</div>"
                $htmlLine += "</td>"
            }

            $csvLine | Out-File -FilePath $CsvFile -Append -Encoding utf8
            $htmlLine += "</tr>"
            $htmlLine | Out-File -FilePath $HtmlFile -Append -Encoding utf8
        }
    }

    Finalize-Report

    # 生成字节差异报告 (对失败的文件进行对比)
    Write-Info "分析失败文件的字节差异..."
    $diffReportContent = @()
    $diffReportContent += "SMB 上传测试 - 字节差异报告"
    $diffReportContent += "生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $diffReportContent += "SMB 服务器: \\$SMB_HOST\$SMB_SHARE"
    $diffReportContent += ""

    $hasDiffs = $false

    # 需要重新连接 SMB 来读取远程文件
    $driveLetter = Connect-SMB
    if ($driveLetter) {
        foreach ($file in $Files) {
            $itemName = Split-Path $file -Leaf
            $isDir = Test-Path $file -PathType Container

            for ($round = 1; $round -le $UPLOAD_ROUNDS; $round++) {
                $key = "${itemName}_$round"
                $result = $results[$key]

                if (-not $result -or $result.Status -eq "pass") { continue }

                # 确定远程路径
                if ($SEPARATE_ROUND_FOLDERS) {
                    $roundFolderName = "${testTimestamp}_round_$round"
                    $uploadPath = Join-Path "$driveLetter\" $roundFolderName
                } else {
                    $uploadPath = "$driveLetter\"
                }

                if ($isDir -and $result.FileDetails) {
                    # 目录: 对比每个失败的子文件
                    foreach ($detail in $result.FileDetails) {
                        if ($detail.Matched) { continue }

                        $localFile = $detail.LocalFile
                        $remoteFile = Join-Path $uploadPath "$itemName\$($detail.RelativePath)"

                        # 构建 SMB 路径用于显示
                        $smbDisplayPath = "\\$SMB_HOST\$($SMB_SHARE -replace '/', '\')"
                        if ($SEPARATE_ROUND_FOLDERS) {
                            $smbDisplayPath += "\${testTimestamp}_round_$round"
                        }
                        $smbDisplayPath += "\$itemName\$($detail.RelativePath)"

                        $diffReportContent += ""
                        $diffReportContent += "第 $round 轮 - $itemName/$($detail.RelativePath)"

                        $compareResult = Compare-FileBytes -File1 $localFile -File2 $remoteFile -MaxDiffs 5
                        $diffReportContent += Format-ByteCompareResult -CompareResult $compareResult -SmbDisplayPath $smbDisplayPath
                        $hasDiffs = $true
                    }
                } else {
                    # 单文件
                    $localFile = $file
                    $remoteFile = Join-Path $uploadPath $itemName

                    # 构建 SMB 路径用于显示
                    $smbDisplayPath = "\\$SMB_HOST\$($SMB_SHARE -replace '/', '\')"
                    if ($SEPARATE_ROUND_FOLDERS) {
                        $smbDisplayPath += "\${testTimestamp}_round_$round"
                    }
                    $smbDisplayPath += "\$itemName"

                    $diffReportContent += ""
                    $diffReportContent += "第 $round 轮 - $itemName"

                    $compareResult = Compare-FileBytes -File1 $localFile -File2 $remoteFile -MaxDiffs 5
                    $diffReportContent += Format-ByteCompareResult -CompareResult $compareResult -SmbDisplayPath $smbDisplayPath
                    $hasDiffs = $true
                }
            }
        }
        Disconnect-SMB -DriveLetter $driveLetter
    } else {
        $diffReportContent += "无法连接 SMB，跳过字节差异分析"
    }

    # 只有存在差异时才输出 diff 文件
    if ($hasDiffs) {
        $diffReportContent -join "`r`n" | Out-File -FilePath $DiffFile -Encoding utf8
        Write-Info "字节差异报告: $DiffFile"
    } else {
        Write-Info "所有文件校验通过，无需生成差异报告"
    }

    Write-Host ""
    Write-Host "========================================"
    Write-Success "测试完成！报告已生成："
    Write-Host "  CSV: $CsvFile"
    Write-Host "  HTML: $HtmlFile"
    if ($hasDiffs) {
        Write-Host "  DIFF: $DiffFile"
    }
    Write-Host "========================================"

    # 打开 HTML 报告
    Start-Process $HtmlFile
}

# ============================================================
# 主程序
# ============================================================

Write-Host "========================================"
Write-Host "SMB 多轮上传测试 (Windows)"
Write-Host "========================================"
Write-Host "服务器: $SMB_PATH"
Write-Host "上传方式: $UPLOAD_METHOD"
Write-Host "上传轮数: $UPLOAD_ROUNDS"

# 检查文件列表
$validFiles = @()
foreach ($file in $UPLOAD_FILES) {
    if ([string]::IsNullOrWhiteSpace($file)) { continue }
    if (Test-Path $file) {
        $validFiles += $file
    } else {
        Write-Error2 "文件不存在: $file"
    }
}

Write-Host "文件/目录数: $($validFiles.Count)"

if ($validFiles.Count -eq 0) {
    Write-Error2 "没有要上传的文件，请检查 config.ps1 中的 UPLOAD_FILES"
    exit 1
}

# 初始化报告
Initialize-Report -TestFiles $validFiles

# 执行多轮测试
Run-MultiRoundTest -Files $validFiles
