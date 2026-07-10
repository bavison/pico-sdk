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

#include "Definition.h"
#include "Expression.h"
#include "Identifier.h"
#include "lexer.h"
#include "main.h"
#include "MemoryRegion.h"
#include "Script.h"
#include "SourceLocation.h"
#include "Symbol.h"

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
                        EQ                  "=="
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
                        WHITESPACE          "whitespace"

    /* Literals */
    <IdentifierToken>   IDENTIFIER          "identifier"
    <IntegerToken>      INTEGER             "integer"
;

%type <ExpressionPtr> primary_expression
%type <ExpressionPtr> unary_expression
%type <ExpressionPtr> multiplicative_expression
%type <ExpressionPtr> additive_expression
%type <ExpressionPtr> relational_expression
%type <ExpressionPtr> equality_expression
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
    | top_level_symbol_assignment
    | SEMICOLON /* arbitrary extra semicolons allowed at top level */
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

relational_expression:
      additive_expression                                       { $$ = std::move($1); }
    | relational_expression GE additive_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::GreaterOrEqual, std::move($1), std::move($3)); }
    | relational_expression GT additive_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::Greater, std::move($1), std::move($3)); }
    | relational_expression LE additive_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::LessOrEqual, std::move($1), std::move($3)); }
    | relational_expression LT additive_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::Less, std::move($1), std::move($3)); }
    ;

equality_expression:
      relational_expression                                     { $$ = std::move($1); }
    | equality_expression EQ relational_expression              { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::Equal, std::move($1), std::move($3)); }
    ;

bitwise_and_expression:
      equality_expression                                       { $$ = std::move($1); }
    | bitwise_and_expression BITWISE_AND equality_expression    { $$ = std::make_unique<BinaryExpression>($2, BinaryOperator::BitwiseAnd, std::move($1), std::move($3)); }
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
            include_file = g_source_manager.loadInclude(g_script.identifiers.toRaw($2.id));
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
            const auto& s = g_script.identifiers.toRaw($1.id);
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
                throw DiagnosticError($1.loc, "error: redefinition of memory region or region alias", {{ g_script.memory_regions[previous].location(), "previous definition was here" }});
            } 
            g_script.memory_region_lookup[$1.id] = g_script.memory_regions.size();
            g_script.memory_regions.emplace_back(MemoryRegion($1.loc, $1.id, $2, Definition($4, $1.id, std::move($6), DefinitionKind::MemoryRegionOrigin), Definition($8, $1.id, std::move($10), DefinitionKind::MemoryRegionLength)));
            std::cout << g_script.memory_regions.back().dump(g_script.identifiers);
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

inner_section_symbol_assignment:
      IDENTIFIER opt_whitespace ASSIGN expression
        {
            std::cout << "assignment\n";
            Definition definition($1.loc, $1.id, std::move($4), DefinitionKind::SectionScopeSymbol);
            auto it = g_script.symbol_lookup.find($1.id);
            if (it == g_script.symbol_lookup.end()) {
                g_script.symbol_lookup[$1.id] = g_script.symbols.size();
                g_script.symbols.emplace_back(Symbol(definition));
            } else
               g_script.symbols[it->second].redefine(definition);
            std::cout << g_script.symbols[g_script.symbol_lookup.find($1.id)->second].dump(g_script.identifiers);
        }
    ;

weak_section_symbol_assignment:
      PROVIDE        LPAREN inner_section_symbol_assignment RPAREN SEMICOLON
    | PROVIDE_HIDDEN LPAREN inner_section_symbol_assignment RPAREN SEMICOLON
        {
        }
    ;

section_symbol_assignment:
      inner_section_symbol_assignment SEMICOLON
    | weak_section_symbol_assignment
    ;

assert_command:
      ASSERT LPAREN expression COMMA IDENTIFIER
        {
        }
    ;

opt_output_section_type:
      /* empty */
    | LPAREN NOLOAD RPAREN
    ;

opt_whitespace:
      /* empty */
    | WHITESPACE
    ;

wildcarded_identifier_element:
      IDENTIFIER
    | STAR
    | QUERY
    ;

wildcarded_identifier:
      wildcarded_identifier_element
    | wildcarded_identifier wildcarded_identifier_element
    ;

filespec:
      wildcarded_identifier
    | COLON wildcarded_identifier
    | wildcarded_identifier COLON
    | wildcarded_identifier COLON wildcarded_identifier
    ;

filespec_list:
      filespec
    | filespec_list WHITESPACE filespec
    ;

exclude_file_command:
      EXCLUDE_FILE opt_whitespace LPAREN opt_whitespace filespec_list opt_whitespace RPAREN
    ;

inner_input_section_list_item:
      wildcarded_identifier
    | exclude_file_command opt_whitespace wildcarded_identifier
    ;

middle_input_section_list_item:
      inner_input_section_list_item
    | SORT_BY_NAME      opt_whitespace LPAREN opt_whitespace inner_input_section_list_item opt_whitespace RPAREN
    | SORT_BY_ALIGNMENT opt_whitespace LPAREN opt_whitespace inner_input_section_list_item opt_whitespace RPAREN
    ;

