
## 进入 DFU 的所有方式

**方式一：上电/Reset 时按住 `BUTTON_DFU`（P1.10 cancel）**
→ 进入 **USB UF2 + CDC Serial DFU**，电脑出现 `MSHTV1BOOT` 拖拽 U 盘

**方式二：上电/Reset 时同时按住 `BUTTON_DFU` + `BUTTON_DFU_OTA`（P0.11 right）**
→ 进入 **BLE OTA DFU**，手机可通过 nRF Connect App 无线升级

**方式三：双击 Reset（500 ms 内按两次）**
→ 进入 **USB UF2 + CDC Serial DFU**，与方式一效果相同
→ 原理：第一次 Reset 时 bootloader 在 RAM 中写入 `DFU_DBL_RESET_MAGIC`，等待 500 ms；第二次 Reset 检测到这个魔法数就进入 DFU

**方式四：App 主动触发（软件层面）**
→ App 代码写 `NRF_POWER->GPREGRET = 0x57`（UF2）或 `0x4e`（Serial only）然后 reset
→ 典型用途：App 内置 OTA 升级入口，用户点击"进入固件升级"按钮

---

两个按钮的分工小结：

| 按钮 | 单独按 | 组合按 |
|------|--------|--------|
| `BUTTON_DFU`（P1.10） | USB/拖拽 DFU | — |
| `BUTTON_DFU_OTA`（P0.11） | **无效**（单独按不触发任何 DFU） | 与 `BUTTON_DFU` 同时按 → BLE OTA |

`BUTTON_DFU_OTA` 单独按住上电**不会**进入任何 DFU 模式，它只在与 `BUTTON_DFU` 组合时才有意义。
