# nRF52840 Bootloader & UF2 学习笔记

> 基于 Adafruit nRF52 Bootloader（`feather_nrf52840_express`）与 Zephyr/NCS v3.2.4 实战总结  
> 源码路径：`E:\JianHao\nRF\2026-03-30-204810-Adafruit_nRF52_Bootloader`

---

## 目录

1. [nRF52840 Flash 内存布局](#1-nrf52840-flash-内存布局)
2. [启动流程与 DFU 模式判定](#2-启动流程与-dfu-模式判定)
3. [固件格式：Intel HEX 与 UF2](#3-固件格式intel-hex-与-uf2)
4. [UF2 虚拟 FAT 升级机制（ghostfat.c 源码分析）](#4-uf2-虚拟-fat-升级机制ghostfatc-源码分析)
5. [App 偏移地址配置与验证实战](#5-app-偏移地址配置与验证实战)

---

## 1. nRF52840 Flash 内存布局

### 1.1 物理 Flash 总览

nRF52840 共 1MB Flash（`0x00000000`–`0x000FFFFF`）。以下为 Release 模式的完整分区布局：

```
┌─────────────────────────────────────────────┐  0x100000
│  Bootloader Settings (4KB)                  │  BOOTLOADER_SETTINGS_ADDRESS = 0xFF000
├─────────────────────────────────────────────┤  0xFF000
│  MBR Params Page (4KB)                      │  BOOTLOADER_MBR_PARAMS_PAGE_ADDRESS = 0xFE000
├─────────────────────────────────────────────┤  0xFE000  ← BOOTLOADER_ADDR_END
│  Bootloader Config / CF2 (2KB)              │  0xFD800
├─────────────────────────────────────────────┤  0xFD800
│  Bootloader Code (~38KB)                    │  BOOTLOADER_ADDR_START = 0xF4000
├─────────────────────────────────────────────┤  0xF4000  ← BOOTLOADER_REGION_START
│  App Data Reserved (40KB)                   │  DFU_APP_DATA_RESERVED = 10×4096
├─────────────────────────────────────────────┤  0xEA000  ← USER_FLASH_END
│                                             │
│  Application Code                           │
│    [With S140 v6.1.1] 起始于 0x26000        │
│    [Without SD]       起始于 0x1000         │
│                                             │
├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤  0x26000  ← SD 存在时的 App 起始
│  [Optional] SoftDevice S140 v6.1.1 (148KB)  │
├─────────────────────────────────────────────┤  0x1000   ← USER_FLASH_START = MBR_SIZE
│  MBR (4KB)                                  │
└─────────────────────────────────────────────┘  0x00000
```

**注意**：`App Data Reserved`（`0xEA000`–`0xF4000`）是独立于 App Code 的保留区，用于 BLE 绑定信息和持久化状态，UF2 App 升级时**不会**触碰此区域（见第 4.3 节）。

### 1.2 关键宏定义一览

| 宏名                                   | 值（nRF52840 Release）                                           | 定义位置                                                           |
| ------------------------------------ | ------------------------------------------------------------- | -------------------------------------------------------------- |
| `MBR_SIZE`                           | `0x1000`                                                      | `lib/softdevice/mbr/headers/nrf_mbr.h:68`                      |
| `BOOTLOADER_REGION_START`            | `0x000F4000`                                                  | `lib/sdk11/components/libraries/bootloader_dfu/dfu_types.h:93` |
| `BOOTLOADER_MBR_PARAMS_PAGE_ADDRESS` | `0x000FE000`                                                  | `dfu_types.h:95`                                               |
| `BOOTLOADER_SETTINGS_ADDRESS`        | `0x000FF000`                                                  | `dfu_types.h:96`                                               |
| `BOOTLOADER_ADDR_START`              | `BOOTLOADER_REGION_START` = `0xF4000`                         | `src/usb/uf2/uf2cfg.h:29`                                      |
| `BOOTLOADER_ADDR_END`                | `BOOTLOADER_MBR_PARAMS_PAGE_ADDRESS` = `0xFE000`              | `uf2cfg.h:32`                                                  |
| `USER_FLASH_START`                   | `MBR_SIZE` = `0x1000`                                         | `uf2cfg.h:25`                                                  |
| `DFU_APP_DATA_RESERVED`              | `10*4096` = `0xA000`                                          | `CMakeLists.txt:269`                                           |
| `USER_FLASH_END`                     | `BOOTLOADER_REGION_START - DFU_APP_DATA_RESERVED` = `0xEA000` | `uf2cfg.h:26`                                                  |

宏依赖关系：

```
USER_FLASH_END = BOOTLOADER_REGION_START - DFU_APP_DATA_RESERVED
               = 0xF4000 - 0xA000
               = 0xEA000
```

### 1.3 MBR（Master Boot Record）的角色

MBR 是芯片在地址 `0x0`–`0xFFF` 的第一级引导程序，出厂烧录，**永远不被擦除**（Nordic 官方文档：*"During a firmware update process, the MBR is never erased."*）。

- 芯片复位后，CPU 从地址 `0x0` 开始执行，即 MBR 的向量表  
- MBR 读取 `UICR.BOOTLOADERADDR`（寄存器 `0x10001014`），若有效则跳转至 Bootloader  
- 向 Bootloader 提供 `SD_MBR_COMMAND_*` 接口，用于安全复制新 Bootloader 或 SoftDevice

**UICR（User Information Configuration Registers）** 是芯片的非易失性配置寄存器区域（`0x10000000`）：

| UICR 寄存器 | 地址 | 本项目中的值 |
|-------------|------|-------------|
| `NRFFW[0]`（Bootloader 起始地址） | `0x10001014` | `0xF4000`（`BOOTLOADER_REGION_START`） |
| `NRFFW[1]`（MBR Params Page 地址） | `0x10001018` | `0xFE000`（`BOOTLOADER_MBR_PARAMS_PAGE_ADDRESS`） |

### 1.4 SoftDevice 是什么

SoftDevice 是 Nordic 提供的预编译 BLE 协议栈二进制文件，不开源，以 `.hex` 形式分发（Nordic DevZone：*"The SoftDevice provided by Nordic Semiconductor is a precompiled and linked binary software implementing a wireless protocol (BLE)."*）。

- **nRF52840 对应型号**：S140（支持 BLE Central + Peripheral 全功能）  
- **本项目使用版本**：S140 v6.1.1，文件路径：`lib/softdevice/s140_nrf52_6.1.1/s140_nrf52_6.1.1_softdevice.hex`  
- **Flash 占用**：`0x1000`（MBR 之后）至 `0x25FFF`，共 `0x25000`（148KB）  
- SoftDevice 在 `0x3000` 处嵌入 Info Struct，Bootloader 通过读取此结构体识别 SD 的存在与版本

### 1.5 SoftDevice 存在性检测

Bootloader **在运行时**动态判断 SoftDevice 是否存在，而非编译期固定。

来源：`lib/sdk11/components/libraries/bootloader_dfu/dfu_types.h:65–71`

```c
#define SD_MAGIC_NUMBER  0x51B1E5DB

static inline bool is_sd_existed(void) {
    return *((uint32_t*)(SOFTDEVICE_INFO_STRUCT_ADDRESS + 4)) == SD_MAGIC_NUMBER;
}
```

- `SOFTDEVICE_INFO_STRUCT_ADDRESS` = `0x2000 + MBR_SIZE` = `0x2000 + 0x1000` = `0x3000`  
- 实际检测地址：`0x3000 + 4` = **`0x3004`**  
- 若该地址的 32 位值等于 `0x51B1E5DB`，则认为 SoftDevice 已烧录

SoftDevice 的实际大小同样从 Info Struct 读取：

来源：`lib/softdevice/.../nrf_sdm.h`

```c
#define SD_SIZE_OFFSET  (SOFTDEVICE_INFO_STRUCT_OFFSET + 0x08)  // = 0x2008
#define SD_SIZE_GET(baseaddr)  (*((uint32_t *)((baseaddr) + SD_SIZE_OFFSET)))
```

调用 `SD_SIZE_GET(MBR_SIZE)` 时读取地址 `0x1000 + 0x2008` = **`0x3008`**，返回 S140 v6.1.1 实际占用字节数 = `0x25000`，则 App 起始地址 = `0x1000 + 0x25000` = `0x26000`。

---

## 2. 启动流程与 DFU 模式判定

### 2.1 启动流程总览

```
芯片复位
  │
  ▼
MBR (0x0)
  │  读取 UICR.BOOTLOADERADDR (0x10001014) = 0xF4000
  │  → 跳转 Bootloader
  ▼
Bootloader main() (0xF4000)
  │
  ├─► check_dfu_mode()
  │     │
  │     ├── GPREGRET 含魔术值?     → DFU
  │     ├── Double-Reset 检测到?   → DFU
  │     ├── DFU 按钮被按下?        → DFU
  │     └── APP_ASKS_FOR_SINGLE_TAP_RESET()?  → DFU
  │
  ├─► bootloader_app_is_valid()
  │     ├── 有效 → bootloader_app_start()  (跳转 App)
  │     └── 无效 → 强制进入 DFU 模式
  │
  └─► DFU 模式（USB MSC / BLE OTA / UART）
```

### 2.2 DFU 模式的 4 种触发条件

来源：`src/main.c: check_dfu_mode()`（line 241）

#### 条件 1：GPREGRET 软件标记

App 可在软重启前将特定值写入 `NRF_POWER->GPREGRET` 寄存器，Bootloader 启动时读取：

| 魔术值 | 宏名 | 含义 |
|--------|------|------|
| `0xB1` | `DFU_MAGIC_OTA_APPJUM` | BLE OTA DFU |
| `0xA8` | `DFU_MAGIC_OTA_RESET` | BLE OTA reset |
| `0x4E` | `DFU_MAGIC_SERIAL_ONLY_RESET` | 仅串口 DFU |
| `0x57` | `DFU_MAGIC_UF2_RESET` | USB MSC / UF2 DFU |
| `0x6D` | `DFU_MAGIC_SKIP` | 跳过 DFU，直接启动 App |

#### 条件 2：Double-Reset（双击 Reset 键）

来源：`src/main.c:116–120, 258, 303–318`

```c
#define DFU_DBL_RESET_MAGIC   0x5A1AD5      // 第一次 reset 写入的标记值
#define DFU_DBL_RESET_APP     0x4ee5677e    // 单击 reset 模式标记
#define DFU_DBL_RESET_DELAY   500           // 双击窗口（毫秒）
#define DFU_DBL_RESET_MEM     0x20007F7C    // 标记在 RAM 中的存储地址
```

RAM 该地址声明为 NOINIT（复位不清零），来源：`linker/nrf52840.ld:28`

```
DBL_RESET (rwx) : ORIGIN = 0x20007F7C, LENGTH = 0x04
```

执行流程：

1. 第一次按 Reset → Bootloader 写入 `*0x20007F7C = 0x5A1AD5`，等待 500ms  
2. 500ms 内第二次按 Reset → 再次启动时检测到 `*0x20007F7C == 0x5A1AD5` → 进入 DFU  
3. 500ms 超时无第二次 Reset → 清除标记，正常启动 App

#### 条件 3：DFU 硬件按钮

若板级 `board.h` 中定义了 `PIN_DFU_BTN`，按住按钮上电即进入 DFU（来源：`src/main.c:272`）。

#### 条件 4：App 主动标记单击 Reset 模式

App 可在起始地址 + `0x200` 处写入魔术值 `0x87eeb07c`，Bootloader 检测到后以单击 Reset 即进入 DFU（来源：`src/main.c:285`，宏 `APP_ASKS_FOR_SINGLE_TAP_RESET()`）。

### 2.3 App 有效性验证：bootloader_app_is_valid()

来源：`lib/sdk11/components/libraries/bootloader_dfu/bootloader.c:150–187`

三步判定，均通过才返回 `true`：

**步骤 1 — 非空检测**  
读取 `DFU_BANK_0_REGION_START`（即 App 起始地址）处两个 word，若均为 `0xFFFFFFFF`（未烧录的 flash 初始值），返回 `false`。

**步骤 2 — Bank 状态检查**  
从 Bootloader Settings（`0xFF000`）读取 `bank_0` 字段，必须为 `BANK_VALID_APP`。

**步骤 3 — CRC16 校验（可选）**  
若 Settings 中 `bank_0_crc != 0`，则对 App 区域计算 CRC16 并与存储值比对；若 `crc == 0` 则跳过此步骤。

> UF2 写入完成后，`bootloader_dfu_update_process(DFU_UPDATE_APP_COMPLETE)` 会自动将 `bank_0` 置为 `BANK_VALID_APP` 并存入 Settings，下次重启步骤 2 即可通过。

### 2.4 跳转地址决定：bootloader_app_start()

来源：`lib/sdk11/components/libraries/bootloader_dfu/bootloader.c:390–434`

```c
if (is_sd_existed()) {
    // 从 SoftDevice 末尾开始
    app_addr = SD_SIZE_GET(MBR_SIZE);         // S140 v6.1.1: 0x1000 + 0x25000 = 0x26000
    sd_softdevice_vector_table_base_set(app_addr);
} else {
    // 紧接 MBR 之后
    app_addr = MBR_SIZE;                       // = 0x1000
    // 通过 MBR 命令设置中断转发
    SD_MBR_COMMAND_IRQ_FORWARD_ADDRESS_SET(app_addr);
}
bootloader_util_app_start(app_addr);           // 保护 MBR/Bootloader flash 区域后跳转
```

**关键结论**：App 的链接地址必须与 Bootloader 运行时 `is_sd_existed()` 的检测结果严格一致：

| Flash 中 SD 状态 | Bootloader 跳转至 | App 必须链接至 |
|-----------------|-------------------|----------------|
| 存在 S140 v6.1.1 | `0x26000` | `0x26000` |
| 不存在 | `0x1000` | `0x1000` |

地址不匹配的表现：Bootloader 跳转到正确地址后，因 flash 内容为非预期值（全 `0xFF` 或另一个 App 的代码），导致 CPU 跑飞，App 无法运行。

---

## 3. 固件格式：Intel HEX 与 UF2

### 3.1 Intel HEX 格式

Intel HEX 是将二进制数据编码为 ASCII 十六进制字符串的文本格式，每行一条记录：

```
:LLAAAATT[DD...]CC
```

| 字段 | 字节数 | 说明 |
|------|--------|------|
| `:` | — | 记录起始标志 |
| `LL` | 1 | 本条记录的数据字节数 |
| `AAAA` | 2 | 16 位地址（加上当前段基地址得到实际地址） |
| `TT` | 1 | 记录类型（见下表） |
| `DD...` | LL | 数据字节 |
| `CC` | 1 | 校验和（所有字节之和取低 8 位取反 +1） |

#### 记录类型

| TT | 类型名称 | 说明 |
|----|---------|------|
| `00` | Data | 普通数据记录 |
| `01` | End of File | 文件结束，`LL=00`，无数据 |
| `04` | Extended Linear Address | 数据中的 16 位值作为地址高半部分（左移 16 位），用于寻址超过 64KB 的地址空间 |
| `05` | Start Linear Address | 程序入口地址（ARM Thumb 模式末位为 1） |

nRF52840 Flash 地址 > `0xFFFF`，必须使用 `04` 记录切换地址段。例如：

```
:020000040000FA       ← 设置高 16 位 = 0x0000，后续记录地址为 0x0000xxxx
:10100000...          ← 数据在 0x00001000（App 起始，无 SD 时）
:020000040001F9       ← 设置高 16 位 = 0x0001，后续记录地址为 0x0001xxxx（仅当地址 ≥ 0x10000）
```

#### merged.hex 中的数据段

- **无 SoftDevice 配置**：`merged.hex` 只含一段，起始地址 `0x1000`  
- **含 SoftDevice 配置**：`merged.hex` 含两段，SoftDevice（`0x1000`）和 App（`0x26000`），两段地址不连续

### 3.2 UF2 Block 格式

UF2（USB Flashing Format）由 Microsoft 设计，专为拖拽烧录而生。每个 Block **固定 512 字节**，结构如下：

来源：`lib/uf2/uf2.h`

```c
struct UF2_Block {
    // 头部（32 字节）
    uint32_t magicStart0;   // 魔术字 0（定义于 uf2.h）
    uint32_t magicStart1;   // 魔术字 1（定义于 uf2.h）
    uint32_t flags;         // 标志位
    uint32_t targetAddr;    // 本 block 在 flash 中的目标写入地址
    uint32_t payloadSize;   // 有效数据字节数（本项目固定为 256）
    uint32_t blockNo;       // 当前 block 的序号（从 0 开始）
    uint32_t numBlocks;     // 文件总 block 数
    uint32_t familyID;      // 目标芯片/用途标识（当 flags 包含 UF2_FLAG_FAMILYID 时有效）
    // 有效数据区（256 字节有效数据 + 220 字节填充 = 476 字节）
    uint8_t  data[476];
    // 尾部
    uint32_t magicEnd;      // 魔术字 2（定义于 uf2.h）
};
// sizeof(UF2_Block) = 512 字节
```

#### 关键 flags 位

| 宏名 | 值 | 含义 |
|------|----|------|
| `UF2_FLAG_NOFLASH` | `0x00000001` | 此 block 不写入 flash（元数据专用） |
| `UF2_FLAG_FAMILYID` | `0x00002000` | `familyID` 字段有效（本项目所有 block 均设置此位） |

#### familyID 对照表

来源：`src/usb/uf2/uf2cfg.h`

| 用途 | familyID | 宏名 | 来源行 |
|------|---------|------|--------|
| nRF52840 通用 App 升级 | `0xADA52840` | `CFG_UF2_FAMILY_APP_ID` | `uf2cfg.h:17` |
| nRF52833 通用 App 升级 | `0x621E937A` | `CFG_UF2_FAMILY_APP_ID`（nRF52833） | `uf2cfg.h:20` |
| Bootloader 自升级 | `0xd663823c` | `CFG_UF2_FAMILY_BOOT_ID` | `uf2cfg.h:8` |
| feather_nrf52840_express 专用 App | `0x239A0029` | `CFG_UF2_BOARD_APP_ID` | 由 VID/PID 计算 |

`CFG_UF2_BOARD_APP_ID` 的计算方式（来源：`uf2cfg.h:12`）：

```c
#define CFG_UF2_BOARD_APP_ID  ((USB_DESC_VID << 16) | USB_DESC_UF2_PID)
```

对于 feather_nrf52840_express（`board.h:58–59`）：`VID = 0x239A`，`UF2_PID = 0x0029`，故 `CFG_UF2_BOARD_APP_ID = 0x239A0029`。

Bootloader 的 `write_block()` 同时接受 `CFG_UF2_BOARD_APP_ID`（板级专用）和 `CFG_UF2_FAMILY_APP_ID`（通用），均视为 App 升级（来源：`ghostfat.c:write_block()` switch 分支）。

### 3.3 HEX 转 UF2

工具：`lib/uf2/utils/uf2conv.py`

```powershell
python lib/uf2/utils/uf2conv.py <input.hex> -c -f <familyID> -o <output.uf2>
```

| 参数 | 说明 |
|------|------|
| `-c` | 输入为 Intel HEX 格式（convert mode） |
| `-f 0xADA52840` | 指定目标芯片的 familyID |
| `-o output.uf2` | 输出文件路径 |

转换过程：
1. 解析 `.hex` 中所有 Data 段，提取地址和数据  
2. 按 256 字节切分，每份封装为一个 UF2 Block  
3. 填写 `targetAddr`（flash 地址）、`blockNo`、`numBlocks`、`familyID = 0xADA52840`  
4. 每个 block 输出 512 字节（32 字节头 + 476 字节数据区 + 4 字节尾魔术字）

**本项目（无 SoftDevice，nRF52840）的实际命令：**

```powershell
python lib/uf2/utils/uf2conv.py build\merged.hex -c -f 0xADA52840 -o app.uf2
```

---

## 4. UF2 虚拟 FAT 升级机制（ghostfat.c 源码分析）

### 4.1 虚拟文件系统概述

Bootloader 进入 USB DFU 模式时，通过 TinyUSB 的 MSC（Mass Storage Class）向主机呈现一个虚拟磁盘。该磁盘**不对应任何真实存储介质**，所有扇区内容均由 `src/usb/uf2/ghostfat.c` 在读取时动态生成。

文件系统参数（ghostfat.c 编译期常量）：

| 参数 | 值 | 含义 |
|------|-----|------|
| `BPB_SECTOR_SIZE` | `512` 字节 | FAT 标准扇区大小 |
| `BPB_SECTORS_PER_CLUSTER` | `1` | 1 扇区 = 1 簇 |
| `BPB_NUMBER_OF_FATS` | `2` | 双 FAT 副本（最高兼容性） |
| `BPB_ROOT_DIR_ENTRIES` | `64` | 根目录最大条目数 |
| FS 类型 | FAT16 | 由 `BPB_TOTAL_SECTORS` 决定 cluster 数量 |

磁盘逻辑扇区分配：

```
Sector 0            : Boot Block（BPB + 0x55AA 引导签名）
Sector 1 ~ N        : FAT0
Sector N+1 ~ 2N     : FAT1（内容与 FAT0 相同）
Sector 2N+1 ~ 2N+4  : 根目录（Root Directory）
Sector 2N+5 ~ ...   : 数据区（虚拟文件内容 + CURRENT.UF2 动态数据）
```

### 4.2 三个虚拟文件

来源：`ghostfat.c:144–148`

```c
static struct TextFile const info[] = {
    {.name = "INFO_UF2TXT", .content = infoUf2File},
    {.name = "INDEX   HTM", .content = indexFile},
    // CURRENT.UF2 必须是最后一个元素，content 必须为 NULL
    {.name = "CURRENT UF2", .content = NULL},
};
```

FAT 目录中的名字格式为"8.3 格式"无分隔符，因此 `"INFO_UF2TXT"` 在主机上显示为 `INFO_UF2.TXT`。

#### INFO_UF2.TXT

字符串在 Bootloader 启动时由 `uf2_init()`（`ghostfat.c:250`）动态拼接：

```
UF2 Bootloader <版本号>
Model: <产品名>
Board-ID: <板型 ID>
Date: <编译日期>
SoftDevice: S140 6.1.1      ← is_sd_existed() 返回 true 时
SoftDevice: not found        ← is_sd_existed() 返回 false 时
```

#### INDEX.HTM

静态 HTML，包含一段 JavaScript，将浏览器重定向至 `UF2_INDEX_URL`（板级配置中定义的产品页 URL，如 `https://adafruit.com` 的对应页面）。

#### CURRENT.UF2

`content = NULL` 是特殊标记，表示文件内容在 `read_block()` 中按需生成，而非静态字符串。

来源：`ghostfat.c:358–379`（`read_block()` 的 CURRENT.UF2 生成分支）

```c
} else { // generate the UF2 file data on-the-fly
    sectionIdx -= NUM_FILES - 1;
    uint32_t addr = USER_FLASH_START + (sectionIdx * UF2_FIRMWARE_BYTES_PER_SECTOR);
    if (addr < CFG_UF2_FLASH_SIZE) {
        UF2_Block *bl = (void *)data;
        bl->magicStart0 = UF2_MAGIC_START0;
        bl->magicStart1 = UF2_MAGIC_START1;
        bl->magicEnd    = UF2_MAGIC_END;
        bl->blockNo     = sectionIdx;
        bl->numBlocks   = UF2_SECTORS;
        bl->targetAddr  = addr;
        bl->payloadSize = UF2_FIRMWARE_BYTES_PER_SECTOR;  // = 256
        bl->flags       = UF2_FLAG_FAMILYID;
        bl->familyID    = CFG_UF2_BOARD_APP_ID;
        memcpy(bl->data, (void *)addr, bl->payloadSize);   // 直接从 flash 读取
    }
}
```

每次主机读取 `CURRENT.UF2` 的某个扇区，`read_block()` 就从 flash 的 `[USER_FLASH_START, USER_FLASH_END)` 区域读取对应 256 字节，封装成 UF2 Block 实时返回。可用于备份当前固件。

### 4.3 UF2 写入流程

#### 入口：USB MSC 写回调

来源：`src/usb/msc_uf2.c:141`

```
tud_msc_write10_cb()
  │  主机每写入 512 字节扇区时调用
  ▼
write_block(block_no, data, &wr_state)
  ├── is_uf2_block(bl) == false → return -1（静默跳过，不视为错误）
  └── is_uf2_block(bl) == true  → 按 familyID 分派处理
```

#### is_uf2_block() 识别条件

来源：`ghostfat.c:221–228`

```c
static inline bool is_uf2_block(UF2_Block const *bl) {
    return (bl->magicStart0 == UF2_MAGIC_START0)              &&
           (bl->magicStart1 == UF2_MAGIC_START1)              &&
           (bl->magicEnd    == UF2_MAGIC_END)                 &&
           (bl->flags & UF2_FLAG_FAMILYID)                    &&
           !(bl->flags & UF2_FLAG_NOFLASH)                    &&
           (bl->payloadSize == UF2_FIRMWARE_BYTES_PER_SECTOR) &&  // 必须为 256
           !(bl->targetAddr & 0xff);                               // 地址必须 256 字节对齐
}
```

**识别依据是 block 自身的内容（魔术字 + payloadSize + flags），与文件名完全无关。** 主机拖拽任意 `.uf2` 文件到虚拟磁盘时，OS 还会写入大量 FAT 和目录元数据扇区，这些扇区均不满足上述条件，被 `return -1` 静默跳过。

#### App 升级路径（familyID = `CFG_UF2_BOARD_APP_ID` 或 `CFG_UF2_FAMILY_APP_ID`）

来源：`ghostfat.c:write_block()` 的 App case

按目标地址分三种处理：

| `bl->targetAddr` 范围 | 处理方式 |
|----------------------|---------|
| `[USER_FLASH_START, USER_FLASH_END)` 即 `[0x1000, 0xEA000)` | `flash_nrf5x_write(targetAddr, data, 256, true)` 直接写入 |
| `< USER_FLASH_START`（即 MBR 区域 `0x0`–`0xFFF`） | 静默跳过（UF2 包含 SD 时会出现此情况，此时 SD 写入地址落在 `[0x1000, 0xEA000)` 范围内正常写入） |
| 其他地址 | `return -1`，视为失败 |

> 代码注释（`ghostfat.c:App case`）：*"SoftDevice is considered as part of application and can be (or not) included in uf2."*  
> SoftDevice 的 flash 地址（`0x1000`–`0x25FFF`）完全落在 `in_app_space()` 范围内，含 SD 的 UF2 可以正常烧录。

#### Bootloader 自升级路径（familyID = `CFG_UF2_FAMILY_BOOT_ID`）

来源：`ghostfat.c:write_block()` 的 Bootloader case，分三步：

**步骤 1 — UICR 验证**（`bl->targetAddr == 0x10001000`）  
从 block 数据中读取 `0x10001014`（bootloader 地址）和 `0x10001018`（MBR Params 地址），与当前固定值比对，不匹配则 `state->aborted = true`，中止升级。

**步骤 2 — 新 Bootloader 写入缓冲区**（`bl->targetAddr` 在 `[BOOTLOADER_ADDR_START, BOOTLOADER_ADDR_END)` 内）  
- 首先验证 Board ID（`bootloaderConfig` 中的 `CFG_BOOTLOADER_BOARD_ID` 与 `(VID<<16)|PID` 比对），防止刷入错误板型的 Bootloader  
- 写入目标地址为 App 区域高端（偏移 `BOOTLOADER_ADDR_END - USER_FLASH_END`），避免在传输中途直接覆盖正在运行的 Bootloader

**步骤 3 — 激活**  
所有 block 写完后，通过 MBR 的 `SD_MBR_COMMAND_COPY_BL` 命令将缓冲区内容复制到 `0xF4000`。

> `#if 0` 注释代码（`ghostfat.c:502–508`）禁止了 Bootloader UF2 中捆绑 SoftDevice，防止混淆：*"don't allow bundle SoftDevice to prevent confusion"*

#### 写入完成判定

来源：`ghostfat.c:write_block()` 底部 + `msc_uf2.c:162`

```c
// ghostfat.c: 所有 block 写完后 flush flash 写缓冲
if (state->numWritten >= state->numBlocks) {
    flash_nrf5x_flush(true);
    if (state->update_bootloader && !state->has_uicr) {
        state->aborted = true;  // Bootloader 升级必须包含 UICR block
    }
}
```

```c
// msc_uf2.c: USB 写完成回调
// numWritten >= numBlocks 时触发
bootloader_dfu_update_process(DFU_UPDATE_APP_COMPLETE);
// → 将 bank_0 置为 BANK_VALID_APP → 写入 Bootloader Settings → 重启
```

重启后 `bootloader_app_is_valid()` 通过，跳转到新 App。

#### OS 防重写保护

来源：`ghostfat.c:536–543`

```c
// 每个 blockNo 只计入一次，防止 OS 缓存机制重复写同一 block
if (!(state->writtenMask[pos] & mask)) {
    state->writtenMask[pos] |= mask;
    state->numWritten++;
}
```

`writtenMask` 是位图，记录每个 `blockNo` 是否已被写入，防止 OS 的写缓冲/重试机制导致 `numWritten` 超额统计。

---

## 5. App 偏移地址配置与验证实战

### 5.1 配置原则

App 的链接起始地址必须与第 2.4 节结论严格一致——由 flash 中 SoftDevice 的实际存在状态决定，而非由构建时的编译选项决定。

在 Zephyr/NCS 项目中，通过 `pm_static.yml`（Partition Manager 静态配置文件）指定分区布局，构建系统据此生成链接器参数，最终决定 App 被链接到哪个地址。

### 5.2 有 SoftDevice 的配置（App 链接到 0x26000）

适用场景：App 使用 BLE 功能，且 flash 中已烧录 S140 SoftDevice。

`pm_static.yml` 示例：

```yaml
nrf5_mbr_and_sd:
  address: 0x0
  end_address: 0x26000
  region: flash_primary
  size: 0x26000
app:
  address: 0x26000
  end_address: 0x100000
  region: flash_primary
  size: 0xda000
sram_primary:
  address: 0x20000000
  end_address: 0x20040000
  region: sram_primary
  size: 0x40000
```

此时 `merged.hex` 包含两个不连续段：SoftDevice（起始 `0x1000`）和 App（起始 `0x26000`）。

### 5.3 无 SoftDevice 的配置（App 链接到 0x1000）

适用场景：App 不使用 BLE，不需要 SoftDevice，App 紧接 MBR 存放。

本项目 cdc_acm 工程修改后的 `pm_static.yml`：

```yaml
nrf5_mbr:
  address: 0x0
  end_address: 0x1000
  placement:
    after:
    - start
  region: flash_primary
  size: 0x1000
app:
  address: 0x1000
  end_address: 0x100000
  region: flash_primary
  size: 0xff000
sram_primary:
  address: 0x20000000
  end_address: 0x20040000
  region: sram_primary
  size: 0x40000
```

此时 `merged.hex` 只含一段，起始 `0x1000`。

### 5.4 三步验证法

#### 步骤 1：检查 partitions.yml

构建完成后，检查 Partition Manager 生成的实际分区信息：

```powershell
Get-Content build\partitions.yml
```

确认 `app` 分区的 `address` 字段为目标值（`0x1000` 或 `0x26000`）。

#### 步骤 2：检查 merged.hex 首行地址

```powershell
Get-Content build\merged.hex -TotalCount 5
```

**无 SoftDevice，App 从 `0x1000` 开始的预期输出：**

```
:020000040000FA        ← Extended Linear Address: 高 16 位 = 0x0000
:10100000...           ← 第一条数据记录，AAAA = 0x1000
```

**含 SoftDevice，SoftDevice 从 `0x1000`、App 从 `0x26000` 开始的预期输出：**

```
:020000040000FA        ← Extended Linear Address
:10100000...           ← SoftDevice 数据，从 0x1000 开始
...
:10260000...           ← App 数据，从 0x26000 开始（中间有跳转）
```

#### 步骤 3：硬件 UF2 拖拽验证

1. **进入 DFU 模式**：双击 Reset 键（500ms 内快速点击两次），等待 USB 大容量存储设备（例如 `FTHR840BOOT`）出现

2. **确认 INFO_UF2.TXT 内容**：打开虚拟磁盘中的 `INFO_UF2.TXT`，确认 `SoftDevice:` 行与当前 flash 实际状态一致

3. **转换并拖拽 UF2**：

   ```powershell
   python lib/uf2/utils/uf2conv.py build\merged.hex -c -f 0xADA52840 -o app.uf2
   # 将 app.uf2 拖拽到虚拟磁盘根目录
   ```

4. **等待自动重启**：虚拟磁盘自动弹出，设备重启后运行新 App

### 5.5 故障排查

| 现象 | 根本原因 | 解决方法 |
|------|---------|---------|
| 拖拽后重启，App 无法运行 | App 链接地址与 flash 中 SD 存在状态不匹配（第 2.4 节） | 核对 `pm_static.yml`；通过 `INFO_UF2.TXT` 确认 SD 实际状态 |
| 虚拟磁盘不出现 | 未进入 DFU 模式 | 确认双击操作；检查 `UICR.BOOTLOADERADDR` 是否为 `0xF4000` |
| `INFO_UF2.TXT` 显示 `SoftDevice: not found` | SD 未烧录 | 若需 BLE：通过 J-Link 先烧录 SD hex；若不需 BLE：将 App 链接到 `0x1000` |
| 拖拽后磁盘不弹出，无反应 | familyID 不匹配，所有 block 均被跳过 | 检查转换命令中 `-f` 是否为 `0xADA52840`；确认 UF2 文件的 familyID |
| 拖拽后磁盘弹出，但 `numWritten` 未达 `numBlocks` | UF2 文件 block 数与 `numBlocks` 字段描述不符 | 重新用 `uf2conv.py` 从 hex 转换，不要手动修改 UF2 文件 |
