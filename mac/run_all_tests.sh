#!/bin/zsh

# 运行所有 SMB 测试

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "${BLUE}========================================${NC}"
echo "${BLUE}   SMB 自动化测试套件${NC}"
echo "${BLUE}========================================${NC}"
echo ""

total_success=0
total_fail=0

# 测试 1: 基础上传测试
echo "${BLUE}>>> 测试 1: 文件上传 MD5 校验${NC}"
if ./smb_test.sh; then
    echo "${GREEN}[通过]${NC} 测试 1"
    ((total_success++))
else
    echo "${RED}[失败]${NC} 测试 1"
    ((total_fail++))
fi
echo ""

# 测试 2: 文本文件修改测试
echo "${BLUE}>>> 测试 2: 文本文件修改${NC}"
if ./smb_test_modify.sh; then
    echo "${GREEN}[通过]${NC} 测试 2"
    ((total_success++))
else
    echo "${RED}[失败]${NC} 测试 2"
    ((total_fail++))
fi
echo ""

# 总结
echo "${BLUE}========================================${NC}"
echo "总测试数: $((total_success + total_fail))"
echo "${GREEN}通过: $total_success${NC}"
echo "${RED}失败: $total_fail${NC}"
echo "${BLUE}========================================${NC}"

[[ $total_fail -eq 0 ]] && exit 0 || exit 1
