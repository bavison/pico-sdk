/*
 * Copyright (c) 2024 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#if !PICO_RP2040
#include "pico/asm_helper.S"
#include "pico/float.h"

 pico_default_asm_setup

float_section macro name
#if PICO_FLOAT_IN_RAM
 section BACKTICK_QUOTED(RAM_SECTION_NAME(name)):CODE:NOROOT(2)
#else
 section BACKTICK_QUOTED(SECTION_NAME(name)):CODE:NOROOT(2)
#endif
 endm

 float_section int2float
#if PICO_ASSEMBLER_IS_IAR
 wrapper_func __aeabi_i2f
#endif
 regular_func int2float
    vmov s0, r0
    vcvt.f32.s32 s0, s0
#if !defined(__ARM_PCS_VFP)
	vmov r0, s0
#endif
	bx lr

 float_section uint2float
#if PICO_ASSEMBLER_IS_IAR
 wrapper_func __aeabi_ui2f
#endif
 regular_func uint2float
	vmov s0, r0
	vcvt.f32.u32 s0, s0
#if !defined(__ARM_PCS_VFP)
	vmov r0, s0
#endif
	bx lr

 float_section float2int
 regular_func float2int
#if !defined(__ARM_PCS_VFP)
	vmov s0, r0
#endif
	vcvtm.s32.f32 s0, s0
	vmov r0, s0
	bx lr

 float_section float2int_z
 regular_func float2int_z
#if !defined(__ARM_PCS_VFP)
	vmov s0, r0
#endif
	vcvt.s32.f32 s0, s0
	vmov r0, s0
	bx lr

 float_section float2uint
 regular_func float2uint
 regular_func float2uint_z
#if !defined(__ARM_PCS_VFP)
	vmov s0, r0
#endif
	vcvt.u32.f32 s0, s0
	vmov r0, s0
	bx lr

 float_section float2fix_z
 regular_func float2fix_z
#if defined(__ARM_PCS_VFP)
  mov r1, r0
  vmov r0, s0
#endif
float2fix_z_entry:
  ubfx r2, r0, #23, #8
  cbz r2, label_2
             // input is zero or denormal
  cmp r2, #0xff
  beq label_3
         // input infinite or nan
  adds r2, r1
  ble label_2
         // modified input is denormal so zero
  cmp r2, #0xff
  bge label_3
         // modified input is infinite
label_1:
  bfi r0, r2, #23, #8
  vmov s0, r0
  vcvt.s32.f32 s0, s0
  vmov r0, s0
  bx lr
label_2:
  movs r0, #0
  bx lr
label_3:
  mvn r1, #0x80000000
  add r0, r1, r0, lsr#31 // so -Inf → 0x80000000, +Inf → 0x7fffffff
  bx lr

 float_section float2fix
 regular_func float2fix
#if defined(__ARM_PCS_VFP)
  mov r1, r0
  vmov r0, s0
#endif
  ubfx r2, r0, #23, #8
  cbz r2, label_5
             // input is zero or denormal
  cmp r2, #0xff
  beq label_6
         // input infinite or nan
  adds r2, r1
  ble label_5
         // modified input is denormal so zero
  cmp r2, #0xff
  bge label_6
         // modified input is infinite
label_4:
  bfi r0, r2, #23, #8
  vmov s0, r0
  vcvtm.s32.f32 s0, s0
  vmov r0, s0
  bx lr
label_5:
  movs r0, #0
  bx lr
label_6:
  mvn r1, #0x80000000
  add r0, r1, r0, lsr#31 // so -Inf → 0x80000000, +Inf → 0x7fffffff
  bx lr

 float_section float2ufix
 regular_func float2ufix
 regular_func float2ufix_z
#if defined(__ARM_PCS_VFP)
  mov r1, r0
  vmov r0, s0
#endif
  ubfx r2, r0, #23, #8
  cbz r2, label_8
             // input is zero or denormal
  cmp r2, #0xff
  beq label_9
         // input infinite or nan
  adds r2, r1
  ble label_8
         // modified input is denormal so zero
  cmp r2, #0xff
  bge label_9
         // modified input is infinite
label_7:
  bfi r0, r2, #23, #8
  vmov s0, r0
  vcvtm.u32.f32 s0, s0
  vmov r0, s0
  bx lr
label_8:
  movs r0, #0
  bx lr
label_9:
  mvn r0, r0, asr #31
  bx lr
#endif

 end
