# SMB 测试通用函数库

# ============================================================
# SMB 连接函数
# ============================================================

# 连接 SMB 共享 (映射网络驱动器)
# 返回: 驱动器盘符 (如 "Z:")
function Connect-SMB {
    # 先检查是否已连接
    $existing = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot -like "*$SMB_HOST*" } | Select-Object -First 1
    if ($existing) {
        Write-Info "发现已有连接: $($existing.Name):"
        return "$($existing.Name):"
    }

    # 寻找可用盘符 (从 Z 往前找)
    $driveLetter = $null
    for ($i = 90; $i -ge 68; $i--) {  # Z to D
        $letter = [char]$i
        if (-not (Test-Path "${letter}:")) {
            $driveLetter = "${letter}:"
            break
        }
    }

    if (-not $driveLetter) {
        Write-Error2 "没有可用的盘符"
        return $null
    }

    # 使用 net use 连接 (比 New-PSDrive 更接近真实操作)
    $result = & net use $driveLetter $SMB_PATH /user:$SMB_USER $SMB_PASSWORD 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Info "已连接: $driveLetter -> $SMB_PATH"
        return $driveLetter
    } else {
        Write-Error2 "连接失败: $result"
        return $null
    }
}

# 断开 SMB 连接
function Disconnect-SMB {
    param([string]$DriveLetter)

    if ($DriveLetter) {
        & net use $DriveLetter /delete /y 2>&1 | Out-Null
    }
}

# ============================================================
# MD5 计算函数
# ============================================================

