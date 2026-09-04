--  parser_selftest.adb
--
--  Exercises Vector_Table_Parser paths that `startup_stm32h533xx.s`
--  never touches: the three trailing-comment styles on a `.word`
--  line, blank/standalone-comment lines tolerated inside the table,
--  the two error conditions, and lines that look almost like a
--  `.word` directive but must be rejected (trailing junk after a
--  closing `*/`, an unterminated `/* ... `).

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Containers; use Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Vector_Table_Parser;

procedure Parser_Selftest is
   use Ada.Text_IO;
   package VTP renames Vector_Table_Parser;

   Failures : Natural := 0;

   type Unbounded_String_Array is
     array (Positive range <>) of Unbounded_String;

   --  Builds a Line_Vectors.Vector from an array of plain String
   --  literals, one per source line, so each test case reads like
   --  the assembly snippet it represents.
   function Lines_Of
     (Items : Unbounded_String_Array) return VTP.Line_Vectors.Vector
   is
      Result : VTP.Line_Vectors.Vector;
   begin
      for Item of Items loop
         Result.Append (Item);
      end loop;
      return Result;
   end Lines_Of;

   function S (Str : String) return Unbounded_String renames
     To_Unbounded_String;

   procedure Check (Name : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("  PASS  " & Name);
      else
         Put_Line ("  FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   ------------------------------------------------------------------
   --  Case 1: the three comment styles, plus tolerated blank and
   --  standalone-comment lines inside the table.
   ------------------------------------------------------------------
   procedure Test_Comment_Styles is
      Lines : constant VTP.Line_Vectors.Vector := Lines_Of
        ([S ("g_pfnVectors:"),
          S (ASCII.HT & ".word" & ASCII.HT & "FOO_Handler"),
          S (ASCII.HT & ".word" & ASCII.HT
             & "BAR_Handler   @ at comment"),
          S (ASCII.HT & ".word" & ASCII.HT
             & "BAZ_Handler   // slash comment"),
          S (ASCII.HT & ".word" & ASCII.HT
             & "QUX_Handler   /* star comment */"),
          S (""),
          S ("/* standalone comment line */"),
          S ("@ standalone at-comment"),
          S ("// standalone slash comment"),
          S (ASCII.HT & ".word" & ASCII.HT & "QUUX_Handler"),
          S (ASCII.HT & ".size" & ASCII.HT
             & "g_pfnVectors, .-g_pfnVectors")]);
      Table : constant VTP.Entry_Vectors.Vector := VTP.Parse (Lines);
   begin
      Check ("comment styles: entry count = 5", Table.Length = 5);
      Check ("entry 1 symbol = FOO_Handler",
             To_String (Table (1).Symbol) = "FOO_Handler");
      Check ("entry 1 has no comment", not Table (1).Has_Comment);
      Check ("entry 2 (@) comment = ""at comment""",
             Table (2).Has_Comment
             and then To_String (Table (2).Comment) = "at comment");
      Check ("entry 3 (//) comment = ""slash comment""",
             Table (3).Has_Comment
             and then To_String (Table (3).Comment) = "slash comment");
      Check ("entry 4 (/* */) comment = ""star comment""",
             Table (4).Has_Comment
             and then To_String (Table (4).Comment) = "star comment");
      Check ("entry 5 symbol = QUUX_Handler (blank/comment lines "
             & "skipped)",
             To_String (Table (5).Symbol) = "QUUX_Handler");
   exception
      when others =>
         Check ("comment styles: parsed without raising", False);
   end Test_Comment_Styles;

   ------------------------------------------------------------------
   --  Case 2: no `g_pfnVectors:` label anywhere -> Parse_Error.
   ------------------------------------------------------------------
   procedure Test_Missing_Label is
      Lines : constant VTP.Line_Vectors.Vector := Lines_Of
        ([S ("some_other_label:"),
          S (ASCII.HT & ".word" & ASCII.HT & "FOO_Handler")]);
   begin
      declare
         Table : constant VTP.Entry_Vectors.Vector := VTP.Parse (Lines);
      begin
         Check ("missing label raises Parse_Error",
                Table.Length = 0 and then False);  --  unreachable
      end;
   exception
      when VTP.Parse_Error =>
         Check ("missing label raises Parse_Error", True);
      when others =>
         Check ("missing label raises Parse_Error (wrong exception)",
                False);
   end Test_Missing_Label;

   ------------------------------------------------------------------
   --  Case 3: label present but followed by no `.word` entries.
   ------------------------------------------------------------------
   procedure Test_Empty_Table is
      Lines : constant VTP.Line_Vectors.Vector := Lines_Of
        ([S ("g_pfnVectors:"),
          S (ASCII.HT & ".size" & ASCII.HT
             & "g_pfnVectors, .-g_pfnVectors")]);
   begin
      declare
         Table : constant VTP.Entry_Vectors.Vector := VTP.Parse (Lines);
      begin
         Check ("empty table raises Parse_Error",
                Table.Length = 0 and then False);  --  unreachable
      end;
   exception
      when VTP.Parse_Error =>
         Check ("empty table raises Parse_Error", True);
      when others =>
         Check ("empty table raises Parse_Error (wrong exception)",
                False);
   end Test_Empty_Table;

   ------------------------------------------------------------------
   --  Case 4: trailing junk after a closing `*/`, and an
   --  unterminated `/* ...`, must each end the table at that line,
   --  exactly like an unrecognised `.word` line would.
   ------------------------------------------------------------------
   procedure Test_Rejected_Word_Lines is
      Lines : constant VTP.Line_Vectors.Vector := Lines_Of
        ([S ("g_pfnVectors:"),
          S (ASCII.HT & ".word" & ASCII.HT & "FIRST_Handler"),
          S (ASCII.HT & ".word" & ASCII.HT
             & "SECOND_Handler /* c */ extra"),
          S (ASCII.HT & ".word" & ASCII.HT & "THIRD_Handler")]);
      Table : constant VTP.Entry_Vectors.Vector := VTP.Parse (Lines);
   begin
      Check ("trailing junk after */ ends the table at 1 entry",
             Table.Length = 1
             and then To_String (Table (1).Symbol) = "FIRST_Handler");
   exception
      when others =>
         Check ("trailing junk after */ ends the table at 1 entry"
                & " (raised instead)", False);
   end Test_Rejected_Word_Lines;

   procedure Test_Unterminated_Comment is
      Lines : constant VTP.Line_Vectors.Vector := Lines_Of
        ([S ("g_pfnVectors:"),
          S (ASCII.HT & ".word" & ASCII.HT & "ONLY_Handler"),
          S (ASCII.HT & ".word" & ASCII.HT
             & "NEVER_Handler /* unterminated")]);
      Table : constant VTP.Entry_Vectors.Vector := VTP.Parse (Lines);
   begin
      Check ("unterminated /* comment ends the table at 1 entry",
             Table.Length = 1
             and then To_String (Table (1).Symbol) = "ONLY_Handler");
   exception
      when others =>
         Check ("unterminated /* comment ends the table at 1 entry"
                & " (raised instead)", False);
   end Test_Unterminated_Comment;

begin
   Put_Line ("Vector_Table_Parser self-test");
   Test_Comment_Styles;
   Test_Missing_Label;
   Test_Empty_Table;
   Test_Rejected_Word_Lines;
   Test_Unterminated_Comment;

   New_Line;
   if Failures = 0 then
      Put_Line ("All checks passed.");
   else
      Put_Line (Failures'Image & " check(s) FAILED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Parser_Selftest;
