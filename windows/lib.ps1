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

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        return $null
    }

    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm MD5
        return $hash.Hash.ToLower()
    } catch {
        return $null
    }
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
        $destinationFolder = $shell.NameSpace($Destination)

        if ($null -eq $destinationFolder) {
            Write-Error2 "无法访问目标文件夹: $Destination"
            return $false
        }

        # 复制标志: 16 = 对所有对话框回答"是", 4 = 不显示进度对话框
        # 如果想看到进度对话框，把 20 改成 16
        $copyFlags = 20

        $destinationFolder.CopyHere($Source, $copyFlags)

        # 等待复制完成 (Shell.CopyHere 是异步的)
        $itemName = Split-Path $Source -Leaf
        $targetPath = Join-Path $Destination $itemName

        $timeout = 300  # 最多等待 300 秒
        $waited = 0
        while ($waited -lt $timeout) {
            Start-Sleep -Milliseconds 500
            $waited += 0.5

            # 检查文件是否存在且可访问
            if (Test-Path $targetPath) {
                # 再等一下确保复制完成
                Start-Sleep -Seconds 1
                return $true
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

        if ($null -eq $localMD5) { return @{ Success = $false; Message = "无法计算本地MD5" } }
        if ($null -eq $remoteMD5) { return @{ Success = $false; Message = "无法计算远程MD5" } }

        if ($localMD5 -eq $remoteMD5) {
            return @{ Success = $true; MD5 = $remoteMD5 }
        } else {
            return @{ Success = $false; Message = "MD5不匹配"; LocalMD5 = $localMD5; RemoteMD5 = $remoteMD5 }
        }
    } elseif (Test-Path $LocalPath -PathType Container) {
        # 目录验证
        $files = Get-ChildItem $LocalPath -Recurse -File
        $failCount = 0
        $totalCount = 0
        $firstMD5 = $null

        foreach ($file in $files) {
            $totalCount++
            $relativePath = $file.FullName.Substring($LocalPath.Length).TrimStart('\')
            $remoteFile = Join-Path $remoteItem $relativePath

            $localMD5 = Get-FileMD5 -FilePath $file.FullName
            $remoteMD5 = Get-FileMD5 -FilePath $remoteFile

            if ($null -eq $firstMD5 -and $null -ne $localMD5) {
                $firstMD5 = $localMD5
            }

            if ($localMD5 -ne $remoteMD5) {
                $failCount++
            }
        }

        if ($failCount -eq 0) {
            return @{ Success = $true; MD5 = $firstMD5; TotalFiles = $totalCount }
        } else {
            return @{ Success = $false; Message = "$failCount/$totalCount 不匹配"; MD5 = $firstMD5 }
        }
    }

    return @{ Success = $false; Message = "路径不存在" }
}
