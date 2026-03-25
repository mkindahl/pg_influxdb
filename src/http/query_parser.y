%code requires {
#include <postgres.h>

#include <commands/schemacmds.h>
#include <nodes/makefuncs.h>
#include <nodes/parsenodes.h>
typedef void *yyscan_t;
}

%code {
#include <utils/palloc.h>

#include "common/utils.h"
#include "http/query_scanner.h"

static void query_yyerror(yyscan_t scanner, Node * *tree, const char *msg);

int query_parse_string(const char *input, Node **parsetree);
}

%define api.prefix {query_yy}
%define api.pure full
%param {yyscan_t scanner}
%parse-param {Node **tree}

%union {
  char *string;
  Node *node;
}

%token  CREATE DATABASE
%token  <string> IDENTIFIER
%type   <node> statement

%%

start
  : statement { *tree = $1; }
  ;

statement
  : CREATE DATABASE IDENTIFIER {
      CreateSchemaStmt *stmt = makeNode(CreateSchemaStmt);
      stmt->schemaname = $3;
      stmt->authrole = NULL;
      stmt->schemaElts = NIL;
      stmt->if_not_exists = true;
      $$ = (Node *)stmt;
    }
  ;

%%

/* 
 * Function: query_yyerror
 * Description: Custom error handler for the query parser. It reports syntax errors
 * along with the offending text.
 */
static void query_yyerror(yyscan_t scanner, Node **tree, const char *msg) {
  (void)scanner;
  (void)tree;
  SYNTAX_ERROR("syntax error", "'%s' at '%s'", msg, query_yyget_text(scanner));
}

/*
 * Function: query_parse_string
 * Description: Parses the given input string and returns a parse tree. The caller is
 * responsible for freeing the parse tree using pfree.
 */
int query_parse_string(const char *input, Node **parsetree) {
  yyscan_t scanner;
  YY_BUFFER_STATE buf;
  int rc;

  query_yylex_init(&scanner);
  buf = query_yy_scan_string(input, scanner);
  rc = query_yyparse(scanner, parsetree);
  query_yy_delete_buffer(buf, scanner);
  query_yylex_destroy(scanner);
  return rc;
}
