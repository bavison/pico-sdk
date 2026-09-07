/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <iostream>

#include "Script.h"

Script g_script;

class SortVisitor : public ConstExpressionVisitor
{
public:
    explicit SortVisitor(std::vector<Definition*>& definition_stack, std::vector<SourceLocation>& reference_stack) : m_definition_stack(definition_stack), m_reference_stack(reference_stack), m_assignee_kind(definition_stack.back()->kind()) {}

    void examine(Definition* d, SourceLocation location)
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
        // Pop stacks
        m_definition_stack.pop_back();
        m_reference_stack.pop_back();
        m_assignee_kind = assignee_kind;
    }

    void visit(const class SymbolExpression& expr) override
    {
        Definition* definition;
        if (expr.identifier() == m_definition_stack.back()->name() &&
                (m_definition_stack.back()->kind() == DefinitionKind::TopLevelSymbol ||
                 m_definition_stack.back()->kind() == DefinitionKind::SectionScopeSymbol)) {
            // We're referring to the same symbol currently being assigned
            // so we should refer to the previous definition of the symbol
            // instead. It is not an error at sorting time if such previous
            // definition doesn't exist because it may be within an untaken
            // branch of a conditional expression - but obviously we can't
            // recurse further in that case.
            definition = m_definition_stack.back();
            if (definition->previous_exists())
                definition  = &definition->previous();
            else
                return;
        } else {
            // Refer to the latest definition of all other symbols.
            if (auto it = g_script.symbol_lookup.find(expr.identifier()); it != g_script.symbol_lookup.end())
                definition = &g_script.symbols[it->second].definition();
            else
                return;
        }
        examine(definition, expr.location());
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
        Definition* definition;
        if (expr.symbol() == m_definition_stack.back()->name() &&
                (m_definition_stack.back()->kind() == DefinitionKind::TopLevelSymbol ||
                 m_definition_stack.back()->kind() == DefinitionKind::SectionScopeSymbol)) {
            // We're referring to the same symbol currently being assigned
            // so we should refer to the previous definition of the symbol
            // instead. It is not an error at sorting time if such previous
            // definition doesn't exist because it may be within an untaken
            // branch of a conditional expression - but obviously we can't
            // recurse further in that case.
            definition = m_definition_stack.back();
            if (definition->previous_exists())
                definition  = &definition->previous();
            else
                return;
        } else {
            // Refer to the latest definition of all other symbols.
            if (auto it = g_script.symbol_lookup.find(expr.symbol()); it != g_script.symbol_lookup.end())
                definition = &g_script.symbols[it->second].definition();
            else
                return;
        }
        examine(definition, expr.location());
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
    std::vector<Definition*>& m_definition_stack;
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
    auto sort = [this](Definition* definition) {
        if (std::find(definition_order.begin(), definition_order.end(), definition) == definition_order.end()) {
            std::vector<Definition*> definition_stack = { definition };
            std::vector<SourceLocation> reference_stack;
            SortVisitor sort(definition_stack, reference_stack);
            definition->expression().accept(sort);
            // Once all referenced definitions are added to the sort order, we can add this one
            definition_order.push_back(definition);
        }
    };
    for (MemoryRegionId m = 0; m < memory_regions.size(); ++m) {
        sort(&memory_regions[m].origin());
        sort(&memory_regions[m].length());
    }
    for (SymbolId s = (SymbolId) 0; s < symbols.size(); ++s) {
        sort(&symbols[s].definition());
    }
    for (OutputSectionPtr& o : output_sections) {
        if (o->vma)
            sort(o->vma.get());
        if (o->lma)
            sort(o->lma.get());
    }
    for (Assertion& a : assertions) {
        sort(&a.definition);
    }
}

class EvaluationVisitor : public ConstExpressionVisitor
{
public:
    explicit EvaluationVisitor(Definition* definition) : m_target(definition) {}

