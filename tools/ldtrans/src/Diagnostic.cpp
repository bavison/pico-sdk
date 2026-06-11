/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "Diagnostic.h"
#include "SourceManager.h"

std::vector<SourceLocation> DiagnosticError::include_sites;

std::string DiagnosticError::format() const
{
    std::string msg;

    /* Prefix with include stack if applicable */
    const char* boilerplate_before = "In file included from ";
    const char* boilerplate_after = "";
    for (auto it = include_sites.rbegin(); it != include_sites.rend(); ++it) {
        msg += boilerplate_before;
        msg += g_source_manager.toFileLine(*it);
        boilerplate_before =      ",\n                 from ";
        boilerplate_after =       ":\n";
    }
    msg += boilerplate_after;

    /* Add main diagnostic */
    msg += g_source_manager.toFileLineColumn(primary) + ": " + what() + "\n";

    /* Add any notes */
    for (const auto& note : notes) {
        msg += g_source_manager.toFileLineColumn(note.location) + ": note: " + note.message + "\n";
    }

    return msg;
}
