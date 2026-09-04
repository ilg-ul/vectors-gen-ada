--  liquid_parser_selftest.adb
--
--  Exercises Liquid_Subset.Parser: the expression grammar in
--  isolation first, then full tag/statement parsing (including the
--  error paths -- mismatched end tags, a stray {% else %}, an
--  unclosed {% for %}, an unknown tag), then a structural check of
--  the parsed AST for the entire real vectors-liquid.c template.

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Containers; use Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Liquid_Subset.Ast;     use Liquid_Subset.Ast;
with Liquid_Subset.Lexer;
with Liquid_Subset.Parser;

procedure Liquid_Parser_Selftest is
   use Ada.Text_IO;
   package Lex renames Liquid_Subset.Lexer;
   package Par renames Liquid_Subset.Parser;

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

   function Parse_Source (Template : String) return Node_Access_Vectors.Vector
   is
   begin
      return Par.Parse (Lex.Tokenize (Template));
   end Parse_Source;

   ------------------------------------------------------------------
   --  Expression grammar, in isolation
   ------------------------------------------------------------------

   procedure Test_Expressions is
      E : Expression_Access;
   begin
      E := Par.Parse_Expression ("isArmArch6m");
      Check ("expr: bare identifier -> 1-segment path",
             E.Kind = Expr_Path
             and then E.Segments.Length = 1
             and then To_String (E.Segments (1)) = "isArmArch6m");

      E := Par.Parse_Expression ("handler.symbol.size");
      Check ("expr: dotted path -> 3 segments",
             E.Kind = Expr_Path
             and then E.Segments.Length = 3
             and then To_String (E.Segments (1)) = "handler"
             and then To_String (E.Segments (2)) = "symbol"
             and then To_String (E.Segments (3)) = "size");

      E := Par.Parse_Expression ("""0""");
      Check ("expr: double-quoted string literal",
             E.Kind = Expr_String and then To_String (E.Str_Value) = "0");

      E := Par.Parse_Expression ("'   '");
      Check ("expr: single-quoted string literal (3 spaces)",
             E.Kind = Expr_String and then To_String (E.Str_Value) = "   ");

      E := Par.Parse_Expression ("39");
      Check ("expr: integer literal",
             E.Kind = Expr_Integer and then E.Int_Value = 39);

      E := Par.Parse_Expression ("handler.symbol == ""0""");
      Check ("expr: equality",
             E.Kind = Expr_Equals
             and then E.Left.Kind = Expr_Path
             and then E.Right.Kind = Expr_String
             and then To_String (E.Right.Str_Value) = "0");

      E := Par.Parse_Expression
        ("39 | minus: handler.symbol.size | minus: commaLength | minus: 4");
      Check ("expr: 3-deep filter chain, outermost is minus 4",
             E.Kind = Expr_Filtered
             and then To_String (E.Filter_Name) = "minus"
             and then E.Args.Length = 1
             and then E.Args (1).Kind = Expr_Integer
             and then E.Args (1).Int_Value = 4);
      Check ("expr: filter chain, middle is minus commaLength",
             E.Base.Kind = Expr_Filtered
             and then To_String (E.Base.Filter_Name) = "minus"
             and then E.Base.Args (1).Kind = Expr_Path
             and then To_String (E.Base.Args (1).Segments (1))
                        = "commaLength");
      Check ("expr: filter chain, innermost base is literal 39",
             E.Base.Base.Kind = Expr_Filtered
             and then E.Base.Base.Base.Kind = Expr_Integer
             and then E.Base.Base.Base.Int_Value = 39
             and then E.Base.Base.Args (1).Kind = Expr_Path
             and then To_String (E.Base.Base.Args (1).Segments (1))
                        = "handler");

      E := Par.Parse_Expression ("'  ' | slice: 0, padLength");
      Check ("expr: 2-arg filter (slice)",
             E.Kind = Expr_Filtered
             and then To_String (E.Filter_Name) = "slice"
             and then E.Args.Length = 2
             and then E.Args (1).Kind = Expr_Integer
             and then E.Args (1).Int_Value = 0
             and then E.Args (2).Kind = Expr_Path
             and then To_String (E.Args (2).Segments (1)) = "padLength");

   exception
      when others =>
         Check ("expression tests ran without raising", False);
   end Test_Expressions;

   procedure Test_Malformed_Expressions is
   begin
      declare
         E : constant Expression_Access := Par.Parse_Expression ("39 extra");
      begin
         Check ("expr: trailing garbage raises Parse_Error",
                E.Kind = Expr_Integer and then False);  --  unreachable
      end;
   exception
      when Par.Parse_Error =>
         Check ("expr: trailing garbage raises Parse_Error", True);
   end Test_Malformed_Expressions;

   procedure Test_Unterminated_String is
   begin
      declare
         E : constant Expression_Access := Par.Parse_Expression ("""abc");
      begin
         Check ("expr: unterminated string raises Parse_Error",
                E.Kind = Expr_String and then False);  --  unreachable
      end;
   exception
      when Par.Parse_Error =>
         Check ("expr: unterminated string raises Parse_Error", True);
   end Test_Unterminated_String;

   ------------------------------------------------------------------
   --  Full tag/statement parsing
   ------------------------------------------------------------------

   procedure Test_For_Loop is
      Nodes : constant Node_Access_Vectors.Vector :=
        Parse_Source ("{% for handler in handlers %}X{% endfor %}");
   begin
      Check ("for: 1 top-level node", Nodes.Length = 1);
      Check ("for: Node_For, loop var/collection correct",
             Nodes (1).Kind = Node_For
             and then To_String (Nodes (1).Loop_Var) = "handler"
             and then Nodes (1).Collection.Kind = Expr_Path
             and then To_String (Nodes (1).Collection.Segments (1))
                        = "handlers");
      Check ("for: body is a single Text ""X""",
             Nodes (1).Body_Nodes.Length = 1
             and then Nodes (1).Body_Nodes (1).Kind = Node_Text
             and then To_String (Nodes (1).Body_Nodes (1).Text) = "X");
   end Test_For_Loop;

   procedure Test_If_Else is
      Nodes : constant Node_Access_Vectors.Vector :=
        Parse_Source ("{% if isArmArch6m %}A{% else %}B{% endif %}");
   begin
      Check ("if/else: Then=""A"", Else=""B""",
             Nodes.Length = 1
             and then Nodes (1).Kind = Node_If
             and then Nodes (1).Then_Nodes.Length = 1
             and then To_String (Nodes (1).Then_Nodes (1).Text) = "A"
             and then Nodes (1).Else_Nodes.Length = 1
             and then To_String (Nodes (1).Else_Nodes (1).Text) = "B");
   end Test_If_Else;

   procedure Test_If_No_Else is
      Nodes : constant Node_Access_Vectors.Vector :=
        Parse_Source ("{% if handler.comment %}C{% endif %}");
   begin
      Check ("if without else: Then=""C"", Else is empty",
             Nodes.Length = 1
             and then Nodes (1).Kind = Node_If
             and then Nodes (1).Then_Nodes.Length = 1
             and then Nodes (1).Else_Nodes.Length = 0);
   end Test_If_No_Else;

   procedure Test_Unless is
      Nodes : constant Node_Access_Vectors.Vector :=
        Parse_Source ("{% unless forloop.last %}D{% endunless %}");
   begin
      Check ("unless: body ""D""",
             Nodes.Length = 1
             and then Nodes (1).Kind = Node_Unless
             and then Nodes (1).Unless_Body.Length = 1
             and then To_String (Nodes (1).Unless_Body (1).Text) = "D");
   end Test_Unless;

   procedure Test_Assign is
      Nodes : constant Node_Access_Vectors.Vector :=
        Parse_Source ("{% assign x = 1 %}");
   begin
      Check ("assign: var/value correct",
             Nodes.Length = 1
             and then Nodes (1).Kind = Node_Assign
             and then To_String (Nodes (1).Var_Name) = "x"
             and then Nodes (1).Value.Kind = Expr_Integer
             and then Nodes (1).Value.Int_Value = 1);
   end Test_Assign;

   procedure Test_Mismatched_End is
   begin
      declare
         Nodes : constant Node_Access_Vectors.Vector :=
           Parse_Source ("{% for x in y %}A{% endif %}");
      begin
         Check ("mismatched end tag raises Parse_Error",
                Nodes.Length = 0 and then False);  --  unreachable
      end;
   exception
      when Par.Parse_Error =>
         Check ("mismatched end tag raises Parse_Error", True);
   end Test_Mismatched_End;

   procedure Test_Stray_Else is
   begin
      declare
         Nodes : constant Node_Access_Vectors.Vector :=
           Parse_Source ("{% else %}");
      begin
         Check ("stray else raises Parse_Error",
                Nodes.Length = 0 and then False);  --  unreachable
      end;
   exception
      when Par.Parse_Error =>
         Check ("stray else raises Parse_Error", True);
   end Test_Stray_Else;

   procedure Test_Unclosed_For is
   begin
      declare
         Nodes : constant Node_Access_Vectors.Vector :=
           Parse_Source ("{% for x in y %}A");
      begin
         Check ("unclosed for raises Parse_Error",
                Nodes.Length = 0 and then False);  --  unreachable
      end;
   exception
      when Par.Parse_Error =>
         Check ("unclosed for raises Parse_Error", True);
   end Test_Unclosed_For;

   procedure Test_Unknown_Tag is
   begin
      declare
         Nodes : constant Node_Access_Vectors.Vector :=
           Parse_Source ("{% foobar %}");
      begin
         Check ("unknown tag raises Parse_Error",
                Nodes.Length = 0 and then False);  --  unreachable
      end;
   exception
      when Par.Parse_Error =>
         Check ("unknown tag raises Parse_Error", True);
   end Test_Unknown_Tag;

   ------------------------------------------------------------------
   --  Whole real template: structural node-count check, not just
   --  "parses without raising". Counts were worked out by hand from
   --  vectors-liquid.c: 2 for-loops, 4 if-blocks (3 with an else, 1
   --  without), 3 unless-blocks, 3 assign-statements, 5 output nodes
   --  (matching the lexer self-test's independently-counted 5 output
   --  tokens).
   ------------------------------------------------------------------

   type Tally is record
      For_Count     : Natural := 0;
      If_Count      : Natural := 0;
      Unless_Count  : Natural := 0;
      Assign_Count  : Natural := 0;
      Output_Count  : Natural := 0;
   end record;

   procedure Count (Nodes : Node_Access_Vectors.Vector; T : in out Tally) is
   begin
      for N of Nodes loop
         case N.Kind is
            when Node_Text =>
               null;
            when Node_Output =>
               T.Output_Count := T.Output_Count + 1;
            when Node_For =>
               T.For_Count := T.For_Count + 1;
               Count (N.Body_Nodes, T);
            when Node_If =>
               T.If_Count := T.If_Count + 1;
               Count (N.Then_Nodes, T);
               Count (N.Else_Nodes, T);
            when Node_Unless =>
               T.Unless_Count := T.Unless_Count + 1;
               Count (N.Unless_Body, T);
            when Node_Assign =>
               T.Assign_Count := T.Assign_Count + 1;
         end case;
      end loop;
   end Count;

   procedure Test_Whole_Template is
      Path : constant String := "templates/vectors-liquid.c";
      File : Ada.Text_IO.File_Type;
      Content : Unbounded_String := Null_Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Content, Ada.Text_IO.Get_Line (File));
         Append (Content, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (File);

      declare
         Nodes : constant Node_Access_Vectors.Vector :=
           Parse_Source (To_String (Content));
         T     : Tally;
      begin
         Count (Nodes, T);
         Check ("whole template: 2 for-loops", T.For_Count = 2);
         Check ("whole template: 4 if-blocks", T.If_Count = 4);
         Check ("whole template: 3 unless-blocks", T.Unless_Count = 3);
         Check ("whole template: 3 assign-statements", T.Assign_Count = 3);
         Check ("whole template: 5 output nodes", T.Output_Count = 5);
      end;
   exception
      when Par.Parse_Error =>
         Check ("whole template parses without error", False);
   end Test_Whole_Template;

begin
   Put_Line ("Liquid_Subset.Parser self-test");
   Test_Expressions;
   Test_Malformed_Expressions;
   Test_Unterminated_String;
   Test_For_Loop;
   Test_If_Else;
   Test_If_No_Else;
   Test_Unless;
   Test_Assign;
   Test_Mismatched_End;
   Test_Stray_Else;
   Test_Unclosed_For;
   Test_Unknown_Tag;
   Test_Whole_Template;

   New_Line;
   if Failures = 0 then
      Put_Line ("All checks passed.");
   else
      Put_Line (Failures'Image & " check(s) FAILED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Liquid_Parser_Selftest;
