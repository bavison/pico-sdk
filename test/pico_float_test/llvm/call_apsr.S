//===-- call_apsr.S - Helpers for ARM EABI floating point tests -----------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is dual licensed under the MIT and the University of Illinois Open
// Source Licenses. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements helpers for ARM EABI floating point tests for the
// compiler_rt library.
//
//===-

#include "pico/asm_helper.S"

 _align 2

 regular_func call_apsr_f
    push {lr}
    blx r2
    mrs r0, apsr
    pop {pc}

 regular_func call_apsr_d
    push {r4, lr}
    ldr r4, [sp, #8]
    blx r4
    mrs r0, apsr
    pop {r4, pc}

 _end
