--  liquid_subset-ast.ads
--
--  The tree shapes produced by Liquid_Subset.Parser and consumed by
--  the (later) renderer. Pure data: no parsing or evaluation logic
--  lives here.

with Ada.Containers.Vectors;

package Liquid_Subset.Ast is

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String);

   ------------------------------------------------------------------
   --  Expressions
   --
   --  Covers exactly what vectors-liquid.c uses: string and integer
   --  literals, dotted identifier paths, one equality comparison
   --  (used only in `if`/`unless` conditions), and filter chains
   --  (`| minus: ...`, `| slice: ...`). No booleans/`and`/`or`, no
   --  arithmetic operators, no other filters.
   ------------------------------------------------------------------

   type Expression_Kind is
     (Expr_String, Expr_Integer, Expr_Path, Expr_Equals, Expr_Filtered);

   type Expression;
   type Expression_Access is access Expression;

   package Expression_Access_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Expression_Access);

   type Expression (Kind : Expression_Kind) is record
      case Kind is
         when Expr_String =>
            Str_Value : Unbounded_String;

         when Expr_Integer =>
            Int_Value : Integer;

         when Expr_Path =>
            --  e.g. `handler.symbol.size` -> ["handler", "symbol",
            --  "size"]; a bare identifier like `isArmArch6m` is a
            --  single-segment path. Whether a given segment is a real
            --  field of the previous segment's value, or one of the
            --  two pseudo-properties (`.size`, `.last`), is decided
            --  at evaluation time, not here.
            Segments : String_Vectors.Vector;

         when Expr_Equals =>
            Left  : Expression_Access;
            Right : Expression_Access;

         when Expr_Filtered =>
            --  `<Base> | <Filter_Name>: <Args>`; a chain of filters
            --  is just nested Expr_Filtered nodes, each one's Base
            --  being the previous filter's result.
            Base        : Expression_Access;
            Filter_Name : Unbounded_String;
            Args        : Expression_Access_Vectors.Vector;
      end case;
   end record;

   ------------------------------------------------------------------
   --  Statements ("nodes")
   ------------------------------------------------------------------

   type Node_Kind is
     (Node_Text, Node_Output, Node_For, Node_If, Node_Unless, Node_Assign);

   type Node;
   type Node_Access is access Node;

   package Node_Access_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Node_Access);

   type Node (Kind : Node_Kind) is record
      case Kind is
         when Node_Text =>
            Text : Unbounded_String;

         when Node_Output =>
            Expr : Expression_Access;

         when Node_For =>
            Loop_Var   : Unbounded_String;
            Collection : Expression_Access;
            Body_Nodes : Node_Access_Vectors.Vector;

         when Node_If =>
            If_Condition : Expression_Access;
            Then_Nodes   : Node_Access_Vectors.Vector;
            Else_Nodes   : Node_Access_Vectors.Vector;  --  empty: no else

         when Node_Unless =>
            --  Deliberately no else branch: nothing in
            --  vectors-liquid.c uses `{% unless %}...{% else %}`,
            --  only `if`/`else` does. Straightforward to add an
            --  Else_Nodes field here later if a future template
            --  needs it.
            Unless_Condition : Expression_Access;
            Unless_Body      : Node_Access_Vectors.Vector;

         when Node_Assign =>
            Var_Name : Unbounded_String;
            Value    : Expression_Access;
      end case;
   end record;

end Liquid_Subset.Ast;
