# SMB 测试配置文件
# 所有测试脚本共享此配置

# ========== SMB 连接配置 ==========
$SMB_HOST = "10.0.0.72"
$SMB_USER = "casaos"
$SMB_PASSWORD = "casaos"
$SMB_SHARE = "HDD-Storage123/3211/alpha118/win"

# 完整的 UNC 路径 (会自动生成)
$SMB_PATH = "\\$SMB_HOST\$($SMB_SHARE -replace '/', '\')"

# ========== 测试文件配置 ==========

# 上传方式:
# - "shell"     : 使用 Shell.Application COM 对象 (模拟资源管理器复制，推荐)
# - "robocopy"  : 使用 robocopy 命令 (Windows 自带，可靠但非 GUI)
# - "xcopy"     : 使用 xcopy 命令 (兼容性好)
$UPLOAD_METHOD = "shell"

# 上传次数: 同一个样本集重复上传的次数
$UPLOAD_ROUNDS = 2

# 每轮上传前是否删除之前上传的文件
# - $true  : 每轮上传前先删除远程已存在的同名文件/目录
# - $false : 保留之前的文件，直接覆盖上传
$DELETE_BEFORE_UPLOAD = $false

# 每轮上传是否使用独立文件夹
# - $true  : 每轮上传到 round_1/, round_2/ 等独立文件夹，保留所有轮次的文件
# - $false : 所有轮次上传到同一位置
# 注意: 启用此选项时，$DELETE_BEFORE_UPLOAD 仅删除当前轮次文件夹内的文件
$SEPARATE_ROUND_FOLDERS = $true

# 测试报告输出目录
$REPORT_DIR = ".\reports"

# 测试文件列表
# 支持：单文件路径、目录路径
$UPLOAD_FILES = @(
    "D:\Downloads\Beyond_Compare_5.0.2.30045_64bit_Green\BCompare"
    # "C:\Users\YourName\Downloads\test.zip"
    # "C:\Users\YourName\Documents\testfolder"
)

# ========== 颜色输出函数 ==========
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Error2 { param($msg) Write-Host "[X] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "[*] $msg" -ForegroundColor Yellow }
