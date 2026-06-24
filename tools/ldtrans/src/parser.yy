/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/* Literal insertions into parser.hpp (near top) */
%code requires {

#include <cstdint>

#include <charconv>
#include <optional>
#include <unordered_map>
#include <vector>

#include "Identifier.h"
#include "lexer.h"
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

class Expression
{
public:
    virtual ~Expression() = default;
    virtual std::string dump() const = 0;
};

using ExpressionPtr = std::unique_ptr<Expression>;

class SymbolExpression : public Expression
{
public:
    SymbolExpression(IdentifierToken symbol) : m_symbol(symbol) {}
    std::string dump() const override
    {
        return g_identifier_manager.toDisplayName(m_symbol.id);
    }
private:
    IdentifierToken m_symbol;
};

class IntegerExpression : public Expression
{
public:
    IntegerExpression(IntegerToken integer) : m_integer(integer) {}
    std::string dump() const override
    {
        char buffer[2 + 16 + 1] = "0x"; // includes null terminator, wherever that is
        auto [ptr, ec] = std::to_chars(buffer + 2, buffer + 2 + 16, m_integer.value, 16);
        if (ec == std::errc{})
            return buffer;
        else
            return "<invalid>";
    }
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
    UnaryExpression(SourceLocation location, UnaryOperator op, ExpressionPtr sub_expr) : m_location(location), m_op(op), m_sub_expr(std::move(sub_expr)) {}
    std::string dump() const override
    {
        switch (m_op) {
        case UnaryOperator::Plus:
            return std::string("+(") + m_sub_expr->dump() + ")";
        case UnaryOperator::Minus:
            return std::string("-(") + m_sub_expr->dump() + ")";
        case UnaryOperator::BitwiseNot:
            return std::string("~(") + m_sub_expr->dump() + ")";
        case UnaryOperator::LogicalNot:
            return std::string("!(") + m_sub_expr->dump() + ")";
        case UnaryOperator::Align:
            return std::string("ALIGN(") + m_sub_expr->dump() + ")";
        default:
            return "<unknown unary op>";
        }
    }
private:
    SourceLocation m_location;
    UnaryOperator m_op;
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
    BitwiseAnd,
    Max,
};

class BinaryExpression : public Expression
{
public:
    BinaryExpression(SourceLocation location, BinaryOperator op, ExpressionPtr left_expr, ExpressionPtr right_expr) : m_location(location), m_op(op), m_left_expr(std::move(left_expr)), m_right_expr(std::move(right_expr)) {}
    std::string dump() const override
    {
        switch (m_op) {
        case BinaryOperator::Multiply:
            return std::string("(") + m_left_expr->dump() + " * " + m_right_expr->dump() + ")";
        case BinaryOperator::Add:
            return std::string("(") + m_left_expr->dump() + " + " + m_right_expr->dump() + ")";
        case BinaryOperator::Subtract:
            return std::string("(") + m_left_expr->dump() + " - " + m_right_expr->dump() + ")";
        case BinaryOperator::GreaterOrEqual:
            return std::string("(") + m_left_expr->dump() + " >= " + m_right_expr->dump() + ")";
        case BinaryOperator::Greater:
            return std::string("(") + m_left_expr->dump() + " > " + m_right_expr->dump() + ")";
        case BinaryOperator::LessOrEqual:
            return std::string("(") + m_left_expr->dump() + " <= " + m_right_expr->dump() + ")";
        case BinaryOperator::Less:
            return std::string("(") + m_left_expr->dump() + " < " + m_right_expr->dump() + ")";
        case BinaryOperator::BitwiseAnd:
            return std::string("(") + m_left_expr->dump() + " & " + m_right_expr->dump() + ")";
        case BinaryOperator::Max:
            return std::string("MAX(") + m_left_expr->dump() + ", " + m_right_expr->dump() + ")";
        default:
            return "<unknown binary op>";
        }
    }
private:
    SourceLocation m_location;
    BinaryOperator m_op;
    ExpressionPtr m_left_expr;
    ExpressionPtr m_right_expr;
};

class TernaryExpression : public Expression
{
public:
    TernaryExpression(SourceLocation location, ExpressionPtr condition_expr, ExpressionPtr if_expr, ExpressionPtr else_expr) : m_location(location), m_condition_expr(std::move(condition_expr)), m_if_expr(std::move(if_expr)), m_else_expr(std::move(else_expr)) {}
    std::string dump() const override
    {
        return std::string("(") + m_condition_expr->dump() + " ? " + m_if_expr->dump() + " ? " + m_else_expr->dump() + ")";
    }
private:
    SourceLocation m_location;
    ExpressionPtr m_condition_expr;
    ExpressionPtr m_if_expr;
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
    SectionExpression(SourceLocation location, SectionOperator op, IdentifierId section) : m_location(location), m_op(op), m_section(section) {}
    std::string dump() const override
    {
        switch (m_op) {
        case SectionOperator::AlignOf:
            return std::string("ALIGNOF(") + g_identifier_manager.toDisplayName(m_section) + ")";
        case SectionOperator::SizeOf:
            return std::string("SIZEOF(") + g_identifier_manager.toDisplayName(m_section) + ")";
        default:
            return "<unknown section op>";
        }
    }
private:
    SourceLocation m_location;
    SectionOperator m_op;
    IdentifierId m_section;
};

class DefinedExpression : public Expression
{
public:
    DefinedExpression(SourceLocation location, IdentifierId symbol) : m_location(location), m_symbol(symbol) {}
    std::string dump() const override
    {
        return std::string("DEFINED(") + g_identifier_manager.toDisplayName(m_symbol) + ")";
    }
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
    MemoryExpression(SourceLocation location, MemoryOperator op, IdentifierId memory) : m_location(location), m_op(op), m_memory(memory) {}
    std::string dump() const override
    {
        switch (m_op) {
        case MemoryOperator::Length:
            return std::string("LENGTH(") + g_identifier_manager.toDisplayName(m_memory) + ")";
        case MemoryOperator::Origin:
            return std::string("ORIGIN(") + g_identifier_manager.toDisplayName(m_memory) + ")";
        default:
            return "<unknown memory region op>";
        }
    }
private:
    SourceLocation m_location;
    MemoryOperator m_op;
    IdentifierId m_memory;
};

enum class MemoryAttribute : uint8_t
{
    ReadOnly   = 1 << 0,
    ReadWrite  = 1 << 1,
    Executable = 1 << 2,
    Alloc      = 1 << 3,
    Init       = 1 << 4,
};

class MemoryAttributes
{
public:
    constexpr MemoryAttributes() = default;
    constexpr MemoryAttributes(char c)
    {
        switch (c) {
        case 'R':
        case 'r':
            m_bits = (uint8_t) MemoryAttribute::ReadOnly;
            break;
        case 'W':
        case 'w':
            m_bits = (uint8_t) MemoryAttribute::ReadWrite;
            break;
        case 'X':
        case 'x':
            m_bits = (uint8_t) MemoryAttribute::Executable;
            break;
        case 'A':
        case 'a':
            m_bits = (uint8_t) MemoryAttribute::Alloc;
            break;
        case 'I':
        case 'i':
        case 'L':
        case 'l':
            m_bits = (uint8_t) MemoryAttribute::Init;
            break;
        default:
            throw DiagnosticError(lexer_symbol_location, "error: invalid attribute specifier");
        }
    }
    MemoryAttributes operator|(const MemoryAttributes& other) const
    {
        return MemoryAttributes{static_cast<uint8_t>(m_bits | other.m_bits)};
    }
    MemoryAttributes& operator|=(const MemoryAttributes& other)
    {
        m_bits |= other.m_bits;
        return *this;
    }
    std::string dump() const
    {
        if (m_bits == 0)
            return "<none>";
        std::string result;
        if (m_bits & (uint8_t) MemoryAttribute::ReadOnly)
            result += "R";
        if (m_bits & (uint8_t) MemoryAttribute::ReadWrite)
            result += "W";
        if (m_bits & (uint8_t) MemoryAttribute::Executable)
            result += "X";
        if (m_bits & (uint8_t) MemoryAttribute::Alloc)
            result += "A";
        if (m_bits & (uint8_t) MemoryAttribute::Init)
            result += "I";
        return result;
    }
private:
    MemoryAttributes(uint8_t bits) : m_bits(bits) {}
    uint8_t m_bits = 0;
};

struct MemoryAttributesRules
{
    MemoryAttributes required;
    MemoryAttributes denied;
    MemoryAttributesRules operator|(const MemoryAttributesRules& other) const
    {
        return MemoryAttributesRules{required | other.required, denied | other.denied};
    }
    std::string dump() const
    {
        return std::string("  required: ") + required.dump() + "\n  denied: " + denied.dump() + "\n";
    }
};

struct MemoryRegion
{
    IdentifierId original_name;
    MemoryAttributesRules rules;
    ExpressionPtr origin;
    ExpressionPtr length;
    std::string dump() const
    {
        return std::string("MEMORY\n") +
            "  name: " + g_identifier_manager.toDisplayName(original_name) + "\n" +
            rules.dump() +
            "  origin: " + origin->dump() + "\n"
            "  length: " + length->dump() + "\n";
    }
};

struct Script
{
    /* Image entry point */
    std::optional<std::pair<SourceLocation,IdentifierId>> entry;
    /* Memory regions (order is significant in case an output section has to match using attributes) */
    std::vector<MemoryRegion> memory_regions;
    /* Map from memory region and region alias names to memory regions */
    std::unordered_map<IdentifierId, std::pair<SourceLocation,size_t>> memory_region_lookup;
};

extern Script g_script;

}

