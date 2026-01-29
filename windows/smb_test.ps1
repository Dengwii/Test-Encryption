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
    if (-not (Test-Path $REPORT_DIR)) {
        New-Item -ItemType Directory -Path $REPORT_DIR -Force | Out-Null
    }

    $script:ReportTime = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:CsvFile = Join-Path $REPORT_DIR "report_$ReportTime.csv"
    $script:HtmlFile = Join-Path $REPORT_DIR "report_$ReportTime.html"

    # CSV 表头
    $header = "文件名"
    for ($i = 1; $i -le $UPLOAD_ROUNDS; $i++) {
        $header += ",第${i}次-大小,第${i}次-MD5,第${i}次-通过"
    }
    $header | Out-File -FilePath $CsvFile -Encoding utf8

    # HTML 开头
    $htmlHead = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SMB 上传测试报告</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .info { color: #666; margin-bottom: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f5f5f5; }
        .pass { background-color: #d4edda; color: #155724; }
        .fail { background-color: #f8d7da; color: #721c24; }
        .size { font-size: 0.9em; color: #666; }
        .md5 { font-family: Consolas, monospace; font-size: 0.85em; }
    </style>
</head>
<body>
<h1>SMB 上传测试报告</h1>
<div class='info'>
<p>测试时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p>SMB 服务器: \\$SMB_HOST\$SMB_SHARE</p>
<p>上传方式: $UPLOAD_METHOD | 上传轮数: $UPLOAD_ROUNDS</p>
</div>
<table>
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
        }
    }

    # 获取远程文件信息
    $remoteItem = Join-Path $RemotePath $itemName
    $sizeHuman = Get-FileSize -Path $remoteItem
    $sizeBytes = Get-FileSizeBytes -Path $remoteItem

    # 验证
    $verifyResult = Verify-Upload -LocalPath $LocalPath -RemotePath $RemotePath

    if ($verifyResult.Success) {
        return @{
            SizeHuman = $sizeHuman
            SizeBytes = $sizeBytes
            MD5 = $verifyResult.MD5
            Status = "pass"
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

        foreach ($file in $Files) {
            $itemName = Split-Path $file -Leaf
            $key = "${itemName}_$round"

            Write-Info "上传: $itemName"

            $result = Upload-AndVerify -LocalPath $file -RemotePath "$driveLetter\"
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

    foreach ($file in $Files) {
        $itemName = Split-Path $file -Leaf
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
            $icon = if ($result.Status -eq "pass") { "✓" } else { "✗" }
            $safeMD5 = $result.MD5 -replace '<', '&lt;' -replace '>', '&gt;'

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

    Finalize-Report

    Write-Host ""
    Write-Host "========================================"
    Write-Success "测试完成！报告已生成："
    Write-Host "  CSV: $CsvFile"
    Write-Host "  HTML: $HtmlFile"
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
Initialize-Report

# 执行多轮测试
Run-MultiRoundTest -Files $validFiles
