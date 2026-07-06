/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_SYMBOL_H_
#define INCLUDE_SYMBOL_H_

#include <string>
#include <unordered_map>

#include "Expression.h"
#include "Identifier.h"
#include "SourceLocation.h"
#include "SourceManager.h"

enum class SymbolKind
{
    TopLevel,
    Section,
};

enum class SymbolState
{
    Unvisited,
    Visiting,
    Visited,
};

class Symbol
{
public:
    Symbol(SourceLocation location, IdentifierId name, ExpressionPtr expression, SymbolKind kind = SymbolKind::TopLevel) : m_location(location), m_name(name), m_expression(std::move(expression)), m_kind(kind) {}
    std::string dump(const IdentifierManager& ids) const
    {
        DumpVisitor expression_dump(ids);
        m_expression->accept(expression_dump);
        return std::string("SYMBOL\n") +
            "  location: " + g_source_manager.toFileLineColumn(m_location) + "\n" +
            "  name: " + ids.toDisplayName(m_name) + "\n" +
            "  value: " + expression_dump.result() + "\n" +
            "  kind: " + (m_kind == SymbolKind::TopLevel ? "top-level\n" : "section\n");
    }
private:
    SourceLocation m_location;
    IdentifierId m_name;
    ExpressionPtr m_expression;
    SymbolKind m_kind;
    SymbolState m_state = SymbolState::Unvisited;
};

/* Symbol ID is an index into the symbol table */
using SymbolId = std::size_t;

#endif /* sentry INCLUDE_SYMBOL_H_ */
