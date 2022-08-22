/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico/asm_helper.S"
#include "pico/bootrom.h"

 _extern rom_funcs_lookup

 __pre_init __aeabi_bits_init, 00010

_macro_1arg(bits_section, name)
#if PICO_BITS_IN_RAM
 _section(RAM_SECTION_NAME(MA(name)), "ax", CODE, 2)
#else
 _section(SECTION_NAME(MA(name)), "ax", CODE, 2)
#endif
 _endm(endm)

 _section(.data.aeabi_bits_funcs, "aw", DATA, 4)
 _global aeabi_bits_funcs, aeabi_bits_funcs_end
 _equ BITS_FUNC_COUNT, 4
 _align 4
aeabi_bits_funcs:
    _word ROM_FUNC_POPCOUNT32
    _word ROM_FUNC_CLZ32
    _word ROM_FUNC_CTZ32
    _word ROM_FUNC_REVERSE32
aeabi_bits_funcs_end:

 _section(.text, "ax", CODE, 2)
 local_func __aeabi_bits_init
    ldr r0, =aeabi_bits_funcs
    movs r1, #BITS_FUNC_COUNT
    ldr r3, =rom_funcs_lookup
    bx r3

 _equ POPCOUNT32, 0
 _equ CLZ32, 4
 _equ CTZ32, 8
 _equ REVERSE32, 12

 bits_section clzsi
 gnu_func __clz
 gnu_func __clzl
 gnu_func __clzsi2
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #CLZ32]
    bx r3

 bits_section ctzsi
 gnu_func __ctzsi2
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #CTZ32]
    bx r3

 bits_section popcountsi
 gnu_func __popcountsi2
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #POPCOUNT32]
    bx r3

 bits_section clzdi
 gnu_func __clzll
 gnu_func __clzdi2
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #CLZ32]
    cmp r1, #0
    bne clzdi_msw_nonzero
    push {lr}
    blx r3
    adds r0, #32
    pop {pc}
clzdi_msw_nonzero:
    mov r0, r1
    bx r3

 bits_section ctzdi
 gnu_func __ctzdi2
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #CTZ32]
    cmp r0, #0
    beq ctzdi_lsw_zero
    bx r3
ctzdi_lsw_zero:
    push {lr}
    mov r0, r1
    blx r3
    adds r0, #32
    pop {pc}

 bits_section popcountdi
 gnu_func __popcountdi2
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #POPCOUNT32]
    push {r1, r3, lr}
    blx r3
    mov r12, r0
    pop {r0, r3}
    blx r3
    mov r1, r12
    add r0, r1
    pop {pc}

 bits_section reverse32
 regular_func reverse32
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #REVERSE32]
    bx r3

 bits_section __rev
 regular_func __rev
 regular_func __revl
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #REVERSE32]
    bx r3

 bits_section __revll
 regular_func __revll
    push {lr}
    ldr r3, =aeabi_bits_funcs
    ldr r3, [r3, #REVERSE32]
    push {r1, r3}
    blx r3
    mov r12, r0 // reverse32 preserves r12
    pop {r0, r3}
    blx r3
    mov r1, r12
    pop {pc}

 _end
