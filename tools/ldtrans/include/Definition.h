/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_DEFINITION_H_
#define INCLUDE_DEFINITION_H_

#include <memory>
#include <string>

#include "Expression.h"
#include "Identifier.h"
#include "SourceLocation.h"
#include "SourceManager.h"

enum class DefinitionKind
{
    TopLevelSymbol,
    SectionScopeSymbol,
    MemoryRegionOrigin,
    MemoryRegionLength,
};

class Definition
{
public:
    Definition(SourceLocation location, IdentifierId name, ExpressionPtr expression, DefinitionKind kind) : m_location(location), m_name(name), m_expression(std::move(expression)), m_kind(kind) {}
    void enchain(std::unique_ptr<Definition>& previous)
    {
        m_previous = std::move(previous);
    }
    std::string describe(const IdentifierManager& ids) const
    {
        switch (m_kind) {
        case DefinitionKind::MemoryRegionOrigin:
            return std::string("memory region ") + ids.toDisplayName(m_name) + " origin";
        case DefinitionKind::MemoryRegionLength:
            return std::string("memory region ") + ids.toDisplayName(m_name) + " length";
        default:
            return std::string("symbol ") + ids.toDisplayName(m_name);
        }
    }
    bool previous_exists() const { return bool(m_previous); }
    const Definition& previous() const { return *m_previous; }
    SourceLocation location() const { return m_location; }
    IdentifierId name() const { return m_name; }
    const Expression& expression() const { return *m_expression; }
    DefinitionKind kind() const { return m_kind; }
private:
    std::unique_ptr<Definition> m_previous;
    SourceLocation m_location;
    IdentifierId m_name;
    ExpressionPtr m_expression;
    DefinitionKind m_kind;
};

#endif /* sentry INCLUDE_DEFINITION_H_ */
