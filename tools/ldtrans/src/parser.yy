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

#include <algorithm>
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

/* GNU ld scripts contain a handful of constructs that require decisions
 * beyond LALR(1), for example:
 *
 *     foo.o bar.o
 *     foo.o (.text)
 *     foo.o = 123;
 *
 * The GLR parser resolves these by pursuing both parses until sufficient
 * lookahead is available, while executing semantic actions only for the
 * surviving parse.
 */
%glr-parser
%skeleton "glr2.cc"

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
                        LOCATION_COUNTER    "."
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
%type <DefinitionPtr> inner_section_symbol_assignment
%type <OutputSectionItemPtr> location_counter_assignment
%type <DefinitionPtr> weak_section_symbol_assignment
%type <DefinitionPtr> section_symbol_assignment_alternatives
%type <OutputSectionItemPtr> section_symbol_assignment
%type <OutputSectionItemPtr> assert_command
%type <DefinitionPtr> output_section_vma
%type <std::pair<DefinitionPtr, bool>> output_section_header
%type <DefinitionPtr> output_section_lma
%type <DefinitionPtr> opt_output_section_lma
%type <std::pair<SourceLocation, std::string>> wildcarded_identifier_element
%type <std::pair<SourceLocation, std::string>> wildcarded_identifier
%type <FileSpec> filespec
%type <std::shared_ptr<std::vector<FileSpec>>> filespec_list
%type <std::pair<SourceLocation, std::shared_ptr<std::vector<FileSpec>>>> exclude_file_command
%type <SectionListItemPtr> inner_input_section_list_item
%type <SectionListItemPtr> self_delimiting_input_section_list_item
%type <std::shared_ptr<std::vector<SectionListItemPtr>>> input_section_list_items
%type <std::shared_ptr<std::vector<SectionListItemPtr>>> input_section_list
%type <FileFilterPtr> inner_input_file_specifier
%type <FileFilterPtr> outer_input_file_specifier
%type <InputSectionFilterPtr> inner_input_section_description
%type <InputSectionFilterPtr> outer_input_section_description
%type <OutputSectionItemPtr> self_delimiting_output_section_item
%type <std::shared_ptr<std::vector<OutputSectionItemPtr>>> output_section_items
%type <std::shared_ptr<std::vector<OutputSectionItemPtr>>> opt_output_section_items
%type <std::optional<IdentifierId>> opt_output_section_region
%type <std::optional<IdentifierId>> opt_output_section_lma_region
%type <std::optional<Fill>> opt_output_section_fill
%type <OutputSectionPtr> output_section_description
%type <DefinitionPtr> inner_top_level_symbol_assignment
%type <DefinitionPtr> weak_top_level_symbol_assignment
%type <DefinitionPtr> top_level_symbol_assignment_alternatives

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
      IDENTIFIER                                                { $$ = std::make_shared<SymbolExpression>($1); }
    | INTEGER                                                   { $$ = std::make_shared<IntegerExpression>($1); }
    | LOCATION_COUNTER                                          { $$ = std::make_shared<LocationCounterExpression>($1); }
    | LPAREN expression RPAREN                                  { $$ = $2; }
    | ALIGN LPAREN expression RPAREN                            { $$ = std::make_shared<UnaryExpression>($1, UnaryOperator::Align, $3); }
    | ALIGNOF LPAREN IDENTIFIER RPAREN                          { $$ = std::make_shared<SectionExpression>($1, SectionOperator::AlignOf, $3.id); }
    | DEFINED LPAREN IDENTIFIER RPAREN                          { $$ = std::make_shared<DefinedExpression>($1, $3.id); }
    | LENGTH LPAREN IDENTIFIER RPAREN                           { $$ = std::make_shared<MemoryExpression>($1, MemoryOperator::Length, $3.id); }
    | LOADADDR LPAREN IDENTIFIER RPAREN                         { $$ = std::make_shared<SectionExpression>($1, SectionOperator::LoadAddr, $3.id); }
    | MAX LPAREN expression COMMA expression RPAREN             { $$ = std::make_shared<BinaryExpression>($1, BinaryOperator::Max, $3, $5); }
    | ORIGIN LPAREN IDENTIFIER RPAREN                           { $$ = std::make_shared<MemoryExpression>($1, MemoryOperator::Origin, $3.id); }
    | SIZEOF LPAREN IDENTIFIER RPAREN                           { $$ = std::make_shared<SectionExpression>($1, SectionOperator::SizeOf, $3.id); }
    ;

