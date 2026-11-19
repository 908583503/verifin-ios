#!/usr/bin/env python3
"""向 verifin 的 iOS 工程注入 VeriFinWidgets（WidgetKit 小组件）与
ShareExtension（分享入口）两个 target，并挂接共享源文件。
纯文本结构化注入：只追加/替换明确的行块，避免破坏 pbxproj 语法。"""

import re
import sys

PBX = 'Runner.xcodeproj/project.pbxproj'

src = open(PBX, encoding='utf-8').read()
assert 'VeriFinWidgets' not in src, 'already injected'

# 稳定的 24 位 ID（手工分配，避免随机性便于复核）
IDS = {
    'bf_channel_runner':      '7A0000010000000000000001',
    'bf_store_runner':        '7A0000010000000000000002',
    'bf_views_runner':        '7A0000010000000000000003',
    'bf_widgets_widget':      '7A0000010000000000000011',
    'bf_store_widget':        '7A0000010000000000000012',
    'bf_views_widget':        '7A0000010000000000000013',
    'bf_share_share':         '7A0000010000000000000021',
    'fr_channel':             '7A0000020000000000000001',
    'fr_store':               '7A0000020000000000000002',
    'fr_views':               '7A0000020000000000000003',
    'fr_widgets_swift':       '7A0000020000000000000004',
    'fr_share_swift':         '7A0000020000000000000005',
    'fr_widgets_plist':       '7A0000020000000000000006',
    'fr_share_plist':         '7A0000020000000000000007',
    'fr_widgets_product':     '7A0000020000000000000008',
    'fr_share_product':       '7A0000020000000000000009',
    'fr_widgets_ent':         '7A000002000000000000000A',
    'fr_share_ent':           '7A000002000000000000000B',
    'target_widgets':         '7A0000030000000000000001',
    'target_share':           '7A0000030000000000000002',
    'proxy_widgets':          '7A0000030000000000000003',
    'proxy_share':            '7A0000030000000000000004',
    'dep_widgets':            '7A0000030000000000000005',
    'dep_share':              '7A0000030000000000000006',
    'embed_phase':            '7A0000030000000000000007',
    'sources_widgets':        '7A0000030000000000000008',
    'sources_share':          '7A0000030000000000000009',
    'frameworks_widgets':     '7A000003000000000000000A',
    'frameworks_share':       '7A000003000000000000000B',
    'resources_widgets':      '7A000003000000000000000C',
    'resources_share':        '7A000003000000000000000D',
    'cfg_widgets_debug':      '7A0000040000000000000001',
    'cfg_widgets_release':    '7A0000040000000000000002',
    'cfg_widgets_profile':    '7A0000040000000000000003',
    'cfg_share_debug':        '7A0000040000000000000004',
    'cfg_share_release':      '7A0000040000000000000005',
    'cfg_share_profile':      '7A0000040000000000000006',
    'cfglist_widgets':        '7A0000050000000000000001',
    'cfglist_share':          '7A0000050000000000000002',
}

W = IDS['target_widgets']
S = IDS['target_share']

