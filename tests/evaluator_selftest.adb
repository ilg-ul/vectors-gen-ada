--  evaluator_selftest.adb
--
--  Exercises Liquid_Subset.Evaluator: Truthy and Display in
--  isolation, then Render_Context/Scope variable resolution
--  (including loop variables, `forloop.last`, and `{% assign %}`
--  variables), equality, and both filters (`minus`, `slice`) --
--  including the slice edge cases already checked directly against
--  liquidjs (zero/negative length, start past the end of the
--  string).

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Containers; use Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Liquid_Subset;          use Liquid_Subset;
with Liquid_Subset.Ast;      use Liquid_Subset.Ast;
with Liquid_Subset.Evaluator; use Liquid_Subset.Evaluator;
with Liquid_Subset.Parser;
with Vector_Table_Parser;

procedure Evaluator_Selftest is
   use Ada.Text_IO;
   package Par renames Liquid_Subset.Parser;
   package VTP renames Vector_Table_Parser;

   Failures : Natural := 0;

   procedure Check (Name : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("  PASS  " & Name);
      else
         Put_Line ("  FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   --  A minimal Render_Context / Scope shared by several cases below.
   Ctx : Render_Context;
   Sc  : Scope := Empty_Scope;

   function Eval (Source : String) return Value is
     (Evaluate (Par.Parse_Expression (Source), Ctx, Sc));

   ------------------------------------------------------------------
   --  Truthy / Display, in isolation
   ------------------------------------------------------------------

   procedure Test_Truthy is
   begin
      Check ("truthy: nil is falsy",
             not Truthy ((Kind => Value_Nil)));
      Check ("truthy: false is falsy",
             not Truthy ((Kind => Value_Boolean, Bool => False)));
      Check ("truthy: true is truthy",
             Truthy ((Kind => Value_Boolean, Bool => True)));
      Check ("truthy: empty string is truthy (checked against "
             & "liquidjs, not assumed)",
             Truthy ((Kind => Value_String,
                      Str  => Null_Unbounded_String)));
      Check ("truthy: integer 0 is truthy (checked against liquidjs)",
             Truthy ((Kind => Value_Integer, Int => 0)));
   end Test_Truthy;

   procedure Test_Display is
   begin
      Check ("display: nil -> """"", Display ((Kind => Value_Nil)) = "");
      Check ("display: string",
             Display ((Kind => Value_String,
                        Str  => To_Unbounded_String ("abc"))) = "abc");
      Check ("display: positive integer, no stray leading space",
             Display ((Kind => Value_Integer, Int => 5)) = "5");
      Check ("display: negative integer",
             Display ((Kind => Value_Integer, Int => -3)) = "-3");
      Check ("display: boolean true",
             Display ((Kind => Value_Boolean, Bool => True)) = "true");
   end Test_Display;

   procedure Test_Display_Entry_Raises is
      Dummy : VTP.Table_Entry;
   begin
      declare
         S : constant String :=
           Display ((Kind => Value_Entry, Entry_Val => Dummy));
      begin
         Check ("display: Value_Entry raises Eval_Error",
                S = "" and then False);  --  unreachable
      end;
   exception
      when Eval_Error =>
         Check ("display: Value_Entry raises Eval_Error", True);
   end Test_Display_Entry_Raises;

   ------------------------------------------------------------------
   --  Render_Context field resolution
   ------------------------------------------------------------------

   procedure Test_Context_Fields is
      E1 : VTP.Table_Entry;
      E2 : VTP.Table_Entry;
      V  : Value;
   begin
      E1.Symbol := To_Unbounded_String ("FOO_Handler");
      E2.Symbol := To_Unbounded_String ("BAR_Handler");
      Ctx.Handlers.Append (E1);
      Ctx.Handlers.Append (E2);
      Ctx.Library_File_Path := To_Unbounded_String ("startup_foo.s");
      Ctx.Is_Arm_Arch_6m := False;
      Ctx.Is_Arm_Arch_8m := True;

      V := Eval ("libraryFilePath");
      Check ("context: libraryFilePath",
             V.Kind = Value_String and then To_String (V.Str)
                                              = "startup_foo.s");

      V := Eval ("isArmArch6m");
      Check ("context: isArmArch6m", V.Kind = Value_Boolean
             and then V.Bool = False);

      V := Eval ("isArmArch8m");
      Check ("context: isArmArch8m", V.Kind = Value_Boolean
             and then V.Bool = True);

      V := Eval ("handlers");
      Check ("context: handlers -> Value_Handlers, length 2",
             V.Kind = Value_Handlers and then V.Handlers_Val.Length = 2);
   end Test_Context_Fields;

   ------------------------------------------------------------------
   --  Loop-variable / forloop.last / handler field resolution
   ------------------------------------------------------------------

   procedure Test_Loop_Variable is
      E    : VTP.Table_Entry;
      V    : Value;
   begin
      E.Symbol := To_Unbounded_String ("WWDG_IRQHandler");
      E.Has_Comment := False;
      Sc.Loop_Var_Name := To_Unbounded_String ("handler");
      Sc.Loop_Var_Value := E;
      Sc.Loop_Is_Last := False;

      V := Eval ("handler.symbol");
      Check ("loop var: handler.symbol",
             V.Kind = Value_String
             and then To_String (V.Str) = "WWDG_IRQHandler");

      V := Eval ("handler.symbol.size");
      Check ("loop var: handler.symbol.size",
             V.Kind = Value_Integer and then V.Int = 15);

      V := Eval ("handler.comment");
      Check ("loop var: handler.comment with Has_Comment=False -> nil",
             V.Kind = Value_Nil);

      E.Has_Comment := True;
      E.Comment := To_Unbounded_String ("a comment");
      Sc.Loop_Var_Value := E;
      V := Eval ("handler.comment");
      Check ("loop var: handler.comment with Has_Comment=True",
             V.Kind = Value_String and then To_String (V.Str)
                                              = "a comment");

      Sc.Loop_Is_Last := False;
      V := Eval ("forloop.last");
      Check ("loop var: forloop.last = False",
             V.Kind = Value_Boolean and then V.Bool = False);

      Sc.Loop_Is_Last := True;
      V := Eval ("forloop.last");
      Check ("loop var: forloop.last = True",
             V.Kind = Value_Boolean and then V.Bool = True);
   end Test_Loop_Variable;

   procedure Test_Equality is
      V : Value;
   begin
      V := Eval ("handler.symbol == ""WWDG_IRQHandler""");
      Check ("equality: matching -> True",
             V.Kind = Value_Boolean and then V.Bool = True);

      V := Eval ("handler.symbol == ""0""");
      Check ("equality: non-matching -> False",
             V.Kind = Value_Boolean and then V.Bool = False);
   end Test_Equality;

   ------------------------------------------------------------------
   --  {% assign %} variable resolution
   ------------------------------------------------------------------

   procedure Test_Assigned_Variable is
      V : Value;
   begin
      Assign_Variable (Sc, "commaLength", (Kind => Value_Integer, Int => 1));
      V := Eval ("commaLength");
      Check ("assigned: first value", V.Kind = Value_Integer
             and then V.Int = 1);

      --  A later loop iteration re-running the same {% assign %}
      --  must replace, not duplicate, the binding.
      Assign_Variable (Sc, "commaLength", (Kind => Value_Integer, Int => 0));
      V := Eval ("commaLength");
      Check ("assigned: re-assignment replaces, doesn't duplicate",
             V.Kind = Value_Integer and then V.Int = 0);
   end Test_Assigned_Variable;

   ------------------------------------------------------------------
   --  Filters
   ------------------------------------------------------------------

   procedure Test_Minus_Filter is
      V : constant Value := Eval ("39 | minus: 15 | minus: 1 | minus: 4");
   begin
      Check ("minus: chained subtraction",
             V.Kind = Value_Integer and then V.Int = 19);
   end Test_Minus_Filter;

   procedure Test_Slice_Filter is
      V : Value;

      function Str_Lit (S : String) return Expression_Access is
        (new Expression'
           (Kind => Expr_String, Str_Value => To_Unbounded_String (S)));

      function Int_Lit (N : Integer) return Expression_Access is
        (new Expression'(Kind => Expr_Integer, Int_Value => N));

      --  Builds `<Base> | slice: <Start>, <Slice_Length>` directly as
      --  an AST, bypassing the text parser: the grammar has no unary
      --  minus, so a negative Slice_Length (needed to exercise one of
      --  the liquidjs-verified edge cases below) can't be written as
      --  source text in this subset in the first place.
      function Slice_Expr
        (Base : String; Start, Slice_Length : Integer) return Expression_Access
      is
         Args : Expression_Access_Vectors.Vector;
      begin
         Args.Append (Int_Lit (Start));
         Args.Append (Int_Lit (Slice_Length));
         return new Expression'
           (Kind        => Expr_Filtered,
            Base        => Str_Lit (Base),
            Filter_Name => To_Unbounded_String ("slice"),
            Args        => Args);
      end Slice_Expr;

   begin
      V := Evaluate (Slice_Expr ("0123456789", 0, 5), Ctx, Sc);
      Check ("slice: ordinary case",
             V.Kind = Value_String and then To_String (V.Str) = "01234");

      V := Evaluate (Slice_Expr ("0123456789", 0, 0), Ctx, Sc);
      Check ("slice: zero length -> """" (matches liquidjs)",
             V.Kind = Value_String and then To_String (V.Str) = "");

      V := Evaluate (Slice_Expr ("0123456789", 0, -3), Ctx, Sc);
      Check ("slice: negative length -> """" (matches liquidjs)",
             V.Kind = Value_String and then To_String (V.Str) = "");

      V := Evaluate (Slice_Expr ("ab", 0, 10), Ctx, Sc);
      Check ("slice: length exceeds string -> clamped (matches liquidjs)",
             V.Kind = Value_String and then To_String (V.Str) = "ab");

      V := Evaluate (Slice_Expr ("ab", 5, 3), Ctx, Sc);
      Check ("slice: start past end of string -> """" (matches liquidjs)",
             V.Kind = Value_String and then To_String (V.Str) = "");
   end Test_Slice_Filter;

   procedure Test_Unknown_Variable_Raises is
   begin
      declare
         V : constant Value := Eval ("thisVariableDoesNotExist");
      begin
         Check ("unknown variable raises Eval_Error",
                V.Kind = Value_Nil and then False);  --  unreachable
      end;
   exception
      when Eval_Error =>
         Check ("unknown variable raises Eval_Error", True);
   end Test_Unknown_Variable_Raises;

   procedure Test_Unsupported_Filter_Raises is
   begin
      declare
         V : constant Value := Eval ("39 | frobnicate: 1");
      begin
         Check ("unsupported filter raises Eval_Error",
                V.Kind = Value_Nil and then False);  --  unreachable
      end;
   exception
      when Eval_Error =>
         Check ("unsupported filter raises Eval_Error", True);
   end Test_Unsupported_Filter_Raises;

   procedure Test_Minus_Wrong_Type_Raises is
   begin
      declare
         V : constant Value := Eval ("""not a number"" | minus: 1");
      begin
         Check ("minus with non-integer base raises Eval_Error",
                V.Kind = Value_Nil and then False);  --  unreachable
      end;
   exception
      when Eval_Error =>
         Check ("minus with non-integer base raises Eval_Error", True);
   end Test_Minus_Wrong_Type_Raises;

   procedure Test_Compare_Entry_Raises is
   begin
      declare
         V : constant Value := Eval ("handler == handler");
      begin
         Check ("comparing two Value_Entry raises Eval_Error",
                V.Kind = Value_Nil and then False);  --  unreachable
      end;
   exception
      when Eval_Error =>
         Check ("comparing two Value_Entry raises Eval_Error", True);
   end Test_Compare_Entry_Raises;

begin
   Put_Line ("Liquid_Subset.Evaluator self-test");
   Test_Truthy;
   Test_Display;
   Test_Display_Entry_Raises;
   Test_Context_Fields;
   Test_Loop_Variable;
   Test_Equality;
   Test_Assigned_Variable;
   Test_Minus_Filter;
   Test_Slice_Filter;
   Test_Unknown_Variable_Raises;
   Test_Unsupported_Filter_Raises;
   Test_Minus_Wrong_Type_Raises;
   Test_Compare_Entry_Raises;

   New_Line;
   if Failures = 0 then
      Put_Line ("All checks passed.");
   else
      Put_Line (Failures'Image & " check(s) FAILED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Evaluator_Selftest;