unary_expression:
      primary_expression                                        { $$ = $1; }
    | PLUS unary_expression                                     { $$ = std::make_shared<UnaryExpression>($1, UnaryOperator::Plus, $2); }
    | MINUS unary_expression                                    { $$ = std::make_shared<UnaryExpression>($1, UnaryOperator::Minus, $2); }
    | BITWISE_NOT unary_expression                              { $$ = std::make_shared<UnaryExpression>($1, UnaryOperator::BitwiseNot, $2); }
    | LOGICAL_NOT unary_expression                              { $$ = std::make_shared<UnaryExpression>($1, UnaryOperator::LogicalNot, $2); }
    ;

multiplicative_expression:
      unary_expression                                          { $$ = $1; }
    | multiplicative_expression STAR unary_expression           { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::Multiply, $1, $3); }
    ;

additive_expression:
      multiplicative_expression                                 { $$ = $1; }
    | additive_expression PLUS multiplicative_expression        { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::Add, $1, $3); }
    | additive_expression MINUS multiplicative_expression       { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::Subtract, $1, $3); }
    ;

relational_expression:
      additive_expression                                       { $$ = $1; }
    | relational_expression GE additive_expression              { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::GreaterOrEqual, $1, $3); }
    | relational_expression GT additive_expression              { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::Greater,        $1, $3); }
    | relational_expression LE additive_expression              { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::LessOrEqual,    $1, $3); }
    | relational_expression LT additive_expression              { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::Less,           $1, $3); }
    ;

equality_expression:
      relational_expression                                     { $$ = $1; }
    | equality_expression EQ relational_expression              { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::Equal, $1, $3); }
    ;

bitwise_and_expression:
      equality_expression                                       { $$ = $1; }
    | bitwise_and_expression BITWISE_AND equality_expression    { $$ = std::make_shared<BinaryExpression>($2, BinaryOperator::BitwiseAnd, $1, $3); }
    ;

ternary_expression: /* lowest priority */
      bitwise_and_expression                                                    { $$ = $1; }
    | bitwise_and_expression QUERY ternary_expression COLON ternary_expression  { $$ = std::make_shared<TernaryExpression>($2, $1, $3, $5); }
    ;

expression:
      ternary_expression                                        { $$ = $1; }
    ;

/* Commands */

whitespace:
      WHITESPACE
    | whitespace WHITESPACE /* we can get multiple whitespace tokens separated by comments */
    ;

opt_whitespace:
      /* empty */
    | whitespace
    ;

entry_command:
    ENTRY LPAREN IDENTIFIER RPAREN
    {
        if (g_script.entry)
            throw DiagnosticError($1, "error: redefinition of entry point", {{ g_script.entry->first, "previous definition was here" }});
        g_script.entry = {$1, $3.id};
    }
    ;

