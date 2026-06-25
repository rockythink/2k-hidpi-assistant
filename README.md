# 2K HiDPI 助手

一个 macOS 菜单栏工具，用来解决 2K / 2.5K 外接显示器在 macOS 上缩放尴尬的问题。

痛点：

- 原生 2K 分辨率：字体和 UI 太小。
- 普通 1080p：尺寸舒服，但不是 HiDPI，文字发糊。
- 理想状态：macOS 使用更高 framebuffer 渲染，再缩放到 2K / 2.5K 面板，兼顾尺寸和清晰度。

当前版本只使用 macOS 已经暴露的真实显示模式，不做 EDID override，不创建虚拟显示器，也不改亮度、输入源或其他显示器硬件状态。

## 功能

- 检测外接显示器和当前显示模式
- 判断屏幕类型：2K、2.5K、4K+、低于 2K
- 列出 macOS 当前可切换的 HiDPI 模式
- 给 2K / 2.5K 屏推荐更舒服的 HiDPI 档位
- 切换后 15 秒确认，否则自动恢复
- 跳转 macOS 原生显示设置
- 中英文界面

## 运行

```bash
./script/build_and_run.sh
```

验证启动：

```bash
./script/build_and_run.sh --verify
```

## 边界

如果一台干净 Mac 没有暴露 HiDPI 模式，本工具不会强行生成新模式。增强版可考虑 EDID override 或虚拟显示器方案，但那会带来更高权限、兼容性和回滚风险。
