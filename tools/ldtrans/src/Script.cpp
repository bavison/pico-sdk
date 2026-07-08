/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "Script.h"

Script g_script;

class SortVisitor : public ExpressionVisitor
{
public:
    explicit SortVisitor(std::vector<const Definition*>& definition_stack, std::vector<SourceLocation>& reference_stack) : m_definition_stack(definition_stack), m_reference_stack(reference_stack), m_assignee_kind(definition_stack.back()->kind()) {}

    void examine(const Definition* d, SourceLocation location)
    {
        // Check if we've already processed this definition
        if (std::find(g_script.definition_order.begin(), g_script.definition_order.end(), d) != g_script.definition_order.end())
            return;
        // Use call stack to preserve previous assignee kind over iteration
        DefinitionKind assignee_kind = m_assignee_kind;
        if (assignee_kind != DefinitionKind::SectionScopeSymbol && d->kind() == DefinitionKind::SectionScopeSymbol)
            throw DiagnosticError(m_definition_stack.back()->location(), "error: invalid context for reference", {{ location, "to section-scope symbol" }});
        m_assignee_kind = d->kind();
        // Add the location of the definition reference to the stack
        m_reference_stack.push_back(location);
        // At this point, the definition stack and reference stack are
        // the same depth, and it's the ideal time to test for circular
        // references
        if (auto definition_it = std::find(m_definition_stack.begin(), m_definition_stack.end(), d); definition_it != m_definition_stack.end()) {
            auto reference_it = m_reference_stack.end() - std::distance(definition_it, m_definition_stack.end());
            std::vector<DiagnosticError::Note> notes;
            while (definition_it != m_definition_stack.end()) {
                const Definition* definition_from = *definition_it;
                ++definition_it;
                const Definition* definition_to = definition_it == m_definition_stack.end() ? d : *definition_it;
                notes.push_back({ *reference_it,
                                   definition_from->describe(g_script.identifiers) +
                                   " depends on " +
                                   definition_to->describe(g_script.identifiers)
                                });
                ++reference_it;
            }
            throw DiagnosticError(d->location(), std::string("error: circular dependency detected while evaluating ") + d->describe(g_script.identifiers), notes);
        }
        // Now add an element to the definition stack and recurse into processing that one
        m_definition_stack.push_back(d);
        SortVisitor sort(m_definition_stack, m_reference_stack);
        d->expression().accept(sort);
        // Once all referenced definitions are added to the sort order, we can add this one
        g_script.definition_order.push_back(d);
        if (d->kind() == DefinitionKind::TopLevelSymbol || d->kind() == DefinitionKind::SectionScopeSymbol) {
            auto symbol_id = static_cast<const Symbol*>(d) - &g_script.symbols[0];
            g_script.symbol_order.push_back(symbol_id);
        }
        // Pop stacks
        m_definition_stack.pop_back();
        m_reference_stack.pop_back();
        m_assignee_kind = assignee_kind;
    }

    void visit(const class SymbolExpression& expr) override
    {
        if (auto it = g_script.symbol_lookup.find(expr.identifier()); it != g_script.symbol_lookup.end()) {
            auto s = it->second;
            auto* definition = static_cast<const Definition*>(&g_script.symbols[s]);
            examine(definition, expr.location());
        } else {
            throw DiagnosticError(expr.location(), "error: undefined symbol");
        }
    }

    void visit(const class IntegerExpression& expr) override
    {
        /* Nothing to do */
    }

    void visit(const class UnaryExpression& expr) override
    {
        expr.sub_expr().accept(*this);
    }

    void visit(const class BinaryExpression& expr) override
    {
        expr.left_expr().accept(*this);
        expr.right_expr().accept(*this);
    }

    void visit(const class TernaryExpression& expr) override
    {
        expr.if_expr().accept(*this);
        expr.then_expr().accept(*this);
        expr.else_expr().accept(*this);
    }

    void visit(const class SectionExpression& expr) override
    {
        /* Nothing to do */
    }

    void visit(const class DefinedExpression& expr) override
    {
/* TODO */
    }

    void visit(const class MemoryExpression& expr) override
    {
        if (auto it = g_script.memory_region_lookup.find(expr.memory()); it != g_script.memory_region_lookup.end()) {
            auto m = it->second;
            auto* definition = expr.operation() == MemoryOperator::Origin ? &g_script.memory_regions[m].origin() : &g_script.memory_regions[m].length();
            examine(definition, expr.location());
        } else {
            throw DiagnosticError(expr.location(), "error: unknown memory region");
        }
    }

    void visit(const class LocationCounterExpression& expr) override
    {
        /* Nothing to do */
    }

private:
    std::vector<const Definition*>& m_definition_stack;
    std::vector<SourceLocation>& m_reference_stack;
    DefinitionKind m_assignee_kind;
};

void Script::SortDefinitions()
{
    /* Some linkers (at least IAR) don't allow forward references to
     * symbols, so sort them into dependency order. While we're at it,
     * check top-level symbols don't depend on section symbols, check
     * there are no dependency loops and check for undefined symbols.
     * Mixing memory region origin and length definitions in with
     * these allows us to set an evaluation order across all values
     * that we may need to calculate. */
    auto sort = [this](const Definition* definition) {
        if (std::find(definition_order.begin(), definition_order.end(), definition) == definition_order.end()) {
            std::vector<const Definition*> definition_stack = { definition };
            std::vector<SourceLocation> reference_stack;
            SortVisitor sort(definition_stack, reference_stack);
            definition->expression().accept(sort);
            // Once all referenced definitions are added to the sort order, we can add this one
            definition_order.push_back(definition);
            if (definition->kind() == DefinitionKind::TopLevelSymbol || definition->kind() == DefinitionKind::SectionScopeSymbol) {
                auto symbol_id = static_cast<const Symbol*>(definition) - &symbols[0];
                symbol_order.push_back(symbol_id);
            }
        }
    };
    for (MemoryRegionId m = 0; m < memory_regions.size(); ++m) {
        sort(&memory_regions[m].origin());
        sort(&memory_regions[m].length());
    }
    for (SymbolId s = (SymbolId) 0; s < symbols.size(); ++s) {
        sort(&symbols[s]);
    }
}
