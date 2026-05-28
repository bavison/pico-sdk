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

float_wrapper_section macro func
 float_section WRAPPER_FUNC_NAME(func)
 endm

 float_wrapper_section conv_tof

#if defined(__ARM_PCS_VFP)
 regular_func int642float
 movs r2,#0       // fall through
 regular_func fix642float
 push {lr}
 bl fix642float_softfp
 vmov s0,r0
 pop {pc}
#endif

// convert int64 to float, rounding
 wrapper_func __aeabi_l2f
#if !defined(__ARM_PCS_VFP)
 regular_func int642float
#endif
 movs r2,#0       // fall through
#if !defined(__ARM_PCS_VFP)
 regular_func fix642float
#endif
// convert signed 64-bit fix to float, rounding; number of r0:r1 bits after point in r2
fix642float_softfp:
 cmp r1,#0
 bge ufix642float_softfp // positive? use unsigned code
 rsbs r0,#0
 sbc r1,r1,r1,lsl#1 // make positive
 cbz r1,label_4
           // high word is zero?
 clz r3,r1
 subs r3,#8
 bmi label_1
 lsls r1,r1,r3
 lsls r12,r0,r3 // bits that will be lost
 rsb r3,#32
 lsr r0,r3
 orr r0,r0,r1
 sub r2,r2,r3
 rsb r2,#149
 adds r12,r12,r12 // rounding bit into carry
 adc r0,r0,r2,lsl#23 // insert exponent, add rounding
 orr r0,r0,#0x80000000
 beq label_5
        // potential rounding tie?
 cmp r2,#0xfe
 bhs label_2
        // over/underflow?
 bx r14
label_1:
 add r3,#33
 lsls r12,r1,r3 // rounding bit in carry, sticky bits in r12
 orrs r12,r12,r0 // all of low word into sticky bits: affects Z but not C
 rsb r3,#33
 lsr r0,r1,r3
// push {r14}
// bl dumpreg
// pop {r14}
 sub r2,r3,r2
 add r2,#22+127+32
 adc r0,r0,r2,lsl#23 // insert exponent, add rounding
 orr r0,r0,#0x80000000
 beq label_5
        // potential rounding tie?
 cmp r2,#0xfe
 it lo
 bxlo r14
// over/underflow?
label_2:
 mov r0,#0x80000000 // underflow
 it ge
 movtge r0,#0xff80 // overflow
label_3:
 bx r14
label_4:
 mov r1,r2
 b fix2float_neg
label_5:
 it cs // rounding tie?
 biccs r0,r0,#1 // force to even if we rounded up
 cmp r2,#0xfe
 it lo
 bxlo r14
 b label_2

// convert signed 32-bit fix to float, rounding; number of r0 bits after point in r1

#if defined(__ARM_PCS_VFP)
 regular_func fix2float
 push {lr}
 bl fix2float_softfp
 vmov s0,r0
 pop {pc}
#else
 regular_func fix2float
#endif
fix2float_softfp:
 cmp r0,#0
 bge ufix2float_softfp // positive? can use unsigned code
 rsbs r0,#0 // make positive
fix2float_neg:
 clz r3,r0
 subs r3,#8
 bmi label_6
 lsls r0,r0,r3
 add r2,r1,r3
 rsb r2,#149
 add r0,r0,r2,lsl#23 // insert exponent
 orr r0,#0x80000000
 cmp r2,#0xfe
 it lo // over/underflow?
 bxlo r14
 b label_7
label_6:
 add r3,#33
 lsls r12,r0,r3 // rounding bit in carry, sticky bits in r12
 rsb r3,#33
 lsr r0,r3
// push {r14}
// bl dumpreg
// pop {r14}
 sub r2,r3,r1
 add r2,#22+127
 adc r0,r0,r2,lsl#23 // insert exponent
 orr r0,#0x80000000
 beq label_9
        // potential rounding tie?
 cmp r2,#0xfe
 it lo
 bxlo r14
// over/underflow?
label_7:
 mov r0,#0x80000000 // underflow
 it ge
 orrge r0,#0x7f800000 // overflow
label_8:
 bx r14
label_9:
 it cs // rounding tie?
 biccs r0,r0,#1 // force to even if we rounded up
 cmp r2,#0xfe
 it lo
 bxlo r14
 b label_7

// convert unsigned 32-bit fix to float, rounding; number of r0 bits after point in r1
#if defined(__ARM_PCS_VFP)
 regular_func ufix2float
 push {lr}
 bl ufix2float_softfp
 vmov s0,r0
 pop {pc}
#else
 regular_func ufix2float
#endif
ufix2float_softfp:
 cbz r0,label_12
           // zero? return it
 clz r3,r0
 subs r3,#8
 bmi label_10
 lsls r0,r0,r3
 add r2,r1,r3
 rsb r2,#149
 add r0,r0,r2,lsl#23 // insert exponent
// push {r14}
// bl dumpreg
// pop {r14}
 cmp r2,#0xfe
 it lo // over/underflow?
 bxlo r14
 b label_11
