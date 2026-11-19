# 用全能签安装 VeriFin（从源码到手机）

本文假设你已经有全能签和可用证书，缺的只是一个能签的 IPA。全程不需要 Mac。

---

## 0. 先决定签哪个包

工程会产出两个 IPA，区别只在「两个系统扩展」是否保留：

| | **lite（推荐先试这个）** | **full** |
|---|---|---|
| 桌面小组件（4 种模板） | ✗ 不可用 | ✓ |
| 系统分享面板「存到 VeriFin」 | ✗ 不可用 | ✓ |
| 记账 / 多账本 / 预算 / 报表 / 图表 | ✓ | ✓ |
| WebDAV + 本地备份 / 恢复 | ✓ | ✓ |
| CSV 导入导出 | ✓ | ✓ |
| AI 记账 / OCR 识图 | ✓ | ✓ |
| 应用锁 + 面容 ID | ✓ | ✓ |
| 通知提醒 | ✓ | ✓ |
| **证书要求** | 任何证书都能签 | 描述文件必须含 App Groups |
| 签名工具要求 | 无 | 必须支持「扩展一并重签」 |

> 为什么必须二选一：`App Group`（`group.top.talyra42.verifin`）是小组件与主 App 交换数据的唯一通道，它属于 **capability**，必须由 Apple 在描述文件里授予。企业证书和共享证书的 profile 几乎都不含它，此时带扩展的包会在安装阶段被系统拒绝（报「无法安装」或装完闪退）。lite 包把那两个 `.appex` 直接删掉，就绕开了整条依赖链。

**先签 lite 把 App 跑起来**，确认账号数据、备份、AI 都正常；只有在你确认自己的证书带 App Group 时，再回头折腾 full。

---

## 1. 拿到 IPA

### 路线 A：GitHub Actions（没有 Mac 就走这条）

1. 在 GitHub 新建一个仓库（**建议 Public** —— public 仓库的 macOS runner 完全免费；private 仓库每月 2000 分钟额度、macOS 按 10 倍计费，只够跑十来次）。
2. 把 `verifin-ios-port/` 整个目录推上去，确保 `.github/workflows/ios-build.yml` 也在里面。

   > 仓库里还有上游自带的两个 workflow（`ci.yml`、`flutter.yml`），它们跑的是 Android 侧的检查与打包，与本次签名无关。push 之后看到它们自动运行、甚至红了，都不影响 iOS 构建；嫌吵可以直接删掉这两个文件。

3. 仓库页面 → **Actions** → 左侧 **iOS Build** → 右侧 **Run workflow** → 绿色按钮。
4. 等 15–25 分钟（首次要装 CocoaPods 依赖，会慢一些）。
5. 构建成功后点进这次运行，页面底部 **Artifacts** 里下载 **verifin-lite-ipa**（是个 zip，解压后得到 `verifin-lite.ipa`）。
6. 把 ipa 传到手机：AirDrop、iCloud Drive、或者微信「文件传输助手」都行（微信里点开 → 用其他应用打开 → 存到「文件」）。

如果构建中途红了，把失败那一步的日志发我，我改代码——Swift 部分我没法在 Linux 上编译验证，第一次跑 CI 是最可能的报错点。

### 路线 B：有 Mac 的话

```bash
cd verifin-ios-port
flutter pub get
flutter build ios --release --no-codesign
python3 scripts/prepare_sideload_ipa.py --app build/ios/iphoneos/Runner.app --mode lite
# 产物：build/ios/ipa/verifin-lite.ipa
```

脚本会先校验 bundle 结构（Info.plist 必填项、可执行文件、`Frameworks/App.framework`），再在副本上删扩展、重新打包，原始 `Runner.app` 不会被改坏。

---

## 2. 全能签签名

不同版本菜单叫法略有差异，按功能找对应的项即可。

**第一步：装证书**
1. 进「证书管理 / 证书」→ 导入你的 `.p12`（输入密码）和对应的 `.mobileprovision` 描述文件。
2. 导入后确认证书状态是「有效」，并留意它标注的类型：**企业证书** / **个人证书** / **免费证书**。

**第二步：导入 IPA**
1. 回首页 → 「签名 / 应用签名」→ 选择文件 → 选中 `verifin-lite.ipa`。
2. 如果全能签直接读不出这个包（提示无签名信息），说明它只认已签名包——换 **Esign** 或 **Sideloadly** 同样能签未签名 IPA，流程一致。

**第三步：签名设置（关键，逐项对照）**

| 设置项 | lite 包怎么填 | 原因 |
|---|---|---|
| Bundle ID | 证书是通配符（如 `com.abc.*`）→ 随便填，如 `com.abc.verifin`；证书是显式 App ID → 必须一字不差照抄 profile 里那个 | 不匹配会签名失败 |
| 应用组 / App Group / 移除 App Group | 保持关闭，或勾选「移除应用组」 | lite 包已无扩展，多带这个 entitlement 只会导致安装被拒 |
| 推送 / Push | **不要开** | 本项目没有实现 APNs，凭空加 `aps-environment` 会让签名校验失败 |
| 关联域 / Associated Domains | 不要开 | 同上 |
| 扩展一并签名 | lite 包不用管 | 没有 `.appex` |
| 重命名 / 图标替换 | 随意，不影响功能 | — |