/* Literal insertions into parser.hpp (near bottom) */
%code provides {

/* When using token-constructor API, we need to declare yylex ourselves, and
 * this has to be after yy::parser::symbol_type is defined
 */
yy::parser::symbol_type yylex();

}

/* Literal insertions into parser.cpp (near top) */
%{

#include <iostream>
#include <stdexcept>

#include "Diagnostic.h"
#include "main.h"
#include "parser.hpp"

//#define TRACE(msg) std::cout << "Consumed " << msg << std::endl;
#define TRACE(msg)

Script g_script;

static bool g_memory_region_attribute_sense_required = true;

%}

/* Bison 3.2 allows semantic values to be held directly as C++ types via its
 * roll-your-own equivalent of std::variant. The main benefit over traditional
 * unions of pointers-to-types is that deletion is handled automatically when
 * going out of scope.
 */
%language "c++"
%define api.value.type variant

/* Generate header file with default name (parser.hpp) */
%defines

/* Saves a bit of typing */
%define api.token.prefix {TOK_}

/* Generate factory functions prefixed with make_ inside the parser namespace */
%define api.token.constructor

%token
    /* Commands */
    <SourceLocation>    ENTRY               "ENTRY"
                        INCLUDE             "INCLUDE"
                        MEMORY              "MEMORY"
                        SECTIONS            "SECTIONS"
                        REGION_ALIAS        "REGION_ALIAS"

    /* Keywords */
                        ASSERT              "ASSERT"
                        AT                  "AT"
                        AT_NAMED            "AT>"
                        EXCLUDE_FILE        "EXCLUDE_FILE"
                        KEEP                "KEEP"
                        NOLOAD              "NOLOAD"
                        PROVIDE_HIDDEN      "PROVIDE_HIDDEN"
                        PROVIDE             "PROVIDE"
                        SORT_BY_ALIGNMENT   "SORT_BY_ALIGNMENT"
                        SORT_BY_NAME        "SORT_BY_NAME"

    /* Built-in functions */
                        ALIGNOF             "ALIGNOF"
                        ALIGN               "ALIGN"
                        DEFINED             "DEFINED"
                        LENGTH              "LENGTH"
                        LOADADDR            "LOADADDR"
                        MAX                 "MAX"
                        ORIGIN              "ORIGIN"
                        SIZEOF              "SIZEOF"

    /* Symbolic operators */
                        ASSIGN              "="
                        BITWISE_AND         "&"
                        BITWISE_NOT         "~"
                        COLON               ":"
                        COMMA               ","
                        GE                  ">="
                        GT                  ">"
                        LBRACE              "{"
                        LE                  "<="
                        LOGICAL_NOT         "!"
                        LPAREN              "("
                        LT                  "<"
                        MINUS               "-"
                        PLUS                "+"
                        QUERY               "?"
                        RBRACE              "}"
                        RPAREN              ")"
                        SEMICOLON           ";"
                        STAR                "*"

    /* Literals */
    <IdentifierToken>   IDENTIFIER          "identifier"
    <IntegerToken>      INTEGER             "integer"
