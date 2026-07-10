/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_EXPRESSION_H_
#define INCLUDE_EXPRESSION_H_

#include <cstdint>

#include <charconv>
#include <memory>

#include "Identifier.h"
#include "main.h"
#include "SourceLocation.h"

struct IdentifierToken
{
    SourceLocation loc;
    IdentifierId id;
};

struct IntegerToken
{
    SourceLocation loc;
    uint64_t value; // future-proofing!
};

// We use the visitor design pattern so we can can encapsulate, for example,
// translators to target grammars in separate source files. This relies on
// using overloads of a common method to select between different subclasses
// and we then specialise that method in the other source file, rather than
// adding a new method for each traversal type to every subclass in its
// primary definition.
class ExpressionVisitor
{
public:
    virtual ~ExpressionVisitor() = default;

    virtual void visit(const class SymbolExpression& expr) = 0;
    virtual void visit(const class IntegerExpression& expr) = 0;
    virtual void visit(const class UnaryExpression& expr) = 0;
    virtual void visit(const class BinaryExpression& expr) = 0;
    virtual void visit(const class TernaryExpression& expr) = 0;
    virtual void visit(const class SectionExpression& expr) = 0;
    virtual void visit(const class DefinedExpression& expr) = 0;
    virtual void visit(const class MemoryExpression& expr) = 0;
    virtual void visit(const class LocationCounterExpression& expr) = 0;
};

// Base class for expression nodes
class Expression
{
public:
    virtual ~Expression() = default;
    virtual void accept(ExpressionVisitor& visitor) const = 0;
};

using ExpressionPtr = std::unique_ptr<Expression>;

class SymbolExpression : public Expression
{
public:
    SymbolExpression(IdentifierToken symbol) : m_symbol(symbol) {}
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    SourceLocation location() const { return m_symbol.loc; }
    IdentifierId identifier() const { return m_symbol.id; }
private:
    IdentifierToken m_symbol;
};

class IntegerExpression : public Expression
{
public:
    IntegerExpression(IntegerToken integer) : m_integer(integer) {}
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    uint64_t value() const { return m_integer.value; }
private:
    IntegerToken m_integer;
};

enum class UnaryOperator
{
    Plus,
    Minus,
    BitwiseNot,
    LogicalNot,
    Align,
};

class UnaryExpression : public Expression
{
public:
    UnaryExpression(SourceLocation location, UnaryOperator op, ExpressionPtr sub_expr) : m_location(location), m_operation(op), m_sub_expr(std::move(sub_expr)) {}
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    SourceLocation location() const { return m_location; }
    UnaryOperator operation() const { return m_operation; }
    const Expression& sub_expr() const { return *m_sub_expr; }
private:
    SourceLocation m_location;
    UnaryOperator m_operation;
    ExpressionPtr m_sub_expr;
};

enum class BinaryOperator
{
    Multiply,
    Add,
    Subtract,
    GreaterOrEqual,
    Greater,
    LessOrEqual,
    Less,
    Equal,
    BitwiseAnd,
    Max,
};

class BinaryExpression : public Expression
{
public:
    BinaryExpression(SourceLocation location, BinaryOperator op, ExpressionPtr left_expr, ExpressionPtr right_expr) : m_location(location), m_operation(op), m_left_expr(std::move(left_expr)), m_right_expr(std::move(right_expr)) {}
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    SourceLocation location() const { return m_location; }
    BinaryOperator operation() const { return m_operation; }
    const Expression& left_expr() const { return *m_left_expr; }
    const Expression& right_expr() const { return *m_right_expr; }
private:
    SourceLocation m_location;
    BinaryOperator m_operation;
    ExpressionPtr m_left_expr;
    ExpressionPtr m_right_expr;
};

class TernaryExpression : public Expression
{
public:
    TernaryExpression(SourceLocation location, ExpressionPtr condition_expr, ExpressionPtr if_expr, ExpressionPtr else_expr) : m_location(location), m_if_expr(std::move(condition_expr)), m_then_expr(std::move(if_expr)), m_else_expr(std::move(else_expr)) {}
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    const Expression& if_expr() const { return *m_if_expr; }
    const Expression& then_expr() const { return *m_then_expr; }
    const Expression& else_expr() const { return *m_else_expr; }
private:
    SourceLocation m_location;
    ExpressionPtr m_if_expr;
    ExpressionPtr m_then_expr;
    ExpressionPtr m_else_expr;
};

enum class SectionOperator
{
    AlignOf,
    SizeOf,
};

class SectionExpression : public Expression
{
public:
    SectionExpression(SourceLocation location, SectionOperator op, IdentifierId section) : m_location(location), m_operation(op), m_section(section) {}
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    SourceLocation location() const { return m_location; }
    SectionOperator operation() const { return m_operation; }
    IdentifierId section() const { return m_section; }
private:
    SourceLocation m_location;
    SectionOperator m_operation;
    IdentifierId m_section;
};

class DefinedExpression : public Expression
{
public:
    DefinedExpression(SourceLocation location, IdentifierId symbol) : m_location(location), m_symbol(symbol) {}
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    SourceLocation location() const { return m_location; }
    IdentifierId symbol() const { return m_symbol; }
private:
    SourceLocation m_location;
    IdentifierId m_symbol;
};

enum class MemoryOperator
{
    Length,
    Origin,
};

