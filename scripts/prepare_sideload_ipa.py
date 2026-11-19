#!/usr/bin/env python3
"""把 `flutter build ios --no-codesign` 的产物打成可直接交给签名工具重签的 IPA。

第三方签名工具（全能签 / Sideloadly / Esign 等）对**嵌套扩展**（.appex）非常挑剔：
主 App 签名了、扩展没签或签错，安装阶段就会失败；而扩展强依赖 App Group，
共享证书/企业证书通常没有 App Group capability。所以这里提供两种模式：

  full  保留 VeriFinWidgets + ShareExtension。仅当签名用的描述文件
        显式包含 App Groups（group.top.talyra42.verifin）时可用。
  lite  删除全部 .appex，主 App 独立签名。小组件与分享入口失效，
        但记账、预算、报表、备份、CSV、AI、OCR、应用锁全部正常。
        兼容任何证书（含免费个人证书、通配符企业证书）。

用法：
  python3 scripts/prepare_sideload_ipa.py --app build/ios/iphoneos/Runner.app --mode lite
  python3 scripts/prepare_sideload_ipa.py --ipa build/ios/verifin-ios-unsigned.ipa --mode full
  python3 scripts/prepare_sideload_ipa.py --app ... --mode lite --bundle-id com.yourteam.verifin
"""

from __future__ import annotations

import argparse
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

APP_GROUP = "group.top.talyra42.verifin"
REQUIRED_KEYS = ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleVersion")


def fail(message: str) -> None:
    print(f"[error] {message}", file=sys.stderr)
    sys.exit(1)


def info(message: str) -> None:
    print(f"[info] {message}")


def read_plist(path: Path) -> dict:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def write_plist(path: Path, payload: dict) -> None:
    with path.open("wb") as handle:
        plistlib.dump(payload, handle, sort_keys=False)


def validate_app(app: Path) -> dict:
    """校验 bundle 结构完整性，返回主 App 的 Info.plist。"""
    plist_path = app / "Info.plist"
    if not plist_path.is_file():
        fail(f"找不到 {plist_path}")
    plist = read_plist(plist_path)
    missing = [key for key in REQUIRED_KEYS if not plist.get(key)]
    if missing:
        fail(f"Info.plist 缺少字段: {', '.join(missing)}")
    executable = app / plist["CFBundleExecutable"]
    if not executable.is_file():
        fail(f"可执行文件缺失: {executable}")
    if not (app / "Frameworks" / "App.framework").is_dir():
        fail("Frameworks/App.framework 缺失，这不像 Flutter 构建产物")
    if (app / "_CodeSignature").exists():
        info("检测到 _CodeSignature：这是已签名包，重签前建议使用 --no-codesign 产物")
    return plist


def list_extensions(app: Path) -> list[Path]:
    plugins = app / "PlugIns"
    if not plugins.is_dir():
        return []
    return sorted(plugins.glob("*.appex"))


def apply_bundle_id(app: Path, bundle_id: str) -> None:
    """把主 App 与其扩展的 bundle id 统一改前缀。

    仅在 full 模式下对扩展有意义；lite 模式扩展已删除。
    扩展 id 必须为主 id 的后缀，否则 iOS 拒绝嵌入。
    """
    plist_path = app / "Info.plist"
    plist = read_plist(plist_path)
    old = plist["CFBundleIdentifier"]
    plist["CFBundleIdentifier"] = bundle_id
    write_plist(plist_path, plist)
    info(f"bundle id: {old} -> {bundle_id}")

    for appex in list_extensions(app):
        appex_plist_path = appex / "Info.plist"
        appex_plist = read_plist(appex_plist_path)
        suffix = appex_plist["CFBundleIdentifier"].removeprefix(old)
        new_id = f"{bundle_id}{suffix}"
        appex_plist["CFBundleIdentifier"] = new_id
        write_plist(appex_plist_path, appex_plist)
        info(f"extension {appex.name}: -> {new_id}")
        if not new_id.startswith(f"{bundle_id}."):
            fail(f"扩展 id {new_id} 不是主 id 的子域，iOS 会拒绝嵌入")


