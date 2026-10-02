# 裂隙猎人 · Time Hunter Offline

以《时空猎人》的横版刷图体验为玩法参考，制作可离线运行的 **Android 原创单机格斗游戏**。当前是 **v0.1.0 可玩原型**：一名角色、一张地图和三波战斗，包含最终 Boss。使用原创矢量画面与合成音效，没有原游戏代码、角色素材或服务器依赖。目前只开发 Android，暂不生成 iOS 代码或打包配置。

![战斗画面](docs/combat.png)

## 当前内容

- 刃锋：三段普通攻击、第三击浮空、瞬斩突进、裂隙范围爆发。
- 横屏触屏摇杆与多点触控，可以同时移动、攻击和施放技能。
- 跳跃躲避攻击，生命值、能量恢复、技能冷却与连击计分。
- 近战机械兵、远程机械兵与带落点预警的裂隙守卫 Boss。
- 生命拾取、胜负结算、晶币强化、最高分与本机存档。
- 暂停、返回基地、静音；应用切到后台后自动暂停。
- Android APK 导出配置、签名验证脚本、GitHub Actions 构建流程。

## 安装与平台状态

Android 调试 APK 已在 macOS 构建并通过签名和 Manifest 检查。支持 Android 7.0（API 24）及以上、ARM64 / ARMv7；实际性能仍需在手机上测试。APK 没有 INTERNET、存储、相机或麦克风权限。首次安装时，在手机系统中允许对应文件管理器安装应用，再打开 APK。

GitHub 构建成功后，可在 Actions 的 `Android APK` 运行记录中下载 `rift-hunter-android-debug` Artifact，解压获得 APK。调试签名用于个人测试；正式发布需配置自己的稳定签名密钥。CI 每次生成新的调试密钥，跨次构建的 APK 可能不能直接覆盖安装；本机脚本保留 `.tools/debug.keystore` 以便后续覆盖更新。

详见 [Android 打包说明](docs/mobile-build.md)。

## 开发运行

使用 **Godot 4.5.2 Standard**（GDScript，不需要 .NET）打开 `project.godot`，按 F6 / F5 运行。导出模板需与引擎版本一致。

```sh
godot --path .
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/run_tests.gd
```

键盘调试：WASD / 方向键移动，J 攻击，K 瞬斩，L 裂隙爆发，空格跳跃，Esc 暂停，Enter 出击。

## 项目结构

```text
project.godot         Godot 工程入口
scenes/main.tscn     主场景
scripts/arena_model.gd  战斗状态、判定、敌人 AI、波次
scripts/fighter.gd      角色状态
scripts/main.gd         画面、HUD、触屏输入、音效
scripts/save_store.gd   存档与强化
tests/run_tests.gd      31 项战斗 / 存档检查
tests/capture.gd        图形运行与多点触控检查、截图
tools/build_android.py 测试、APK 导出与签名验证
export_presets.cfg     Android 导出预设
```

## 验证边界与后续开发

已完成 Godot 4.5.2 导入与运行、31 项逻辑检查、桌面图形运行和触控事件检查、Android APK 导出及 v2/v3 签名验证。桌面触控事件检查不能替代手机真机测试，GitHub Actions 也需以实际运行结果为准。

后续可逐步扩展职业、角色动画、装备掉落、更多地图、剧情和音效，并优化 Android 真机表现。当前原型采用几何角色与固定镜头，不具备原作完整内容量与美术表现。

字体和引擎许可见 [第三方说明](docs/third-party.md)。