    void visit(const class SymbolExpression& expr) override
    {
        if (m_target->m_dead_branch) {
            m_target->m_value = { 0 };
            return;
        }
        Definition* d;
        if (expr.identifier() == m_target->name() &&
                (m_target->kind() == DefinitionKind::TopLevelSymbol ||
                 m_target->kind() == DefinitionKind::SectionScopeSymbol)) {
            // We're referring to the same symbol currently being assigned
            // so we should refer to the previous definition of the symbol
            // instead.
            if (!m_target->previous_exists()) {
                throw DiagnosticError(m_target->location(), std::string("error: circular dependency detected while evaluating ") + m_target->describe(g_script.identifiers),
                        {{ expr.location(), m_target->describe(g_script.identifiers) + " depends on " + m_target->describe(g_script.identifiers) + " (and there is no earlier definition)" }});
            }
            d = &m_target->previous();
        } else {
            // Refer to the latest definition of all other symbols.
            if (auto it = g_script.symbol_lookup.find(expr.identifier()); it != g_script.symbol_lookup.end())
                d = &g_script.symbols[it->second].definition();
            else
                throw DiagnosticError(expr.location(), "error: undefined symbol");
        }
        // Definition sorting means we can rely on the symbol value already having been evaluated
        m_target->m_value = d->value();
    }

    void visit(const class IntegerExpression& expr) override
    {
        m_target->m_value = { expr.value() };
    }

    void visit(const class UnaryExpression& expr) override
    {
        expr.sub_expr().accept(*this);
        if (m_target->m_value.type != DefinitionValueType::Absolute)
            m_target->m_value.type = DefinitionValueType::ModifiedLocationCounter;
        switch (expr.operation()) {
        case UnaryOperator::Plus:
            /* unary plus is a nop */
            break;
        case UnaryOperator::Minus:
            m_target->m_value.absolute = -m_target->m_value.absolute;
            break;
        case UnaryOperator::BitwiseNot:
            m_target->m_value.absolute = ~m_target->m_value.absolute;
            break;
        case UnaryOperator::LogicalNot:
            m_target->m_value.absolute = !m_target->m_value.absolute;
            break;
        case UnaryOperator::Align:
            // This has an implicit argument of the location counter, which
            // is only valid in section scope, and we leave evaluation of
            // section-scope symbols to the external linker program
            throw DiagnosticError(expr.location(), "error: invalid context for built-in function");
            break;
        default:
            throw DiagnosticError(expr.location(), "error: unknown unary op");
            break;
        }
    }

    void visit(const class BinaryExpression& expr) override
    {
        expr.left_expr().accept(*this);
        auto left_expr = m_target->value();
        expr.right_expr().accept(*this);
        auto right_expr = m_target->value();
        m_target->m_value.type = left_expr.type == DefinitionValueType::Absolute && right_expr.type == DefinitionValueType::Absolute ? DefinitionValueType::Absolute : DefinitionValueType::ModifiedLocationCounter;
        m_target->m_value.uses_location_counter = left_expr.uses_location_counter || right_expr.uses_location_counter;
        switch (expr.operation()) {
        case BinaryOperator::Multiply:
            m_target->m_value.absolute = left_expr.absolute * right_expr.absolute;
            break;
        case BinaryOperator::Add:
            m_target->m_value.absolute = left_expr.absolute + right_expr.absolute;
            break;
        case BinaryOperator::Subtract:
            m_target->m_value.absolute = left_expr.absolute - right_expr.absolute;
            break;
        case BinaryOperator::GreaterOrEqual:
            m_target->m_value.absolute = left_expr.absolute >= right_expr.absolute;
            break;
        case BinaryOperator::Greater:
            m_target->m_value.absolute = left_expr.absolute > right_expr.absolute;
            break;
        case BinaryOperator::LessOrEqual:
            m_target->m_value.absolute = left_expr.absolute <= right_expr.absolute;
            break;
        case BinaryOperator::Less:
            m_target->m_value.absolute = left_expr.absolute < right_expr.absolute;
            break;
        case BinaryOperator::Equal:
            m_target->m_value.absolute = left_expr.absolute == right_expr.absolute;
            break;
        case BinaryOperator::BitwiseAnd:
            m_target->m_value.absolute = left_expr.absolute & right_expr.absolute;
            break;
        case BinaryOperator::Max:
            m_target->m_value.absolute = left_expr.absolute > right_expr.absolute ? left_expr.absolute : right_expr.absolute;
            break;
        default:
            throw DiagnosticError(expr.location(), "error: unknown binary op");
            break;
        }
    }

