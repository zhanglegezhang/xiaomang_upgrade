# 小蟒通用升级工具 1.2

用于将标准便携版小蟒 2.6 起的 2.x 升级到 **2.13 或后续支持启动确认的版本**。无需安装或注册输入法组件。

## 使用

1. Code → Download ZIP，完整解压到旧小蟒目录之外。
2. 从 https://github.com/zhanglegezhang/xiaomang/releases/tag/v2.13-20261019 下载使用包 ZIP，不解压该包。
3. 保存并关闭日记和输入法设置、结束录音录屏。
4. 双击 Upgrade.cmd，选择旧 xiaomang.exe、目标使用包，输入标签 v2.13-20261019。
5. 等待官方 SHA256 核验、备份、替换和数据加载确认；完成后主窗口自动恢复。

脚本即源码，可直接运行，要求 Windows PowerShell 5.1 和 GitHub 网络连接。

## 数据保护与限制

- 没有输入法组件不拦截；有残留配置则原样备份。
- 退出后再备份实际数据并逐文件核验；启动后确认目录、待办、收藏和关键设置加载，不以进程存在代替成功。
- 失败时恢复程序及备份原文件；旧目录与已安装组件保留，不重新注册系统组件。
- 备份：%LOCALAPPDATA%\XiaomangUpdates\universal-随机编号。attempt/final-data-backup.zip 中的条目与 data-snapshot.json 一起用于恢复；另保留 old-app-backup.zip、input-data-backup.zip 和日志。备份含个人数据，请勿上传。
- 不支持降级、同版重装、跨大版本、自定义 PersonalPath.cfg、网络或链接目录。目标 2.11 及更早包不支持启动确认，会在替换前拒绝。
- 大量数据会增加备份时间和空间；断电或强制结束可能需要人工恢复。

## 验证和开发

在本机独立目录验证真实 2.9 升级：无组件（含残留输入配置）、已有 OCR 组件两种场景，保留待办、收藏、设置；失败启动回退。非干净 Windows 或其他物理电脑测试；未改动系统组件注册。2.13 发布使用包也执行同样回归。

编辑 Upgrade.ps1、Core.ps1、VersionReader.cs、install.ps1、XiaomangUpdateRecovery.ps1 即可开发；install.ps1 从 source/ProductUpdateInstaller.cs 的 Script 提取。许可 GPL-3.0，见 LICENSE.txt；上游项目 https://github.com/zhanglegezhang/xiaomang 。详见使用说明.txt。

本次目标程序 2.13 修复启动时新增剪贴板记录被误判为原数据丢失的问题。校验在监听开始前完成；工具保留备份、启动确认及失败回退协议。该修复位于目标主程序，不能通过工具修正旧目标包。

恢复脚本使用兼容 Windows PowerShell 5.1 的 UTF-8 BOM 编码。程序文件占用会触发回退；原数据变化或备份不一致时保留现场，不强行覆盖。