label_10:
 add r3,#33
 lsls r12,r0,r3 // rounding bit in carry, sticky bits in r12
 rsb r3,#33
 lsr r0,r3
// push {r14}
// bl dumpreg
// pop {r14}
 sub r2,r3,r1
 add r2,#22+127
 adc r0,r0,r2,lsl#23 // insert exponent
 beq label_13
        // potential rounding tie?
 cmp r2,#0xfe
 it lo
 bxlo r14
// over/underflow?
label_11:
 ite ge
 movge r0,#0x7f800000 // overflow
 movlt r0,#0x00000000 // underflow
label_12:
 bx r14
label_13:
 it cs // rounding tie?
 biccs r0,r0,#1 // force to even if we rounded up
 cmp r2,#0xfe
 it lo
 bxlo r14
 b label_11

#if defined(__ARM_PCS_VFP)
 regular_func uint642float
 movs r2,#0
 regular_func ufix642float
 push {lr}
 bl ufix642float_softfp
 vmov s0,r0
 pop {pc}
#endif

 wrapper_func __aeabi_ul2f
#if !defined(__ARM_PCS_VFP)
 regular_func uint642float
#endif
 movs r2,#0       // fall through
#if !defined(__ARM_PCS_VFP)
 regular_func ufix642float
#endif
// convert unsigned 64-bit fix to float, rounding; number of r0:r1 bits after point in r2
ufix642float_softfp:
 cbz r1,label_17
           // high word is zero?
 clz r3,r1
 subs r3,#8
 bmi label_14
 lsls r1,r1,r3
 lsls r12,r0,r3 // bits that will be lost
 rsb r3,#32
 lsr r0,r3
 orr r0,r0,r1
 sub r2,r2,r3
 rsb r2,#149
 adds r12,r12,r12 // rounding bit into carry
 adc r0,r0,r2,lsl#23 // insert exponent, add rounding
 beq label_18
        // potential rounding tie?
 cmp r2,#0xfe
 bhs label_15
        // over/underflow?
 bx r14
label_14:
 add r3,#33
 lsls r12,r1,r3 // rounding bit in carry, sticky bits in r12
 orrs r12,r12,r0 // all of low word into sticky bits: affects Z but not C
 rsb r3,#33
 lsr r0,r1,r3
// push {r14}
// bl dumpreg
// pop {r14}
 sub r2,r3,r2
 add r2,#22+127+32
 adc r0,r0,r2,lsl#23 // insert exponent, add rounding
 beq label_18
        // potential rounding tie?
 cmp r2,#0xfe
 it lo
 bxlo r14
// over/underflow?
label_15:
 ite ge
 movge r0,#0x7f800000 // overflow
 movlt r0,#0x00000000 // underflow
label_16:
 bx r14
label_17:
 mov r1,r2
 b ufix2float_softfp
label_18:
 it cs // rounding tie?
 biccs r0,r0,#1 // force to even if we rounded up
 cmp r2,#0xfe
 it lo
 bxlo r14
 b label_15

 float_section conv_ftoi64
 regular_func float2int64
#if defined(__ARM_PCS_VFP)
  vmov r0, s0
#endif
  lsls r1, r0, #1
  // r0 = abs(zero)                   => r1 = 0x00000000
  // r0 = abs(denornaml)              => r1 = 0x00xxxxxx
  // r0 = abs(1.0f)                   => r1 = 0x7f000000
  // r0 = abs(inf/nan)                => r1 = 0xffxxxxxx
  bls float2int64_z_softfp // positive or zero or -zero are ok for int64_z
  lsrs r1, r1, #24
  subs r1, #0x7f
  bcc label_19
         // <1 means subtract 1
  // mask off all but fractional bits
  lsls r2, r0, r1
  lsls r2, r2, #9
  beq float2int64_z_softfp // integer
label_19:
  push {lr}
  bl float2int64_z_softfp
  subs r0, #1
  sbcs r1, r1, #0
  pop {pc}

 float_section conv_ftof64
 regular_func float2fix64
#if defined(__ARM_PCS_VFP)
  mov r1, r0
  vmov r0, s0
#endif
  lsls r2, r0, #1
  // r0 = abs(zero)                   => r1 = 0x00000000
  // r0 = abs(denornaml)              => r1 = 0x00xxxxxx
  // r0 = abs(1.0f)                   => r1 = 0x7f000000
  // r0 = abs(inf/nan)                => r1 = 0xffxxxxxx
  bls float2fix64_z_softfp // positive or zero or -zero are ok for fix64_z
  lsrs r2, r2, #24
  rsbs r3, r1, #0x7f
  subs r2, r3
  bcc label_20
         // <1 means subtract 1
  // mask off all but fractional bits
  lsls r2, r0, r2
  lsls r2, r2, #9
  beq float2fix64_z_softfp // integer
label_20:
  push {lr}
  bl float2fix64_z_softfp
  subs r0, #1
  sbcs r1, r1, #0
  pop {pc}

 float_wrapper_section conv_ftoi64z

#if defined(__ARM_PCS_VFP)
 regular_func float2fix64_z
 mov r1,r0
 vmov r0,s0
 b float2fix64_z_softfp
