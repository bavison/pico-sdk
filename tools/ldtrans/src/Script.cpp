/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "Script.h"

Script g_script;

void Script::SortSymbols()
{
    /* Some linkers (at least IAR) don't allow forward references to
     * symbols, so sort them into dependency order. While we're at it,
     * check top-level symbols don't depend on section symbols, check
     * there are no dependency loops and check for undefined symbols */
    for (SymbolId s = (SymbolId) 0; s < symbols.size(); ++s) {

    }
}