    void visit(const class TernaryExpression& expr) override
    {
        bool parent_dead_branch = m_target->m_dead_branch;
        expr.if_expr().accept(*this);
        auto if_expr = m_target->value();
        DefinitionValue then_expr;
        DefinitionValue else_expr;
        if (if_expr.type != DefinitionValueType::Absolute)
            throw DiagnosticError(expr.location(), "error: location counter cannot be used in if clause of ternary operator in this context");
        if (m_target->value().absolute) {
            m_target->m_dead_branch = true;
            expr.else_expr().accept(*this);
            else_expr = m_target->value();
            m_target->m_dead_branch = parent_dead_branch;
            expr.then_expr().accept(*this);
            then_expr = m_target->value();
        } else {
            m_target->m_dead_branch = true;
            expr.then_expr().accept(*this);
            then_expr = m_target->value();
            m_target->m_dead_branch = parent_dead_branch;
            expr.else_expr().accept(*this);
            else_expr = m_target->value();
        }
        m_target->m_value.uses_location_counter = if_expr.uses_location_counter || then_expr.uses_location_counter || else_expr.uses_location_counter;
    }

    void visit(const class SectionExpression& expr) override
    {
        throw DiagnosticError(expr.location(), "error: invalid context for built-in function");
    }

    void visit(const class DefinedExpression& expr) override
    {
        if (expr.symbol() == m_target->name() &&
                (m_target->kind() == DefinitionKind::TopLevelSymbol ||
                 m_target->kind() == DefinitionKind::SectionScopeSymbol)) {
            // We're referring to the same symbol currently being assigned
            // so we should refer to the previous definition of the symbol
            // instead.
            m_target->m_value = { m_target->previous_exists() };
        } else {
            // Refer to the latest definition of all other symbols.
            auto it = g_script.symbol_lookup.find(expr.symbol());
            m_target->m_value = { it != g_script.symbol_lookup.end() };
        }
    }

    void visit(const class MemoryExpression& expr) override
    {
        // Definition sorting means we can rely on the value already having
        // been evaluated. Check for undefined memory region was already
        // performed at definition sorting time.
        auto& memory_region = g_script.memory_regions[g_script.memory_region_lookup.find(expr.memory())->second];
        switch (expr.operation()) {
        case MemoryOperator::Length:
            m_target->m_value = memory_region.length().value();
            break;
        case MemoryOperator::Origin:
            m_target->m_value = memory_region.origin().value();
            break;
        default:
            throw DiagnosticError(expr.location(), "error: unknown memory region op");
        }
    }

    void visit(const class LocationCounterExpression& expr) override
    {
        if (m_target->kind() != DefinitionKind::OutputSectionVMA &&
            m_target->kind() != DefinitionKind::OutputSectionLMA)
            throw DiagnosticError(expr.location(), "error: invalid context for location counter");
        m_target->m_value = { 0, DefinitionValueType::LocationCounter, true };
    }

private:
    Definition* m_target;
};

void Script::EvaluateDefinitions()
{
    for (auto definition : definition_order) {
        if (definition->kind() != DefinitionKind::SectionScopeSymbol &&
            definition->kind() != DefinitionKind::Assertion) {
            EvaluationVisitor evaluate(definition);
            definition->expression().accept(evaluate);
            if ((definition->kind() == DefinitionKind::OutputSectionVMA ||
                 definition->kind() == DefinitionKind::OutputSectionLMA) &&
                    definition->value().type == DefinitionValueType::ModifiedLocationCounter)
                throw DiagnosticError(definition->location(), "error: unsupported use of location counter in output section address");
//            std::cout << definition->dump(identifiers) << std::endl;
        }
    }
}

unsigned Script::GenerateAnchorIndex()
{
    static unsigned index = 0;
    return ++index;
}
