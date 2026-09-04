--  liquid_subset-lexer.ads
--
--  Splits a Liquid template into a flat sequence of literal-text,
--  output (`{{ ... }}`), and tag (`{% ... %}`) tokens, applying
--  Liquid's `-` whitespace-control trimming (`{%-`, `-%}`, `{{-`,
--  `-}}`) exactly as liquidjs does: each `-` strips *all* contiguous
--  whitespace (spaces, tabs, newlines, carriage returns, form feeds,
--  vertical tabs) immediately adjacent to it in the surrounding
--  literal text -- not just up to the next line break.
--
--  Interior whitespace immediately inside the delimiters (e.g. the
--  padding in `{{ handler.symbol }}`) is left untouched here: ignoring
--  it is the expression/tag parser's job (see Liquid_Subset.Parser,
--  a later milestone), not the lexer's.
--
--  This is a deliberately narrow lexer, scoped to exactly what
--  vectors-liquid.c uses: it has no notion of quoted strings, so a
--  literal `%}` or `}}` inside a string literal inside a tag would be
--  (mis)treated as that tag's closing delimiter. That case does not
--  occur in the template this tool renders.

with Ada.Containers.Vectors;

package Liquid_Subset.Lexer is

   type Token_Kind is (Text_Token, Output_Token, Tag_Token);

   type Token (Kind : Token_Kind := Text_Token) is record
      case Kind is
         when Text_Token =>
            Text : Unbounded_String;
         when Output_Token | Tag_Token =>
            --  Raw content between the delimiters, with the `-`
            --  whitespace-control markers (if any) already consumed.
            --  Whitespace immediately inside the delimiters (e.g. the
            --  leading/trailing space in `{{ x }}`) is preserved as-is.
            Source : Unbounded_String;
      end case;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Token);

   Lex_Error : exception;

   function Tokenize (Template : String) return Token_Vectors.Vector;
   --  Raises Lex_Error if a `{{` or `{%` is opened but never closed.

end Liquid_Subset.Lexer;
