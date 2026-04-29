# CHANGELOG

本文档记录项目的主要变更历史。

格式说明：
- 按日期倒序排列（最新的在最上面）
- 使用 Conventional Commits 规范分类
- 中英文混排时保持空格

---

## 2026-04-29

### Bug 修复 (Fixes)
- fix(tools): 修复 build.sh 硬编码 NCS_ENV 路径, 替换为 $ROOT_DIR 相对路径

### 文档更新 (Documentation)
- docs: 补充 nRF5 SDK Linux 入门文档中 nvm/node 安装步骤, 移除 xpm 安装的 sudo

### 其他变更 (Others)
- chore: .gitignore 新增 tmp*/ 忽略规则

---

## 2026-04-22

### 新功能 (Features)
- feat(board): 新增 meshtastic_v1 (nRF52840) 板级支持，含 board.h, board.mk, board.cmake, pinconfig.c

### 其他变更 (Others)
- chore(tools): 新增 .github/tools/shell/build.sh 一键编译烧录脚本
- chore: 新增 .github/.gitignore 忽略配置
- docs: 新增 .github/docs/ 开发文档（SDK 入门, UF2 指南, RTT 调试, DFU 方式）
- chore: 新增 .github/prompts/release.prompt.md 版本提交提示词

---
