# TinyStat

[中文](README.md) | [English](README.en.md)

只看需要的 CPU、GPU、内存和温度：一个原生、轻量的 macOS 菜单栏监控工具。

## 为什么做它

TinyStat 把 CPU、GPU、内存与温度放在眼前。想知道为什么升高，在底部直接提问：助手带上本次读数和主要进程，解释依据，再由你决定处理哪些。

- 三张不可点击的指标卡片；发送问题后进入独立聊天窗口，收起菜单不丢对话。
- 每次检查可展开具体进程、采样时间和覆盖范围，区分事实、推测与未知。
- 支持本机 Codex / Claude Code，也可设置兼容服务商；API 密钥保存在 Keychain。
- 操作卡片支持正常退出已识别的应用，以及把你选择的普通文件移到废纸篓。执行前确认，执行后保留回执并重新采样。
- 不提问时没有模型调用。原生 Swift + AppKit，GPU 使用率持续保留历史、温度按需采集，窗口关闭时每 5 秒刷新、打开后每 2 秒刷新。

## 当前状态

**早期可用版本，兼容性验证仍有限。** 面向 Apple Silicon / macOS 13+；实机验证仅覆盖 M1 Max / macOS 26.4，其他系统版本只是编译目标、尚未实测；CPU/GPU 温度取已映射 M1 SMC 传感器最高有效值，不含 HID；映射在 M1 Max 上核验为 CPU 33 项、GPU 9 项，缺项以 `*` 标记。其他型号温度会显示不可用，不猜测传感器。

不是 iStat Menus 的完整替代：没有网速、磁盘、天气、风扇控制或通知。尚无经过 Apple 公证的下载包，当前从源码构建。不同系统版本可能影响未公开的只读传感器接口。

应用包约 0.5 MB，不包含外部 agent CLI。旧版监控性能数据不能代表聊天时的开销；模型请求期间会临时启动 CLI，结束或取消后回收进程组。测法与历史数据见[性能说明](docs/performance.md)。

## 开始使用

需要 Apple Command Line Tools（`xcode-select --install`）和 Apple Silicon Mac。

```sh
git clone https://github.com/Jerryx333/tinystat.git
cd tinystat
bash scripts/build.sh
bash scripts/install.sh
open "$HOME/Applications/TinyStat.app"
```

安装到个人 Applications 目录；更新前退出 TinyStat。已有版本会备份，不需要管理员权限。不会替你退出其他监控工具或开启登录启动。

菜单栏首次放在右侧可见区域；按住 Command 拖动可调整，重启记住位置。Ice 等管理器仍可将它隐藏。[使用、指标口径与卸载](docs/guide.zh-CN.md)。

## 开发与贡献

```sh
bash scripts/check.sh       # 构建、签名与文档检查；适用于 CI
bash scripts/verify.sh      # 真机传感器与采样检查，需要 M1 Max
bash scripts/verify-assistant.sh # 不联网的助手与操作边界检查
```

欢迎提供可复现的问题、传感器适配和性能改进。请不要附带密钥、完整进程列表或私人窗口截图。阅读[贡献指南](CONTRIBUTING.md)。

计划中的姊妹项目：[TinyBar](https://github.com/Jerryx333/tinybar)，专注菜单栏项目管理，目前处于设计阶段。

许可证：[Apache-2.0](LICENSE)，Copyright 2026 Jerry。
