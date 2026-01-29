# SMB 加密文件夹测试工具

自动化测试工具，验证 SMB 加密文件夹的文件上传、修改操作是否会导致 MD5 不一致或文件损坏。

## 支持平台

| 平台 | 状态 | 说明 |
|------|------|------|
| macOS | ✅ 已完成 | Shell 脚本 (zsh) |
| Windows | 🚧 开发中 | PowerShell 脚本 |

## 项目结构

```
smb-encryption-test/
├── README.md           # 本文件
├── mac/                # macOS 版本
│   ├── config.sh       # 配置文件
│   ├── lib.sh          # 通用函数库
│   ├── smb_test.sh     # 上传 + MD5 校验
│   ├── smb_test_modify.sh  # 文件修改测试
│   ├── run_all_tests.sh    # 运行所有测试
│   └── reports/        # 测试报告输出
└── windows/            # Windows 版本
    ├── config.ps1      # 配置文件
    ├── lib.ps1         # 通用函数库
    └── smb_test.ps1    # 上传测试
```

## 测试场景

1. **上传校验** - 文件上传到 SMB 加密文件夹后，MD5 是否一致
2. **修改校验** - 在 SMB 上修改文件后，文件是否完整
3. **多轮测试** - 多次上传同一文件，验证一致性

## 快速开始

### macOS

```bash
cd mac
# 编辑配置
vim config.sh

# 运行测试
./smb_test.sh
```

### Windows

```powershell
cd windows
# 编辑配置
notepad config.ps1

# 运行测试
.\smb_test.ps1
```

## 测试报告

测试完成后会生成：
- **CSV 报告** - 便于数据分析
- **HTML 报告** - 可视化展示，自动打开

## 许可证

MIT License
