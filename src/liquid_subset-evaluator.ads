--  liquid_subset-evaluator.ads
--
--  Evaluates a Liquid_Subset.Ast.Expression against two things:
--  Render_Context (Liquid_Subset), the fixed set of values supplied
--  once from outside (handlers, libraryFilePath, isArmArch6m/8m), and
--  Scope, the dynamic state that changes as the (later) renderer
--  walks the tree -- the current `for` loop's variable binding, and
--  the variables introduced so far by `{% assign %}`.
--
--  Variable/property vocabulary supported (exactly what
--  vectors-liquid.c uses): the four Render_Context fields; the
--  current loop variable (whatever name a `{% for %}` bound it to);
--  `forloop.last` (no other `forloop.*` property); `.symbol` and
--  `.comment` on a handler entry; `.size` on a string; and variables
--  set by `{% assign %}`. Filters: `minus` and `slice`, matching
--  liquidjs's own clamping behaviour (a `slice` length of zero or
--  less, or a start past the end of the string, yields "").

with Ada.Containers.Vectors;
with Liquid_Subset.Ast; use Liquid_Subset.Ast;
with Vector_Table_Parser;

package Liquid_Subset.Evaluator is

   type Value_Kind is
     (Value_Nil, Value_String, Value_Integer, Value_Boolean,
      Value_Entry, Value_Handlers);

   type Value (Kind : Value_Kind := Value_Nil) is record
      case Kind is
         when Value_Nil =>
            null;
         when Value_String =>
            Str : Unbounded_String;
         when Value_Integer =>
            Int : Integer;
         when Value_Boolean =>
            Bool : Boolean;
         when Value_Entry =>
            --  e.g. the current `for handler in handlers` iteration
            --  variable, before any further `.symbol`/`.comment`.
            Entry_Val : Vector_Table_Parser.Table_Entry;
         when Value_Handlers =>
            --  `handlers` itself, only ever used as a `for` loop's
            --  collection expression -- never dotted into further.
            Handlers_Val : Vector_Table_Parser.Entry_Vectors.Vector;
      end case;
   end record;

   package Value_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Value);

   type Named_Value is record
      Name : Unbounded_String;
      Val  : Value;
   end record;

   package Named_Value_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Named_Value);

   type Scope is record
      --  Empty Loop_Var_Name means "not currently inside a for loop".
      Loop_Var_Name  : Unbounded_String := Null_Unbounded_String;
      Loop_Var_Value : Vector_Table_Parser.Table_Entry;
      Loop_Is_Last   : Boolean := False;
      Assigned       : Named_Value_Vectors.Vector;
   end record;

   Empty_Scope : constant Scope := (others => <>);

   procedure Assign_Variable (S : in out Scope; Name : String; Val : Value);
   --  Sets Name to Val in S.Assigned, replacing any existing binding
   --  for the same name (mirrors `{% assign %}` re-running for a
   --  later loop iteration).

   Eval_Error : exception;

   function Evaluate
     (Expr    : Expression_Access;
      Context : Render_Context;
      S       : Scope) return Value;
   --  Raises Eval_Error on an unknown variable, an unsupported
   --  `.segment` access, or a filter given the wrong argument types,
   --  count, or an unsupported name.

   function Truthy (V : Value) return Boolean;
   --  Liquid truthiness: only Value_Nil and Value_Boolean(False) are
   --  falsy; everything else -- including an empty string or the
   --  integer 0 -- is truthy. Verified against liquidjs directly
   --  rather than assumed.

   function Display (V : Value) return String;
   --  Renders V the way `{{ ... }}` would. Value_Nil renders as ""
   --  (matching real Liquid). Value_Entry and Value_Handlers raise
   --  Eval_Error instead of printing something meaningless: nothing
   --  in vectors-liquid.c ever outputs a whole handler or the whole
   --  handlers list directly, so reaching this is a template bug, not
   --  a case to render silently.

end Liquid_Subset.Evaluator;
