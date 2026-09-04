--  main.adb
--
--  Ada port of convert-startup-to-vectors.mjs. Reads a CMSIS/HAL
--  startup_<device>.s file and a Liquid template (vectors-liquid.c by
--  default), and writes the rendered vectors-<device>.c to a file, or
--  to standard output if no output path is given.
--
--  One deliberate difference from the JS tool: the template path is
--  an explicit third argument here (defaulting to
--  "templates/vectors-liquid.c", resolved relative to the current
--  directory). The JS version instead resolves its template relative
--  to the *script's own* location, using Node's `import.meta.url` --
--  a compiled Ada program has no equivalent of "the source file's own
--  directory" at run time, so rather than silently guess (e.g.
--  relative to the executable, which need not sit anywhere near a
--  `templates/` directory in an out-of-tree build), this makes the
--  choice explicit and overridable.
--
--  Another deliberate difference: the JS version computes
--  `libraryFilePath` as `path.relative(process.cwd(), inputFilePath)`.
--  This just uses the input path exactly as given on the command
--  line. For the common case -- a relative path, as in every example
--  in this project -- the two are identical; they'd only differ if
--  the input path were given as absolute.

with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Ada.Streams.Stream_IO;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Containers; use Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Vector_Table_Parser;
with Liquid_Subset;          use Liquid_Subset;
with Liquid_Subset.Lexer;
with Liquid_Subset.Parser;
with Liquid_Subset.Evaluator;
with Liquid_Subset.Renderer;

procedure Main is
   use Ada.Text_IO;

   package VTP renames Vector_Table_Parser;
   package Lex renames Liquid_Subset.Lexer;
   package Par renames Liquid_Subset.Parser;
   package Ren renames Liquid_Subset.Renderer;

   Default_Template_Path : constant String := "templates/vectors-liquid.c";

   --  The first 16 vector-table entries (initial SP, Reset_Handler,
   --  and the 14 core-exception vectors, including reserved slots)
   --  are fixed by the Cortex-M architecture, not device-specific IRQ
   --  handlers -- mirrors CORE_VECTOR_COUNT in
   --  convert-startup-to-vectors.mjs.
   Core_Vector_Count : constant := 16;

   procedure Print_Usage is
   begin
      Put_Line
        (Standard_Error,
         "Usage: vectors_gen <input.s> [output.c] [template.c]");
   end Print_Usage;

   --  Reads Path as a single String, exactly (byte-for-byte,
   --  including the final line terminator, if any). Deliberately not
   --  Ada.Text_IO.Get_Line-then-Put back out for the *output* side of
   --  this program: see the Stream_IO use below for why.
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

   --  Writes Text to Path exactly as given, with no extra trailing
   --  newline. Ada.Text_IO.Put followed by Close does NOT guarantee
   --  this: if Text's own last character is already an embedded LF
   --  (as it always is here, and as the golden fixture confirms it
   --  must be to match byte-for-byte), GNAT's Text_IO silently adds
   --  *another* trailing LF on Close, because from Text_IO's own
   --  line-tracking point of view the final line was never
   --  "properly" terminated via New_Line. Confirmed directly with an
   --  isolated test while chasing this exact symptom in milestone 6.
   --  Stream_IO has no such line-oriented state, so it doesn't have
   --  the problem.
   procedure Write_Whole_File (Path : String; Text : String) is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Path);
      String'Write (Ada.Streams.Stream_IO.Stream (File), Text);
      Ada.Streams.Stream_IO.Close (File);
   end Write_Whole_File;

begin
   if Ada.Command_Line.Argument_Count < 1 then
      Print_Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Input_Path : constant String := Ada.Command_Line.Argument (1);

      Output_Path_Given : constant Boolean :=
        Ada.Command_Line.Argument_Count >= 2;
      Output_Path : constant String :=
        (if Output_Path_Given
         then Ada.Command_Line.Argument (2)
         else "");

      Template_Path : constant String :=
        (if Ada.Command_Line.Argument_Count >= 3
         then Ada.Command_Line.Argument (3)
         else Default_Template_Path);
   begin
      if not Ada.Directories.Exists (Input_Path) then
         Put_Line
           (Standard_Error,
            "missing mandatory input file '" & Input_Path & "'...");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      if not Ada.Directories.Exists (Template_Path) then
         Put_Line
           (Standard_Error,
            "missing mandatory template file '" & Template_Path & "'...");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      New_Line (Standard_Error);
      Put_Line (Standard_Error, "Processing '" & Input_Path & "'...");

      declare
         Lines : constant VTP.Line_Vectors.Vector :=
           VTP.Read_Lines (Input_Path);
         Table : constant VTP.Entry_Vectors.Vector := VTP.Parse (Lines);
      begin
         Put_Line
           (Standard_Error,
            "Found" & Table.Length'Image & " vector table entries.");

         if Output_Path_Given then
            Put_Line (Standard_Error, "Writing '" & Output_Path & "'...");
         else
            Put_Line
              (Standard_Error,
               "No output file given, will print the result to "
               & "stdout...");
         end if;

         declare
            Ctx : Render_Context;
         begin
            for I in Table.First_Index + Core_Vector_Count
                       .. Table.Last_Index
            loop
               Ctx.Handlers.Append (Table (I));
            end loop;

            Ctx.Library_File_Path := To_Unbounded_String (Input_Path);
            Ctx.Is_Arm_Arch_6m :=
              Table.Length >= 5 and then Table (5).Symbol = "0";
            Ctx.Is_Arm_Arch_8m :=
              Table.Length >= 8 and then Table (8).Symbol /= "0";

            declare
               Template : constant String := Read_Whole_File (Template_Path);
               Rendered : constant String :=
                 Ren.Render (Par.Parse (Lex.Tokenize (Template)), Ctx);
            begin
               if Output_Path_Given then
                  Write_Whole_File (Output_Path, Rendered);
               else
                  String'Write
                    (Ada.Text_IO.Text_Streams.Stream (Standard_Output),
                     Rendered);
               end if;
            end;
         end;
      end;

      Put_Line (Standard_Error, "Done.");
   end;

exception
   when E : VTP.Parse_Error
          | Lex.Lex_Error
          | Par.Parse_Error
          | Liquid_Subset.Evaluator.Eval_Error
          | Ren.Render_Error
     =>
      Put_Line
        (Standard_Error, "error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Main;
