# nRF5 SDK Linux 开发入门

## 1. 环境准备

### 1.1 前置条件

本文假设已通过 nRF Connect for VS Code 插件安装好 NCS（nRF Connect SDK v3.2.x 或以上）。

NCS 工具链内置以下烧录工具，需在 **NCS 终端**（通过 VS Code 插件打开）中调用：

| 工具 | 用途 |
|------|------|
| `nrfutil` | J-Link 烧录、设备管理（Nordic 主推） |
| `pyocd` | CMSIS-DAP/DAPLink 烧录 |

> 上述工具在普通终端中不可用，必须通过 NCS 终端调用。

### 1.2 安装编译工具链

nRF5 SDK 的 armgcc 构建系统需要标准的 `arm-none-eabi-gcc`（工具链前缀 `arm-none-eabi-`）。NCS 工具链内置的 `arm-zephyr-eabi-gcc` 前缀不同，**不可替代**。

推荐使用 xPack 管理工具链，支持多版本共存：

```bash
# 安装 xpm（需要 Node.js）
sudo npm install -g xpm

# 安装指定版本（nRF5 SDK 17.x 兼容 GCC 10.x / 11.x）
xpm install -g @xpack-dev-tools/arm-none-eabi-gcc@10.3.1-2.3.1
```

安装完成后，工具链位于：
```
~/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/10.3.1-2.3.1/.content/bin/
```

> **版本限制**：GCC 12.x 及以上版本编译 nRF5 SDK 17.x 会触发
> `-Werror=array-bounds` 错误，请使用 10.x 或 11.x。

查询 xPack 可用版本：
```bash
npm show @xpack-dev-tools/arm-none-eabi-gcc versions --json
```

### 1.3 安装 SEGGER J-Link Software

`nrfutil` 操作 J-Link 调试器时，依赖系统安装的 J-Link 共享库（`libjlinkarm.so`）。未安装时所有 J-Link 操作均失败并提示：
```
WARNING: JLinkARM DLL not found.
```

从 https://www.segger.com/downloads/jlink/ 下载：
- 选择 `J-Link Software and Documentation Pack` → `Linux` → `DEB Installer 64-bit`

```bash
sudo dpkg -i JLink_Linux_V*_x86_64.deb
```


---

## 2. 工程结构

### 2.1 与 SDK 的目录关系

nRF5 SDK 示例工程通过 Makefile 中的 `SDK_ROOT` 变量定位 SDK 根目录，默认使用相对路径（如 `../../../../../..`，从 `armgcc/` 目录向上 6 级）。

若工程放置在 SDK 目录外，编译时需显式覆盖 `SDK_ROOT`：

```
/him/
├── nRF5_SDK_17.1.0_ddde560/   ← SDK 根目录（SDK_ROOT）
└── nrf5/
    └── blinky_freertos/       ← 工程目录（在 SDK 外）
```

### 2.2 平台目录命名

每个示例工程按开发板型号分级组织：

| 目录 | 开发板 | 芯片 |
|------|--------|------|
| `pca10040/` | nRF52 DK | nRF52832 |
| `pca10056/` | nRF52840 DK | nRF52840 |
| `pca10100/` | nRF52833 DK | nRF52833 |

每个板型目录下再按 SoftDevice 配置分级：

| 目录 | 含义 |
|------|------|
| `blank/` | 无 SoftDevice（裸机，不使用 BLE 协议栈） |
| `s132/` | 搭配 S132 SoftDevice（nRF52832 BLE） |
| `s140/` | 搭配 S140 SoftDevice（nRF52840 BLE） |

### 2.3 构建系统选择

每个平台目录下提供多套构建配置，Linux 下使用 `armgcc/`：

| 子目录 | 工具链 | 平台支持 |
|--------|--------|---------|
| `armgcc/` | GNU Make + arm-none-eabi-gcc | Linux / Windows / macOS |
| `iar/` | IAR Embedded Workbench | Windows |
| `arm5_no_packs/` | Keil MDK | Windows |
| `ses/` | SEGGER Embedded Studio | Linux / Windows / macOS |