**第四步：签名并安装**
1. 点「开始签名」，等进度走完（lite 包约 30–60 秒）。
2. 完成后直接点「安装」，或导出 IPA 后用工具装。
3. 企业证书首次安装后要去 **设置 → 通用 → VPN与设备管理** 里找到对应描述文件，点「信任」。

---

## 3. 首次打开会遇到的三个系统弹窗

| 提示 | 处理 |
|---|---|
| 「未受信任的开发者」 | 设置 → 通用 → VPN与设备管理 → 信任该证书 |
| 「需要开发者模式」（iOS 16+，仅部分签名方式） | 设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启手机 |
| 通知 / 面容 ID 授权 | 按需允许。拒绝也能用，只是提醒不弹、应用锁退化为 PIN |

---

## 4. 装完自检：按这个顺序点一遍

| # | 操作 | 期望结果 |
|---|---|---|
| 1 | 新建一个账本，记 3 笔不同分类的支出 | 首页今日支出、分类占比同步变化 |
| 2 | 切到「报表」，切周/月/年 | 图表有数据，切换不卡 |
| 3 | 设一个预算并超支 | 预算卡片变成超支状态 |
| 4 | 设置 → 备份 → 选择备份目录（会弹系统文件选择器） | 能选中「我的 iPhone」或 iCloud Drive 里的文件夹 |
| 5 | 执行一次「导出备份」 | 目录里出现 `.json` 或 `.zip` 备份文件，列表能看到它 |
| 6 | 导出 CSV | 弹系统分享面板，选「存储到文件」能存下 |
| 7 | 设置一个提醒，时间设 2 分钟后 | 到点收到本地通知 |
| 8 | 设置 → 应用锁 → 开启，锁屏再进 | 弹面容 ID 验证 |
| 9 | 拍照/选图记一笔（OCR） | 能识别金额 |
| 10 | 杀进程重开 | 数据都在，账本状态正确 |

第 4–6 项测的是 `vfbk://` 书签通道（对应 Android 的 SAF），是全套里最需要验证的部分——如果某一步失败，把现象告我。

---

## 5. 报错对照表

| 现象 | 原因 | 处理 |
|---|---|---|
| 安装到一半失败 / 「无法安装此 App」 | 包里有未签名或签错的 `.appex` | 用 **lite** 包重签 |
| 装完点图标立刻闪退 | entitlements 超出描述文件权限（最常见是 App Group） | 用 lite 包；或签名时勾「移除应用组」 |
| 签名时报 `invalid entitlements` / `Failed to verify code signature` | profile 不含包里声明的某个 capability | 同上，逐项关掉推送/关联域/应用组 |
| 「Application identifier 不匹配」 | Bundle ID 与 profile 不一致 | 按证书类型填（见上表） |
| 安装后小组件列表里找不到 VeriFin | lite 包本来就没有小组件 | 这是预期行为，需要 full 包 + 带 App Group 的证书 |
| 「设备未授权 / UDID 未包含」 | 个人证书的 profile 只含注册过的设备 | 在全能签里读本机 UDID，加进 Apple 后台 profile 后重新下载描述文件 |
| 能装但打不开，白屏 | Flutter 引擎没起来（极少数签名工具会破坏 Frameworks 里的 dylib 签名） | 换 Sideloadly 或 Esign 重签 |

---

## 6. full 包的前提（如果你确实想要小组件）

签名前先确认三件事，缺一件就别试了：

1. 你的 Apple Developer 账号（付费 $99）里创建了**显式 App ID** `top.talyra42.verifin`，并在 Capabilities 里**开启 App Groups**，创建组 `group.top.talyra42.verifin`；
2. 描述文件里确实包含这个 group（下载后可以用 `security cms -D -i xxx.mobileprovision` 查看 `Entitlements`）；
3. 签名工具勾选了「连同扩展一起签名」，且两个扩展的 bundle id 分别是 `top.talyra42.verifin.VeriFinWidgets` 和 `top.talyra42.verifin.ShareExtension`。

满足后第一个坑是：**改了主 Bundle ID 就必须同步改两个扩展的 ID，且 App Group 名不能跟着改**（它是硬编码常量）。用脚本改 ID 时它会自动把扩展 ID 跟着改：

```bash
python3 scripts/prepare_sideload_ipa.py \
  --app build/ios/iphoneos/Runner.app --mode full --bundle-id com.yourteam.verifin
```

免费的个人 Apple ID 做不到——它不允许创建 App Group，所以小组件在免费证书下无解。

---

## 7. 两个务实的提醒

- **别把唯一一份数据放在企业证书签的 App 里**。企业证书/共享证书随时可能被 Apple 吊销，一旦吊销 App 直接打不开。装好第一件事就是导出一份备份（设置 → 备份 → 导出到文件），之后定期导 CSV。应用支持 WebDAV，可以接到坚果云/群晖做自动备份。
- **许可证**：上游是 GPLv3。自己装、自己用不受任何限制；如果你把这个 IPA 或改过的代码发给别人，需要一并提供源码。仓库里已经保留了原始 `LICENSE` 和上游署名。
