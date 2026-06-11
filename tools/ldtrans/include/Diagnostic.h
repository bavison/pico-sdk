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

class DiagnosticError : public std::runtime_error
{
public:
    struct Note
    {
        SourceLocation location;
        std::string message;
    };

    DiagnosticError(SourceLocation location, std::string message, std::vector<Note> _notes = {}) :
        std::runtime_error(message), primary(location), notes(std::move(_notes)) {}

    void addNote(SourceLocation location, std::string message)
    {
        notes.push_back({location, std::move(message)});
    }

    std::string format() const;

    static void push_include(SourceLocation location)
    {
        include_sites.push_back(location);
    }

    static void pop_include()
    {
        include_sites.pop_back();
    }

private:
    SourceLocation primary;
    std::vector<Note> notes;
    static std::vector<SourceLocation> include_sites;
};

#endif /* sentry INCLUDE_DIAGNOSTIC_H_ */
