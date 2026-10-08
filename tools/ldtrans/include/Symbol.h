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
    Symbol(DefinitionPtr definition) : m_definition(definition) {}
    void redefine(DefinitionPtr definition)
    {
        if (m_definition->kind() != definition->kind())
            throw DiagnosticError(definition->location(), "error: cannot redefine a symbol with a different scope", {{ m_definition->location(), "previous definition was here" }});
        definition->enchain(m_definition);
        m_definition = definition;
    }
    std::string dump(const IdentifierManager& ids) const
    {
        DumpVisitor expression_dump(ids);
        m_definition->expression().accept(expression_dump);
        return std::string("SYMBOL\n") +
            "  location: " + g_source_manager.toFileLineColumn(m_definition->location()) + "\n" +
            "  name: " + ids.toDisplayName(*m_definition->name()) + "\n" +
            "  value: " + expression_dump.result() + "\n" +
            "  kind: " + (m_definition->kind() == DefinitionKind::TopLevelSymbol ? "top-level\n" : "section\n") +
            "  visibility: " + (m_definition->visibility() == DefinitionVisibility::Standard ? "standard\n" : m_definition->visibility() == DefinitionVisibility::Provide ? "provide\n" : "provide hidden\n");
    }
    Definition& definition() const { return *m_definition; }
private:
    std::shared_ptr<Definition> m_definition;
};

#endif /* sentry INCLUDE_SYMBOL_H_ */
