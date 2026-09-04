--  renderer_selftest.adb
--
--  Exercises Liquid_Subset.Renderer: isolated control-flow cases
--  first (plain text, output, for, if/else, unless, assign, and the
--  forloop.last comma-suppression pattern used by the real template),
--  then -- as the strongest check available before main.adb exists --
--  a full parse-and-render of the real vectors-liquid.c template
--  against real data from startup_stm32h533xx.s, diffed byte-for-byte
--  against the known-good vectors-stm32h533xx.c golden file.

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Liquid_Subset;           use Liquid_Subset;
with Liquid_Subset.Lexer;
with Liquid_Subset.Parser;
with Liquid_Subset.Renderer;  use Liquid_Subset.Renderer;
with Vector_Table_Parser;

procedure Renderer_Selftest is
   use Ada.Text_IO;
   package Lex renames Liquid_Subset.Lexer;
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

   function Render_Source
     (Template : String; Context : Render_Context) return String
   is
   begin
      return Render (Par.Parse (Lex.Tokenize (Template)), Context);
   end Render_Source;

   function Read_Whole_File (Path : String) return String is
      File    : Ada.Text_IO.File_Type;
      Content : Unbounded_String := Null_Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Content, Ada.Text_IO.Get_Line (File));
         Append (Content, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (File);
      return To_String (Content);
   end Read_Whole_File;

   Blank_Context : Render_Context;

   ------------------------------------------------------------------
   --  Isolated control-flow cases
   ------------------------------------------------------------------

   procedure Test_Plain_Text is
   begin
      Check ("plain text passthrough",
             Render_Source ("Hello, world!", Blank_Context)
               = "Hello, world!");
   end Test_Plain_Text;

   procedure Test_Output is
      Ctx : Render_Context;
   begin
      Ctx.Library_File_Path := To_Unbounded_String ("startup_foo.s");
      Check ("output: bare context field",
             Render_Source ("{{ libraryFilePath }}", Ctx)
               = "startup_foo.s");
   end Test_Output;

   procedure Test_For_Loop is
      Ctx : Render_Context;
      E1, E2, E3 : VTP.Table_Entry;
   begin
      E1.Symbol := To_Unbounded_String ("AAA");
      E2.Symbol := To_Unbounded_String ("BBB");
      E3.Symbol := To_Unbounded_String ("CCC");
      Ctx.Handlers.Append (E1);
      Ctx.Handlers.Append (E2);
      Ctx.Handlers.Append (E3);
      Check ("for: concatenates each handler's symbol",
             Render_Source
               ("{% for h in handlers %}[{{h.symbol}}]{% endfor %}", Ctx)
               = "[AAA][BBB][CCC]");
   end Test_For_Loop;

   procedure Test_If_Else is
      Ctx : Render_Context;
   begin
      Ctx.Is_Arm_Arch_6m := True;
      Check ("if/else: then-branch taken",
             Render_Source
               ("{% if isArmArch6m %}A{% else %}B{% endif %}", Ctx) = "A");
      Ctx.Is_Arm_Arch_6m := False;
      Check ("if/else: else-branch taken",
             Render_Source
               ("{% if isArmArch6m %}A{% else %}B{% endif %}", Ctx) = "B");
   end Test_If_Else;

   procedure Test_Unless is
      Ctx : Render_Context;
   begin
      Ctx.Is_Arm_Arch_8m := True;
      Check ("unless: condition true -> body suppressed",
             Render_Source
               ("{% unless isArmArch8m %}hidden{% endunless %}", Ctx)
               = "");
      Ctx.Is_Arm_Arch_8m := False;
      Check ("unless: condition false -> body rendered",
             Render_Source
               ("{% unless isArmArch8m %}shown{% endunless %}", Ctx)
               = "shown");
   end Test_Unless;

   procedure Test_Assign is
   begin
      Check ("assign: value visible in a later output",
             Render_Source ("{% assign x = 5 %}{{x}}", Blank_Context)
               = "5");
   end Test_Assign;

   procedure Test_Forloop_Last_Comma is
      Ctx : Render_Context;
      E1, E2, E3 : VTP.Table_Entry;
   begin
      E1.Symbol := To_Unbounded_String ("AAA");
      E2.Symbol := To_Unbounded_String ("BBB");
      E3.Symbol := To_Unbounded_String ("CCC");
      Ctx.Handlers.Append (E1);
      Ctx.Handlers.Append (E2);
      Ctx.Handlers.Append (E3);
      --  Mirrors the real template's
      --  `{{handler.symbol}}{% unless forloop.last %},{% endunless %}`.
      Check ("for: comma after every item except the last",
             Render_Source
               ("{% for h in handlers %}{{h.symbol}}"
                & "{% unless forloop.last %},{% endunless %}{% endfor %}",
                Ctx)
               = "AAA,BBB,CCC");
   end Test_Forloop_Last_Comma;

   procedure Test_Reassign_Each_Iteration is
      Ctx : Render_Context;
      E1, E2 : VTP.Table_Entry;
   begin
      E1.Symbol := To_Unbounded_String ("A");
      E2.Symbol := To_Unbounded_String ("B");
      Ctx.Handlers.Append (E1);
      Ctx.Handlers.Append (E2);
      --  Mirrors the real template's per-iteration
      --  `{% assign commaLength = 0 %}` /
      --  `{% unless forloop.last %}{% assign commaLength = 1 %}
      --  {% endunless %}` pair: a value assigned on one iteration
      --  must not leak into the next iteration's default.
      Check ("assign: re-assigned fresh each loop iteration",
             Render_Source
               ("{% for h in handlers %}"
                & "{% assign n = 0 %}"
                & "{% unless forloop.last %}{% assign n = 1 %}"
                & "{% endunless %}"
                & "{{h.symbol}}{{n}}"
                & "{% endfor %}",
                Ctx)
               = "A1B0");
   end Test_Reassign_Each_Iteration;

   procedure Test_Bad_For_Collection_Raises is
   begin
      declare
         S : constant String :=
           Render_Source ("{% for h in libraryFilePath %}x{% endfor %}",
                          Blank_Context);
      begin
         Check ("for over a non-list collection raises Render_Error",
                S = "" and then False);  --  unreachable
      end;
   exception
      when Render_Error =>
         Check ("for over a non-list collection raises Render_Error", True);
   end Test_Bad_For_Collection_Raises;

   ------------------------------------------------------------------
   --  Full end-to-end: real template + real data vs. the golden file
   ------------------------------------------------------------------

   procedure Test_Whole_Template_Matches_Golden is
      Template_Path : constant String := "templates/vectors-liquid.c";
      Input_Path    : constant String :=
        "tests/golden/startup_stm32h533xx.s";
      Golden_Path   : constant String :=
        "tests/golden/vectors-stm32h533xx.c";

      Lines : constant VTP.Line_Vectors.Vector := VTP.Read_Lines (Input_Path);
      Table : constant VTP.Entry_Vectors.Vector := VTP.Parse (Lines);

      Ctx : Render_Context;
   begin
      --  Mirrors CORE_VECTOR_COUNT = 16 in convert-startup-to-vectors.mjs:
      --  the first 16 entries are the fixed Cortex-M core exception
      --  vectors, not device IRQ handlers, so they're excluded here.
      for I in Table.First_Index + 16 .. Table.Last_Index loop
         Ctx.Handlers.Append (Table (I));
      end loop;
      Ctx.Library_File_Path := To_Unbounded_String
        ("platforms/nucleo-h533re/device/stm32cubemx/"
         & "startup_stm32h533xx.s");
      Ctx.Is_Arm_Arch_6m := Table (5).Symbol = "0";
      Ctx.Is_Arm_Arch_8m := Table (8).Symbol /= "0";

      declare
         Rendered : constant String :=
           Render_Source (Read_Whole_File (Template_Path), Ctx);
         Golden   : constant String := Read_Whole_File (Golden_Path);
      begin
         Check ("whole template render matches the golden file "
                & "byte-for-byte", Rendered = Golden);
         if Rendered /= Golden then
            Put_Line ("    (rendered length:" & Rendered'Length'Image
                      & "  golden length:" & Golden'Length'Image & ")");
            declare
               Out_File : Ada.Text_IO.File_Type;
            begin
               Ada.Text_IO.Create
                 (Out_File, Ada.Text_IO.Out_File,
                  "/tmp/renderer_selftest_actual.c");
               Ada.Text_IO.Put (Out_File, Rendered);
               Ada.Text_IO.Close (Out_File);
            end;
            --  Report roughly where the two texts first diverge, to
            --  make a future regression here easy to diagnose instead
            --  of just seeing FAIL.
            declare
               Shorter : constant Natural :=
                 Natural'Min (Rendered'Length, Golden'Length);
               Diff_At : Natural := 0;
            begin
               for I in 1 .. Shorter loop
                  if Rendered (Rendered'First + I - 1)
                    /= Golden (Golden'First + I - 1)
                  then
                     Diff_At := I;
                     exit;
                  end if;
               end loop;
               if Diff_At = 0 then
                  Put_Line ("    (lengths differ: rendered="
                            & Rendered'Length'Image & " golden="
                            & Golden'Length'Image & ", one is a "
                            & "prefix of the other)");
               else
                  Put_Line ("    (first differs at character"
                            & Diff_At'Image & ")");
                  Put_Line ("    rendered context: ["
                            & Rendered
                                (Natural'Max (Rendered'First, Diff_At - 20)
                                 .. Natural'Min (Rendered'Last, Diff_At + 20))
                            & "]");
                  Put_Line ("    golden   context: ["
                            & Golden
                                (Natural'Max (Golden'First, Diff_At - 20)
                                 .. Natural'Min (Golden'Last, Diff_At + 20))
                            & "]");
               end if;
            end;
         end if;
      end;
   end Test_Whole_Template_Matches_Golden;

begin
   Put_Line ("Liquid_Subset.Renderer self-test");
   Test_Plain_Text;
   Test_Output;
   Test_For_Loop;
   Test_If_Else;
   Test_Unless;
   Test_Assign;
   Test_Forloop_Last_Comma;
   Test_Reassign_Each_Iteration;
   Test_Bad_For_Collection_Raises;
   Test_Whole_Template_Matches_Golden;

   New_Line;
   if Failures = 0 then
      Put_Line ("All checks passed.");
   else
      Put_Line (Failures'Image & " check(s) FAILED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Renderer_Selftest;