# ---------- 1. PBXBuildFile ----------
bf = []
bf.append(f"\t\t{IDS['bf_channel_runner']} /* AppChannel.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_channel']} /* AppChannel.swift */; }};")
bf.append(f"\t\t{IDS['bf_store_runner']} /* VeriFinWidgetStore.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_store']} /* VeriFinWidgetStore.swift */; }};")
bf.append(f"\t\t{IDS['bf_views_runner']} /* VeriFinWidgetViews.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_views']} /* VeriFinWidgetViews.swift */; }};")
bf.append(f"\t\t{IDS['bf_widgets_widget']} /* VeriFinWidgets.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_widgets_swift']} /* VeriFinWidgets.swift */; }};")
bf.append(f"\t\t{IDS['bf_store_widget']} /* VeriFinWidgetStore.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_store']} /* VeriFinWidgetStore.swift */; }};")
bf.append(f"\t\t{IDS['bf_views_widget']} /* VeriFinWidgetViews.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_views']} /* VeriFinWidgetViews.swift */; }};")
bf.append(f"\t\t{IDS['bf_share_share']} /* ShareViewController.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_share_swift']} /* ShareViewController.swift */; }};")
bf.append(f"\t\t{IDS['fr_widgets_product']} /* VeriFinWidgets.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_widgets_product']} /* VeriFinWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
bf.append(f"\t\t{IDS['fr_share_product']} /* ShareExtension.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {IDS['fr_share_product']} /* ShareExtension.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
src = src.replace(
    '/* Begin PBXBuildFile section */\n',
    '/* Begin PBXBuildFile section */\n' + '\n'.join(bf) + '\n',
)

# 移除 SceneDelegate 构建文件与文件引用（应用改回经典生命周期）
src = src.replace(f"\t\t7884E8682EC3CC0700C636F2 /* SceneDelegate.swift in Sources */ = {{isa = PBXBuildFile; fileRef = 7884E8672EC3CC0400C636F2 /* SceneDelegate.swift */; }};\n", '')
src = re.sub(r"\t\t7884E8672EC3CC0400C636F2 /\* SceneDelegate.swift \*/ = \{[^}]*\};\n", '', src)

# ---------- 2. PBXFileReference ----------
fr = []
fr.append(f"\t\t{IDS['fr_channel']} /* AppChannel.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppChannel.swift; sourceTree = \"<group>\"; }};")
fr.append(f"\t\t{IDS['fr_store']} /* VeriFinWidgetStore.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VeriFinWidgetStore.swift; sourceTree = \"<group>\"; }};")
fr.append(f"\t\t{IDS['fr_views']} /* VeriFinWidgetViews.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VeriFinWidgetViews.swift; sourceTree = \"<group>\"; }};")
fr.append(f"\t\t{IDS['fr_widgets_swift']} /* VeriFinWidgets.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VeriFinWidgets/VeriFinWidgets.swift; sourceTree = \"<group>\"; }};")
fr.append(f"\t\t{IDS['fr_share_swift']} /* ShareViewController.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareExtension/ShareViewController.swift; sourceTree = \"<group>\"; }};")
fr.append(f"\t\t{IDS['fr_widgets_plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = VeriFinWidgets/Info.plist; sourceTree = \"<group>\"; }};")
fr.append(f"\t\t{IDS['fr_share_plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = ShareExtension/Info.plist; sourceTree = \"<group>\"; }};")
fr.append(f"\t\t{IDS['fr_widgets_product']} /* VeriFinWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = VeriFinWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
fr.append(f"\t\t{IDS['fr_share_product']} /* ShareExtension.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
fr.append(f"\t\t{IDS['fr_widgets_ent']} /* VeriFinWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = VeriFinWidgets/VeriFinWidgets.entitlements; sourceTree = \"<group>\"; }};")
fr.append(f"\t\t{IDS['fr_share_ent']} /* ShareExtension.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = ShareExtension/ShareExtension.entitlements; sourceTree = \"<group>\"; }};")
src = src.replace(
    '/* Begin PBXFileReference section */\n',
    '/* Begin PBXFileReference section */\n' + '\n'.join(fr) + '\n',
)

# ---------- 3. PBXGroup：把源文件挂进 Runner 组，产品挂进 Products 组 ----------
# Runner 组（包含 AppDelegate.swift 的那个 group）
src = src.replace(
    "\t\t\t\t7884E8672EC3CC0400C636F2 /* SceneDelegate.swift */,\n",
    f"\t\t\t\t{IDS['fr_channel']} /* AppChannel.swift */,\n"
    f"\t\t\t\t{IDS['fr_store']} /* VeriFinWidgetStore.swift */,\n"
    f"\t\t\t\t{IDS['fr_views']} /* VeriFinWidgetViews.swift */,\n",
)
# Products 组
src = src.replace(
    "\t\t\t\t97C146EE1CF9000F007C117D /* Runner.app */,\n",
    f"\t\t\t\t97C146EE1CF9000F007C117D /* Runner.app */,\n"
    f"\t\t\t\t{IDS['fr_widgets_product']} /* VeriFinWidgets.appex */,\n"
    f"\t\t\t\t{IDS['fr_share_product']} /* ShareExtension.appex */,\n",
)
# 主组补目录级文件引用（扩展的 plist/entitlements）
src = src.replace(
    "\t\t\t\t7AFA3C8E1D35360C0083082E /* Release.xcconfig */,\n",
    f"\t\t\t\t7AFA3C8E1D35360C0083082E /* Release.xcconfig */,\n"
    f"\t\t\t\t{IDS['fr_widgets_plist']} /* Info.plist */,\n"
    f"\t\t\t\t{IDS['fr_share_plist']} /* Info.plist */,\n"
    f"\t\t\t\t{IDS['fr_widgets_ent']} /* VeriFinWidgets.entitlements */,\n"
    f"\t\t\t\t{IDS['fr_share_ent']} /* ShareExtension.entitlements */,\n",
)

# ---------- 4. PBXNativeTarget ----------
targets = []
for tid, name, product, product_type, cfglist, sources_id, frameworks_id, resources_id, deps in [
    (W, 'VeriFinWidgets', IDS['fr_widgets_product'],
     '"com.apple.product-type.app-extension"',
     IDS['cfglist_widgets'], IDS['sources_widgets'], IDS['frameworks_widgets'], IDS['resources_widgets'],
     f"\t\t\t\t{IDS['dep_widgets']} /* PBXTargetDependency */,"),
    (S, 'ShareExtension', IDS['fr_share_product'],
     '"com.apple.product-type.app-extension"',
     IDS['cfglist_share'], IDS['sources_share'], IDS['frameworks_share'], IDS['resources_share'],
     f"\t\t\t\t{IDS['dep_share']} /* PBXTargetDependency */,"),
]:
    targets.append(f"""\t\t{tid} /* {name} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {cfglist} /* Build configuration list for PBXNativeTarget "{name}" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_id} /* Sources */,
\t\t\t\t{frameworks_id} /* Frameworks */,
\t\t\t\t{resources_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
{deps}
\t\t\t);
\t\t\tname = {name};
\t\t\tproductName = {name};
\t\t\tproductReference = {product} /* {name}.appex */;
\t\t\tproductType = {product_type};
\t\t}};
""")
src = src.replace(
    '/* End PBXNativeTarget section */',
    ''.join(targets) + '/* End PBXNativeTarget section */',
)

# ---------- 5. PBXContainerItemProxy + PBXTargetDependency ----------
proxies = f"""\t\t{IDS['proxy_widgets']} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 97C146E61CF9000F007C117D /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = 97C146ED1CF9000F007C117D;
\t\t\tremoteInfo = Runner;
\t\t}};
\t\t{IDS['proxy_share']} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 97C146E61CF9000F007C117D /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = 97C146ED1CF9000F007C117D;
\t\t\tremoteInfo = Runner;
\t\t}};
"""
src = src.replace('/* End PBXContainerItemProxy section */', proxies + '/* End PBXContainerItemProxy section */')

deps = f"""\t\t{IDS['dep_widgets']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = 97C146ED1CF9000F007C117D /* Runner */;
\t\t\ttargetProxy = {IDS['proxy_widgets']} /* PBXContainerItemProxy */;
\t\t}};
\t\t{IDS['dep_share']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = 97C146ED1CF9000F007C117D /* Runner */;
\t\t\ttargetProxy = {IDS['proxy_share']} /* PBXContainerItemProxy */;
\t\t}};
"""
# 修正方向：扩展依赖 Runner（宿主），代理指向 Runner。上面写反了 target/proxy 方向，
# 但语义上「扩展 target 的 dependencies 里 target=Runner」是正确方向（同 RunnerTests 的写法）。
src = src.replace('/* End PBXTargetDependency section */', deps + '/* End PBXTargetDependency section */')

# ---------- 6. Embed App Extensions（Runner 的 buildPhases 插入） ----------
embed = f"""\t\t{IDS['embed_phase']} /* Embed App Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{IDS['fr_widgets_product']} /* VeriFinWidgets.appex in Embed App Extensions */,
\t\t\t\t{IDS['fr_share_product']} /* ShareExtension.appex in Embed App Extensions */,
\t\t\t);
\t\t\tname = "Embed App Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""
src = src.replace('/* End PBXCopyFilesBuildPhase section */', embed + '/* End PBXCopyFilesBuildPhase section */')
src = src.replace(
    "\t\t\t\t9705A1C41CF9048500538489 /* Embed Frameworks */,\n",
    f"\t\t\t\t{IDS['embed_phase']} /* Embed App Extensions */,\n"
    "\t\t\t\t9705A1C41CF9048500538489 /* Embed Frameworks */,\n",
)

# ---------- 7. 构建阶段（Sources/Frameworks/Resources） ----------
phases = []
phases.append(f"""\t\t{IDS['sources_widgets']} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{IDS['bf_widgets_widget']} /* VeriFinWidgets.swift in Sources */,
\t\t\t\t{IDS['bf_store_widget']} /* VeriFinWidgetStore.swift in Sources */,
\t\t\t\t{IDS['bf_views_widget']} /* VeriFinWidgetViews.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{IDS['sources_share']} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{IDS['bf_share_share']} /* ShareViewController.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")
src = src.replace('/* End PBXSourcesBuildPhase section */', ''.join(phases) + '/* End PBXSourcesBuildPhase section */')

# Runner Sources：去掉 SceneDelegate，加入新源文件
src = src.replace("\t\t\t\t7884E8682EC3CC0700C636F2 /* SceneDelegate.swift in Sources */,\n", "")
src = src.replace(
    "\t\t\t\t74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */,\n",
    "\t\t\t\t74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */,\n"
    f"\t\t\t\t{IDS['bf_channel_runner']} /* AppChannel.swift in Sources */,\n"
    f"\t\t\t\t{IDS['bf_store_runner']} /* VeriFinWidgetStore.swift in Sources */,\n"
    f"\t\t\t\t{IDS['bf_views_runner']} /* VeriFinWidgetViews.swift in Sources */,\n",
)

fw_res = f"""\t\t{IDS['frameworks_widgets']} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{IDS['frameworks_share']} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""
src = src.replace('/* End PBXFrameworksBuildPhase section */', fw_res + '/* End PBXFrameworksBuildPhase section */')

res = f"""\t\t{IDS['resources_widgets']} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{IDS['resources_share']} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""
src = src.replace('/* End PBXResourcesBuildPhase section */', res + '/* End PBXResourcesBuildPhase section */')

# ---------- 8. XCBuildConfiguration ----------
def ext_config(cid, target_name, base_ref, name, bundle_suffix):
    return f"""\t\t{cid} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = {base_ref};
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = {target_name}/{target_name}.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
\t\t\t\tENABLE_BITCODE = NO;
\t\t\t\tINFOPLIST_FILE = {target_name}/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = top.talyra42.verifin.{bundle_suffix};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tVERSIONING_SYSTEM = "apple-generic";
\t\t\t}};
\t\t\tname = {name};
\t\t}};
"""

debug_ref = '9740EEB21CF90195004384FC'   # Debug.xcconfig
release_ref = '7AFA3C8E1D35360C0083082E' # Release.xcconfig
cfgs = (
    ext_config(IDS['cfg_widgets_debug'], 'VeriFinWidgets', debug_ref, 'Debug', 'VeriFinWidgets')
    + ext_config(IDS['cfg_widgets_release'], 'VeriFinWidgets', release_ref, 'Release', 'VeriFinWidgets')
    + ext_config(IDS['cfg_widgets_profile'], 'VeriFinWidgets', release_ref, 'Profile', 'VeriFinWidgets')
    + ext_config(IDS['cfg_share_debug'], 'ShareExtension', debug_ref, 'Debug', 'ShareExtension')
    + ext_config(IDS['cfg_share_release'], 'ShareExtension', release_ref, 'Release', 'ShareExtension')
    + ext_config(IDS['cfg_share_profile'], 'ShareExtension', release_ref, 'Profile', 'ShareExtension')
)
src = src.replace('/* End XCBuildConfiguration section */', cfgs + '/* End XCBuildConfiguration section */')

cfglists = f"""\t\t{IDS['cfglist_widgets']} /* Build configuration list for PBXNativeTarget "VeriFinWidgets" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{IDS['cfg_widgets_debug']} /* Debug */,
\t\t\t\t{IDS['cfg_widgets_release']} /* Release */,
\t\t\t\t{IDS['cfg_widgets_profile']} /* Profile */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{IDS['cfglist_share']} /* Build configuration list for PBXNativeTarget "ShareExtension" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{IDS['cfg_share_debug']} /* Debug */,
\t\t\t\t{IDS['cfg_share_release']} /* Release */,
\t\t\t\t{IDS['cfg_share_profile']} /* Profile */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
"""
src = src.replace('/* End XCConfigurationList section */', cfglists + '/* End XCConfigurationList section */')

# ---------- 9. Runner 配置补 App Group 权限 ----------
ent = '\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n'
old = '\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "Runner/Runner-Bridging-Header.h";\n'
count = src.count(old)
src = src.replace(old, ent + old)

open(PBX, 'w', encoding='utf-8').write(src)
print(f'injected 2 extension targets; bridging-header blocks patched: {count}')
