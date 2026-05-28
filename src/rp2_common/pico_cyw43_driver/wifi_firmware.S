/*
 * Copyright (c) 2024 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "boot/picobin.h"
            
#if PICO_CRT0_IMAGE_TYPE_TBYB
#define CRT0_TBYB_FLAG PICOBIN_IMAGE_TYPE_EXE_TBYB_BITS
#else
#define CRT0_TBYB_FLAG 0
#endif

 section `.wifi_fw`:DATA:ROOT(2)
 public _start
_start:
    dc32 0
    dc32 0
    dc32 0
    dc32 0

 alignrom 2
embedded_block:
    dc32 PICOBIN_BLOCK_MARKER_START

    dc8 PICOBIN_BLOCK_ITEM_1BS_IMAGE_TYPE
    dc8 0x1 // 1 word
    dc16 PICOBIN_IMAGE_TYPE_IMAGE_TYPE_AS_BITS(EXE) | \
       PICOBIN_IMAGE_TYPE_EXE_CPU_AS_BITS(RISCV) | \
       PICOBIN_IMAGE_TYPE_EXE_CHIP_AS_BITS(RP2350) | \
       CRT0_TBYB_FLAG

// Entry point into SRAM
    dc8 PICOBIN_BLOCK_ITEM_1BS_ENTRY_POINT
    dc8 0x3 // word size to next item
    dc8 0 // pad
    dc8 0 // pad
    dc32 _start
    dc32 0x20082000 // stack pointer

_lm_item:
    dc8 PICOBIN_BLOCK_ITEM_LOAD_MAP
    dc8 7
    dc8 0 // pad
    dc8 2 // 2 entries
// To sign the firmware
    dc32 (_start - _lm_item)
    dc32 _start
    dc32 (firmware_end - _start)
// But clear SRAM if actually running this, so it doesn't boot
    dc32 0
    dc32 _start
    dc32 0x00082000

    dc8 PICOBIN_BLOCK_ITEM_2BS_LAST
    dc16 (embedded_block_end - embedded_block - 16 ) / 4 // total size of all
    dc8 0
    dc32 0
    dc32 PICOBIN_BLOCK_MARKER_END
embedded_block_end:

#include "firmware_blob.S"

firmware_end:

 end
