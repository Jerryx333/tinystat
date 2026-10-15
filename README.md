# TinyStat

[中文](README.md) | [English](README.en.md)

只看需要的 CPU、GPU、内存和温度：一个原生、轻量的 macOS 菜单栏监控工具。

## 为什么做它

完整的系统监控工具常带有用不到的面板和后台任务。TinyStat 把常用读数放在菜单栏，点击展开紧凑概览，鼠标移出收起；CPU/GPU 与内存详情合并，不必来回打开多个窗口。

- CPU 与 GPU 分别显示温度，结合系统热状态和内存压力提示当前负担。
- 进程前五名可切换 CPU / 内存，更多指标默认收起。
- 收起时每 10 秒刷新；展开默认每 5 秒。GPU、进程和每核指标按可见页面采集。
- Swift + AppKit + 小型 C 读取桥接，只有系统框架，无网络请求或第三方运行时。

## 当前状态

**早期可用版本，兼容性验证仍有限。** 面向 Apple Silicon / macOS 13+；实机验证仅覆盖 M1 Max / macOS 26.4，其他系统版本只是编译目标、尚未实测；CPU/GPU 温度映射仅覆盖 M1 系列。其他型号温度会显示不可用，不猜测传感器。

不是 iStat Menus 的完整替代：没有网速、磁盘、天气、风扇控制或通知。尚无经过 Apple 公证的下载包，当前从源码构建。不同系统版本可能影响未公开的只读传感器接口。

应用包约 0.3 MB。短时参考测试中，收起 CPU 约 0.06%–0.10%（单核 100%），可见页面约 0.20%–0.37%；这些是开发阶段测量，**不是每台机器的保证**。热使用后常驻内存仍有优化空间。测法、口径和限制见[性能说明](docs/performance.md)。

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
```

欢迎提供可复现的问题、传感器适配和性能改进。请不要附带密钥、完整进程列表或私人窗口截图。阅读[贡献指南](CONTRIBUTING.md)。

计划中的姊妹项目：[TinyBar](https://github.com/Jerryx333/tinybar)，专注菜单栏项目管理，目前处于设计阶段。

许可证：[Apache-2.0](LICENSE)，Copyright 2026 Jerry。