function Get-FileMD5 {
    param([string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        return $null
    }

    # 方式1: 标准 Get-FileHash (使用 LiteralPath 避免通配符问题)
    try {
        $hash = Get-FileHash -LiteralPath $FilePath -Algorithm MD5
        return $hash.Hash.ToLower()
    } catch {
        # 被杀毒软件拦截, 回退到直接读取字节流
    }

    # 方式2: 用 FileStream 直接读取 (绕过部分杀毒拦截)
    try {
        $stream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $md5 = [System.Security.Cryptography.MD5]::Create()
            $hashBytes = $md5.ComputeHash($stream)
            return [BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
        } finally {
            $stream.Close()
        }
    } catch {
        # 仍然失败, 尝试 certutil
    }

    # 方式3: 用 certutil 计算 (系统工具, 有时不受拦截)
    try {
        $output = & certutil -hashfile $FilePath MD5 2>&1
        if ($LASTEXITCODE -eq 0) {
            $hashLine = $output | Where-Object { $_ -match '^[0-9a-fA-F\s]+$' } | Select-Object -First 1
            if ($hashLine) {
                return ($hashLine -replace '\s', '').ToLower()
            }
        }
    } catch {}

    Write-Warning "无法计算MD5 (被杀毒软件拦截): $FilePath"
    return $null
}

# ============================================================
# 字节对比函数 (类似 cmp -l)
# ============================================================

# 对比两个文件的字节差异，返回前 N 个差异
function Compare-FileBytes {
    param(
        [string]$File1,
        [string]$File2,
        [int]$MaxDiffs = 5
    )

    $result = @{
        File1 = $File1
        File2 = $File2
        File1Size = 0
        File2Size = 0
        Differences = @()
        TotalDiffs = 0
        Error = $null
    }

    # 检查文件是否存在
    if (-not (Test-Path -LiteralPath $File1 -PathType Leaf)) {
        $result.Error = "文件1不存在: $File1"
        return $result
    }
    if (-not (Test-Path -LiteralPath $File2 -PathType Leaf)) {
        $result.Error = "文件2不存在: $File2"
        return $result
    }

    try {
        $result.File1Size = (Get-Item -LiteralPath $File1).Length
        $result.File2Size = (Get-Item -LiteralPath $File2).Length

        $stream1 = [System.IO.File]::Open($File1, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $stream2 = [System.IO.File]::Open($File2, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

        try {
            $bufferSize = 4096
            $buffer1 = New-Object byte[] $bufferSize
            $buffer2 = New-Object byte[] $bufferSize
            $position = 0
            $diffCount = 0
            $foundDiffs = @()

            $minSize = [Math]::Min($result.File1Size, $result.File2Size)

            while ($position -lt $minSize -and $foundDiffs.Count -lt $MaxDiffs) {
                $toRead = [Math]::Min($bufferSize, $minSize - $position)
                $read1 = $stream1.Read($buffer1, 0, $toRead)
                $read2 = $stream2.Read($buffer2, 0, $toRead)

                for ($i = 0; $i -lt $read1 -and $foundDiffs.Count -lt $MaxDiffs; $i++) {
                    if ($buffer1[$i] -ne $buffer2[$i]) {
                        $diffCount++
                        $foundDiffs += @{
                            Offset = $position + $i
                            Byte1 = $buffer1[$i]
                            Byte2 = $buffer2[$i]
                        }
                    }
                }
                $position += $read1
            }

            # 继续统计剩余差异数量 (不记录详情)
            while ($position -lt $minSize) {
                $toRead = [Math]::Min($bufferSize, $minSize - $position)
                $read1 = $stream1.Read($buffer1, 0, $toRead)
                $read2 = $stream2.Read($buffer2, 0, $toRead)

                for ($i = 0; $i -lt $read1; $i++) {
                    if ($buffer1[$i] -ne $buffer2[$i]) {
                        $diffCount++
                    }
                }
                $position += $read1
            }

            $result.Differences = $foundDiffs
            $result.TotalDiffs = $diffCount

            # 如果文件大小不同，额外的字节也算差异
            if ($result.File1Size -ne $result.File2Size) {
                $result.TotalDiffs += [Math]::Abs($result.File1Size - $result.File2Size)
            }

        } finally {
            $stream1.Close()
            $stream2.Close()
        }
    } catch {
        $result.Error = "对比失败: $_"
    }

    return $result
}

# 格式化字节对比结果为文本
function Format-ByteCompareResult {
    param(
        $CompareResult,
        [string]$SmbDisplayPath = ""
    )

    # 如果提供了 SMB 显示路径，使用它替代实际的目标文件路径
    $displayFile2 = if ($SmbDisplayPath) { $SmbDisplayPath } else { $CompareResult.File2 }

    $lines = @()
    $lines += "=" * 60
    $lines += "文件字节对比报告"
    $lines += "=" * 60
    $lines += ""
    $lines += "源文件: $($CompareResult.File1)"
    $lines += "目标文件: $displayFile2"
    $lines += ""
    $lines += "源文件大小: $($CompareResult.File1Size) 字节"
    $lines += "目标文件大小: $($CompareResult.File2Size) 字节"

    if ($CompareResult.File1Size -ne $CompareResult.File2Size) {
        $diff = $CompareResult.File2Size - $CompareResult.File1Size
        $lines += "大小差异: $(if ($diff -gt 0) { "+$diff" } else { $diff }) 字节"
    }

    $lines += ""

    if ($CompareResult.Error) {
        $lines += "错误: $($CompareResult.Error)"
    } elseif ($CompareResult.TotalDiffs -eq 0) {
        $lines += "结果: 文件完全相同"
    } else {
        $lines += "总差异字节数: $($CompareResult.TotalDiffs)"
        $lines += ""
        $lines += "前 $($CompareResult.Differences.Count) 个差异位置:"
        $lines += "-" * 50
        $lines += "{0,-15} {1,-12} {2,-12}" -f "偏移量(十进制)", "源文件", "目标文件"
        $lines += "-" * 50

        foreach ($diff in $CompareResult.Differences) {
            $hex1 = "0x{0:X2}" -f $diff.Byte1
            $hex2 = "0x{0:X2}" -f $diff.Byte2
            $char1 = if ($diff.Byte1 -ge 32 -and $diff.Byte1 -le 126) { [char]$diff.Byte1 } else { "." }
            $char2 = if ($diff.Byte2 -ge 32 -and $diff.Byte2 -le 126) { [char]$diff.Byte2 } else { "." }
            $lines += "{0,-15} {1,-5} ({2}) {3,-5} ({4})" -f $diff.Offset, $hex1, $char1, $hex2, $char2
        }
    }

    $lines += ""
    $lines += "=" * 60

    return $lines -join "`r`n"
}

# ============================================================
# 文件大小函数
# ============================================================

# 获取人类可读的文件大小
function Get-FileSize {
    param([string]$Path)

    if (Test-Path $Path -PathType Leaf) {
        $size = (Get-Item $Path).Length
    } elseif (Test-Path $Path -PathType Container) {
        $size = (Get-ChildItem $Path -Recurse -File | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $size) { $size = 0 }
    } else {
        return "0B"
    }

    if ($size -ge 1GB) { return "{0:N2}GB" -f ($size / 1GB) }
    if ($size -ge 1MB) { return "{0:N2}MB" -f ($size / 1MB) }
    if ($size -ge 1KB) { return "{0:N2}KB" -f ($size / 1KB) }
    return "${size}B"
}

# 获取精确字节数
function Get-FileSizeBytes {
    param([string]$Path)

    if (Test-Path $Path -PathType Leaf) {
        return (Get-Item $Path).Length
    } elseif (Test-Path $Path -PathType Container) {
        $size = (Get-ChildItem $Path -Recurse -File | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $size) { return 0 }
        return $size
    }
    return 0
}

# ============================================================
# 上传函数 - 使用 Shell.Application (模拟资源管理器)
# ============================================================

function Copy-FileWithShell {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path $Source)) {
        Write-Error2 "文件不存在: $Source"
        return $false
    }

    try {
        $shell = New-Object -ComObject Shell.Application

        # Shell.NameSpace 对网络路径有时需要等待，重试几次
        $destinationFolder = $null
        for ($retry = 0; $retry -lt 5; $retry++) {
            $destinationFolder = $shell.NameSpace($Destination)
            if ($null -ne $destinationFolder) { break }
            Start-Sleep -Milliseconds 500
        }

        if ($null -eq $destinationFolder) {
            Write-Error2 "无法访问目标文件夹: $Destination"
            return $false
        }

        # 复制标志: 16 = 对所有对话框回答"是", 4 = 不显示进度对话框
        $copyFlags = 20

        $destinationFolder.CopyHere($Source, $copyFlags)

        # 等待复制完成 (Shell.CopyHere 是异步的)
        $itemName = Split-Path $Source -Leaf
        $targetPath = Join-Path $Destination $itemName
        $isDir = Test-Path $Source -PathType Container

        $timeout = 600  # 最多等待 600 秒
        $waited = 0

        if ($isDir) {
            # 目录复制: 等待所有文件都可访问
            $sourceFiles = Get-ChildItem $Source -Recurse -File
            $sourceFileCount = $sourceFiles.Count

            while ($waited -lt $timeout) {
                Start-Sleep -Seconds 2
                $waited += 2

                if (-not (Test-Path -LiteralPath $targetPath)) { continue }

                # 检查目标目录中的文件数量
                try {
                    $targetFiles = Get-ChildItem -LiteralPath $targetPath -Recurse -File -ErrorAction Stop
                    $targetFileCount = $targetFiles.Count

                    if ($targetFileCount -ge $sourceFileCount) {
                        # 文件数量匹配，再等待确保所有文件都可读
                        Start-Sleep -Seconds 3

                        # 尝试读取每个文件确认可访问
                        $allAccessible = $true
                        foreach ($tf in $targetFiles) {
                            try {
                                $null = Get-Item -LiteralPath $tf.FullName -ErrorAction Stop
                            } catch {
                                $allAccessible = $false
                                break
                            }
                        }

                        if ($allAccessible) {
                            return $true
                        }
                    }
                } catch {
                    # 目录还在复制中，继续等待
                }
            }
        } else {
            # 单文件复制
            while ($waited -lt $timeout) {
                Start-Sleep -Milliseconds 500
                $waited += 0.5

                if (Test-Path -LiteralPath $targetPath) {
                    # 检查文件是否可读 (不再被占用)
                    try {
                        $fileInfo = Get-Item -LiteralPath $targetPath -ErrorAction Stop
                        # 尝试打开文件确认不被占用
                        $stream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                        $stream.Close()
                        Start-Sleep -Seconds 1
                        return $true
                    } catch {
                        # 文件还在复制中
                    }
                }
            }
        }

        Write-Error2 "复制超时"
        return $false

    } catch {
        Write-Error2 "Shell 复制失败: $_"
        return $false
    }
}

# ============================================================
# 上传函数 - 使用 robocopy (Windows 自带)
# ============================================================

function Copy-FileWithRobocopy {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path $Source)) {
        Write-Error2 "文件不存在: $Source"
        return $false
    }

    $isDir = Test-Path $Source -PathType Container

    if ($isDir) {
        # 目录复制
        $itemName = Split-Path $Source -Leaf
        $targetDir = Join-Path $Destination $itemName
        $result = & robocopy $Source $targetDir /E /NFL /NDL /NJH /NJS /nc /ns /np 2>&1
    } else {
        # 单文件复制
        $sourceDir = Split-Path $Source -Parent
        $fileName = Split-Path $Source -Leaf
        $result = & robocopy $sourceDir $Destination $fileName /NFL /NDL /NJH /NJS /nc /ns /np 2>&1
    }

    # robocopy 返回值: 0-7 表示成功
    if ($LASTEXITCODE -le 7) {
        return $true
    } else {
        Write-Error2 "robocopy 失败 (代码: $LASTEXITCODE)"
        return $false
    }
}

