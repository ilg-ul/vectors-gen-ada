with Ada.Strings.Fixed;
with Ada.Strings.Maps;

package body Liquid_Subset.Lexer is

   use Ada.Strings.Fixed;

   Whitespace : constant Ada.Strings.Maps.Character_Set :=
     Ada.Strings.Maps.To_Set
       (" " & ASCII.HT & ASCII.LF & ASCII.CR & ASCII.FF & ASCII.VT);

   --  Strips whitespace from just one side, so the "which side is
   --  which" question only has to be answered once, here, instead of
   --  at every call site.
   function Strip_Trailing_Ws (S : String) return String is
     (Trim (S, Ada.Strings.Maps.Null_Set, Whitespace));

   function Strip_Leading_Ws (S : String) return String is
     (Trim (S, Whitespace, Ada.Strings.Maps.Null_Set));

   ---------------------------------------------------------------------
   --  Tokenize
   ---------------------------------------------------------------------

   function Tokenize (Template : String) return Token_Vectors.Vector is
      Result             : Token_Vectors.Vector;
      Pos                : Positive;
      --  True right after a tag/output closes with a trailing "-":
      --  the next literal-text token (if any) still needs its leading
      --  whitespace stripped once it is known.
      Pending_Trim_Right : Boolean := False;

      --  Appends Content as a Text_Token, applying a pending
      --  right-trim from the previous delimiter (if any) first.
      procedure Append_Text (Content : String) is
      begin
         if Pending_Trim_Right then
            Result.Append
              (Token'(Kind => Text_Token,
                       Text => To_Unbounded_String
                                 (Strip_Leading_Ws (Content))));
            Pending_Trim_Right := False;
         else
            Result.Append
              (Token'(Kind => Text_Token,
                       Text => To_Unbounded_String (Content)));
         end if;
      end Append_Text;

      --  Strips trailing whitespace from the last token in Result, in
      --  place, but only if that token is a Text_Token (a `{%-` right
      --  at the very start of the template, or right after another
      --  tag/output with nothing textual between them, has nothing to
      --  trim).
      procedure Trim_Last_Text_Trailing is
      begin
         if not Result.Is_Empty
           and then Result (Result.Last_Index).Kind = Text_Token
         then
            Result (Result.Last_Index) :=
              (Kind => Text_Token,
               Text => To_Unbounded_String
                 (Strip_Trailing_Ws
                    (To_String (Result (Result.Last_Index).Text))));
         end if;
      end Trim_Last_Text_Trailing;

   begin
      if Template'Length = 0 then
         return Result;
      end if;

      Pos := Template'First;
      loop
         declare
            Next_Output : constant Natural := Index (Template, "{{", Pos);
            Next_Tag    : constant Natural := Index (Template, "{%", Pos);
            Next_Delim  : Natural;
            Is_Output   : Boolean;
         begin
            if Next_Output = 0 and then Next_Tag = 0 then
               if Template'Last >= Pos then
                  Append_Text (Template (Pos .. Template'Last));
               end if;
               Pending_Trim_Right := False;
               exit;
            elsif Next_Tag = 0
              or else (Next_Output /= 0 and then Next_Output < Next_Tag)
            then
               Next_Delim := Next_Output;
               Is_Output  := True;
            else
               Next_Delim := Next_Tag;
               Is_Output  := False;
            end if;

            if Next_Delim > Pos then
               Append_Text (Template (Pos .. Next_Delim - 1));
            else
               Pending_Trim_Right := False;
            end if;

            declare
               Closing       : constant String :=
                 (if Is_Output then "}}" else "%}");
               Open_Len      : Natural := 2;
               Trim_Left     : Boolean := False;
               Content_Start : Natural;
            begin
               if Next_Delim + 2 <= Template'Last
                 and then Template (Next_Delim + 2) = '-'
               then
                  Trim_Left := True;
                  Open_Len  := 3;
               end if;
               Content_Start := Next_Delim + Open_Len;

               declare
                  Close_At : constant Natural :=
                    (if Content_Start > Template'Last
                     then 0
                     else Index (Template, Closing, Content_Start));
               begin
                  if Close_At = 0 then
                     raise Lex_Error
                       with "unterminated '"
                         & (if Is_Output then "{{" else "{%") & "'";
                  end if;

                  declare
                     Trim_Right  : Boolean := False;
                     Content_End : Natural := Close_At - 1;
                  begin
                     if Close_At > Content_Start
                       and then Template (Close_At - 1) = '-'
                     then
                        Trim_Right  := True;
                        Content_End := Close_At - 2;
                     end if;

                     if Trim_Left then
                        Trim_Last_Text_Trailing;
                     end if;

                     declare
                        Raw_Source : constant String :=
                          (if Content_End >= Content_Start
                           then Template (Content_Start .. Content_End)
                           else "");
                     begin
                        if Is_Output then
                           Result.Append
                             (Token'(Kind   => Output_Token,
                                     Source => To_Unbounded_String
                                                  (Raw_Source)));
                        else
                           Result.Append
                             (Token'(Kind   => Tag_Token,
                                     Source => To_Unbounded_String
                                                  (Raw_Source)));
                        end if;
                     end;

                     Pending_Trim_Right := Trim_Right;
                     Pos := Close_At + Closing'Length;
                  end;
               end;
            end;
         end;
      end loop;

      return Result;
   end Tokenize;

end Liquid_Subset.Lexer;
