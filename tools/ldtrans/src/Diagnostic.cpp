/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "Diagnostic.h"
#include "SourceManager.h"

std::vector<SourceLocation> Diagnostic::s_include_sites;

std::string Diagnostic::format() const
{
    std::string msg;

    /* Prefix with include stack if applicable */
    const char* boilerplate_before = "In file included from ";
    const char* boilerplate_after = "";
    for (auto it = s_include_sites.rbegin(); it != s_include_sites.rend(); ++it) {
        msg += boilerplate_before;
        msg += g_source_manager.toFileLine(*it);
        boilerplate_before =      ",\n                 from ";
        boilerplate_after =       ":\n";
    }
    msg += boilerplate_after;

    /* Add main diagnostic */
    msg += g_source_manager.toFileLineColumn(m_primary) + ": " + m_message + "\n";
    auto [ text, column ] = g_source_manager.toLineInfo(m_primary);
    msg += text + "\n" + std::string(column - 1, ' ') + "^\n";

    /* Add any notes */
    for (const auto& note : m_notes) {
        msg += g_source_manager.toFileLineColumn(note.location) + ": note: " + note.message + "\n";
        auto [ text, column ] = g_source_manager.toLineInfo(note.location);
        msg += text + "\n" + std::string(column - 1, ' ') + "^\n";
    }

    return msg;
}
