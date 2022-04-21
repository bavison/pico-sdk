/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico/asm_helper.S"
#include "hardware/irq.h"

 _extern irq_add_tail_to_free_list

#if !PICO_DISABLE_SHARED_IRQ_HANDLERS
 _section(.data, `.data`, "aw", DATA, 2)
 _align 2

 _global irq_handler_chain_slots

 _global irq_handler_chain_first_slot
 _global irq_handler_chain_remove_tail

//
// These Slots make up the code and structure of the handler chains; the only external information are the VTABLE entries
// (obviously one set per core) and a free list head. Each individual handler chain starts with the VTABLE entry I
// pointing at the address of slot S (with thumb bit set). Thus each slot which is part of a chain is executble.
//
// The execution jumps (via branch instruction) from one slot to the other, then jumps to the end of chain handler.
// The entirety of the state needed to traverse the chain is contained within the slots of the chain, which is why
// a VTABLE entry is all that is needed per chain (rather than requiring a separarte set of head pointers)
//

irq_handler_chain_slots:
 _set next_slot_number, 1
 rept PICO_MAX_SHARED_IRQ_HANDLERS
    // a slot is executable and is always 3 instructions long.
    _hword 0    // inst1 (either: ldr r0, [pc, #4]    or for the FIRST slot : add r1, pc, #0                 )
    _hword 0    // inst2 (        blx r0                                      b irq_handler_chain_first_slot )

    _hword 0    // inst3 (either: b next_slot         or for the LAST         pop {pc}                       )

    // next is a single byte index of next slot in chain (or -1 to end)
 if next_slot_number == PICO_MAX_SHARED_IRQ_HANDLERS
    _byte 0xff
 else
    _byte next_slot_number
 endif
    // next is the 8 bit unsigned priority
    _byte 0x00

    // and finally the handler function pointer
    _word 0x00000000
 _set next_slot_number, next_slot_number + 1
 endr

irq_handler_chain_first_slot:
    push {lr}
    ldr  r0, [r1, #4]
    adds r1, #1
    mov  lr, r1
    bx   r0
irq_handler_chain_remove_tail:
    mov  r0, lr
    subs r0, #9
    ldr  r1, =irq_add_tail_to_free_list
    blx  r1
    pop  {pc}


#endif

 _end
