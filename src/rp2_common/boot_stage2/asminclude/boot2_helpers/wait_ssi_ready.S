/*
 * Copyright (c) 2021 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef _BOOT2_HELPER_WAIT_SSI_READY
#define _BOOT2_HELPER_WAIT_SSI_READY

wait_ssi_ready:
    push {r0, r1, lr}

    // Command is complete when there is nothing left to send
    // (TX FIFO empty) and SSI is no longer busy (CSn deasserted)
poll_for_command_complete:
    ldr r1, [r3, #SSI_SR_OFFSET]
    movs r0, #SSI_SR_TFE_BITS
    tst r1, r0
    beq poll_for_command_complete
    movs r0, #SSI_SR_BUSY_BITS
    tst r1, r0
    bne poll_for_command_complete

    pop {r0, r1, pc}

#endif
