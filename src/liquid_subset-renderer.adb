with Liquid_Subset.Evaluator; use Liquid_Subset.Evaluator;

package body Liquid_Subset.Renderer is

   use Liquid_Subset.Ast;

   procedure Render_Nodes
     (Nodes   : Node_Access_Vectors.Vector;
      Context : Render_Context;
      S       : in out Scope;
      Output  : in out Unbounded_String)
   is
   begin
      for N of Nodes loop
         case N.Kind is

            when Node_Text =>
               Append (Output, N.Text);

            when Node_Output =>
               Append (Output, Display (Evaluate (N.Expr, Context, S)));

            when Node_For =>
               declare
                  Collection  : constant Value :=
                    Evaluate (N.Collection, Context, S);
                  Saved_Name  : constant Unbounded_String :=
                    S.Loop_Var_Name;
                  Saved_Value : constant Vector_Table_Parser.Table_Entry :=
                    S.Loop_Var_Value;
                  Saved_Last  : constant Boolean := S.Loop_Is_Last;
               begin
                  if Collection.Kind /= Value_Handlers then
                     raise Render_Error
                       with "{% for %} collection did not evaluate to "
                         & "a list of handlers";
                  end if;

                  for I in Collection.Handlers_Val.First_Index
                             .. Collection.Handlers_Val.Last_Index
                  loop
                     S.Loop_Var_Name  := N.Loop_Var;
                     S.Loop_Var_Value := Collection.Handlers_Val (I);
                     S.Loop_Is_Last   :=
                       I = Collection.Handlers_Val.Last_Index;
                     Render_Nodes (N.Body_Nodes, Context, S, Output);
                  end loop;

                  --  Restore whatever loop binding (if any) was active
                  --  before this loop, so a construct that follows at
                  --  the same nesting level never sees a stale one.
                  --  vectors-liquid.c never nests loops, so this isn't
                  --  exercised by the real template -- it's here for
                  --  general correctness, not because it's needed.
                  S.Loop_Var_Name  := Saved_Name;
                  S.Loop_Var_Value := Saved_Value;
                  S.Loop_Is_Last   := Saved_Last;
               end;

            when Node_If =>
               if Truthy (Evaluate (N.If_Condition, Context, S)) then
                  Render_Nodes (N.Then_Nodes, Context, S, Output);
               else
                  Render_Nodes (N.Else_Nodes, Context, S, Output);
               end if;

            when Node_Unless =>
               if not Truthy (Evaluate (N.Unless_Condition, Context, S))
               then
                  Render_Nodes (N.Unless_Body, Context, S, Output);
               end if;

            when Node_Assign =>
               Assign_Variable
                 (S, To_String (N.Var_Name),
                  Evaluate (N.Value, Context, S));
         end case;
      end loop;
   end Render_Nodes;

   function Render
     (Nodes : Node_Access_Vectors.Vector; Context : Render_Context)
      return String
   is
      S      : Scope := Empty_Scope;
      Output : Unbounded_String := Null_Unbounded_String;
   begin
      Render_Nodes (Nodes, Context, S, Output);
      return To_String (Output);
   end Render;

end Liquid_Subset.Renderer;
