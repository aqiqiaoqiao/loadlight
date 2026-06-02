# LoadLight

macOS 菜单栏 CPU/GPU 负载指示灯。闲置 🟢 绿灯，高负载 🔴 红灯呼吸。

## 功能

- 实时监控 CPU 和 GPU 使用率
- CPU > 70% 或 GPU > 70% 触发红灯呼吸动画
- 负载回落自动恢复绿灯（连续 3 次采样确认，避免抖动）
- 点击菜单栏图标查看详细读数
- macOS 13+

## 安装

```bash
git clone https://github.com/aqiqiaoqiao/loadlight.git
cd loadlight
./build.sh --run
```

或手动构建：

```bash
swift build -c release
cp .build/release/LoadLight /Applications/
```

启动后会在菜单栏右侧出现绿色圆点。

## 使用

- **绿色常亮**：系统空闲
- **红色呼吸**：CPU 或 GPU 超过 70%
- **点击图标**：弹出菜单显示 CPU/GPU 精确读数和当前状态

菜单栏提示文本也会实时显示负载百分比。

## 技术细节

- Swift 5.9 + AppKit，无第三方依赖
- CPU 采样：`host_statistics()` 获取 kernel ticks
- GPU 采样：IOKit `IOAccelerator` 服务读取 `Device Utilization %`
- 图标：24×24 NSImage，径向渐变 + 环形光晕，呼吸动画 30fps
- 不对称去抖：绿→红即时响应，红→绿需连续 3 次每 1 秒确认

## 退出

点击菜单栏图标 → Quit，或 `pkill LoadLight`。
