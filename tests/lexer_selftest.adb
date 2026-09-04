--  lexer_selftest.adb
--
--  Exercises Liquid_Subset.Lexer.Tokenize: isolated left/right trim
--  behaviour first (so a Left/Right mix-up shows up immediately and
--  in isolation), then the actual for/unless/endfor snippet from
--  vectors-liquid.c, whose expected token stream was worked out by
--  hand against Liquid's documented whitespace-control semantics.

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Containers; use Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Liquid_Subset.Lexer;
use Liquid_Subset.Lexer;

procedure Lexer_Selftest is
   use Ada.Text_IO;
   package Lex renames Liquid_Subset.Lexer;

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

   function Text_Of (T : Lex.Token) return String is
     (To_String (T.Text));

   function Source_Of (T : Lex.Token) return String is
     (To_String (T.Source));

   ------------------------------------------------------------------
   --  Case 1: no trim markers at all -- interior padding is kept
   --  as-is (trimming it is the parser's job, not the lexer's).
   ------------------------------------------------------------------
   procedure Test_No_Trim is
      Tokens : constant Lex.Token_Vectors.Vector :=
        Lex.Tokenize ("before {{ x }} after");
   begin
      Check ("no-trim: 3 tokens", Tokens.Length = 3);
      Check ("no-trim: [1] Text ""before """,
             Tokens (1).Kind = Lex.Text_Token
             and then Text_Of (Tokens (1)) = "before ");
      Check ("no-trim: [2] Output "" x """,
             Tokens (2).Kind = Lex.Output_Token
             and then Source_Of (Tokens (2)) = " x ");
      Check ("no-trim: [3] Text "" after""",
             Tokens (3).Kind = Lex.Text_Token
             and then Text_Of (Tokens (3)) = " after");
   end Test_No_Trim;

   ------------------------------------------------------------------
   --  Case 2: `{%-` only -- strips the preceding text's trailing
   --  whitespace, leaves the following text's leading whitespace
   --  untouched.
   ------------------------------------------------------------------
   procedure Test_Trim_Left_Only is
      Tokens : constant Lex.Token_Vectors.Vector :=
        Lex.Tokenize ("before   {%- assign x = 1 %}   after");
   begin
      Check ("trim-left: 3 tokens", Tokens.Length = 3);
      Check ("trim-left: [1] Text ""before"" (trailing spaces gone)",
             Text_Of (Tokens (1)) = "before");
      Check ("trim-left: [2] Tag "" assign x = 1 """,
             Source_Of (Tokens (2)) = " assign x = 1 ");
      Check ("trim-left: [3] Text ""   after"" (untouched)",
             Text_Of (Tokens (3)) = "   after");
   end Test_Trim_Left_Only;

   ------------------------------------------------------------------
   --  Case 3: `-%}` only -- the mirror image of case 2.
   ------------------------------------------------------------------
   procedure Test_Trim_Right_Only is
      Tokens : constant Lex.Token_Vectors.Vector :=
        Lex.Tokenize ("before   {% assign x = 1 -%}   after");
   begin
      Check ("trim-right: 3 tokens", Tokens.Length = 3);
      Check ("trim-right: [1] Text ""before   "" (untouched)",
             Text_Of (Tokens (1)) = "before   ");
      Check ("trim-right: [2] Tag "" assign x = 1 """,
             Source_Of (Tokens (2)) = " assign x = 1 ");
      Check ("trim-right: [3] Text ""after"" (leading spaces gone)",
             Text_Of (Tokens (3)) = "after");
   end Test_Trim_Right_Only;

   ------------------------------------------------------------------
   --  Case 4: both sides trimmed at once.
   ------------------------------------------------------------------
   procedure Test_Trim_Both is
      Tokens : constant Lex.Token_Vectors.Vector :=
        Lex.Tokenize ("before   {%- assign x = 1 -%}   after");
   begin
      Check ("trim-both: 3 tokens", Tokens.Length = 3);
      Check ("trim-both: [1] Text ""before""",
             Text_Of (Tokens (1)) = "before");
      Check ("trim-both: [3] Text ""after""",
             Text_Of (Tokens (3)) = "after");
   end Test_Trim_Both;

   ------------------------------------------------------------------
   --  Case 5: an unterminated tag must raise Lex_Error.
   ------------------------------------------------------------------
   procedure Test_Unterminated is
   begin
      declare
         Tokens : constant Lex.Token_Vectors.Vector :=
           Lex.Tokenize ("before {% assign x = 1 after");
      begin
         Check ("unterminated tag raises Lex_Error",
                Tokens.Length = 0 and then False);  --  unreachable
      end;
   exception
      when Lex.Lex_Error =>
         Check ("unterminated tag raises Lex_Error", True);
      when others =>
         Check ("unterminated tag raises Lex_Error (wrong exception)",
                False);
   end Test_Unterminated;

   ------------------------------------------------------------------
   --  Case 6: the real for/unless/endfor snippet from
   --  vectors-liquid.c. Expected tokens were derived by hand,
   --  tracing Liquid's trim rule through each line; see the
   --  accompanying commit/turn notes for the full derivation.
   ------------------------------------------------------------------
   procedure Test_Real_Snippet is
      LF       : constant Character := ASCII.LF;
      Snippet  : constant String :=
        "{%- for handler in handlers %}" & LF
        & "{%- unless handler.symbol == ""0"" %}" & LF
        & "void {{handler.symbol}}(void) __attribute__ "
        & "((weak, alias (""Default_Handler"")));" & LF
        & "{%- endunless %}" & LF
        & "{%- endfor %}" & LF;
      Tokens : constant Lex.Token_Vectors.Vector := Lex.Tokenize (Snippet);
   begin
      Check ("real snippet: 10 tokens", Tokens.Length = 10);
      Check ("real snippet: [1] Tag ""for""",
             Tokens (1).Kind = Lex.Tag_Token
             and then Source_Of (Tokens (1)) = " for handler in handlers ");
      Check ("real snippet: [2] Text """" (newline eaten by "
             & "unless's trim-left)",
             Tokens (2).Kind = Lex.Text_Token
             and then Text_Of (Tokens (2)) = "");
      Check ("real snippet: [3] Tag ""unless""",
             Tokens (3).Kind = Lex.Tag_Token
             and then Source_Of (Tokens (3))
                        = " unless handler.symbol == ""0"" ");
      Check ("real snippet: [4] Text ""(LF)void """,
             Tokens (4).Kind = Lex.Text_Token
             and then Text_Of (Tokens (4)) = [1 => LF] & "void ");
      Check ("real snippet: [5] Output ""handler.symbol""",
             Tokens (5).Kind = Lex.Output_Token
             and then Source_Of (Tokens (5)) = "handler.symbol");
      Check ("real snippet: [6] Text ends in ');' with no "
             & "trailing newline",
             Tokens (6).Kind = Lex.Text_Token
             and then Text_Of (Tokens (6))
                        = "(void) __attribute__ ((weak, alias "
                          & "(""Default_Handler"")));");
      Check ("real snippet: [7] Tag ""endunless""",
             Tokens (7).Kind = Lex.Tag_Token
             and then Source_Of (Tokens (7)) = " endunless ");
      Check ("real snippet: [8] Text """" (newline eaten by "
             & "endfor's trim-left)",
             Tokens (8).Kind = Lex.Text_Token
             and then Text_Of (Tokens (8)) = "");
      Check ("real snippet: [9] Tag ""endfor""",
             Tokens (9).Kind = Lex.Tag_Token
             and then Source_Of (Tokens (9)) = " endfor ");
      Check ("real snippet: [10] Text (LF) (final newline, "
             & "nothing to trim it)",
             Tokens (10).Kind = Lex.Text_Token
             and then Text_Of (Tokens (10)) = [1 => LF]);
   end Test_Real_Snippet;

   ------------------------------------------------------------------
   --  Case 7: smoke-test the *entire* real template file -- must not
   --  raise Lex_Error (i.e. every {{ / {% is properly closed), and
   --  should produce a plausible number of tokens. This does not
   --  check token content (that needs the milestone-4 parser to be
   --  meaningful), only that nothing in the full file, including the
   --  parts case 6 doesn't cover (the isArmArch6m/8m if/else blocks,
   --  the `slice` filter expression, the padding calculation), trips
   --  up the lexer.
   ------------------------------------------------------------------
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
         Tokens : constant Lex.Token_Vectors.Vector :=
           Lex.Tokenize (To_String (Content));
         Output_Count : Natural := 0;
         Tag_Count    : Natural := 0;
      begin
         for T of Tokens loop
            case T.Kind is
               when Lex.Output_Token => Output_Count := Output_Count + 1;
               when Lex.Tag_Token    => Tag_Count := Tag_Count + 1;
               when Lex.Text_Token   => null;
            end case;
         end loop;
         Check ("whole template: tokenizes without error",
                Tokens.Length > 0);
         Check ("whole template: at least one output token found",
                Output_Count > 0);
         Check ("whole template: at least one tag token found",
                Tag_Count > 0);
         Put_Line ("    (" & Tokens.Length'Image & " tokens total, "
                   & Output_Count'Image & " output, "
                   & Tag_Count'Image & " tag)");
      end;
   exception
      when Lex.Lex_Error =>
         Check ("whole template: tokenizes without error", False);
   end Test_Whole_Template;

begin
   Put_Line ("Liquid_Subset.Lexer self-test");
   Test_No_Trim;
   Test_Trim_Left_Only;
   Test_Trim_Right_Only;
   Test_Trim_Both;
   Test_Unterminated;
   Test_Real_Snippet;
   Test_Whole_Template;

   New_Line;
   if Failures = 0 then
      Put_Line ("All checks passed.");
   else
      Put_Line (Failures'Image & " check(s) FAILED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Lexer_Selftest;