;

%type <ExpressionPtr> primary_expression
%type <ExpressionPtr> unary_expression
%type <ExpressionPtr> multiplicative_expression
%type <ExpressionPtr> additive_expression
%type <ExpressionPtr> comparison_expression
%type <ExpressionPtr> bitwise_and_expression
%type <ExpressionPtr> ternary_expression
%type <ExpressionPtr> expression
%type <MemoryAttributesRules> memory_attr
%type <MemoryAttributesRules> memory_attr_list
%type <MemoryAttributesRules> opt_memory_attrs

%%

/* Top level */

command_list:
    /* empty */
    | command_list command
    ;

command:
      entry_command
    | include_command
    | memory_command
    | sections_command
    | region_alias_command
    | symbol_assignment
    | SEMICOLON /*  */
    ;

/* Expressions */

primary_expression: /* highest priority */
      IDENTIFIER                                                { $$ = std::make_unique<SymbolExpression>($1); }
    | INTEGER                                                   { $$ = std::make_unique<IntegerExpression>($1); }
    | LPAREN expression RPAREN                                  { $$ = std::move($2); }
    | ALIGN LPAREN expression RPAREN                            { $$ = std::make_unique<UnaryExpression>($1, UnaryOperator::Align, std::move($3)); }
    | ALIGNOF LPAREN IDENTIFIER RPAREN                          { $$ = std::make_unique<SectionExpression>($1, SectionOperator::AlignOf, $3.id); }
    | DEFINED LPAREN IDENTIFIER RPAREN                          { $$ = std::make_unique<DefinedExpression>($1, $3.id); }
    | LENGTH LPAREN IDENTIFIER RPAREN                           { $$ = std::make_unique<MemoryExpression>($1, MemoryOperator::Length, $3.id); }
    | MAX LPAREN expression COMMA expression RPAREN             { $$ = std::make_unique<BinaryExpression>($1, BinaryOperator::Max, std::move($3), std::move($5)); }
    | ORIGIN LPAREN IDENTIFIER RPAREN                           { $$ = std::make_unique<MemoryExpression>($1, MemoryOperator::Origin, $3.id); }
    | SIZEOF LPAREN IDENTIFIER RPAREN                           { $$ = std::make_unique<SectionExpression>($1, SectionOperator::SizeOf, $3.id); }
    ;

