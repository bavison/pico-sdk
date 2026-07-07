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
    explicit SortVisitor(std::vector<SymbolId>& symbol_stack, std::vector<SourceLocation>& reference_stack, SymbolKind assignee_kind) : m_symbol_stack(symbol_stack), m_reference_stack(reference_stack), m_assignee_kind(assignee_kind) {}

    void visit(const class SymbolExpression& expr) override
    {
        if (auto it = g_script.symbol_lookup.find(expr.identifier()); it != g_script.symbol_lookup.end()) {
            auto s = it->second;
            // Check if we've already processed this symbol
            if (std::find(g_script.symbol_order.begin(), g_script.symbol_order.end(), s) != g_script.symbol_order.end())
                return;
            // Use call stack to preserve previous assignee kind over iteration
            SymbolKind assignee_kind = m_assignee_kind;
            if (assignee_kind == SymbolKind::TopLevel && g_script.symbols[s].kind() == SymbolKind::Section)
                throw DiagnosticError(g_script.symbols[m_symbol_stack.back()].location(), "error: assignment to top-level symbol", {{ expr.location(), "from section-scope symbol" }});
            m_assignee_kind = g_script.symbols[s].kind();
            // Add the location of the symbol reference to the stack.
            m_reference_stack.push_back(expr.location());
            // At this point, the symbol stack and reference stack are the
            // same depth, and it's the ideal time to test for circular
            // references
            if (auto symbol_it = std::find(m_symbol_stack.begin(), m_symbol_stack.end(), s); symbol_it != m_symbol_stack.end()) {
                SourceLocation primary_location = g_script.symbols[*symbol_it].location();
                std::string primary_name = g_script.identifiers.toDisplayName(g_script.symbols[*symbol_it].name());
                auto reference_it = m_reference_stack.end() - std::distance(symbol_it, m_symbol_stack.end());
                std::vector<DiagnosticError::Note> notes;
                while (symbol_it != m_symbol_stack.end()) {
                    SymbolId symbol_from = *symbol_it;
                    ++symbol_it;
                    SymbolId symbol_to = symbol_it == m_symbol_stack.end() ? s : *symbol_it;
                    notes.push_back({ *reference_it,
                                      g_script.identifiers.toDisplayName(g_script.symbols[symbol_from].name()) +
                                      " depends on " +
                                      g_script.identifiers.toDisplayName(g_script.symbols[symbol_to].name())});
                    ++reference_it;
                }
                throw DiagnosticError(primary_location, std::string("error: circular dependency detected while evaluating symbol ") + primary_name, notes);
            }
            // Now add an element to the symbol stack and recurse into processing that one
            m_symbol_stack.push_back(s);
            SortVisitor sort(m_symbol_stack, m_reference_stack, g_script.symbols[s].kind());
            g_script.symbols[s].expression().accept(sort);
            // Once all child symbols are added to the sort order, we can add this one
            g_script.symbol_order.push_back(s);
            // Pop stacks
            m_symbol_stack.pop_back();
            m_reference_stack.pop_back();
            m_assignee_kind = assignee_kind;
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
        /* Nothing to do */
    }

    void visit(const class LocationCounterExpression& expr) override
    {
        /* Nothing to do */
    }

private:
    std::vector<SymbolId>& m_symbol_stack;
    std::vector<SourceLocation>& m_reference_stack;
    SymbolKind m_assignee_kind;
};

void Script::SortSymbols()
{
    /* Some linkers (at least IAR) don't allow forward references to
     * symbols, so sort them into dependency order. While we're at it,
     * check top-level symbols don't depend on section symbols, check
     * there are no dependency loops and check for undefined symbols */
    for (SymbolId s = (SymbolId) 0; s < symbols.size(); ++s) {
        if (std::find(symbol_order.begin(), symbol_order.end(), s) == symbol_order.end()) {
            std::vector<SymbolId> symbol_stack = { s };
            std::vector<SourceLocation> reference_stack;
            SortVisitor sort(symbol_stack, reference_stack, symbols[s].kind());
            symbols[s].expression().accept(sort);
            // Once all child symbols are added to the sort order, we can add this one
            symbol_order.push_back(s);
        }
    }
}