def strip_extensions(app: Path, keep: set[str]) -> list[str]:
    removed: list[str] = []
    for appex in list_extensions(app):
        if appex.stem in keep:
            info(f"保留扩展: {appex.stem}")
            continue
        shutil.rmtree(appex)
        removed.append(appex.stem)
        info(f"移除扩展: {appex.stem}")
    plugins = app / "PlugIns"
    if plugins.is_dir() and not any(plugins.iterdir()):
        plugins.rmdir()
    return removed


def package(app: Path, out_dir: Path, name: str) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / name
    if target.exists():
        target.unlink()
    with tempfile.TemporaryDirectory() as tmp:
        payload = Path(tmp) / "Payload"
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        subprocess.run(
            ["zip", "-qry", str(target), "Payload", "-x", "*.DS_Store"],
            cwd=tmp,
            check=True,
        )
    return target


def stage(source: Path, work_dir: Path) -> Path:
    """把源 bundle 复制到工作目录，后续所有改动都落在副本上。

    这样 lite 模式删除扩展不会破坏 CI 里的原始构建产物，
    两个模式可以在同一次构建里连续执行。
    """
    payload = work_dir / "Payload"
    payload.mkdir()
    staged = payload / source.name
    shutil.copytree(source, staged, symlinks=True)
    return staged


def emit(app: Path, out_dir: Path, name: str) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / name
    if target.exists():
        target.unlink()
    subprocess.run(
        ["zip", "-qry", str(target), "Payload", "-x", "*.DS_Store"],
        cwd=app.parent.parent,
        check=True,
    )
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description="生成可重签的 iOS IPA")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--app", type=Path, help="Runner.app 目录")
    source.add_argument("--ipa", type=Path, help="已有 IPA（将重新打包）")
    parser.add_argument("--mode", choices=("lite", "full"), default="lite")
    parser.add_argument("--bundle-id", help="覆盖主 App bundle id（扩展自动跟随）")
    parser.add_argument(
        "--keep-extension",
        action="append",
        default=[],
        choices=("VeriFinWidgets", "ShareExtension"),
        help="lite 模式下保留的扩展（需要描述文件支持 App Group）",
    )
    parser.add_argument("--out-dir", type=Path, default=Path("build/ios/ipa"))
    parser.add_argument("--name", help="输出文件名，默认按模式命名")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as extract_dir, \
            tempfile.TemporaryDirectory() as work_dir:
        if args.ipa:
            info(f"解包 {args.ipa}")
            with zipfile.ZipFile(args.ipa) as archive:
                archive.extractall(extract_dir)
            apps = sorted(Path(extract_dir).glob("Payload/*.app"))
            if not apps:
                fail("IPA 内找不到 Payload/*.app")
            app = stage(apps[0], Path(work_dir))
        else:
            origin = args.app.resolve()
            if not origin.is_dir():
                fail(f"{origin} 不存在")
            app = stage(origin, Path(work_dir))

        plist = validate_app(app)
        extensions = list_extensions(app)
        info(f"应用: {app.name}  版本: {plist.get('CFBundleShortVersionString', '?')} "
             f"({plist['CFBundleVersion']})")
        info(f"扩展: {', '.join(e.stem for e in extensions) or '无'}")

        if args.mode == "lite":
            removed = strip_extensions(app, set(args.keep_extension))
            if removed:
                info(f"已移除 {len(removed)} 个扩展 -> 无需签名嵌套 bundle")
        else:
            if not extensions:
                info("未发现扩展，full 与 lite 等价")
            info(f"full 模式要求描述文件包含 App Group: {APP_GROUP}")

        if args.bundle_id:
            if args.mode == "full" and extensions:
                info("提示：改 bundle id 后 App Group 名不会自动变化，"
                     f"描述文件里的 group 仍须为 {APP_GROUP}")
            apply_bundle_id(app, args.bundle_id)

        name = args.name or f"verifin-{args.mode}.ipa"
        target = emit(app, args.out_dir.resolve(), name)

    size = target.stat().st_size / (1024 * 1024)
    print()
    print(f"[done] {target}  ({size:.1f} MiB)")
    print("[next] 把这个文件导入全能签 -> 选择证书 -> 签名安装")


if __name__ == "__main__":
    main()