# ============================================================
# 上传函数 - 使用 xcopy (兼容性好)
# ============================================================

function Copy-FileWithXcopy {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path $Source)) {
        Write-Error2 "文件不存在: $Source"
        return $false
    }

    $isDir = Test-Path $Source -PathType Container

    if ($isDir) {
        $itemName = Split-Path $Source -Leaf
        $targetDir = Join-Path $Destination $itemName
        # /E = 复制目录和子目录, /I = 假定目标是目录, /Y = 覆盖确认, /Q = 安静模式
        $result = & xcopy $Source $targetDir /E /I /Y /Q 2>&1
    } else {
        # /Y = 覆盖确认, /Q = 安静模式
        $result = & xcopy $Source $Destination /Y /Q 2>&1
    }

    return $LASTEXITCODE -eq 0
}

# ============================================================
# 通用上传入口
# ============================================================

function Upload-File {
    param(
        [string]$Source,
        [string]$Destination
    )

    switch ($UPLOAD_METHOD) {
        "shell" {
            return Copy-FileWithShell -Source $Source -Destination $Destination
        }
        "robocopy" {
            return Copy-FileWithRobocopy -Source $Source -Destination $Destination
        }
        "xcopy" {
            return Copy-FileWithXcopy -Source $Source -Destination $Destination
        }
        default {
            return Copy-FileWithShell -Source $Source -Destination $Destination
        }
    }
}

