# nRF52840 OTA 升级完全指南

> 目标板：`meshtastic_v1`（nRF52840）
> LED：红色 = `LED_PRIMARY`（P1.3），蓝色 = `LED_SECONDARY`（P1.1），均为低电平有效
> 按钮：均为低电平有效（PULLUP，按下接 GND）

---

## 目录

1. [两种升级通道概览](#1-两种升级通道概览)
2. [进入 DFU 模式：触发方式与 LED 现象](#2-进入-dfu-模式触发方式与-led-现象)
3. [固件格式选择：UF2 / HEX / ZIP](#3-固件格式选择uf2--hex--zip)
4. [生成升级包](#4-生成升级包)
- [附录 A：为什么 UF2 不支持 SoftDevice 升级](#附录-a为什么-uf2-不支持-softdevice-升级)
- [附录 B：手机 App 选择](#附录-b手机-app-选择)

---

## 1. 两种升级通道概览

| 通道 | 接口 | 触发方式 | 升级包格式 | 可升级目标 |
|------|------|----------|------------|------------|
| **USB UF2** | USB Mass Storage（拖拽 U 盘） | 按 `BUTTON_DFU` 上电 / 双击 Reset / GPREGRET=`0x57` | `.uf2` | App、Bootloader |
| **BLE OTA** | Bluetooth LE（手机无线） | 同时按 `BUTTON_DFU` + `BUTTON_DFU_OTA` 上电 / GPREGRET=`0x4e`/`0xB1` | `.zip`（DFU package） | App、Bootloader、SoftDevice |

> 本表是全文的索引。"触发方式详细说明"见第 2 章，"格式差异"见第 3 章，"生成命令"见第 4 章。

---

## 2. 进入 DFU 模式：触发方式与 LED 现象

### 2.1 USB UF2 DFU 模式

#### 触发方式

| 方式 | 操作 |
|------|------|
| 按钮 | 按住 `BUTTON_DFU`（P1.10）的同时上电或按 Reset |
| 双击 Reset | 500 ms 内连续按两次 Reset（第一次写入魔法数 `0x5A1AD5` 到 RAM，第二次检测到后进入 DFU） |
| 软件触发 | App 写 `NRF_POWER->GPREGRET = 0x57`，然后软件复位 |

#### LED 现象（源码依据：`src/boards/boards.c` + `src/usb/msc_uf2.c`）

| 阶段 | 红色 LED（P1.3） | 蓝色 LED（P1.1） | 说明 |
|------|-----------------|-----------------|------|
| 进入 DFU，等待 USB 枚举 | 快速闪烁（300 ms 周期） | 灭 | `STATE_USB_UNMOUNTED`：`primary_cycle_length=300` |
| USB 枚举成功，U 盘出现 | 慢速呼吸（3000 ms 周期） | 灭 | `STATE_USB_MOUNTED`：`primary_cycle_length=3000` |
| 文件写入中（收到 UF2 块） | 急速闪烁（100 ms 周期） | 灭 | `STATE_WRITING_STARTED`：`primary_cycle_length=100` |
| 写入完成，即将重启 | 慢速呼吸（3000 ms 周期）→ 重启 | 灭 | `STATE_WRITING_FINISHED`：`primary_cycle_length=3000` |

> **蓝色 LED 在 USB UF2 模式下始终不亮**，因为 `secondary_cycle_length` 从未在 USB 路径被赋值（初始为 0）。

---

### 2.2 BLE OTA DFU 模式

#### 触发方式

| 方式 | 操作 |
|------|------|
| 按钮组合 | 同时按住 `BUTTON_DFU`（P1.10）+ `BUTTON_DFU_OTA`（P0.11）上电或 Reset |
| 软件触发（App 内） | App 写 `NRF_POWER->GPREGRET = 0xB1`（SD 已初始化）或 `0xA8`（SD 未初始化），然后复位 |

> `BUTTON_DFU_OTA` **单独按住**不会触发任何 DFU 模式，必须与 `BUTTON_DFU` 组合。

#### LED 现象（源码依据：`src/main.c` + `lib/sdk11/components/libraries/bootloader_dfu/dfu_transport_ble.c`）

| 阶段 | 红色 LED（P1.3） | 蓝色 LED（P1.1） | 说明 |
|------|-----------------|-----------------|------|
| 广播中，等待手机连接 | 快速闪烁（300 ms 周期） | 快速闪烁（300 ms 周期） | `STATE_BLE_DISCONNECTED`：`secondary_cycle_length=300`；red 沿用 `STATE_BOOTLOADER_STARTED` 的 300 ms |
| 手机已连接，等待传输 | 快速闪烁（300 ms 周期） | 慢速呼吸（3000 ms 周期） | `STATE_BLE_CONNECTED`：`secondary_cycle_length=3000` |
| 正在接收固件数据包 | 急速闪烁（100 ms 周期） | 慢速呼吸（3000 ms 周期） | `STATE_WRITING_STARTED`：`primary_cycle_length=100` |
| 手机断开（如传输完毕） | 快速闪烁（300 ms 周期） | 快速闪烁（300 ms 周期） | `STATE_BLE_DISCONNECTED`，随即重启 |

> **诊断要点**：广播等待时**双灯同时快速闪烁**；连接成功后蓝灯转为慢速呼吸；收到数据后红灯加速为急速闪烁。

---

### 2.3 LED 周期速查

| `cycle_length` | 视觉效果 | 出现场景 |
|---------------|----------|----------|
| 100 ms | 急速闪烁（几乎实心感） | 文件/数据写入中 |
| 300 ms | 快速闪烁（约 3 次/秒） | DFU 等待、BLE 广播/断开 |
| 3000 ms | 慢速呼吸（约 0.33 次/秒） | USB 已枚举、BLE 已连接 |

---

## 3. 固件格式选择：UF2 / HEX / ZIP

### 3.1 三种格式的本质差异

| 格式 | 本质 | 传输通道 | 生成方式 |
|------|------|----------|----------|
| **`.uf2`** | 将 Intel HEX 切分为 256 字节块，每块附带目标地址，整体封装为虚拟 FAT 文件 | USB Mass Storage（拖拽到 U 盘） | `make` / `build.sh` 直接输出 |
| **`.hex`** | Intel HEX 原始格式，含绝对地址 | JLink / nrfjprog（调试器直连） | 编译直接输出，**不走 OTA** |
| **`.zip`** | 固件 `.bin` + init packet（`.dat`）+ `manifest.json`，打包为 zip | BLE OTA（手机 App 推送） | `adafruit-nrfutil` 命令生成 |

> `.hex` 只用于开发阶段调试器烧录，**不能**通过 USB UF2 或 BLE OTA 使用。

### 3.2 升级目标 × 通道矩阵

| 升级目标 | USB UF2 拖拽 | BLE OTA ZIP |
|----------|:-----------:|:-----------:|
| **App（用户应用）** | ✅ | ✅ |
| **Bootloader 自身** | ✅（自升级 UF2，familyID = `0xd663823c`） | ✅ |
| **SoftDevice** | ❌ | ✅ |

> UF2 **不能**升级 SoftDevice 的原因见[附录 A](#附录-a为什么-uf2-不支持-softdevice-升级)。

---

## 4. 生成升级包

### 4.1 UF2 文件

`build.sh` / `make` 编译完成后在 `_build/build-meshtastic_v1/` 目录自动输出 `.uf2` 文件，**无需额外步骤**。

```bash
# 编译输出 UF2
.github/tools/shell/build.sh

# 产物路径示例
_build/build-meshtastic_v1/update-meshtastic_v1_bootloader-<版本>_nosd.uf2
```

将 `.uf2` 文件拖入 `MSHTV1BOOT` 磁盘即可完成升级，写入完成后设备自动重启。

---

### 4.2 BLE OTA ZIP：adafruit-nrfutil 命令

**工具本质**：只负责将 hex/bin 转为 bin、计算 CRC、生成 init packet、写入 `manifest.json` 并打包为 zip。
工具**不知道也不关心目标 flash 地址**——地址路由完全由设备端 bootloader 根据 `manifest.json` 中的键名（`application` / `bootloader` / `softdevice`）和自身编译时的地址常量决定。

| 文件                                             | 内容                                | 用途                            |
| ------------------------------------------------ | ----------------------------------- | ------------------------------- |
| `meshtastic_v1_bootloader-<ver>.hex`             | 纯 Bootloader 代码（无 MBR、无 SD） | **`--bootloader` 参数使用这个** |
| `meshtastic_v1_bootloader-<ver>_nosd.hex`        | Bootloader + MBR 合并               | JLink 直接烧录 (`make flash`)   |
| `meshtastic_v1_bootloader-<ver>_s140_6.1.1.hex`  | Bootloader + MBR + SD 全合并        | 首次初始化烧录                  |
| `update-meshtastic_v1_bootloader-<ver>_nosd.uf2` | UF2 自升级包                        | 拖拽到 U 盘升级 Bootloader      |


#### 升级 App

```bash
adafruit-nrfutil dfu genpkg \
  --dev-type 0x0052 \
  --sd-req 0xB6 \
  --application app.hex \
  app_dfu.zip
```

#### 升级 Bootloader

- 使用不带 _nosd 后缀的纯 bootloader hex（不含 MBR、不含 SD）

```bash
adafruit-nrfutil dfu genpkg \
  --dev-type 0x0052 \
  --dev-revision 52840 \
  --sd-req 0xB6 \
  --bootloader _build/build-meshtastic_v1/meshtastic_v1_bootloader-<ver>.hex \
  bootloader_dfu.zip
```

#### 升级 SoftDevice

```bash
adafruit-nrfutil dfu genpkg \
  --dev-type 0x0052 \
  --dev-revision 52840 \
  --sd-req 0xB6 \
  --softdevice lib/softdevice/s140_nrf52_6.1.1/s140_nrf52_6.1.1_softdevice.hex \
  sd_dfu.zip
```

> **`--sd-req`**：目标设备上当前 SoftDevice 的 Firmware ID。S140 v6.1.1 = `0xB6`。
> 可用 `adafruit-nrfutil dfu genpkg --help` 查看完整 SD ID 列表。

---

### 4.3 支持的 ZIP 组合（Nordic 官方限制）

| 组合 | 支持 | 说明 |
|------|:----:|------|
| BL + SD | ✅ | 无特殊限制 |
| **BL + APP** | **❌** | **工具不支持，必须分两个 ZIP 分别推送** |
| BL + SD + APP | ✅ | 需两次连接（第一次更新 SD+BL，第二次更新 APP） |
| SD + APP | ✅ | 需两次连接 |

---

### 4.4 注意事项

| 注意事项 | 说明 |
|---------|------|
| **`--debug-mode`** | 跳过版本号校验，用于开发调试；生产固件不使用 |
| **SIGNED_FW=1** | 编译时启用签名验证，UF2 升级会被禁用（除非同时启用 `FORCE_UF2=1`） |
| **BL + APP 组合** | 必须先推送 Bootloader ZIP，重启后再推送 App ZIP |
| **地址无需指定** | 工具只打类型标签，设备端自动路由；无需（也不支持）手动指定 flash 地址 |

推送 ZIP 到设备的命令（USB CDC 口）：

```bash
adafruit-nrfutil dfu serial \
  --package app_dfu.zip \
  --port /dev/ttyACM0 \
  --baudrate 115200
```

或直接使用手机 App（见[附录 B](#附录-b手机-app-选择)）通过 BLE 推送。

---

## 附录 A：为什么 UF2 不支持 SoftDevice 升级

UF2 的写入分发由 `src/usb/uf2/ghostfat.c` 的 `write_block()` 函数根据 UF2 块的 `familyID` 字段来决定：

```c
switch (bl->familyID) {
  case CFG_UF2_FAMILY_APP_ID:   // 0xADA52840 (nRF52840)
  case CFG_UF2_BOARD_APP_ID:    // (VID<<16)|PID，板级专属
    // → 写入 USER_FLASH_START(0x1000) ~ USER_FLASH_END(0xEA000) 范围
    // → 0x0 ~ 0x1000（MBR）的写入请求被静默跳过
    break;

  case CFG_UF2_FAMILY_BOOT_ID:  // 0xd663823c
    // → 先写入 App 区暂存，收齐后通过 MBR SD_MBR_COMMAND_COPY_BL 安全激活
    break;

  // 注意：没有 SoftDevice 专用的 familyID case
}
```

**根本原因有两点：**

1. **无 SoftDevice familyID**：`write_block()` 中没有处理 SoftDevice 的 `case`。即使把 SD hex 做成 UF2，bootloader 只会通过 App 路径直接覆写 SoftDevice 所在的 flash 区域（0x1000–0x25FFF 在 App 范围内），**跳过了 Nordic MBR 的 `SD_MBR_COMMAND_COPY_SD` 激活流程**。

2. **激活机制缺失**：SoftDevice 更新需要 MBR 协调（先写备份区，校验，再原子切换）。UF2 的直接 flash 写入无法满足这个顺序，会导致设备进入不可恢复状态（SD 损坏后 BLE 和 USB 均不可用）。

**结论**：升级 SoftDevice 必须使用 BLE OTA ZIP 包（走 `dfu_transport_ble.c` 的正规流程），禁止使用 UF2。

---

## 附录 B：手机 App 选择

BLE OTA 推送 ZIP 包时，手机 App 的选择**取决于设备端 bootloader 类型**，两款常见 App 不可互换：

| | `nRF Device Firmware Update` | `nRF Connect Device Manager` |
|--|:---:|:---:|
| **开发商** | Nordic Semiconductor | Nordic Semiconductor |
| **适配协议** | nRF5 SDK Secure Bootloader（旧版 DFU 协议） | nRF Connect SDK / MCUboot（新版 SMP 协议） |
| **本项目适用** | ✅ **正确选择** | ❌ 协议不兼容，无法推送 |
| **BLE 扫描名** | 扫描并连接 `AdaDFU` | 无法识别 `AdaDFU` |
| **包格式** | `.zip`（nRF5 SDK DFU package） | `.bin` / MCUboot envelope |
| **平台** | iOS / Android | iOS / Android |

> 广告名 `AdaDFU` 来自 `lib/sdk11/components/libraries/bootloader_dfu/dfu_transport_ble.c` 第 46 行的 `#define DEVICE_NAME "AdaDFU"`。`BLEDIS_MANUFACTURER`（`sainstore`）和 `BLEDIS_MODEL`（`Meshtastic v1`）是 DIS 服务字段，只在连接后可读，**不影响广告扫描名**。

