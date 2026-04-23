# nRF52840 Bootloader 开发笔记

> 项目路径: `/him/Adafruit_nRF52_Bootloader`
> 目标板: `meshtastic_v1` (nRF52840)
> 工具链: xPack ARM GCC 10.3.1 + NCS Python 环境

---

## 目录

1. [工具链环境](#1-工具链环境)
2. [编译与烧录](#2-编译与烧录)
3. [RTT 实时调试](#3-rtt-实时调试)
4. [bootloader 日志解读](#4-bootloader-日志解读)
5. [自定义板级包](#5-自定义板级包)
6. [DFU 按钮说明](#6-dfu-按钮说明)
7. [常见问题](#7-常见问题)

---

## 1. 工具链环境

| 组件 | 路径 / 版本 |
|------|------------|
| ARM GCC | `~/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/10.3.1-2.3.1/.content/bin/arm-none-eabi-` |
| Python 环境 | NCS toolchain `/home/sainstroe/ncs/toolchains/2ac5840438` |
| NCS 环境脚本 | `/him/ncs_pro/.github/tmp/ncs_env.sh` |
| 烧录工具 | `nrfjprog`（通过 J-Link SWD） |

---

## 2. 编译与烧录

### build.sh 用法

脚本位于 `.github/tools/shell/build.sh`，默认 BOARD 已设为 `meshtastic_v1`。

```bash
# 编译（release 模式）
build.sh
build.sh all

# 编译并烧录（release 模式）
build.sh flash

# debug 模式编译（开启 RTT 日志输出）
build.sh DEBUG=1
build.sh DEBUG=1 all

# debug 模式编译并烧录
build.sh DEBUG=1 flash

# 仅烧录 SoftDevice
build.sh flash-sd

# 清除构建产物
build.sh clean
```

### 切换 DEBUG 模式时必须 clean

make 不感知 CFLAGS 变化，`DEBUG=0 ↔ DEBUG=1` 切换后直接编译会复用旧 `.o`
导致链接错误（`undefined reference to 'SEGGER_RTT_Write'`）。

```bash
# 正确切换流程
build.sh clean
build.sh DEBUG=1 flash   # 或 build.sh flash
```

### 两种模式对比

| 项目 | release（默认） | debug（`DEBUG=1`） |
|------|----------------|--------------------|
| Flash 占用 | ~36 KB | ~38 KB（debug linker script） |
| `PRINTF(...)` | 空宏，无输出 | 输出到 SEGGER RTT |
| RTT 库 | 不链接 | 链接 `SEGGER_RTT.c` |
| 生产使用 | ✅ | ❌（RTT buffer 写满会卡住 MCU） |

---

## 3. RTT 实时调试

RTT（Real Time Transfer）是 SEGGER 的专有调试输出技术，通过 SWD 调试线读写芯片 RAM 中的 ring buffer，**不占用任何 UART 引脚**，速度可达 1 MB/s。

### 架构

```
nRF52840 RAM
└── SEGGER RTT ring buffer
      ↑ SEGGER_RTT_Write() 写入
      ↓ J-Link 通过 SWD 读取（JLinkRTTLogger）
      ↓ 实时写入本地文件
```

### 使用方法（单终端，无需 GDB Server）

**步骤一：查找设备 SEGGER ID**

```bash
nrfutil device list
# 输出示例:
# 150710309
# Product    J-Link
# Ports      /dev/ttyACM0
# Traits     jlink, seggerUsb, serialPorts, usb
```

**步骤二：启动 JLinkRTTLogger**

```bash
JLinkRTTLogger \
  -device NRF52840_XXAA \
  -if SWD \
  -speed 4000 \
  -SelectEmuBySN <SEGGER_ID> \
  -RTTChannel 0 \
  /tmp/rtt.log
```

**步骤三：实时查看日志（另一终端，可选）**

```bash
tail -f /tmp/rtt.log
```

> **操作时序**：必须先启动 JLinkRTTLogger，再 Reset 设备。bootloader 运行窗口 < 500 ms，顺序颠倒会错过所有输出。

> **注意**：`DEBUG=1` 编译的 bootloader 使用 `SEGGER_RTT_MODE_BLOCK_IF_FIFO_FULL`。
> 若 RTT Logger **未连接**且 buffer 写满，MCU 会卡死等待。
> 生产固件必须使用 release 模式（无 RTT）。

---

## 4. bootloader 日志解读

bootloader 运行时间极短（通常 < 500 ms），完整日志序列如下：

```
Bootloader Start              ← board_init() 完成，进入 main()
SD_MBR_COMMAND_INIT_SD        ← 仅 BLE OTA 路径出现
App is valid                  ← Flash 中存在合法 App
Starting app...               ← 跳转 App（之后 RTT 断开）
```

### 根据日志判断状态

| 日志停在哪里 | 含义 |
|-------------|------|
| `Bootloader Start`（然后停） | Flash 中无 App，进入 DFU 等待 |
| `Bootloader Start` + 电脑出现 U 盘 | 进入 USB UF2 DFU 模式 |
| `App is valid` + `Starting app...` | 正常启动 App |
| 只有 `Bootloader Start`，无 U 盘 | 无 USB 连接，3 秒后会重置重试 |

### 烧录过程中的日志（flash/UF2 时）

```
Erase 0x000F4000
Write 0x000F4000
Erase 0x000F5000
Write 0x000F5000
...
```

### LED 状态含义

| 状态 | Primary LED（Red P1.3） | Secondary LED（Blue P1.1） |
|------|------------------------|--------------------------|
| DFU Serial / USB | 慢闪 | 熄灭 |
| DFU OTA（BLE） | 慢闪 | 同时慢闪 |
| 烧录中 | 快闪 ×2 | 快闪 ×2 |
| Fatal Error | 交替闪 | 交替闪 |
| BLE 已连接 | 常亮 | 常亮 |

---

## 5. 自定义板级包

板级包路径: `src/boards/meshtastic_v1/`

### 文件结构

```
src/boards/meshtastic_v1/
├── board.h        ← 引脚定义、USB VID/PID、BLE 信息、UF2 元数据
├── board.mk       ← MCU_SUB_VARIANT = nrf52840
├── board.cmake    ← set(MCU_VARIANT nrf52840)
└── pinconfig.c    ← CF2 配置（Flash/RAM 大小、UF2 Family ID）
```

### board.h 主要配置项

```c
// LED（最多 2 路 PWM，active-low）
#define LEDS_NUMBER       2
#define LED_PRIMARY_PIN   PINNUM(1, 3)   // Red   LED
#define LED_SECONDARY_PIN PINNUM(1, 1)   // Blue  LED
#define LED_STATE_ON      0              // 低电平点亮

// DFU 按钮（两个按钮必须使用同一 BUTTON_PULL）
#define BUTTON_DFU        PINNUM(1, 10)  // cancel 按住上电 → USB/Serial DFU
#define BUTTON_DFU_OTA    PINNUM(0, 11)  // right  同时按住 BUTTON_DFU → BLE OTA DFU
#define BUTTON_PULL       NRF_GPIO_PIN_PULLUP  // 两个按钮都接 GND

// DC/DC（不定义 = 使用 LDO，无需外部电感）
// #define ENABLE_DCDC_0 1  // 不使用
// #define ENABLE_DCDC_1 1  // 不使用

// USB（生产前替换为正式 VID/PID）
#define USB_DESC_VID          0x1915   // Nordic 测试用，生产必须替换
#define USB_DESC_UF2_PID      0x520A
#define USB_DESC_CDC_ONLY_PID 0x520B

// BLE OTA 显示名称
#define BLEDIS_MANUFACTURER "sainstore"
#define BLEDIS_MODEL        "Meshtastic v1"

// UF2 虚拟 U 盘
#define UF2_PRODUCT_NAME  "Meshtastic v1"
#define UF2_VOLUME_LABEL  "MSHTV1BOOT"   // ≤11 字符，FAT 卷标
#define UF2_BOARD_ID      "nRF52840-Meshtastic-v1"
```

### pinconfig.c 关键参数

```c
204, 0x100000,   // FLASH_BYTES = 1 MB（nRF52840 固定）
205, 0x40000,    // RAM_BYTES   = 256 KB（nRF52840 固定）
209, 0xada52840, // UF2_FAMILY  = nRF52840（固定）
```

---

## 6. DFU 按钮说明

### 触发方式

| 操作 | 进入模式 |
|------|---------|
| 上电时按住 `BUTTON_DFU`（P1.10 cancel） | USB/Serial DFU，电脑出现 `MSHTV1BOOT` U 盘 |
| 上电时同时按住 `BUTTON_DFU` + `BUTTON_DFU_OTA`（P0.11 right） | BLE OTA DFU |
| 双击 Reset | 也可触发 DFU（500 ms 内按两次） |
| App 调用 `NRF_POWER->GPREGRET = 0x57` 后 reset | 进入 UF2 DFU |

### 按钮硬件要求

两个 DFU 按钮**必须使用同一上拉/下拉方向**（bootloader 限制）：
- 当前配置: `BUTTON_PULL = NRF_GPIO_PIN_PULLUP`，即按钮接 GND（低电平有效）
- `BUTTON_DFU`（P1.10）: 原 PCB 已接 GND ✅
- `BUTTON_DFU_OTA`（P0.11）: **需确认 PCB 接 GND 而非 VCC**，若接 VCC 则需修改硬件

---

## 7. 常见问题

### 链接错误: `undefined reference to 'SEGGER_RTT_Write'`

原因: 之前用 `DEBUG=1` 编译留下的 `.o` 缓存，切回 release 模式时 make 未重新编译。

```bash
build.sh clean
build.sh flash
```

### 电脑不出现 UF2 U 盘

检查顺序:
1. USB 数据线是否是数据线（非充电线）
2. 是否在上电/Reset 时按住了 `BUTTON_DFU`
3. 查看 RTT 日志确认进入了 DFU 模式
4. `lsusb` 查看是否有 VID 0x1915 的设备

### P0.9 / P0.10 作为 GPIO 不工作

nRF52840 出厂默认 P0.9、P0.10 是 NFC 引脚。需要 App 层（NCS 固件）在启动时将 UICR NFCPINS 写为 GPIO 模式（`nfct-pins-as-gpios`），bootloader 不处理此配置。全新芯片首次烧录 NCS App 后该配置才会生效并持久保存。

### RTT 板子卡死（无 App 情况下）

debug 模式的 bootloader 使用阻塞 RTT（buffer 满时等待）。保持 `JLinkRTTClient` 连接即可，或改用 release 模式烧录。