---

## 3. 编译工程

### 3.1 执行编译

进入目标板型的 `armgcc/` 目录，执行 `make` 并传入路径参数：

```bash
cd /him/nrf5/blinky_freertos/pca10056/blank/armgcc

make \
  SDK_ROOT="/him/nRF5_SDK_17.1.0_ddde560" \
  GNU_INSTALL_ROOT="$HOME/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/10.3.1-2.3.1/.content/bin/" \
  GNU_VERSION="10.3.1" \
  GNU_PREFIX="arm-none-eabi"
```

**参数说明：**

| 参数 | 说明 |
|------|------|
| `SDK_ROOT` | nRF5 SDK 根目录绝对路径；工程在 SDK 目录内时可省略 |
| `GNU_INSTALL_ROOT` | 编译器 `bin/` 目录路径，末尾必须含 `/` |
| `GNU_VERSION` | 编译器版本号 |
| `GNU_PREFIX` | 工具链前缀，固定为 `arm-none-eabi` |

也可将参数写入 SDK 的 `components/toolchain/gcc/Makefile.posix`，避免每次手动传入：

```makefile
GNU_INSTALL_ROOT ?= $(HOME)/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/10.3.1-2.3.1/.content/bin/
GNU_VERSION ?= 10.3.1
GNU_PREFIX ?= arm-none-eabi
```

**构建输出**（位于 `_build/` 目录）：

| 文件 | 用途 |
|------|------|
| `nrf52840_xxaa.hex` | Intel HEX 格式，烧录用（推荐） |
| `nrf52840_xxaa.bin` | 纯二进制格式，部分工具烧录用 |
| `nrf52840_xxaa.out` | ELF 格式，含调试符号，用于 GDB 调试 |

### 3.2 配置 VS Code IntelliSense

nRF5 SDK 的 Makefile 不内置 `compile_commands.json` 生成目标，需借助外部工具。
`bear` 是常见方案，但在交叉编译场景下其拦截机制对 `arm-none-eabi-gcc` 无效，实际生成空文件。因此使用 `compiledb`，它通过解析 make 的 dry-run 输出来提取编译命令，不依赖进程拦截。

> 在 `ncs` 终端中执行, 安装在 ncs 内置的 `python` 环境中; 避免污染系统 `pip3`;

**安装 compiledb：**

```bash
pip install compiledb
```

**生成 `compile_commands.json`：**

在每次编译时，将 `make` 替换为 `compiledb make`，其余参数完全相同：

```bash
cd /him/nrf5/blinky_freertos/pca10056/blank/armgcc

compiledb make \
  SDK_ROOT="/him/nRF5_SDK_17.1.0_ddde560" \
  GNU_INSTALL_ROOT="$HOME/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/10.3.1-2.3.1/.content/bin/" \
  GNU_VERSION="10.3.1" \
  GNU_PREFIX="arm-none-eabi"
```

`compiledb` 会在当前目录（`armgcc/`）生成 `compile_commands.json`，内容为每个 `.c`/`.S` 文件的完整编译命令，包括所有 `-I`（头文件搜索路径）和 `-D`（宏定义）。

**配置 VS Code 读取该文件：**

在工程根目录的 `.vscode/c_cpp_properties.json` 中指定文件路径：

```json
{
    "configurations": [
        {
            "name": "nRF52840",
            "compileCommands": "${workspaceFolder}/pca10056/blank/armgcc/compile_commands.json",
            "intelliSenseMode": "gcc-arm"
        }
    ],
    "version": 4
}
```

配置生效后，VS Code C/C++ 扩展能够正确解析 SDK 头文件路径和宏定义，头文件跳转、宏展开、代码补全均可正常工作。源文件变动后重新运行 `compiledb make` 即可更新索引。


