# Android 打包

## Android APK

准备 Godot 4.5.2 Standard 和对应 Export Templates、OpenJDK 17、Android SDK。SDK 需要 `platform-tools`、`platforms;android-35` 与 `build-tools;35.0.1`。本项目使用预编译 APK 模板，不需要自编译引擎或安装 NDK。

```sh
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.1"
python3 tools/build_android.py \
  --godot /path/to/godot \
  --java-home /path/to/jdk17 \
  --sdk /path/to/android-sdk
```

macOS 的 `--godot` 可指向 `Godot.app/Contents/MacOS/Godot`。脚本自动定位普通或便携版编辑器配置，修改 Java / Android SDK 路径，保留其他配置。必要时使用 `--editor-data` 明确指定配置目录。

脚本先导入资源并运行测试，再导出 `build/android/rift-hunter-debug.apk`，最后使用 `apksigner verify` 验证签名。调试密钥位于 `.tools/debug.keystore`，已被 Git 忽略。更换调试密钥会影响已有安装的覆盖更新；卸载游戏会删除本机进度。

正式发行时应在 Godot 导出界面配置自己的 Release Keystore，并导出 Release APK；如上传 Google Play，则需使用 Gradle Build 生成 AAB。请自行保管签名密钥，勿将证书或密码提交到 Git。

## 官方参考

- [Godot 4.5 Android 导出](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_android.html)
