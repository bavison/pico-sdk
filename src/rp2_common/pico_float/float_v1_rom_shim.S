/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico/asm_helper.S"

 _extern sf_table

#if PICO_FLOAT_SUPPORT_ROM_V1 && PICO_RP2040_B0_SUPPORTED
#ifndef PICO_FLOAT_IN_RAM
#define PICO_FLOAT_IN_RAM 0
#endif

_macro_1arg(float_section, name)
// todo separate flag for shims?
#if PICO_FLOAT_IN_RAM
 _section(RAM_SECTION_NAME(MA(name)), "ax", CODE, 2)
#else
 _section(SECTION_NAME(MA(name)), "ax", CODE, 2)
#endif
 _endm(endm)

 float_section float_table_shim_on_use_helper
 regular_func float_table_shim_on_use_helper
    push {r0-r2, lr}
    mov r0, r12
#ifndef NDEBUG
    // sanity check to make sure we weren't called by non (shimmable_) table_tail_call macro
    cmp r0, #0
    bne float_table_shim_on_use_helper_1
    bkpt #0
#endif
float_table_shim_on_use_helper_1:
    ldrh r1, [r0]
    lsrs r2, r1, #8
    adds r0, #2
    cmp r2, #0xdf
    bne float_table_shim_on_use_helper_1
    uxtb r1, r1 // r1 holds table offset
    lsrs r2, r0, #2
    bcc float_table_shim_on_use_helper_2
    // unaligned
    ldrh r2, [r0, #0]
    ldrh r0, [r0, #2]
    lsls r0, r0, #16
    orrs r0, r2
    b float_table_shim_on_use_helper_3
float_table_shim_on_use_helper_2:
    ldr r0, [r0]
float_table_shim_on_use_helper_3:
    ldr r2, =sf_table
    str r0, [r2, r1]
    str r0, [sp, #12]
    pop {r0-r2, pc}

 float_section sixtyfourbit_to_float_shims

// convert uint64 to float, rounding
 regular_func uint642float_shim
 movs r2,#0       // fall through

// convert unsigned 64-bit fix to float, rounding; number of r0:r1 bits after point in r2
 regular_func ufix642float_shim
 push {r4,r5,r14}
 cmp r1,#0
 bpl sixtyfourbit_to_float_shims_1 // positive? we can use signed code
 lsls r5,r1,#31  // contribution to sticky bits
 orrs r5,r0
 lsrs r0,r1,#1
 subs r2,#1
 b sixtyfourbit_to_float_shims_4

// convert int64 to float, rounding
 regular_func int642float_shim
 movs r2,#0       // fall through

// convert signed 64-bit fix to float, rounding; number of r0:r1 bits after point in r2
 regular_func fix642float_shim
 push {r4,r5,r14}
sixtyfourbit_to_float_shims_1:
 movs r5,r0
 orrs r5,r1
 beq ret_pop45   // zero? return +0
 asrs r5,r1,#31  // sign bits
sixtyfourbit_to_float_shims_2:
 asrs r4,r1,#24  // try shifting 7 bits at a time
 cmp r4,r5
 bne sixtyfourbit_to_float_shims_3 // next shift will overflow?
 lsls r1,r1,#7
 lsrs r4,r0,#25
 orrs r1,r4
 lsls r0,r0,#7
 adds r2,#7
 b sixtyfourbit_to_float_shims_2
sixtyfourbit_to_float_shims_3:
 movs r5,r0
 movs r0,r1
sixtyfourbit_to_float_shims_4:
 rsbs r2,#0
 adds r2,#32+29

 // bl packx
 ldr r1, =0x29ef // packx
 blx r1
ret_pop45:
 pop {r4,r5,r15}

 float_section fatan2_shim
 regular_func fatan2_shim
 push {r4,r5,r14}

 ldr r4, =0x29c1 // unpackx
 mov r12, r4
// unpack arguments and shift one down to have common exponent
 blx r12
 mov r4,r0
 mov r0,r1
 mov r1,r4
 mov r4,r2
 mov r2,r3
 mov r3,r4
 blx r12
 lsls r0,r0,#5  // Q28
 lsls r1,r1,#5  // Q28
 adds r4,r2,r3  // this is -760 if both arguments are 0 and at least -380-126=-506 otherwise
 asrs r4,r4,#9
 adds r4,#1
 bmi fatan2_shim_2 // force y to 0 proper, so result will be zero
 subs r4,r2,r3  // calculate shift
 bge fatan2_shim_1 // ex>=ey?
 rsbs r4,#0     // make shift positive
 asrs r0,r0,r4
 cmp r4,#28
 blo fatan2_shim_4
 asrs r0,r0,#31
 b fatan2_shim_4
fatan2_shim_1:
 asrs r1,r1,r4
 cmp r4,#28
 blo fatan2_shim_4
fatan2_shim_2:
// here |x|>>|y| or both x and y are ±0
 cmp r0,#0
 bge fatan2_shim_3 // x positive, return signed 0
 ldr r3, =0x2cfc         // &pi_q29, circular coefficients
 ldr r0,[r3]    // x negative, return +/- pi
 asrs r1,r1,#31
 eors r0,r1
 b fatan2_shim_7
fatan2_shim_3:
 asrs r0,r1,#31
 b fatan2_shim_7
fatan2_shim_4:
 movs r2,#0              // initial angle
 ldr r3, =0x2cfc         // &pi_q29, circular coefficients
 cmp r0,#0               // x negative
 bge fatan2_shim_5
 rsbs r0,#0              // rotate to 1st/4th quadrants
 rsbs r1,#0
 ldr r2,[r3]             // pi Q29
fatan2_shim_5:
 movs r4,#1              // m=1
 ldr r5, =0x2b97         // cordic_vec
 blx r5                  // also produces magnitude (with scaling factor 1.646760119), which is discarded
 mov r0,r2               // result here is -pi/2..3pi/2 Q29
// asrs r2,r2,#29
// subs r0,r2
 ldr r3, =0x2cfc         // &pi_q29, circular coefficients
 ldr r2,[r3]             // pi Q29
 adds r4,r0,r2           // attempt to fix -3pi/2..-pi case
 bcs fatan2_shim_6       // -pi/2..0? leave result as is
 subs r4,r0,r2           // <pi? leave as is
 bmi fatan2_shim_6
 subs r0,r4,r2           // >pi: take off 2pi
fatan2_shim_6:
 subs r0,#1              // fiddle factor so atan2(0,1)==0
fatan2_shim_7:
 movs r2,#0              // exponent for pack
 ldr r3, =0x2b19
 bx r3

 float_section float232_shims

 regular_func float2int_shim
     movs r1,#0                    // fall through
 regular_func float2fix_shim
     // check for -0 or -denormal upfront
     asrs r2, r0, #23
     adds r2, #128
     adds r2, #128
     beq float2fix_shim_1
     // call original
     ldr r2, =0x2acd
     bx r2
float2fix_shim_1:
     movs r0, #0
     bx lr

 float_section float264_shims

 regular_func float2int64_shim
 movs r1,#0                    // and fall through
 regular_func float2fix64_shim
 push {r14}
 bl f2fix
 b d2f64_a

 regular_func float2uint64_shim
 movs r1,#0                    // and fall through
 regular_func float2ufix64_shim
 asrs r3,r0,#23                // negative? return 0
 bmi ret_dzero
// and fall through

// convert float in r0 to signed fixed point in r0:r1:r3, r1 places after point, rounding towards -Inf
// result clamped so that r3 can only be 0 or -1
// trashes r12
 local_func f2fix
 push {r4,r14}
 mov r12,r1
 asrs r3,r0,#31
 lsls r0,r0,#1
 lsrs r2,r0,#24
 beq float264_shims_1          // zero?
 cmp r2,#0xff                  // Inf?
 beq float264_shims_2
 subs r1,r2,#1
 subs r2,#0x7f                 // remove exponent bias
 lsls r1,r1,#24
 subs r0,r1                    // insert implied 1
 eors r0,r3
 subs r0,r3                    // top two's complement
 asrs r1,r0,#4                 // convert to double format
 lsls r0,r0,#28
 ldr r4, =d2fix_a
 bx r4
float264_shims_1:
 movs r0,#0
 movs r1,r0
 movs r3,r0
 pop {r4,r15}
float264_shims_2:
 mvns r0,r3                    // return max/min value
 mvns r1,r3
 pop {r4,r15}

ret_dzero:
 movs r0,#0
 movs r1,#0
 bx r14

 float_section d2fix_a_float

 weak_func d2fix_a // weak because it exists in float shims too
// here
// r0:r1 two's complement mantissa
// r2    unbaised exponent
// r3    mantissa sign extension bits
 add r2,r12                    // exponent plus offset for required binary point position
 subs r2,#52                   // required shift
 bmi d2fix_a_2                 // shift down?
// here a shift up by r2 places
 cmp r2,#12                    // will clamp?
 bge d2fix_a_1
 movs r4,r0
 lsls r1,r1,r2
 lsls r0,r0,r2
 rsbs r2,#0
 adds r2,#32                   // complementary shift
 lsrs r4,r4,r2
 orrs r1,r4
 pop {r4,r15}
d2fix_a_1:
 mvns r0,r3
 mvns r1,r3                    // overflow: clamp to extreme fixed-point values
 pop {r4,r15}
d2fix_a_2:
// here a shift down by -r2 places
 adds r2,#32
 bmi d2fix_a_3                 // long shift?
 mov r4,r1
 lsls r4,r4,r2
 rsbs r2,#0
 adds r2,#32                   // complementary shift
 asrs r1,r1,r2
 lsrs r0,r0,r2
 orrs r0,r4
 pop {r4,r15}
d2fix_a_3:
// here a long shift down
 movs r0,r1
 asrs r1,r1,#31                // shift down 32 places
 adds r2,#32
 bmi d2fix_a_4                 // very long shift?
 rsbs r2,#0
 adds r2,#32
 asrs r0,r0,r2
 pop {r4,r15}
d2fix_a_4:
 movs r0,r3                    // result very near zero: use sign extension bits
 movs r1,r3
 pop {r4,r15}
d2f64_a:
 asrs r2,r1,#31
 cmp r2,r3
 bne d2fix_a_5                 // sign extension bits fail to match sign of result?
 pop {r15}
d2fix_a_5:
 mvns r0,r3
 movs r1,#1
 lsls r1,r1,#31
 eors r1,r1,r0                 // generate extreme fixed-point values
 pop {r15}

 float_section float2double_shim
 regular_func float2double_shim
 lsrs r3,r0,#31                // sign bit
 lsls r3,r3,#31
 lsls r1,r0,#1
 lsrs r2,r1,#24                // exponent
 beq float2double_shim_1       // zero?
 cmp r2,#0xff                  // Inf?
 beq float2double_shim_3
 lsrs r1,r1,#4                 // exponent and top 20 bits of mantissa
 ldr r2,=(0x3ff-0x7f)<<20      // difference in exponent offsets
 adds r1,r2
 orrs r1,r3
 lsls r0,r0,#29                // bottom 3 bits of mantissa
 bx r14
float2double_shim_1:
 movs r1,r3                    // return signed zero
float2double_shim_2:
 movs r0,#0
 bx r14
float2double_shim_3:
 ldr r1,=0x7ff00000            // return signed infinity
 adds r1,r3
 b float2double_shim_2

#endif

 _end