class MemoryExpression : public Expression
{
public:
    MemoryExpression(SourceLocation location, MemoryOperator op, IdentifierId memory) : m_location(location), m_operation(op), m_memory(memory) {}
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    SourceLocation location() const { return m_location; }
    MemoryOperator operation() const { return m_operation; }
    IdentifierId memory() const { return m_memory; }
private:
    SourceLocation m_location;
    MemoryOperator m_operation;
    IdentifierId m_memory;
};

class LocationCounterExpression : public Expression
{
public:
    void accept(ExpressionVisitor& visitor) const override { visitor.visit(*this); }
    SourceLocation location() const { return m_location; }
private:
    SourceLocation m_location;
};


class DumpVisitor : public ExpressionVisitor
{
public:
    explicit DumpVisitor(const IdentifierManager& ids) : m_ids(ids) {}

    void visit(const SymbolExpression& expr) override
    {
        m_result = m_ids.toDisplayName(expr.identifier());
    }

    void visit(const IntegerExpression& expr) override
    {
        char buffer[2 + 16 + 1] = "0x"; // includes null terminator, wherever that is
        auto [ptr, ec] = std::to_chars(buffer + 2, buffer + 2 + 16, expr.value(), 16);
        m_result = ec == std::errc{} ? buffer : "<invalid>";
    }

    void visit(const UnaryExpression& expr) override
    {
        expr.sub_expr().accept(*this);
        switch (expr.operation()) {
        case UnaryOperator::Plus:
            m_result = std::string("+(") + m_result + ")";
            break;
        case UnaryOperator::Minus:
            m_result = std::string("-(") + m_result + ")";
            break;
        case UnaryOperator::BitwiseNot:
            m_result = std::string("~(") + m_result + ")";
            break;
        case UnaryOperator::LogicalNot:
            m_result = std::string("!(") + m_result + ")";
            break;
        case UnaryOperator::Align:
            m_result = std::string("ALIGN(") + m_result + ")";
            break;
        default:
            m_result = "<unknown unary op>";
            break;
        }
    }

    void visit(const BinaryExpression& expr) override
    {
        expr.left_expr().accept(*this);
        auto left_expr = std::move(m_result);
        expr.right_expr().accept(*this);
        auto right_expr = std::move(m_result);
        switch (expr.operation()) {
        case BinaryOperator::Multiply:
            m_result = std::string("(") + left_expr + " * " + right_expr + ")";
            break;
        case BinaryOperator::Add:
            m_result = std::string("(") + left_expr + " + " + right_expr + ")";
            break;
        case BinaryOperator::Subtract:
            m_result = std::string("(") + left_expr + " - " + right_expr + ")";
            break;
        case BinaryOperator::GreaterOrEqual:
            m_result = std::string("(") + left_expr + " >= " + right_expr + ")";
            break;
        case BinaryOperator::Greater:
            m_result = std::string("(") + left_expr + " > " + right_expr + ")";
            break;
        case BinaryOperator::LessOrEqual:
            m_result = std::string("(") + left_expr + " <= " + right_expr + ")";
            break;
        case BinaryOperator::Less:
            m_result = std::string("(") + left_expr + " < " + right_expr + ")";
            break;
        case BinaryOperator::Equal:
            m_result = std::string("(") + left_expr + " == " + right_expr + ")";
            break;
        case BinaryOperator::BitwiseAnd:
            m_result = std::string("(") + left_expr + " & " + right_expr + ")";
            break;
        case BinaryOperator::Max:
            m_result = std::string("MAX(") + left_expr + ", " + right_expr + ")";
            break;
        default:
            m_result = "<unknown binary op>";
            break;
        }
    }

    void visit(const TernaryExpression& expr) override
    {
        expr.if_expr().accept(*this);
        auto if_expr = std::move(m_result);
        expr.then_expr().accept(*this);
        auto then_expr = std::move(m_result);
        expr.else_expr().accept(*this);
        auto else_expr = std::move(m_result);
        m_result = std::string("(") + if_expr + " ? " + then_expr + " : " + else_expr + ")";
    }

    void visit(const SectionExpression& expr) override
    {
        switch (expr.operation()) {
        case SectionOperator::AlignOf:
            m_result = std::string("ALIGNOF(") + m_ids.toDisplayName(expr.section()) + ")";
            break;
        case SectionOperator::SizeOf:
            m_result = std::string("SIZEOF(") + m_ids.toDisplayName(expr.section()) + ")";
            break;
        default:
            m_result = "<unknown section op>";
            break;
        }
    }

    void visit(const DefinedExpression& expr) override
    {
        m_result = std::string("DEFINED(") + m_ids.toDisplayName(expr.symbol()) + ")";
    }

    void visit(const MemoryExpression& expr) override
    {
        switch (expr.operation()) {
        case MemoryOperator::Length:
            m_result = std::string("LENGTH(") + m_ids.toDisplayName(expr.memory()) + ")";
            break;
        case MemoryOperator::Origin:
            m_result = std::string("ORIGIN(") + m_ids.toDisplayName(expr.memory()) + ")";
            break;
        default:
            m_result = "<unknown memory region op>";
            break;
        }
    }

    void visit(const LocationCounterExpression& expr) override
    {
        m_result = "<location counter unimplemeted>";
    }

    std::string result() const { return m_result; }

private:
    const IdentifierManager& m_ids;
    std::string m_result;
};

#endif /* sentry INCLUDE_EXPRESSION_H_ */
