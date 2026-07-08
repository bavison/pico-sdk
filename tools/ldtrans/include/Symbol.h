/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_SYMBOL_H_
#define INCLUDE_SYMBOL_H_

#include <memory>
#include <string>

#include "Definition.h"
#include "Diagnostic.h"
#include "Expression.h"
#include "Identifier.h"
#include "SourceLocation.h"
#include "SourceManager.h"

class Symbol
{
public:
    Symbol(Definition& definition) : m_definition(std::make_unique<Definition>(std::move(definition))) {}
    void redefine(Definition& definition)
    {
        if (m_definition->kind() != definition.kind())
            throw DiagnosticError(definition.location(), "error: cannot redefine a symbol with a different scope", {{ m_definition->location(), "previous definition was here" }});
        auto new_definition = std::make_unique<Definition>(std::move(definition));
        new_definition->enchain(m_definition);
        m_definition = std::move(new_definition);
    }
    std::string dump(const IdentifierManager& ids) const
    {
        DumpVisitor expression_dump(ids);
        m_definition->expression().accept(expression_dump);
        return std::string("SYMBOL\n") +
            "  location: " + g_source_manager.toFileLineColumn(m_definition->location()) + "\n" +
            "  name: " + ids.toDisplayName(m_definition->name()) + "\n" +
            "  value: " + expression_dump.result() + "\n" +
            "  kind: " + (m_definition->kind() == DefinitionKind::TopLevelSymbol ? "top-level\n" : "section\n");
    }
    const Definition& definition() const { return *m_definition; }
private:
    std::unique_ptr<Definition> m_definition;
};

#endif /* sentry INCLUDE_SYMBOL_H_ */