outer_input_section_list_item:
      middle_input_section_list_item
    | SORT_BY_NAME      opt_whitespace LPAREN opt_whitespace middle_input_section_list_item opt_whitespace RPAREN
    | SORT_BY_ALIGNMENT opt_whitespace LPAREN opt_whitespace middle_input_section_list_item opt_whitespace RPAREN
    ;

input_section_list_items:
    /* Whether the delimiting whitespace is required depends on the type of
     * the preceding item, so our hands are tied to use right-recursion */
      inner_input_section_list_item
    | inner_input_section_list_item WHITESPACE input_section_list_items
    | outer_input_section_list_item
    | outer_input_section_list_item opt_whitespace input_section_list_items
    ;

input_section_list:
      LPAREN opt_whitespace input_section_list_items opt_whitespace RPAREN
    ;

inner_input_file_specifier:
      wildcarded_identifier
    | exclude_file_command opt_whitespace wildcarded_identifier
    ;

outer_input_file_specifier:
      inner_input_file_specifier
    | SORT_BY_NAME opt_whitespace LPAREN opt_whitespace inner_input_file_specifier opt_whitespace RPAREN

inner_input_section_description:
      outer_input_file_specifier opt_whitespace input_section_list
    ;

outer_input_section_description:
      inner_input_section_description
    | KEEP opt_whitespace LPAREN opt_whitespace inner_input_section_description opt_whitespace RPAREN
    ;

self_delimiting_output_section_item:
      section_symbol_assignment
    | assert_command SEMICOLON /* yes, trailing semicolon required here unlike in other places */
    | outer_input_section_description
    | SEMICOLON
    ;

output_section_items:
    /* Whether the delimiting whitespace is required depends on the type of
     * the preceding item, so our hands are tied to use right-recursion */
      /* empty */
    | filespec
    | filespec WHITESPACE output_section_items
    | self_delimiting_output_section_item
    | self_delimiting_output_section_item opt_whitespace output_section_items
    ;

opt_output_section_region:
      /* empty */
    | GT IDENTIFIER
    ;

opt_output_section_lma_region:
      /* empty */
    | AT GT IDENTIFIER
    ;

output_section_description:
      IDENTIFIER opt_output_section_type COLON LBRACE opt_whitespace output_section_items opt_whitespace RBRACE opt_output_section_region opt_output_section_lma_region

sections_item:
      section_symbol_assignment
    | assert_command
    | output_section_description
    /* unlike top-level commands or within output section descriptions, stray semicolons are not accepted here */
    ;

sections_items:
    /* empty */
    | sections_items sections_item
    ;

sections_command:
      SECTIONS LBRACE sections_items RBRACE
        {
          std::cout << "sections command\n";
        }
    ;

region_alias_command:
      REGION_ALIAS LPAREN IDENTIFIER COMMA IDENTIFIER RPAREN
        {
            std::cout << "region_alias command\n";
            auto it = g_script.memory_region_lookup.find($3.id);
            if (it != g_script.memory_region_lookup.end()) {
                auto const& previous = it->second;
                throw DiagnosticError($3.loc, "error: redefinition of memory region or region alias", {{ g_script.memory_regions[previous].location(), "previous definition was here" }});
            } 
            it = g_script.memory_region_lookup.find($5.id);
            if (it == g_script.memory_region_lookup.end())
                throw DiagnosticError($5.loc, "error: unknown memory region");
            g_script.memory_region_lookup[$3.id] = g_script.memory_region_lookup[$5.id];
        }
    ;

inner_top_level_symbol_assignment:
      IDENTIFIER ASSIGN expression
        {
            std::cout << "assignment\n";
            Definition definition($1.loc, $1.id, std::move($3), DefinitionKind::TopLevelSymbol);
            auto it = g_script.symbol_lookup.find($1.id);
            if (it == g_script.symbol_lookup.end()) {
                g_script.symbol_lookup[$1.id] = g_script.symbols.size();
                g_script.symbols.emplace_back(Symbol(definition));
            } else
               g_script.symbols[it->second].redefine(definition);
            std::cout << g_script.symbols[g_script.symbol_lookup.find($1.id)->second].dump(g_script.identifiers);
        }
    ;

weak_top_level_symbol_assignment:
      PROVIDE        LPAREN inner_top_level_symbol_assignment RPAREN SEMICOLON
    | PROVIDE_HIDDEN LPAREN inner_top_level_symbol_assignment RPAREN SEMICOLON
        {
        }
    ;

top_level_symbol_assignment:
      inner_top_level_symbol_assignment SEMICOLON
    | weak_top_level_symbol_assignment
    ;

%%
/* Literal insertions into parser.cpp (near bottom) */

void yy::parser::error(const std::string& s)
{
    throw DiagnosticError(lexer_symbol_location, "error: " + s);
}