---

## 4. 烧录工程

以下操作均在 **NCS 终端**中执行。

### 4.1 查看已连接设备

烧录前先确认设备被正确识别，获取序列号：

```bash
nrfutil device list
```

示例输出：
```
150710309
Product         J-Link
Ports           /dev/ttyACM0
Traits          serialPorts, usb
```

### 4.2 J-Link 烧录（主要方式）

```bash
nrfutil device program \
  --firmware <hex文件路径> \
  --serial-number <序列号> \
  --options chip_erase_mode=ERASE_ALL
```

实际示例：
```bash
nrfutil device program \
  --firmware /him/nrf5/blinky_freertos/pca10056/blank/armgcc/_build/nrf52840_xxaa.hex \
  --serial-number 150710309 \
  --options chip_erase_mode=ERASE_ALL
```

### 4.3 CMSIS-DAP / DAPLink 烧录（备用）

若使用 DAPLink 调试器而非 J-Link：

```bash
pyocd load \
  --target nrf52840 \
  <hex文件路径>
```

> **已知问题**：pyocd + DAPLink 烧录完成后可能输出
> `Error during board uninit`，这是断开连接时的清理步骤报错，
> 固件已正确写入，可忽略。

> **APPROTECT 锁定**：若设备被保护，pyocd 会输出
> `NRF52840 APPROTECT enabled: will try to unlock via mass erase`
> 并自动尝试解锁。若 pyocd 版本较旧无此逻辑，需先执行第 5 章的
> recover 操作再烧录。


---

## 5. 常用指令速查

### 5.1 APPROTECT 说明

nRF52840 revision 3（build code **Fxx** 及以后）出厂时 APPROTECT 默认启用，调试接口被锁定，表现为调试工具无法连接芯片（`SoCTarget has no selected core` / `Memory transfer fault`）。

解锁的唯一方式是通过 CTRL-AP 发送 ERASEALL 命令（即 recover），该操作会**完全擦除 flash、UICR 和 RAM**。

nRF5 SDK 17.x 的 MDK 启动代码（`system_nrf52_approtect.h`）在未定义 `ENABLE_APPROTECT` 时，会在每次启动时向 `APPROTECT.DISABLE` 写入 `SwDisable`，**一旦烧入 SDK 固件，调试口在复位后保持开启，无需每次手动解锁**。

### 5.2 解锁芯片（recover）

当设备被 APPROTECT 锁定时执行，需已安装 J-Link Software（见第 1.3 节）：

```bash
# NCS 终端
nrfutil device recover --serial-number <序列号>
```

recover 完成后写入一段小固件，防止复位后重新锁定，之后可直接烧录。

### 5.3 擦除芯片

```bash
# J-Link（NCS 终端）
nrfutil device erase --serial-number <序列号>

# DAP / pyocd（NCS 终端）
pyocd erase --target nrf52840 --chip
```

### 5.4 烧录 + 验证

```bash
# J-Link（NCS 终端）
nrfutil device program \
  --firmware <hex文件路径> \
  --serial-number <序列号> \
  --options chip_erase_mode=ERASE_ALL,verify=VERIFY_READ

# DAP / pyocd（NCS 终端）
pyocd load --target nrf52840 <hex文件路径>
```

### 5.5 复位设备

```bash
# J-Link（NCS 终端）
nrfutil device reset --serial-number <序列号>

# DAP / pyocd（NCS 终端）
pyocd reset --target nrf52840
```

### 5.6 检查工具安装状态

```bash
# 检查编译工具链（普通终端）
~/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/10.3.1-2.3.1/.content/bin/arm-none-eabi-gcc --version

# 检查 J-Link 库是否已安装（普通终端）
find /usr/lib /opt -name "libjlinkarm.so*" 2>/dev/null

# 检查 NCS 终端内工具版本（NCS 终端）
nrfutil --version
pyocd --version
```




