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
 *   Active-low: pull-up, press connects pin to GND.
 *   BUTTON_DFU     : P0.10 -- hold on power-on to enter serial/USB DFU mode.
 *   BUTTON_DFU_OTA : P0.11 -- hold on power-on to enter BLE OTA DFU mode.
 *   Temporarily disabled to isolate boot-loop root cause.
 *------------------------------------------------------------------*/
#if 1
  #define BUTTON_DFU     PINNUM(0, 10)
  #define BUTTON_DFU_OTA PINNUM(0, 11)
  #define BUTTON_PULL    NRF_GPIO_PIN_PULLUP
#endif

/*------------------------------------------------------------------*/
/* Power
 *   Board uses pure LDO supply (no DC/DC inductor fitted).
 *   ENABLE_DCDC_0 and ENABLE_DCDC_1 default to 0 in boards.h;
 *   do NOT define them here to keep DCDC converters disabled.
 *------------------------------------------------------------------*/

//--------------------------------------------------------------------+
// BLE OTA
//--------------------------------------------------------------------+
#define BLEDIS_MANUFACTURER "Nodara"
#define BLEDIS_MODEL        "Nodara"

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
#define UF2_PRODUCT_NAME  "Nodara"
#define UF2_VOLUME_LABEL  "Nodara"
#define UF2_BOARD_ID      "Nodara"
#define UF2_INDEX_URL     "https://github.com/adafruit/Adafruit_nRF52_Bootloader"

#endif // _MESHTASTIC_V1_H
