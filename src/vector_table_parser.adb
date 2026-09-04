with Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;

package body Vector_Table_Parser is

   use Ada.Strings.Fixed;

   --  Matches JS's `\s` closely enough for CMSIS assembly source:
   --  space, tab, and a stray CR left over from a CRLF file.
   Whitespace : constant Ada.Strings.Maps.Character_Set :=
     Ada.Strings.Maps.To_Set (" " & ASCII.HT & ASCII.CR);

   function Trim_Line (S : String) return String is
     (Trim (S, Whitespace, Whitespace));

   function Is_Ws (C : Character) return Boolean is
     (Ada.Strings.Maps.Is_In (C, Whitespace));

   --  Private helpers, forward-declared here so each one below is a
   --  completion of a known spec (required by the -gnatyg style check)
   --  rather than a body with no declaration at all.

   function Is_Vector_Table_Label (Trimmed_Line : String) return Boolean;
   --  Mirrors `/^g_pfnVectors\s*:/`.

   function Is_Comment_Only_Line (Trimmed_Line : String) return Boolean;
   --  Mirrors `/^(?:\/\*.*\*\/|@.*|\/\/.*)$/`.

   function Try_Parse_Word_Line
     (Trimmed_Line : String;
      Result       : out Table_Entry) return Boolean;
   --  Mirrors (see convert-startup-to-vectors.mjs):
   --  /^\.word\s+(\S+)(?:\s+(?:@\s*(.*)|\/\/\s*(.*)
   --                            |\/\*\s*(.*?)\s*\*\/\s*))?$/

   ---------------------------------------------------------------------
   --  Read_Lines
   ---------------------------------------------------------------------

   function Read_Lines (Path : String) return Line_Vectors.Vector is
      File   : Ada.Text_IO.File_Type;
      Result : Line_Vectors.Vector;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Result.Append (To_Unbounded_String (Ada.Text_IO.Get_Line (File)));
      end loop;
      Ada.Text_IO.Close (File);
      return Result;
   end Read_Lines;

   ---------------------------------------------------------------------
   --  Is_Vector_Table_Label
   ---------------------------------------------------------------------

   function Is_Vector_Table_Label (Trimmed_Line : String) return Boolean is
      Lit : constant String := "g_pfnVectors";
      Pos : Natural;
   begin
      if Trimmed_Line'Length < Lit'Length
        or else Trimmed_Line
                  (Trimmed_Line'First .. Trimmed_Line'First + Lit'Length - 1)
                /= Lit
      then
         return False;
      end if;

      Pos := Trimmed_Line'First + Lit'Length;
      while Pos <= Trimmed_Line'Last and then Is_Ws (Trimmed_Line (Pos)) loop
         Pos := Pos + 1;
      end loop;

      return Pos <= Trimmed_Line'Last and then Trimmed_Line (Pos) = ':';
   end Is_Vector_Table_Label;

   ---------------------------------------------------------------------
   --  Is_Comment_Only_Line
   ---------------------------------------------------------------------

   function Is_Comment_Only_Line (Trimmed_Line : String) return Boolean is
      F : constant Natural := Trimmed_Line'First;
      L : constant Natural := Trimmed_Line'Last;
   begin
      if Trimmed_Line'Length >= 2
        and then Trimmed_Line (F .. F + 1) = "/*"
        and then Trimmed_Line (L - 1 .. L) = "*/"
      then
         return True;
      end if;

      if Trimmed_Line'Length >= 1 and then Trimmed_Line (F) = '@' then
         return True;
      end if;

      if Trimmed_Line'Length >= 2 and then Trimmed_Line (F .. F + 1) = "//"
      then
         return True;
      end if;

      return False;
   end Is_Comment_Only_Line;

   ---------------------------------------------------------------------
   --  Try_Parse_Word_Line
   ---------------------------------------------------------------------

   function Try_Parse_Word_Line
     (Trimmed_Line : String;
      Result       : out Table_Entry) return Boolean
   is
      Pos : Natural := Trimmed_Line'First;

      function Match_Literal (Lit : String) return Boolean is
      begin
         if Pos + Lit'Length - 1 <= Trimmed_Line'Last
           and then Trimmed_Line (Pos .. Pos + Lit'Length - 1) = Lit
         then
            Pos := Pos + Lit'Length;
            return True;
         end if;
         return False;
      end Match_Literal;

      function Match_Whitespace_Plus return Boolean is
         Start : constant Natural := Pos;
      begin
         while Pos <= Trimmed_Line'Last and then Is_Ws (Trimmed_Line (Pos))
         loop
            Pos := Pos + 1;
         end loop;
         return Pos > Start;
      end Match_Whitespace_Plus;

      procedure Skip_Whitespace_Star is
      begin
         while Pos <= Trimmed_Line'Last and then Is_Ws (Trimmed_Line (Pos))
         loop
            Pos := Pos + 1;
         end loop;
      end Skip_Whitespace_Star;

   begin
      Result := (Symbol      => Null_Unbounded_String,
                 Has_Comment => False,
                 Comment     => Null_Unbounded_String);

      if not Match_Literal (".word") then
         return False;
      end if;

      if not Match_Whitespace_Plus then
         return False;
      end if;

      --  Symbol: one-or-more non-whitespace characters.
      declare
         Symbol_Start : constant Natural := Pos;
      begin
         while Pos <= Trimmed_Line'Last
           and then not Is_Ws (Trimmed_Line (Pos))
         loop
            Pos := Pos + 1;
         end loop;
         if Pos = Symbol_Start then
            return False;
         end if;
         Result.Symbol :=
           To_Unbounded_String (Trimmed_Line (Symbol_Start .. Pos - 1));
      end;

      --  A bare ".word SYMBOL" line, nothing trailing.
      if Pos > Trimmed_Line'Last then
         return True;
      end if;

      --  Anything else needs at least one whitespace before a comment
      --  marker, exactly like the `\s+` in the optional group.
      if not Match_Whitespace_Plus then
         return False;
      end if;

      if Pos > Trimmed_Line'Last then
         return False;
      end if;

      if Trimmed_Line (Pos) = '@' then
         Pos := Pos + 1;
         Skip_Whitespace_Star;
         Result.Has_Comment := True;
         Result.Comment :=
           To_Unbounded_String (Trimmed_Line (Pos .. Trimmed_Line'Last));
         return True;

      elsif Pos + 1 <= Trimmed_Line'Last
        and then Trimmed_Line (Pos .. Pos + 1) = "//"
      then
         Pos := Pos + 2;
         Skip_Whitespace_Star;
         Result.Has_Comment := True;
         Result.Comment :=
           To_Unbounded_String (Trimmed_Line (Pos .. Trimmed_Line'Last));
         return True;

      elsif Pos + 1 <= Trimmed_Line'Last
        and then Trimmed_Line (Pos .. Pos + 1) = "/*"
      then
         Pos := Pos + 2;
         Skip_Whitespace_Star;
         declare
            Comment_Start : constant Natural := Pos;
            Close_At      : constant Natural :=
              Ada.Strings.Fixed.Index (Trimmed_Line, "*/", Pos);
            Comment_End   : Natural;
         begin
            if Close_At = 0 then
               return False;  --  unterminated /* comment
            end if;

            Comment_End := Close_At - 1;
            while Comment_End >= Comment_Start
              and then Is_Ws (Trimmed_Line (Comment_End))
            loop
               Comment_End := Comment_End - 1;
            end loop;

            Result.Has_Comment := True;
            Result.Comment := To_Unbounded_String
              (Trimmed_Line (Comment_Start .. Comment_End));

            Pos := Close_At + 2;
            Skip_Whitespace_Star;
            if Pos <= Trimmed_Line'Last then
               return False;  --  trailing junk after the closing "*/"
            end if;
            return True;
         end;

      else
         return False;
      end if;
   end Try_Parse_Word_Line;

   ---------------------------------------------------------------------
   --  Parse
   ---------------------------------------------------------------------

   function Parse (Lines : Line_Vectors.Vector) return Entry_Vectors.Vector is
      Label_Index : Natural := 0;
      Result      : Entry_Vectors.Vector;
   begin
      for I in Lines.First_Index .. Lines.Last_Index loop
         if Is_Vector_Table_Label (Trim_Line (To_String (Lines (I)))) then
            Label_Index := I;
            exit;
         end if;
      end loop;

      if Label_Index = 0 then
         raise Parse_Error with "could not find the 'g_pfnVectors:' label...";
      end if;

      for I in Label_Index + 1 .. Lines.Last_Index loop
         declare
            Trimmed    : constant String := Trim_Line (To_String (Lines (I)));
            Item       : Table_Entry;
         begin
            if Trimmed = "" or else Is_Comment_Only_Line (Trimmed) then
               null;  --  tolerated, keep scanning
            elsif Try_Parse_Word_Line (Trimmed, Item) then
               Result.Append (Item);
            else
               exit;  --  first non-`.word` line ends the table
            end if;
         end;
      end loop;

      if Result.Is_Empty then
         raise Parse_Error
           with "no '.word' entries found after 'g_pfnVectors:'...";
      end if;

      return Result;
   end Parse;

end Vector_Table_Parser;