#endif

// convert float to signed int64, rounding towards 0, clamping
 regular_func float2int64_z
#if defined(__ARM_PCS_VFP)
 vmov r0,s0
#endif
 wrapper_func __aeabi_f2lz
float2int64_z_softfp:
 movs r1,#0      // fall through
#if !defined(__ARM_PCS_VFP)
 regular_func float2fix64_z
#endif
// convert float in r0 to signed fixed point in r0:r1, clamping
float2fix64_z_softfp:
 subs r1,#0x95 // remove exponent bias, compensate for mantissa length
 asrs r2,r0,#23 // sign and exponent
 sub r3,r2,#1
 sub r0,r0,r3,lsl#23 // install implied 1, clear exponent
 uxtb r3,r3
 cmp r3,#0xfe
 bhs label_23
        // 0 or Inf/NaN?
 adds r1,r3 // offset exponent by fix precision; r1 is now required left shift
 bmi label_26
        // actually a right shift?
 subs r3,r1,#32 // result fits in high 32 bits only?
 bge label_22
 subs r3,r1,#8 // result fits in low 32 bits only?
 ble label_21
 lsls r0,r0,#8
 rsbs r1,r3,#32
 lsrs r1,r0,r1
 lsls r0,r0,r3
 cmp r2,#0
 it ge
 bxge r14
 rsbs r0,#0 // negate if necessary
 sbcs r1,r1,r1,lsl#1
 bx r14
label_21:
 lsls r0,r0,r1
 movs r1,r2,asr#31 // sign extend
 eors r0,r0,r1 // negate if necessary
 subs r0,r0,r1
 bx r14
label_22:
 cmp r3,#8 // overflow?
 bge label_24
 lsls r0,r0,r3
 eor r1,r0,r2,asr#31 // negate if necessary
 add r1,r1,r2,lsr#31
 movs r0,#0
 bx r14
label_23:
 bhi label_25
        // 0?
 lsls r1,r0,#9 // mantissa field
 it ne // NaN?
 movne r2,#0 // treat NaNs as +∞
label_24:
 mvn r1,#0x80000000 // = 0x7fffffff
 add r1,r1,r2,lsr#31 // so -Inf → 0x80000000, +Inf → 0x7fffffff
 mvn r0,r2,asr#31
 bx r14
label_25:
 movs r0,#0
 movs r1,#0
 bx r14
label_26:
 rsbs r1,#0
 usat r1,#5,r1
 lsrs r0,r0,r1
 eors r0,r0,r2,asr#31 // negate if necessary
 adds r0,r0,r2,lsr#31
 movs r1,r0,asr#31 // sign extend
 bx r14

 float_wrapper_section conv_ftoui64

#if defined(__ARM_PCS_VFP)
 regular_func float2ufix64
 regular_func float2ufix64_z
 mov r1,r0
 vmov r0,s0
 b float2ufix64_z_softfp
#endif
// convert float to unsigned int64, rounding towards -Inf, clamping
 regular_func float2uint64
 regular_func float2uint64_z
#if defined(__ARM_PCS_VFP)
 vmov r0,s0
#endif
 wrapper_func __aeabi_f2ulz
 movs r1,#0      // fall through
#if !defined(__ARM_PCS_VFP)
 regular_func float2ufix64
 regular_func float2ufix64_z
#endif
// convert float in r0 to unsigned fixed point in r0:r1, clamping
float2ufix64_z_softfp:
 subs r1,#0x96 // remove exponent bias, compensate for mantissa length
 asrs r2,r0,#23 // sign and exponent
 sub r3,r2,#1
 cmp r3,#0xfe
 bhs label_31
        // -ve, 0 or Inf/NaN?
 sub r0,r0,r3,lsl#23 // install implied 1, clear exponent
 adds r1,r2 // offset exponent by fix precision; r1 is now required left shift
 bmi label_30
        // actually a right shift?
 subs r2,r1,#7
 ble label_27
        // result (easily) fits in lo 32 bits?
 subs r3,r1,#32
 bge label_28
        // results might fit in hi 32 bits?
 lsls r0,r0,#7
 rsbs r3,r2,#32
 lsrs r1,r0,r3
 lsls r0,r0,r2
 bx r14
label_27:
 lsls r0,r0,r1
 movs r1,#0
 bx r14
label_28:
 cmp r1,#32+9 // overflow?
 bge label_29
 lsls r1,r0,r3
 movs r0,#0
 bx r14
label_29:
 mvn r0,#0 // = 0xffffffff
 mvn r1,#0 // = 0xffffffff
 bx r14
label_30:
 rsbs r1,#0
 usat r1,#5,r1 // if shift is long return 0
 lsrs r0,r0,r1
 movs r1,#0
 bx r14
label_31:
 cmp r0,#0xff800000
 bhi label_29
        // -NaN, return 0xffffffff
 cmp r0,#0x00800000
 bgt label_29
        // +Inf or +NaN, return 0xfffffff
label_32:
 movs r0,#0 // return 0
 movs r1,#0
 bx r14

#endif

 end