unary_expression:
      primary_expression                                        { $$ = std::move($1); }
    | PLUS unary_expression                                     { $$ = std::make_unique<UnaryExpression>($1, UnaryOperator::Plus, std::move($2)); }
    | MINUS unary_expression                                    { $$ = std::make_unique<UnaryExpression>($1, UnaryOperator::Minus, std::move($2)); }
    | BITWISE_NOT unary_expression                              { $$ = std::make_unique<UnaryExpression>($1, UnaryOperator::BitwiseNot, std::move($2)); }
    | LOGICAL_NOT unary_expression                              { $$ = std::make_unique<UnaryExpression>($1, UnaryOperator::LogicalNot, std::move($2)); }
    ;

multiplicative_expression:
      unary_expression                                          { $$ = std::move($1); }
    | multiplicative_expression STAR unary_expression           { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::Multiply, std::move($1), std::move($3)); }
    ;

additive_expression:
      multiplicative_expression                                 { $$ = std::move($1); }
    | additive_expression PLUS multiplicative_expression        { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::Add, std::move($1), std::move($3)); }
    | additive_expression MINUS multiplicative_expression       { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::Subtract, std::move($1), std::move($3)); }
    ;

comparison_expression:
      additive_expression                                       { $$ = std::move($1); }
    | comparison_expression GE additive_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::GreaterOrEqual, std::move($1), std::move($3)); }
    | comparison_expression GT additive_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::Greater, std::move($1), std::move($3)); }
    | comparison_expression LE additive_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::LessOrEqual, std::move($1), std::move($3)); }
    | comparison_expression LT additive_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::Less, std::move($1), std::move($3)); }
    ;

