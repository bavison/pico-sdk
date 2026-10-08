/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_DIAGNOSTIC_H_
#define INCLUDE_DIAGNOSTIC_H_

#include <stdexcept>
#include <string>
#include <vector>

#include "SourceLocation.h"

class Diagnostic
{
public:
    struct Note
    {
        SourceLocation location;
        std::string message;
    };

    Diagnostic(SourceLocation primary, std::string message, std::vector<Note> notes = {}) :
        m_primary(primary), m_message(message), m_notes(std::move(notes)) {}

    void addNote(SourceLocation location, std::string message)
    {
        m_notes.push_back({location, std::move(message)});
    }

    std::string format() const;

    static void push_include(SourceLocation location)
    {
        s_include_sites.push_back(location);
    }

    static void pop_include()
    {
        s_include_sites.pop_back();
    }

protected:
    SourceLocation m_primary;
    std::string m_message;
    std::vector<Note> m_notes;
    static std::vector<SourceLocation> s_include_sites;
};

class DiagnosticError : public Diagnostic, public std::runtime_error
{
public:
    DiagnosticError(SourceLocation primary, std::string message, std::vector<Note> notes = {}) :
        Diagnostic(primary, message, std::move(notes)),
        std::runtime_error(message) {}
};

#endif /* sentry INCLUDE_DIAGNOSTIC_H_ */
