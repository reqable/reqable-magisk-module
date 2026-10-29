# Reqable System CA Module (Magisk / KernelSU / SukiSU / APatch)

将 [Reqable](https://reqable.com/) 抓包根证书以 Systemless 方式注入到 Android 系统受信任凭据列表中的 Root 模块。

本模块针对高版本 Android 的 **APEX Conscrypt 证书隔离机制**与新一代 Root 框架（KernelSU / SukiSU / APatch）进行了深度适配，**无需依赖额外的挂载元模块（如 `Magic-mount-rs` 或 `mountify`）即可独立工作**。

---

## ✨ 核心特性

- **全版本通杀（Android 11 ~ Android 17）**：
  - **Android 11 ~ 13**：自动注入 `/system/etc/security/cacerts`。
  - **Android 14 ~ 17（含 HyperOS / ColorOS / OneUI 等最新系统）**：双通道同步注入 `/system/etc/security/cacerts` 与 `/apex/com.android.conscrypt/cacerts`。
- **全 Root 框架兼容**：完美支持 **Magisk**、**KernelSU**、**SukiSU**、**APatch**（脚本内自包含 `tmpfs` 挂载逻辑，不依赖外部 Metamodule 元模块）。
- **防自动卸载（Anti-Umount）**：采用内存文件系统（`tmpfs`）脱离 `/data/adb/modules` 路径绑定，并在挂载完成后自动卸载清理临时挂载点，规避 Root 框架对模块目录的自动卸载与安全软件的路径特征扫描。
- **Zygote 命名空间穿透**：通过 `post-fs-data.sh`（注入 PID 1 `init` 命名空间）+ `service.sh`（开机后智能巡检并通过 `nsenter` 穿透 `zygote` / `zygote64` 挂载命名空间）双重保障，确保所有应用 100% 读取到根证书。
- **动态 SELinux 上下文**：自动识别并继承当前系统原厂证书目录的 SELinux 标签（如 `system_security_cacerts_file` 或 `system_file`），完美兼容 Enforcing 强制模式。

---

## ⚠️ 重要前提：获取你的 Reqable 专属证书

新版 Reqable 采用**“一机一证（动态生成）”**机制，每台设备首次安装启动 Reqable 时都会生成一张独一无二的根证书（文件名格式为 `<8位Hash>.0`，例如 `b5c7838e.0`）。

因此，**你必须将自己设备上 Reqable 生成的 `.0` 证书文件放入本模块中**，不能使用他人的固定证书。

### 导出 `.0` 证书步骤：
1. 打开手机上的 **Reqable** App。
2. 进入 **设置 / 证书管理 -> 安装证书 -> Root设备 -> 手动复制文件**。
3. 点击步骤 2.1 中的蓝色文件名链接（例如 `b5c7838e.0`），将其导出保存到手机存储（默认保存在 `/sdcard/Download/`）。

---

## 🚀 安装与使用方法

你可以选择 **“方式一：在手机上直接配置”** 或 **“方式二：在电脑上自行打包”**。

### 方式一：在手机上直接配置（推荐，无需电脑）

1. 在 Root 管理器（Magisk / KernelSU / SukiSU / APatch）中刷入本模块 `.zip` 包（若压缩包内未放证书，刷入后暂不生效）。
2. 打开拥有 Root 权限的文件管理器（如 **MT 管理器**）。
3. 将你从 Reqable 导出的 `<Hash>.0` 证书文件复制到以下模块目录中：
   ```text
   /data/adb/modules/reqable-magisk-module/system/etc/security/cacerts/
   ```
4. **重启手机**即可生效（或者直接在 MT 管理器中以 Root 权限执行模块目录下的 `service.sh` 脚本立即生效）。

---

### 方式二：在电脑上自行打包（适合开发者）

1. 克隆本仓库到本地：
   ```bash
   git clone [https://github.com/reqable/reqable-magisk-module.git](https://github.com/reqable/reqable-magisk-module.git)
   cd reqable-magisk-module
   ```
2. 将从 Reqable 导出的 `<Hash>.0` 证书文件放入项目的 `system/etc/security/cacerts/` 目录下。
3. 在项目**根目录内部**执行以下命令生成刷机包（切勿在文件管理器中直接右键压缩外层文件夹，否则会多套一层目录导致刷入失败）：

   ```bash
   chmod +x post-fs-data.sh service.sh META-INF/com/google/android/update-binary

   COPYFILE_DISABLE=1 zip -r9 ../reqable-magisk-module-release.zip . \
     -x "*.git*" \
     -x "*.idea*" \
     -x "*.github*" \
     -x "*.DS_Store" \
     -x "*__MACOSX*" \
     -x "._*" \
     -x "*.gitkeep"
   ```
4. 将生成的 `reqable-magisk-module-release.zip` 传至手机，通过 Magisk / KernelSU / SukiSU / APatch 刷入并重启。

---

## ✅ 验证是否安装成功

重启手机后，可通过以下两种方式验证：

1. **系统设置检查**：
   打开手机 **设置 -> 安全（或密码与安全 -> 系统安全） -> 加密与凭据 -> 信任的凭据 -> 系统**，下滑找到 **Reqable**，确认列表中存在 `Reqable CA` 证书。
2. **Reqable App 检查**：
   打开 Reqable App，证书状态显示已安装激活，开启抓包后可正常解密 HTTPS 流量。

---

## 🛠️ 故障排查 (Troubleshooting)

1. **系统设置里能看到证书，但某个特定 App 依然抓不到包？**
   - **检查 SukiSU / KernelSU 的“卸载模块 (Umount modules)”开关**：打开你的 Root 管理器 -> 超级用户列表 -> 找到你要抓包的目标 App（以及 Reqable），确保在抓包期间**关闭该 App 的“卸载模块”选项**，否则内核会在目标 App 启动时强制卸载掉证书挂载点。
   - **目标 App 开启了 SSL Pinning（证书绑定）**：部分应用（如社交、金融