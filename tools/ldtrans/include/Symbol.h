/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_SYMBOL_H_
#define INCLUDE_SYMBOL_H_

#include <string>

#include "Definition.h"
#include "Expression.h"
#include "Identifier.h"
#include "SourceLocation.h"
#include "SourceManager.h"

enum class SymbolKind
{
    TopLevel,
    SectionScope,
};

class Symbol : public Definition
{
public:
    Symbol(SourceLocation location, IdentifierId name, ExpressionPtr expression, SymbolKind kind = SymbolKind::TopLevel) :
        Definition(location, name, std::move(expression), kind == SymbolKind::TopLevel ? DefinitionKind::TopLevelSymbol : DefinitionKind::SectionScopeSymbol) {}
    std::string dump(const IdentifierManager& ids) const
    {
        DumpVisitor expression_dump(ids);
        expression().accept(expression_dump);
        return std::string("SYMBOL\n") +
            "  location: " + g_source_manager.toFileLineColumn(location()) + "\n" +
            "  name: " + ids.toDisplayName(name()) + "\n" +
            "  value: " + expression_dump.result() + "\n" +
            "  kind: " + (Definition::kind() == DefinitionKind::TopLevelSymbol ? "top-level\n" : "section\n");
    }
    SymbolKind kind() const { return Definition::kind() == DefinitionKind::TopLevelSymbol ? SymbolKind::TopLevel : SymbolKind::SectionScope; }
private:
};

#endif /* sentry INCLUDE_SYMBOL_H_ */
