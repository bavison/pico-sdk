/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_MEMORYREGION_H_
#define INCLUDE_MEMORYREGION_H_

#include <cstdint>

#include <string>

#include "Definition.h"
#include "Diagnostic.h"
#include "Expression.h"
#include "Identifier.h"
#include "lexer.h"

enum class MemoryAttribute : uint8_t
{
    ReadOnly   = 1 << 0,
    ReadWrite  = 1 << 1,
    Executable = 1 << 2,
    Alloc      = 1 << 3,
    Init       = 1 << 4,
};

class MemoryAttributes
{
public:
    constexpr MemoryAttributes() = default;
    constexpr MemoryAttributes(char c)
    {
        switch (c) {
        case 'R':
        case 'r':
            m_bits = (uint8_t) MemoryAttribute::ReadOnly;
            break;
        case 'W':
        case 'w':
            m_bits = (uint8_t) MemoryAttribute::ReadWrite;
            break;
        case 'X':
        case 'x':
            m_bits = (uint8_t) MemoryAttribute::Executable;
            break;
        case 'A':
        case 'a':
            m_bits = (uint8_t) MemoryAttribute::Alloc;
            break;
        case 'I':
        case 'i':
        case 'L':
        case 'l':
            m_bits = (uint8_t) MemoryAttribute::Init;
            break;
        default:
            throw DiagnosticError(lexer_symbol_location, "error: invalid attribute specifier");
        }
    }
    MemoryAttributes operator|(const MemoryAttributes& other) const
    {
        return MemoryAttributes{static_cast<uint8_t>(m_bits | other.m_bits)};
    }
    MemoryAttributes& operator|=(const MemoryAttributes& other)
    {
        m_bits |= other.m_bits;
        return *this;
    }
    std::string dump() const
    {
        if (m_bits == 0)
            return "<none>";
        std::string result;
        if (m_bits & (uint8_t) MemoryAttribute::ReadOnly)
            result += "R";
        if (m_bits & (uint8_t) MemoryAttribute::ReadWrite)
            result += "W";
        if (m_bits & (uint8_t) MemoryAttribute::Executable)
            result += "X";
        if (m_bits & (uint8_t) MemoryAttribute::Alloc)
            result += "A";
        if (m_bits & (uint8_t) MemoryAttribute::Init)
            result += "I";
        return result;
    }
private:
    MemoryAttributes(uint8_t bits) : m_bits(bits) {}
    uint8_t m_bits = 0;
};

struct MemoryAttributesRules
{
    MemoryAttributes required;
    MemoryAttributes denied;
    MemoryAttributesRules operator|(const MemoryAttributesRules& other) const
    {
        return MemoryAttributesRules{required | other.required, denied | other.denied};
    }
    std::string dump() const
    {
        return std::string("  required: ") + required.dump() + "\n  denied: " + denied.dump() + "\n";
    }
};

class MemoryRegion
{
public:
    MemoryRegion(SourceLocation location, IdentifierId name, MemoryAttributesRules rules, Definition origin, Definition length) :
        m_location(location), m_name(name), m_rules(rules), m_origin(std::move(origin)), m_length(std::move(length)) {}
    std::string dump(const IdentifierManager& ids) const
    {
        DumpVisitor origin_dump(ids), length_dump(ids);
        m_origin.expression().accept(origin_dump);
        m_length.expression().accept(length_dump);
        return std::string("MEMORY\n") +
            "  location: " + g_source_manager.toFileLineColumn(m_location) + "\n" +
            "  name: " + ids.toDisplayName(m_name) + "\n" +
            m_rules.dump() +
            "  origin: " + origin_dump.result() + "\n" +
            "  length: " + length_dump.result() + "\n";
    }
    SourceLocation location() const { return m_location; }
    IdentifierId name() const { return m_name; }
    MemoryAttributesRules rules() const { return m_rules; }
    Definition& origin() { return m_origin; }
    Definition& length() { return m_length; }
private:
    SourceLocation m_location;
    IdentifierId m_name;
    MemoryAttributesRules m_rules;
    Definition m_origin;
    Definition m_length;
};

#endif /* INCLUDE_MEMORYREGION_H_ */