bitwise_and_expression:
      comparison_expression                                     { $$ = std::move($1); }
    | bitwise_and_expression BITWISE_AND comparison_expression  { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::BitwiseAnd, std::move($1), std::move($3)); }
    ;

ternary_expression: /* lowest priority */
      bitwise_and_expression                                                    { $$ = std::move($1); }
    | bitwise_and_expression QUERY ternary_expression COLON ternary_expression  { $$ = std::make_unique<TernaryExpression>($2, std::move($1), std::move($3), std::move($5)); }
    ;

expression:
      ternary_expression                                        { $$ = std::move($1); }
    ;

/* Commands */

entry_command:
    ENTRY LPAREN IDENTIFIER RPAREN
    {
        std::cout << "entry command\n";
        if (g_script.entry)
            throw DiagnosticError($1, "error: redefinition of entry point", {{ g_script.entry->first, "previous definition was here" }});
        g_script.entry = {$1, $3.id};
    }
    ;

include_command:
    INCLUDE IDENTIFIER
    {
        std::cout << "include command\n";
        FileId include_file;
        try {
            include_file = g_source_manager.loadInclude(g_identifier_manager.toRaw($2.id));
        }
        catch (const std::exception& e) {
            throw DiagnosticError($1, std::string("error: ") + e.what());
        }
        lexer_push_include(include_file);
        DiagnosticError::push_include($1);
    }
    ;

memory_attr:
      IDENTIFIER
        {
            const auto& s = g_identifier_manager.toRaw($1.id);
            $$ = MemoryAttributesRules();
            for (auto c : s) {
                (g_memory_region_attribute_sense_required ? $$.required : $$.denied) |= MemoryAttributes(c);
            }
        }
    | LOGICAL_NOT
        {
            g_memory_region_attribute_sense_required = !g_memory_region_attribute_sense_required;
            $$ = MemoryAttributesRules();
        }
    ;

memory_attr_list:
    /* empty */                         { $$ = MemoryAttributesRules(); }
    | memory_attr_list memory_attr      { $$ = $1 | $2; }
    ;

opt_memory_attrs:
    /* empty */                         { $$ = MemoryAttributesRules(); }
    | LPAREN memory_attr_list RPAREN    { $$ = $2; g_memory_region_attribute_sense_required = true; }
    ;

memory_block:
      IDENTIFIER opt_memory_attrs COLON ORIGIN ASSIGN expression COMMA LENGTH ASSIGN expression
        {
            auto it = g_script.memory_region_lookup.find($1.id);
            if (it != g_script.memory_region_lookup.end()) {
                auto const& previous = it->second;
                throw DiagnosticError($1.loc, "error: redefinition of memory region or region alias", {{ previous.first, "previous definition was here" }});
            } 
            g_script.memory_region_lookup[$1.id] = { $1.loc, g_script.memory_regions.size() };
            g_script.memory_regions.emplace_back(MemoryRegion{$1.id, $2, std::move($6), std::move($10)});
            std::cout << g_script.memory_regions.back().dump();
        }
    ;

memory_item:
      memory_block
    | include_command
    ;

memory_items:
    /* empty */
    | memory_items memory_item
    ;

memory_command:
      MEMORY LBRACE memory_items RBRACE
        {
            std::cout << "memory command\n";
        }
    ;

