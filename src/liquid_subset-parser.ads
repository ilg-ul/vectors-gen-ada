--  liquid_subset-parser.ads
--
--  Builds the statement tree (Liquid_Subset.Ast.Node_Access_Vectors)
--  from the token stream produced by Liquid_Subset.Lexer, and the
--  expression tree (Liquid_Subset.Ast.Expression_Access) from the raw
--  content of a single output (`{{ ... }}`) or tag (`{% ... %}`)
--  token.
--
--  Tag vocabulary supported (exactly what vectors-liquid.c uses):
--  `for <var> in <path>` / `endfor`; `if <expr>` / `else` / `endif`;
--  `unless <expr>` / `endunless` (no `else`, see Liquid_Subset.Ast);
--  `assign <name> = <expr>`.
--
--  Expression grammar supported (see Liquid_Subset.Ast for why this
--  is enough):
--    expression   ::= filtered [ "==" filtered ]
--    filtered     ::= term ( "|" IDENT ":" arglist )*
--    arglist      ::= term ( "," term )*
--    term         ::= STRING | INTEGER | path
--    path         ::= IDENT ( "." IDENT )*

with Liquid_Subset.Ast;
with Liquid_Subset.Lexer;

package Liquid_Subset.Parser is

   Parse_Error : exception;

   function Parse
     (Tokens : Liquid_Subset.Lexer.Token_Vectors.Vector)
      return Liquid_Subset.Ast.Node_Access_Vectors.Vector;
   --  Raises Parse_Error on any unmatched/mismatched tag (e.g. a
   --  `{% for %}` closed by `{% endif %}`, or an `{% else %}` with no
   --  enclosing `if`), an unrecognised tag keyword, or a malformed
   --  expression.

   function Parse_Expression
     (Raw : String) return Liquid_Subset.Ast.Expression_Access;
   --  Exposed mainly so the expression grammar can be unit-tested in
   --  isolation from full tag/statement parsing. Raises Parse_Error on
   --  malformed input or unexpected trailing content.

end Liquid_Subset.Parser;