# ============================================================
# 验证函数
# ============================================================

function Verify-Upload {
    param(
        [string]$LocalPath,
        [string]$RemotePath
    )

    $itemName = Split-Path $LocalPath -Leaf
    $remoteItem = Join-Path $RemotePath $itemName

    if (Test-Path $LocalPath -PathType Leaf) {
        # 单文件验证
        $localMD5 = Get-FileMD5 -FilePath $LocalPath
        $remoteMD5 = Get-FileMD5 -FilePath $remoteItem

        if ($null -eq $localMD5) { return @{ Success = $false; Message = "无法计算本地MD5"; LocalFile = $LocalPath; RemoteFile = $remoteItem } }
        if ($null -eq $remoteMD5) { return @{ Success = $false; Message = "无法计算远程MD5"; LocalFile = $LocalPath; RemoteFile = $remoteItem } }

        if ($localMD5 -eq $remoteMD5) {
            return @{ Success = $true; MD5 = $remoteMD5 }
        } else {
            return @{ Success = $false; Message = "MD5不匹配"; LocalMD5 = $localMD5; RemoteMD5 = $remoteMD5; LocalFile = $LocalPath; RemoteFile = $remoteItem }
        }
    } elseif (Test-Path $LocalPath -PathType Container) {
        # 目录验证
        $files = Get-ChildItem $LocalPath -Recurse -File
        $failCount = 0
        $totalCount = 0
        $firstMD5 = $null
        $fileDetails = @()

        foreach ($file in $files) {
            $totalCount++
            $relativePath = $file.FullName.Substring($LocalPath.Length).TrimStart('\')
            $remoteFile = Join-Path $remoteItem $relativePath

            $localMD5 = Get-FileMD5 -FilePath $file.FullName
            $remoteMD5 = Get-FileMD5 -FilePath $remoteFile

            if ($null -eq $firstMD5 -and $null -ne $localMD5) {
                $firstMD5 = $localMD5
            }

            $matched = ($localMD5 -eq $remoteMD5) -and ($null -ne $localMD5)
            if (-not $matched) {
                $failCount++
            }

            $fileDetails += @{
                RelativePath = $relativePath
                LocalFile = $file.FullName
                RemoteFile = $remoteFile
                LocalMD5 = $localMD5
                RemoteMD5 = $remoteMD5
                Matched = $matched
                SizeBytes = $file.Length
            }
        }

        if ($failCount -eq 0) {
            return @{ Success = $true; MD5 = $firstMD5; TotalFiles = $totalCount; FileDetails = $fileDetails }
        } else {
            return @{ Success = $false; Message = "$failCount/$totalCount 不匹配"; MD5 = $firstMD5; FileDetails = $fileDetails }
        }
    }

    return @{ Success = $false; Message = "路径不存在" }
}