sections_command:
    SECTIONS LBRACE input RBRACE   { std::cout << "sections command\n"; }
    ;

region_alias_command:
      REGION_ALIAS LPAREN IDENTIFIER COMMA IDENTIFIER RPAREN
        {
            std::cout << "region_alias command\n";
            auto it = g_script.memory_region_lookup.find($3.id);
            if (it != g_script.memory_region_lookup.end()) {
                auto const& previous = it->second;
                throw DiagnosticError($3.loc, "error: redefinition of memory region or region alias", {{ previous.first, "previous definition was here" }});
            } 
            it = g_script.memory_region_lookup.find($5.id);
            if (it == g_script.memory_region_lookup.end())
                throw DiagnosticError($5.loc, "error: unknown memory region");
            g_script.memory_region_lookup[$3.id] = { $3.loc, g_script.memory_region_lookup[$5.id].second };
        }
    ;

symbol_assignment:
      IDENTIFIER ASSIGN expression SEMICOLON   { std::cout << "assignment\n"; }
    ;




input:
    /* empty */
    | input token
    ;

token:
      ENTRY             { TRACE("ENTRY") }
    | INCLUDE           { TRACE("INCLUDE") }
    | MEMORY            { TRACE("MEMORY") }
    | SECTIONS          { TRACE("SECTIONS") }
    | REGION_ALIAS      { TRACE("REGION_ALIAS") }

    | ASSERT            { TRACE("ASSERT") }
    | AT                { TRACE("AT") }
    | AT_NAMED          { TRACE("AT_NAMED") }
    | EXCLUDE_FILE      { TRACE("EXCLUDE_FILE") }
    | KEEP              { TRACE("KEEP") }
    | NOLOAD            { TRACE("NOLOAD") }
    | PROVIDE_HIDDEN    { TRACE("PROVIDE_HIDDEN") }
    | PROVIDE           { TRACE("PROVIDE") }
    | SORT_BY_ALIGNMENT { TRACE("SORT_BY_ALIGNMENT") }
    | SORT_BY_NAME      { TRACE("SORT_BY_NAME") }

    | ALIGNOF           { TRACE("ALIGNOF") }
    | ALIGN             { TRACE("ALIGN") }
    | DEFINED           { TRACE("DEFINED") }
    | LENGTH            { TRACE("LENGTH") }
    | LOADADDR          { TRACE("LOADADDR") }
    | MAX               { TRACE("MAX") }
    | ORIGIN            { TRACE("ORIGIN") }
    | SIZEOF            { TRACE("SIZEOF") }

    | ASSIGN            { TRACE("ASSIGN") }
    | BITWISE_AND       { TRACE("BITWISE_AND") }
    | BITWISE_NOT       { TRACE("BITWISE_NOT") }
    | COLON             { TRACE("COLON") }
    | COMMA             { TRACE("COMMA") }
    | GE                { TRACE("GE") }
    | GT                { TRACE("GT") }
    | LBRACE            { TRACE("LBRACE") }
    | LE                { TRACE("LE") }
    | LOGICAL_NOT       { TRACE("LOGICAL_NOT") }
    | LPAREN            { TRACE("LPAREN") }
    | LT                { TRACE("LT") }
    | MINUS             { TRACE("MINUS") }
    | PLUS              { TRACE("PLUS") }
    | QUERY             { TRACE("QUERY") }
    | RBRACE            { TRACE("RBRACE") }
    | RPAREN            { TRACE("RPAREN") }
    | SEMICOLON         { TRACE("SEMICOLON") }
    | STAR              { TRACE("STAR") }

    | IDENTIFIER        { TRACE("IDENTIFIER: " << g_identifier_manager.toDisplayName($1.id)) }

    | INTEGER           { TRACE("INTEGER: " << $1.value) }
    ;

%%
/* Literal insertions into parser.cpp (near bottom) */

void yy::parser::error(const std::string& s)
{
    throw DiagnosticError(lexer_symbol_location, "error: " + s);
}