include_command:
    INCLUDE opt_whitespace IDENTIFIER
    {
        FileId include_file;
        try {
            include_file = g_source_manager.loadInclude(g_script.identifiers.toRaw($3.id));
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
            g_script.memory_regions.emplace_back(MemoryRegion($1.loc, $1.id, $2, Definition($4, $1.id, $6, DefinitionKind::MemoryRegionOrigin), Definition($8, $1.id, $10, DefinitionKind::MemoryRegionLength)));
//            std::cout << g_script.memory_regions.back().dump(g_script.identifiers);
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
        }
    ;

location_counter_assignment:
      LOCATION_COUNTER opt_whitespace ASSIGN expression SEMICOLON
        {
            auto unary = std::dynamic_pointer_cast<UnaryExpression>($4);
            if (unary && unary->operation() == UnaryOperator::Align) {
                auto align = dynamic_cast<IntegerExpression*>(&unary->sub_expr());
                if (align)
                    $$ = std::make_shared<OutputSectionAlign>($1, align->value());
                else
                    throw DiagnosticError($1, "error: unsupported expression for assignment to location counter");
            } else {
                throw DiagnosticError($1, "error: unsupported expression for assignment to location counter");
            }
        }
    ;

inner_section_symbol_assignment:
      IDENTIFIER opt_whitespace ASSIGN expression
        {
            $$ = std::make_shared<Definition>($1.loc, $1.id, $4, DefinitionKind::SectionScopeSymbol);
        }
    ;

weak_section_symbol_assignment:
      PROVIDE        LPAREN inner_section_symbol_assignment RPAREN SEMICOLON
        {
            $$ = $3;
            $$->set_visibility($1, DefinitionVisibility::Provide);
        }
    | PROVIDE_HIDDEN LPAREN inner_section_symbol_assignment RPAREN SEMICOLON
        {
            $$ = $3;
            $$->set_visibility($1, DefinitionVisibility::ProvideHidden);
        }
    ;

section_symbol_assignment_alternatives:
      inner_section_symbol_assignment SEMICOLON
    | weak_section_symbol_assignment
    ;

section_symbol_assignment:
      section_symbol_assignment_alternatives
        {
            bool location_counter_used = false;
            auto index = g_script.GenerateAnchorIndex();
            for_each_location_counter($1->expression(), [index, &location_counter_used](LocationCounterExpression& expr) {
                location_counter_used = true;
                expr.set_anchor(index);
            });
            if (location_counter_used)
                $$ = std::make_shared<OutputSectionLocationMarker>($1->location(), index);
            else
                $$ = std::make_shared<OutputSectionNop>();
            auto name = *$1->name();
            auto it = g_script.symbol_lookup.find(name);
            if (it == g_script.symbol_lookup.end()) {
                g_script.symbol_lookup[name] = g_script.symbols.size();
                g_script.symbols.emplace_back(Symbol($1));
            } else
               g_script.symbols[it->second].redefine($1);
//            std::cout << g_script.symbols[g_script.symbol_lookup.find(name)->second].dump(g_script.identifiers);
        }
    ;

assert_command:
      ASSERT LPAREN expression COMMA IDENTIFIER RPAREN
        {
            bool location_counter_used = false;
            auto index = g_script.GenerateAnchorIndex();
            for_each_location_counter(*$3, [index, &location_counter_used](LocationCounterExpression& expr) {
                location_counter_used = true;
                expr.set_anchor(index);
            });
            if (location_counter_used)
                $$ = std::make_shared<OutputSectionLocationMarker>($1, index);
            else
                $$ = std::make_shared<OutputSectionNop>();
            g_script.assertions.emplace_back(Assertion{ Definition($1, std::nullopt, $3, DefinitionKind::Assertion), $5.id });
//            std::cout << "ASSERT\n";
//            std::cout << "  location: " + g_source_manager.toFileLineColumn($1) + "\n";
//            DumpVisitor expression_dump(g_script.identifiers);
//            $3->accept(expression_dump);
//            std::cout << "  expression: " + expression_dump.result() + "\n";
//            std::cout << "  message: " + g_script.identifiers.toDisplayName($5.id) + "\n";
        }
    ;

output_section_vma:
      expression                             { $$ = std::make_shared<Definition>($1->location(), std::nullopt, $1, DefinitionKind::OutputSectionVMA); }
    ;

output_section_type:
      LPAREN NOLOAD RPAREN
    ;

output_section_header:
      /* empty */                            { $$ = { nullptr, false }; }
    | output_section_type                    { $$ = { nullptr, true }; }
    | output_section_vma                     { $$ = { $1, false }; }
    | output_section_vma output_section_type { $$ = { $1, true }; }
    ;

output_section_lma:
      AT LPAREN expression RPAREN            { $$ = std::make_shared<Definition>($1, std::nullopt, $3, DefinitionKind::OutputSectionLMA); }
    ;

opt_output_section_lma:
      /* empty */                            { $$ = nullptr; }
    | output_section_lma                     { $$ = $1; }
    ;

wildcarded_identifier_element:
      IDENTIFIER                             { $$ = { $1.loc, g_script.identifiers.toRaw($1.id) }; }
    | STAR                                   { $$ = { $1, "*" }; }
    | QUERY                                  { $$ = { $1, "?" }; }
    ;

wildcarded_identifier:
      wildcarded_identifier_element                       { $$ = $1; }
    | wildcarded_identifier wildcarded_identifier_element { $$.first = $1.first; $$.second = $1.second + $2.second; }
    ;

filespec:
      wildcarded_identifier                               { $$ = { $1.first, ArchiveSpecType::Any, "", $1.second }; }
    | COLON wildcarded_identifier                         { $$ = { $1,       ArchiveSpecType::None, "", $2.second }; }
    | wildcarded_identifier COLON                         { $$ = { $1.first, ArchiveSpecType::Specified, $1.second, "" }; }
    | wildcarded_identifier COLON wildcarded_identifier   { $$ = { $1.first, ArchiveSpecType::Specified, $1.second, $3.second }; }
    ;

filespec_list:
      filespec                               { $$ = std::make_shared<std::vector<FileSpec>>(); $$->push_back($1); }
    | filespec_list whitespace filespec      { $$ = $1; $$->push_back($3); }
    ;

exclude_file_command:
      EXCLUDE_FILE opt_whitespace LPAREN opt_whitespace filespec_list opt_whitespace RPAREN  { $$ = { $1, $5 }; }
    ;

inner_input_section_list_item:
      wildcarded_identifier
        {
            $$ = std::make_shared<SectionListItem>(SectionListItem{$1.first, $1.second});
        }
    | exclude_file_command opt_whitespace wildcarded_identifier
        {
            $$ = std::make_shared<SectionListItem>(SectionListItem{$1.first, $3.second, $1.second});
        }
    ;

self_delimiting_input_section_list_item:
      SORT_BY_NAME      opt_whitespace LPAREN opt_whitespace           inner_input_section_list_item opt_whitespace RPAREN
        { $$ = $5; $$->location = $1; $$->sorts.push_back(SortType::ByName); }
    | SORT_BY_NAME      opt_whitespace LPAREN opt_whitespace self_delimiting_input_section_list_item opt_whitespace RPAREN
        { $$ = $5; $$->location = $1; $$->sorts.push_back(SortType::ByName); }
    | SORT_BY_ALIGNMENT opt_whitespace LPAREN opt_whitespace           inner_input_section_list_item opt_whitespace RPAREN
        { $$ = $5; $$->location = $1; $$->sorts.push_back(SortType::ByAlignment); }
    | SORT_BY_ALIGNMENT opt_whitespace LPAREN opt_whitespace self_delimiting_input_section_list_item opt_whitespace RPAREN
        { $$ = $5; $$->location = $1; $$->sorts.push_back(SortType::ByAlignment); }
    ;

input_section_list_items:
    /* Use left-recursion to work around bison bug, at the cost of some input compatibility */
      inner_input_section_list_item                                                   { $$ = std::make_shared<std::vector<SectionListItemPtr>>(); $$->push_back($1); }
    | input_section_list_items whitespace inner_input_section_list_item               { $$ = $1; $$->push_back($3); }
    | self_delimiting_input_section_list_item                                         { $$ = std::make_shared<std::vector<SectionListItemPtr>>(); $$->push_back($1); }
    | input_section_list_items whitespace self_delimiting_input_section_list_item     { $$ = $1; $$->push_back($3); }

//    /* Whether the delimiting whitespace is required depends on the type of
//     * the preceding item, so our hands are tied to use right-recursion */
//      inner_input_section_list_item                                                   { $$ = std::make_shared<std::vector<SectionListItemPtr>>(); $$->push_back($1); }
//    | inner_input_section_list_item whitespace input_section_list_items               { $$ = $3; $$->push_back($1); }
//    | self_delimiting_input_section_list_item                                         { $$ = std::make_shared<std::vector<SectionListItemPtr>>(); $$->push_back($1); }
//    | self_delimiting_input_section_list_item opt_whitespace input_section_list_items { $$ = $3; $$->push_back($1); }
    ;

input_section_list:
      LPAREN opt_whitespace input_section_list_items opt_whitespace RPAREN
        {
            $$ = $3;
//            /* Now undo the effect of the right-recursion */
//            std::reverse($$->begin(), $$->end());
        }
    ;

inner_input_file_specifier:
      filespec                                     { $$ = std::make_shared<FileFilter>(FileFilter{$1.location, $1}); }
    | exclude_file_command opt_whitespace filespec { $$ = std::make_shared<FileFilter>(FileFilter{$1.first, $3, std::move(*$1.second)}); }
    ;

outer_input_file_specifier:
      inner_input_file_specifier                                                                         { $$ = $1; }
    | SORT_BY_NAME opt_whitespace LPAREN opt_whitespace inner_input_file_specifier opt_whitespace RPAREN { $$ = $5; $$->location = $1; $$->sorted_by_name = true; }

inner_input_section_description:
      outer_input_file_specifier opt_whitespace input_section_list { $$ = std::make_shared<InputSectionFilter>(InputSectionFilter{$1->location, std::move(*$1), $3}); }
    ;

outer_input_section_description:
      inner_input_section_description                                                                 { $$ = $1; }
    | KEEP opt_whitespace LPAREN opt_whitespace inner_input_section_description opt_whitespace RPAREN { $$ = $5; $$->location = $1; $$->keep = true; }
    ;

self_delimiting_output_section_item:
      location_counter_assignment                                                                 { $$ = $1; }
    | section_symbol_assignment                                                                   { $$ = $1; }
    | assert_command SEMICOLON /* yes, trailing semicolon required here unlike in other places */ { $$ = $1; }
    | outer_input_section_description                                                             { $$ = std::make_shared<OutputSectionInputSectionDescription>($1); }
    | include_command                                                                             { $$ = std::make_shared<OutputSectionNop>(); }
    | SEMICOLON                                                                                   { $$ = std::make_shared<OutputSectionNop>(); }
    ;

output_section_items:
    /* Use left-recursion to work around bison bug, at the cost of some input compatibility */
      filespec
        {
            $$ = std::make_shared<std::vector<OutputSectionItemPtr>>();
            $$->push_back(std::make_shared<OutputSectionInputSectionDescription>(std::make_shared<InputSectionFilter>(InputSectionFilter{ $1.location, /*FileFilter*/ { $1.location, /*FileSpec*/ $1 } })));
        }
    | output_section_items whitespace filespec
        {
            $$ = $1;
            $$->push_back(std::make_shared<OutputSectionInputSectionDescription>(std::make_shared<InputSectionFilter>(InputSectionFilter{ $3.location, /*FileFilter*/ { $3.location, /*FileSpec*/ $3 } })));
        }
    | self_delimiting_output_section_item
        {
            $$ = std::make_shared<std::vector<OutputSectionItemPtr>>();
            $$->push_back($1);
        }
    | output_section_items whitespace self_delimiting_output_section_item
        {
            $$ = $1;
            $$->push_back($3);
        }

//    /* Whether the delimiting whitespace is required depends on the type of
//     * the preceding item, so our hands are tied to use right-recursion */
//      filespec
//        {
//            $$ = std::make_shared<std::vector<OutputSectionItemPtr>>();
//            $$->push_back(std::make_shared<OutputSectionInputSectionDescription>(std::make_shared<InputSectionFilter>(InputSectionFilter{ $1.location, /*FileFilter*/ { $1.location, /*FileSpec*/ $1 } })));
//        }
//    | filespec whitespace output_section_items
//        {
//            $$ = $3;
//            $$->push_back(std::make_shared<OutputSectionInputSectionDescription>(std::make_shared<InputSectionFilter>(InputSectionFilter{ $1.location, /*FileFilter*/ { $1.location, /*FileSpec*/ $1 } })));
//        }
//    | self_delimiting_output_section_item
//        {
//            $$ = std::make_shared<std::vector<OutputSectionItemPtr>>();
//            $$->push_back($1);
//        }
//    | self_delimiting_output_section_item opt_whitespace output_section_items
//        {
//            $$ = $3;
//            $$->push_back($1);
//        }
    ;

opt_output_section_items:
      opt_whitespace
        {
            $$ = std::make_shared<std::vector<OutputSectionItemPtr>>();
        }
    | opt_whitespace output_section_items opt_whitespace
        {
            $$ = $2;
//            /* Now undo the effect of the right-recursion */
//            std::reverse($$->begin(), $$->end());
        }
    ;

opt_output_section_region:
      /* empty */   { $$.reset(); }
    | GT IDENTIFIER { $$ = $2.id; }
    ;

opt_output_section_lma_region:
      /* empty */      { $$.reset(); }
    | AT GT IDENTIFIER { $$ = $3.id; }
    ;

opt_output_section_fill:
      /* empty */
        {
            $$.reset();
        }
    | ASSIGN expression
        {
            auto integer = std::dynamic_pointer_cast<IntegerExpression>($2);
            if (integer)
                $$ = Fill{integer->value()};
            else
                throw DiagnosticError($2->location(), "error: unsupported expression for assignment to fill value");
        }
    ;

output_section_description:
      IDENTIFIER output_section_header COLON opt_output_section_lma LBRACE opt_output_section_items RBRACE opt_output_section_region opt_output_section_lma_region opt_output_section_fill
        {
            if ($2.first)
                $2.first->set_name($1.id);
            if ($4)
                $4->set_name($1.id);
            $$ = std::make_shared<OutputSection>(OutputSection{ $1.loc, $1.id, $2.second, $2.first, $4, $8, $9, $10, $6 });
        }

sections_item:
      location_counter_assignment
       {
           Diagnostic warning(*$1->location(), "warning: assignment to location counter outside output section description doesn't reserve space");
           std::cerr << warning.format();
       }
    | section_symbol_assignment
      {
          if (std::dynamic_pointer_cast<OutputSectionLocationMarker>($1))
              throw DiagnosticError(*$1->location(), "error: assignment from location counter outside section description is not supported");
      }
    | assert_command
      {
          if (std::dynamic_pointer_cast<OutputSectionLocationMarker>($1))
              throw DiagnosticError(*$1->location(), "error: assertion expression involving location counter outside section description is not supported");
      }
    | output_section_description
        {
            for (const auto& other : g_script.output_sections) {
                if (other->name == $1->name) {
                    Diagnostic warning($1->location, "warning: output section is defined more than once", {{ other->location, "first definition is here" }});
                    std::cerr << warning.format();
                    break;
                }
            }
            g_script.output_sections.push_back($1);
//            std::cout << $1->dump(g_script.identifiers);
        }
    /* unlike top-level commands or within output section descriptions, stray semicolons are not accepted here */
    ;

sections_items:
    /* empty */
    | sections_items sections_item
    ;

sections_command:
      SECTIONS LBRACE sections_items RBRACE
        {
        }
    ;

region_alias_command:
      REGION_ALIAS LPAREN IDENTIFIER COMMA IDENTIFIER RPAREN
        {
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
            $$ = std::make_shared<Definition>($1.loc, $1.id, $3, DefinitionKind::TopLevelSymbol);
        }
    ;

weak_top_level_symbol_assignment:
      PROVIDE        LPAREN inner_top_level_symbol_assignment RPAREN SEMICOLON
        {
            $$ = $3;
            $$->set_visibility($1, DefinitionVisibility::Provide);
        }
    | PROVIDE_HIDDEN LPAREN inner_top_level_symbol_assignment RPAREN SEMICOLON
        {
            $$ = $3;
            $$->set_visibility($1, DefinitionVisibility::ProvideHidden);
        }
    ;

top_level_symbol_assignment_alternatives:
      inner_top_level_symbol_assignment SEMICOLON
    | weak_top_level_symbol_assignment
    ;

top_level_symbol_assignment:
      top_level_symbol_assignment_alternatives
        {
            auto name = *$1->name();
            for_each_location_counter($1->expression(), [](LocationCounterExpression& expr) {
                throw DiagnosticError(expr.location(), "error: assignment from location counter outside section description is not supported");
            });
            auto it = g_script.symbol_lookup.find(name);
            if (it == g_script.symbol_lookup.end()) {
                g_script.symbol_lookup[name] = g_script.symbols.size();
                g_script.symbols.emplace_back(Symbol($1));
            } else
               g_script.symbols[it->second].redefine($1);
//            std::cout << g_script.symbols[g_script.symbol_lookup.find(name)->second].dump(g_script.identifiers);
        }
    ;

%%
/* Literal insertions into parser.cpp (near bottom) */

void yy::parser::error(const std::string& s)
{
    throw DiagnosticError(lexer_symbol_location, "error: " + s);
}
