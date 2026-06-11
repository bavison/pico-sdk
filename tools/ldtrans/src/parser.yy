/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/* Literal insertions into parser.hpp (near top) */
%code requires {

#include <cstdint>

#include "Identifier.h"
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
#include "lexer.h"
#include "main.h"

#define TRACE(msg) std::cout << "Consumed " << msg << std::endl;
//#define TRACE(msg)

%}

/* Track lines and columns (Bison machinery) */
/*%locations*/

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
                        LPAREN              "("
                        LT                  "<"
                        MINUS               "-"
                        NEWLINE             "newline"
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




/* Textual operators */
/*
 TOK_AT_GT
 TOK_ALIGN
 TOK_ORIGIN
 TOK_LENGTH
 TOK_LOADADDR
 TOK_SIZEOF

 TOK_PLUS
 TOK_MINUS
 TOK_STAR
 TOK_SLASH
 TOK_GT
 TOK_LT

 TOK_DOT
*/

/* Punctuation */
/*
 TOK_LPAREN
 TOK_RPAREN
 TOK_LBRACE
 TOK_RBRACE
 TOK_COLON
 TOK_SEMICOLON
 TOK_COMMA
*/

%%

input:
    /* empty */
    | input token
    ;

token:
      ENTRY             { TRACE("ENTRY") }
    | INCLUDE           { TRACE("INCLUDE") }
    | MEMORY            { TRACE("MEMORY") }
    | SECTIONS          { TRACE("SECTIONS") }

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

    | ASSIGN            { TRACE("ASSIGN") }
    | BITWISE_AND       { TRACE("BITWISE_AND") }
    | BITWISE_NOT       { TRACE("BITWISE_NOT") }
    | COLON             { TRACE("COLON") }
    | COMMA             { TRACE("COMMA") }
    | GE                { TRACE("GE") }
    | GT                { TRACE("GT") }
    | LBRACE            { TRACE("LBRACE") }
    | LE                { TRACE("LE") }
    | LPAREN            { TRACE("LPAREN") }
    | LT                { TRACE("LT") }
    | MINUS             { TRACE("MINUS") }
    | NEWLINE           { TRACE("NEWLINE") }
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
    throw DiagnosticError(lexer_symbol_location, s);
}
