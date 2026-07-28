/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_DEFINITION_H_
#define INCLUDE_DEFINITION_H_

#include <charconv>
#include <memory>
#include <string>

#include "Expression.h"
#include "Identifier.h"
#include "SourceLocation.h"
#include "SourceManager.h"

enum class DefinitionKind : std::uint8_t
{
    TopLevelSymbol,
    SectionScopeSymbol,
    MemoryRegionOrigin,
    MemoryRegionLength,
    OutputSectionVMA,
    OutputSectionLMA,
    Assertion,
};

enum class DefinitionVisibility : std::uint8_t
{
    Standard,
    Provide,
    ProvideHidden,
};

class Definition
{
public:
    Definition(SourceLocation location, std::optional<IdentifierId> name, ExpressionPtr expression, DefinitionKind kind) : m_location(location), m_name(name), m_expression(expression), m_kind(kind) {}
    void enchain(std::shared_ptr<Definition>& previous)
    {
        m_previous = std::move(previous);
    }
    std::string describe(const IdentifierManager& ids) const
    {
        switch (m_kind) {
        case DefinitionKind::MemoryRegionOrigin:
            return std::string("memory region ") + ids.toDisplayName(*m_name) + " origin";
        case DefinitionKind::MemoryRegionLength:
            return std::string("memory region ") + ids.toDisplayName(*m_name) + " length";
        case DefinitionKind::OutputSectionVMA:
            return std::string("output section ") + ids.toDisplayName(*m_name) + " VMA";
        case DefinitionKind::OutputSectionLMA:
            return std::string("output section ") + ids.toDisplayName(*m_name) + " LMA";
        case DefinitionKind::Assertion:
            return "assertion";
        default:
            return std::string("symbol ") + ids.toDisplayName(*m_name);
        }
    }
    void set_visibility(SourceLocation new_location, DefinitionVisibility new_visibility)
    {
        m_location = new_location;
        m_visibility = new_visibility;
    }
    void set_name(IdentifierId new_name)
    {
        m_name = new_name;
    }
    std::string dump(const IdentifierManager& ids) const {
        char buffer[2 + 16 + 1] = "0x"; // includes null terminator, wherever that is
        auto [ptr, ec] = std::to_chars(buffer + 2, buffer + 2 + 16, m_value, 16);
        return describe(ids) + describe_visibility() + " = " + dump_expression_chain(ids) + " = " + (ec == std::errc{} ? buffer : "<invalid>");
    }
    friend class EvaluationVisitor;
    bool previous_exists() const { return bool(m_previous); }
    Definition& previous() const { return *m_previous; }
    SourceLocation location() const { return m_location; }
    std::optional<IdentifierId> name() const { return m_name; }
    Expression& expression() { return *m_expression; }
    const Expression& expression() const { return *m_expression; }
    DefinitionKind kind() const { return m_kind; }
    DefinitionVisibility visibility() const { return m_visibility; }
    uint64_t value() const { return m_value; }
private:
    std::string dump_expression_chain(const IdentifierManager& ids) const {
        std::string earlier;
        if (m_previous)
            earlier = m_previous->dump_expression_chain(ids) + ", ";
        DumpVisitor expression_dump(ids);
        m_expression->accept(expression_dump);
        return earlier + expression_dump.result();
    }
    std::string describe_visibility() const
    {
        switch (m_visibility) {
        case DefinitionVisibility::ProvideHidden:
            return " (provide hidden)";
        case DefinitionVisibility::Provide:
            return " (provide)";
        default:
            return "";
        }
    }
    std::shared_ptr<Definition> m_previous;
    SourceLocation m_location;
    std::optional<IdentifierId> m_name;
    ExpressionPtr m_expression;
    DefinitionKind m_kind;
    DefinitionVisibility m_visibility = DefinitionVisibility::Standard;
    uint64_t m_value = 0;
};

using DefinitionPtr = std::shared_ptr<Definition>;

#endif /* sentry INCLUDE_DEFINITION_H_ */
