--  vector_table_parser.ads
--
--  Parses the vector table that follows a `g_pfnVectors:` label in a
--  CMSIS/HAL `startup_<device>.s` assembly file, mirroring the
--  behaviour of `parseVectorTable()` in `convert-startup-to-vectors.mjs`.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Vector_Table_Parser is

   type Table_Entry is record
      Symbol      : Unbounded_String;
      Has_Comment : Boolean := False;
      Comment     : Unbounded_String := Null_Unbounded_String;
   end record;

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Table_Entry);

   package Line_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String);

   Parse_Error : exception;

   function Read_Lines (Path : String) return Line_Vectors.Vector;
   --  Reads the file at Path and splits it into lines, mirroring
   --  `fs.readFileSync(path, 'utf8').split('\n')`.

   function Parse (Lines : Line_Vectors.Vector) return Entry_Vectors.Vector;
   --  Parses the vector table that follows the first `g_pfnVectors:`
   --  label found in Lines: the contiguous run of `.word <symbol>`
   --  directives up to (but excluding) the line that ends it (typically
   --  `.size g_pfnVectors, ...`). Blank lines and standalone comment
   --  lines (`/* ... */`, `@ ...`, `// ...`) are tolerated anywhere
   --  within the table. A trailing `@ ...`, `// ...`, or `/* ... */`
   --  comment on a `.word` line, if present, is preserved.
   --
   --  Raises Parse_Error if no `g_pfnVectors:` label is found, or if
   --  the label is found but is followed by no `.word` entries.

end Vector_Table_Parser;
