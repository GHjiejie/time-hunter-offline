#!/usr/bin/env python3
"""Build a signed debug APK with Godot 4.5.2 and an existing Android SDK."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def editor_data_dir(executable: Path) -> Path:
    for ancestor in executable.parents:
        if ancestor.suffix == ".app":
            marker = ancestor / "Contents/MacOS/._sc_"
            if marker.exists() or marker.with_name("_sc_").exists():
                return ancestor.parent / "editor_data"
    if any((executable.parent / name).exists() for name in ("_sc_", "._sc_")):
        return executable.parent / "editor_data"
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/Godot"
    if sys.platform == "win32":
        return Path(os.environ["APPDATA"]) / "Godot"
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "godot"


def configure_settings(directory: Path, java: Path, sdk: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    settings = directory / "editor_settings-4.5.tres"
    content = settings.read_text() if settings.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    for key, value in {"export/android/java_sdk_path": str(java), "export/android/android_sdk_path": str(sdk)}.items():
        line = key + " = " + json.dumps(value)
        pattern = re.compile(r"^" + re.escape(key) + r"\s*=.*$", re.MULTILINE)
        if pattern.search(content):
            content = pattern.sub(lambda _match: line, content)
        else:
            content += "\n" + line + "\n"
    settings.write_text(content)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", shutil.which("godot")))
    parser.add_argument("--java-home", default=os.environ.get("JAVA_HOME"))
    parser.add_argument("--sdk", default=os.environ.get("ANDROID_SDK_ROOT", os.environ.get("ANDROID_HOME")))
    parser.add_argument("--editor-data", help="Override the Godot editor settings directory")
    parser.add_argument("--output", default=str(ROOT / "build/android/rift-hunter-debug.apk"))
    args = parser.parse_args()
    if not all((args.godot, args.java_home, args.sdk)):
        parser.error("Provide --godot, --java-home and --sdk, or GODOT_BIN / JAVA_HOME / ANDROID_SDK_ROOT.")
    godot = Path(args.godot).expanduser().resolve()
    java = Path(args.java_home).expanduser().resolve()
    sdk = Path(args.sdk).expanduser().resolve()
    suffix = ".exe" if sys.platform == "win32" else ""
    for required in [godot, java / ("bin/java" + suffix), java / ("bin/keytool" + suffix), sdk / ("platform-tools/adb" + suffix), sdk / "build-tools/35.0.1"]:
        if not required.exists():
            parser.error(f"Missing build dependency: {required}")
    version = subprocess.check_output([str(godot), "--version"], text=True).strip()
    if not version.startswith("4.5.2."):
        parser.error("This project is pinned to Godot 4.5.2 with matching export templates.")
    configure_settings(Path(args.editor_data) if args.editor_data else editor_data_dir(godot), java, sdk)
    tools = ROOT / ".tools"
    tools.mkdir(exist_ok=True)
    keystore = tools / "debug.keystore"
    env = dict(os.environ, JAVA_HOME=str(java))
    if not keystore.exists():
        subprocess.run([str(java / ("bin/keytool" + suffix)), "-genkeypair", "-keystore", str(keystore), "-alias", "androiddebugkey", "-storepass", "android", "-keypass", "android", "-dname", "CN=Android Debug,O=Android,C=US", "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000"], env=env, check=True)
    env.update(GODOT_ANDROID_KEYSTORE_DEBUG_PATH=str(keystore), GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey", GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android")
    output = Path(args.output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(godot), "--headless", "--path", str(ROOT), "--editor", "--import", "--quit"], env=env, check=True)
    for test_script in ("res://tests/run_tests.gd", "res://tests/skill_buffer_test.gd"):
        subprocess.run([str(godot), "--headless", "--path", str(ROOT), "--script", test_script], env=env, check=True)
    subprocess.run([str(godot), "--headless", "--path", str(ROOT), "--export-debug", "Android", str(output)], env=env, check=True)
    if not output.exists():
        raise SystemExit("Godot did not produce an APK.")
    signer = sdk / ("build-tools/35.0.1/apksigner.bat" if sys.platform == "win32" else "build-tools/35.0.1/apksigner")
    subprocess.run([str(signer), "verify", "--verbose", str(output)], env=env, check=True)
    print(f"Signed debug APK: {output} ({output.stat().st_size / 1024 / 1024:.1f} MiB)")


if __name__ == "__main__":
    main()
