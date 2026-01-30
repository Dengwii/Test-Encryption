#!/bin/zsh

# SMB 测试配置文件
# 所有测试脚本共享此配置

# ========== SMB 连接配置 ==========
SMB_HOST="10.0.0.72"
SMB_USER="casaos"
SMB_PASSWORD="casaos"
SMB_SHARE="HDD-Storage123/3211/alpha118/mac"

# ========== 测试文件配置 ==========

# 上传方式: applescript, gui, pyautogui, quartz
# - applescript: Finder duplicate 命令，自动覆盖（推荐）
# - gui: System Events 模拟 Cmd+C/V，会弹出冲突对话框（需要辅助功能权限）
# - pyautogui: Python PyAutoGUI（需要 pip3 install pyautogui）
# - quartz: Python Quartz（需要 pip3 install pyobjc-framework-Quartz）
UPLOAD_METHOD="applescript"

# 上传模式: "batch"=批量一起复制, "sequential"=逐个轮流复制
UPLOAD_MODE="batch"

# 上传次数: 同一个样本集重复上传的次数
UPLOAD_ROUNDS=50

# 每轮上传前是否删除之前上传的文件
# - true  : 每轮上传前先删除远程已存在的同名文件/目录
# - false : 保留之前的文件，直接覆盖上传
DELETE_BEFORE_UPLOAD=false

# 每轮上传是否使用独立文件夹
# - true  : 每轮上传到 timestamp_round_1/, timestamp_round_2/ 等独立文件夹，保留所有轮次的文件
# - false : 所有轮次上传到同一位置
# 注意: 启用此选项时，DELETE_BEFORE_UPLOAD 仅删除当前轮次文件夹内的文件
SEPARATE_ROUND_FOLDERS=true

# 测试报告输出目录
REPORT_DIR="./reports"

# 测试 1: 基础上传测试的文件列表
# 支持：单文件路径、多个文件路径、目录路径（保留目录结构）
UPLOAD_FILES=(
    "/Users/zimaos/Downloads/测试样本集mac"
    # "/path/to/file2.pdf"
    # "/path/to/some_directory"    # 目录会自动展开
)

# 测试 2: 文本文件修改测试的文件列表
MODIFY_FILES=(
    # "/Users/zimaos/Downloads/test.txt"
    # "/path/to/config.yaml"
    # "/path/to/README.md"
)

# ========== 通用配置 ==========

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 通用函数
success() { echo "${GREEN}✓${NC} $1"; }
error() { echo "${RED}✗${NC} $1"; }
info() { echo "${YELLOW}•${NC} $1"; }

