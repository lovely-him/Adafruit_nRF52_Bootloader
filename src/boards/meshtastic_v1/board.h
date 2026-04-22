/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2024 sainstore
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#ifndef _MESHTASTIC_V1_H
#define _MESHTASTIC_V1_H

/*------------------------------------------------------------------*/
/* LED
 *   3 LEDs, all active-low (GPIO low = LED on).
 *   Bootloader PWM only drives 2: primary (Red) and secondary (Blue).
 *   Green LED (P0.14) is unused by bootloader but available to app.
 *------------------------------------------------------------------*/
#define LEDS_NUMBER       2
#define LED_PRIMARY_PIN   PINNUM(1, 3)   // Red   LED (LED3 in NCS DTS)
#define LED_SECONDARY_PIN PINNUM(1, 1)   // Blue  LED (LED1 in NCS DTS)
#define LED_STATE_ON      0              // Active-low: drive low to turn on

/*------------------------------------------------------------------*/
/* BUTTON
 *   All bootloader DFU buttons MUST share the same BUTTON_PULL.
 *
 *   BUTTON_DFU     : P1.10 (cancel / SW_BUT) -- hold on power-on to enter
 *                    serial/USB DFU mode.
 *   BUTTON_DFU_OTA : P0.11 (right  / SW_F5)  -- hold on power-on to enter
 *                    BLE OTA DFU mode.
 *
 *   *** PCB NOTE ***
 *   Both buttons use PULLUP (active-low: button connects pin to GND).
 *   - P1.10 is already wired to GND (matches PULLUP).
 *   - P0.11 must also be wired to GND (NOT to VCC) on the PCB.
 *     If the original schematic had P0.11 pulling to VCC, change the
 *     button circuit to pull-to-GND before enabling BUTTON_DFU_OTA.
 *     Until the PCB is corrected, comment out BUTTON_DFU_OTA below.
 *------------------------------------------------------------------*/
#define BUTTON_DFU        PINNUM(1, 10)  // cancel button (SW_BUT)
#define BUTTON_DFU_OTA    PINNUM(0, 11)  // right button  (SW_F5) -- needs PCB fix
#define BUTTON_PULL       NRF_GPIO_PIN_PULLUP

/*------------------------------------------------------------------*/
/* Power
 *   Board uses pure LDO supply (no DC/DC inductor fitted).
 *   ENABLE_DCDC_0 and ENABLE_DCDC_1 default to 0 in boards.h;
 *   do NOT define them here to keep DCDC converters disabled.
 *------------------------------------------------------------------*/

//--------------------------------------------------------------------+
// BLE OTA
//--------------------------------------------------------------------+
#define BLEDIS_MANUFACTURER "sainstore"
#define BLEDIS_MODEL        "Meshtastic v1"

//--------------------------------------------------------------------+
// USB
//   VID 0x1915 = Nordic Semiconductor (placeholder only).
//   Replace with your own VID/PID before production.
//--------------------------------------------------------------------+
#define USB_DESC_VID          0x1915
#define USB_DESC_UF2_PID      0x520A
#define USB_DESC_CDC_ONLY_PID 0x520B

//--------------------------------------------------------------------+
// UF2
//--------------------------------------------------------------------+
#define UF2_PRODUCT_NAME  "Meshtastic v1"
#define UF2_VOLUME_LABEL  "MSHTV1BOOT"
#define UF2_BOARD_ID      "nRF52840-Meshtastic-v1"
#define UF2_INDEX_URL     "https://github.com/lovely-him/Adafruit_nRF52_Bootloader"

#endif // _MESHTASTIC_V1_H
