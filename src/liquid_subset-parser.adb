with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Characters.Handling;

package body Liquid_Subset.Parser is

   use Ada.Strings.Fixed;
   use Liquid_Subset.Ast;
   use Liquid_Subset.Lexer;

   Whitespace : constant Ada.Strings.Maps.Character_Set :=
     Ada.Strings.Maps.To_Set (" " & ASCII.HT & ASCII.LF & ASCII.CR);

   function Is_Ws (C : Character) return Boolean is
     (Ada.Strings.Maps.Is_In (C, Whitespace));

   function Is_Ident_Start (C : Character) return Boolean is
     (Ada.Characters.Handling.Is_Letter (C) or else C = '_');

   function Is_Ident_Continue (C : Character) return Boolean is
     (Ada.Characters.Handling.Is_Alphanumeric (C) or else C = '_');

   procedure Skip_Ws (S : String; Pos : in out Natural) is
   begin
      while Pos <= S'Last and then Is_Ws (S (Pos)) loop
         Pos := Pos + 1;
      end loop;
   end Skip_Ws;

   ---------------------------------------------------------------------
   --  Identifier / path scanning
   ---------------------------------------------------------------------

   function Parse_Identifier
     (S : String; Pos : in out Natural) return String
   is
      Start : constant Natural := Pos;
   begin
      if Pos > S'Last or else not Is_Ident_Start (S (Pos)) then
         raise Parse_Error
           with "expected identifier in expression: '" & S & "'";
      end if;
      Pos := Pos + 1;
      while Pos <= S'Last and then Is_Ident_Continue (S (Pos)) loop
         Pos := Pos + 1;
      end loop;
      return S (Start .. Pos - 1);
   end Parse_Identifier;

   function Parse_Path
     (S : String; Pos : in out Natural) return Expression_Access
   is
      Segments : String_Vectors.Vector;
   begin
      Segments.Append (To_Unbounded_String (Parse_Identifier (S, Pos)));
      while Pos <= S'Last and then S (Pos) = '.' loop
         Pos := Pos + 1;
         Segments.Append (To_Unbounded_String (Parse_Identifier (S, Pos)));
      end loop;
      return new Expression'(Kind => Expr_Path, Segments => Segments);
   end Parse_Path;

   ---------------------------------------------------------------------
   --  term ::= STRING | INTEGER | path
   ---------------------------------------------------------------------

   function Parse_Term
     (S : String; Pos : in out Natural) return Expression_Access
   is
   begin
      if Pos > S'Last then
         raise Parse_Error with "expected a value in expression: '" & S & "'";
      end if;

      if S (Pos) = '"' or else S (Pos) = ''' then
         declare
            Quote : constant Character := S (Pos);
            Start : Natural;
            Close : Natural;
         begin
            Pos := Pos + 1;
            Start := Pos;
            Close := Index (S, String'([1 => Quote]), Pos);
            if Close = 0 then
               raise Parse_Error
                 with "unterminated string literal in expression: '"
                   & S & "'";
            end if;
            Pos := Close + 1;
            return new Expression'
              (Kind      => Expr_String,
               Str_Value => To_Unbounded_String (S (Start .. Close - 1)));
         end;

      elsif S (Pos) in '0' .. '9' then
         declare
            Start : constant Natural := Pos;
         begin
            while Pos <= S'Last and then S (Pos) in '0' .. '9' loop
               Pos := Pos + 1;
            end loop;
            return new Expression'
              (Kind      => Expr_Integer,
               Int_Value => Integer'Value (S (Start .. Pos - 1)));
         end;

      elsif Is_Ident_Start (S (Pos)) then
         return Parse_Path (S, Pos);

      else
         raise Parse_Error
           with "unexpected character '" & S (Pos)
             & "' in expression: '" & S & "'";
      end if;
   end Parse_Term;

   ---------------------------------------------------------------------
   --  filtered ::= term ( "|" IDENT ":" arglist )*
   --  arglist  ::= term ( "," term )*
   ---------------------------------------------------------------------

   function Parse_Filtered
     (S : String; Pos : in out Natural) return Expression_Access
   is
      Result : Expression_Access := Parse_Term (S, Pos);
   begin
      Skip_Ws (S, Pos);
      while Pos <= S'Last and then S (Pos) = '|' loop
         Pos := Pos + 1;
         Skip_Ws (S, Pos);

         declare
            Filter_Name : constant String := Parse_Identifier (S, Pos);
            Args        : Expression_Access_Vectors.Vector;
         begin
            Skip_Ws (S, Pos);
            if Pos > S'Last or else S (Pos) /= ':' then
               raise Parse_Error
                 with "expected ':' after filter name '" & Filter_Name
                   & "' in expression: '" & S & "'";
            end if;
            Pos := Pos + 1;
            Skip_Ws (S, Pos);

            Args.Append (Parse_Term (S, Pos));
            Skip_Ws (S, Pos);
            while Pos <= S'Last and then S (Pos) = ',' loop
               Pos := Pos + 1;
               Skip_Ws (S, Pos);
               Args.Append (Parse_Term (S, Pos));
               Skip_Ws (S, Pos);
            end loop;

            Result := new Expression'
              (Kind        => Expr_Filtered,
               Base        => Result,
               Filter_Name => To_Unbounded_String (Filter_Name),
               Args        => Args);
         end;
      end loop;
      return Result;
   end Parse_Filtered;

   ---------------------------------------------------------------------
   --  expression ::= filtered [ "==" filtered ]
   ---------------------------------------------------------------------

   function Parse_Equality
     (S : String; Pos : in out Natural) return Expression_Access
   is
      Left : constant Expression_Access := Parse_Filtered (S, Pos);
   begin
      Skip_Ws (S, Pos);
      if Pos + 1 <= S'Last and then S (Pos .. Pos + 1) = "==" then
         Pos := Pos + 2;
         Skip_Ws (S, Pos);
         return new Expression'
           (Kind  => Expr_Equals,
            Left  => Left,
            Right => Parse_Filtered (S, Pos));
      end if;
      return Left;
   end Parse_Equality;

   ---------------------------------------------------------------------
   --  Parse_Expression  (public)
   ---------------------------------------------------------------------

   function Parse_Expression
     (Raw : String) return Liquid_Subset.Ast.Expression_Access
   is
      Pos : Natural := Raw'First;
   begin
      if Raw'Length = 0 then
         raise Parse_Error with "expected an expression, got nothing";
      end if;

      Skip_Ws (Raw, Pos);
      declare
         Result : constant Expression_Access := Parse_Equality (Raw, Pos);
      begin
         Skip_Ws (Raw, Pos);
         if Pos <= Raw'Last then
            raise Parse_Error
              with "unexpected trailing content in expression: '"
                & Raw (Pos .. Raw'Last) & "'";
         end if;
         return Result;
      end;
   end Parse_Expression;

   ---------------------------------------------------------------------
   --  Tag-content helpers
   ---------------------------------------------------------------------

   --  First identifier-word of a trimmed tag body, and everything
   --  after it (not re-trimmed; each specific tag parser below trims
   --  what it needs via Skip_Ws as it goes).
   procedure Split_Keyword
     (Trimmed_Raw : String; Keyword : out Unbounded_String;
      Rest        : out Unbounded_String)
   is
      Pos : Natural := Trimmed_Raw'First;
   begin
      Keyword := To_Unbounded_String (Parse_Identifier (Trimmed_Raw, Pos));
      Rest :=
        (if Pos <= Trimmed_Raw'Last
         then To_Unbounded_String (Trimmed_Raw (Pos .. Trimmed_Raw'Last))
         else Null_Unbounded_String);
   end Split_Keyword;

   procedure Expect_Empty (Keyword : String; Rest : String) is
   begin
      if Trim (Rest, Whitespace, Whitespace) /= "" then
         raise Parse_Error
           with "unexpected content after '" & Keyword & "': '"
             & Rest & "'";
      end if;
   end Expect_Empty;

   --  `<var> in <path-expression>`
   procedure Parse_For_Header
     (Rest       : String;
      Loop_Var   : out Unbounded_String;
      Collection : out Expression_Access)
   is
      Pos : Natural := Rest'First;
   begin
      Skip_Ws (Rest, Pos);
      Loop_Var := To_Unbounded_String (Parse_Identifier (Rest, Pos));
      Skip_Ws (Rest, Pos);
      if Pos + 1 > Rest'Last or else Rest (Pos .. Pos + 1) /= "in"
        or else (Pos + 2 <= Rest'Last
                 and then Is_Ident_Continue (Rest (Pos + 2)))
      then
         raise Parse_Error
           with "expected 'in' in for-loop header: '" & Rest & "'";
      end if;
      Pos := Pos + 2;
      Skip_Ws (Rest, Pos);
      Collection := Parse_Equality (Rest, Pos);
      Skip_Ws (Rest, Pos);
      if Pos <= Rest'Last then
         raise Parse_Error
           with "unexpected trailing content in for-loop header: '"
             & Rest & "'";
      end if;
   end Parse_For_Header;

   --  `<var> = <expression>`
   procedure Parse_Assign_Body
     (Rest     : String;
      Var_Name : out Unbounded_String;
      Value    : out Expression_Access)
   is
      Pos : Natural := Rest'First;
   begin
      Skip_Ws (Rest, Pos);
      Var_Name := To_Unbounded_String (Parse_Identifier (Rest, Pos));
      Skip_Ws (Rest, Pos);
      if Pos > Rest'Last or else Rest (Pos) /= '=' then
         raise Parse_Error
           with "expected '=' in assign statement: '" & Rest & "'";
      end if;
      Pos := Pos + 1;
      Skip_Ws (Rest, Pos);
      Value := Parse_Equality (Rest, Pos);
      Skip_Ws (Rest, Pos);
      if Pos <= Rest'Last then
         raise Parse_Error
           with "unexpected trailing content in assign statement: '"
             & Rest & "'";
      end if;
   end Parse_Assign_Body;

   ---------------------------------------------------------------------
   --  Parse_Block: parses a sequence of nodes up to (and consuming)
   --  the first `else`/`endif`/`endfor`/`endunless` it meets, or to
   --  the end of the token stream. The terminator actually found is
   --  handed back so the caller (top-level Parse, or the for/if/
   --  unless handling below) can check it matches what it expected.
   ---------------------------------------------------------------------

   Empty_Terminator : constant Unbounded_String := Null_Unbounded_String;

   function Describe (Terminator : Unbounded_String) return String is
     (if Terminator = Empty_Terminator
      then "end of input"
      else "{% " & To_String (Terminator) & " %}");

   procedure Parse_Block
     (Tokens     : Token_Vectors.Vector;
      Pos        : in out Positive;
      Nodes      : out Node_Access_Vectors.Vector;
      Terminator : out Unbounded_String)
   is
   begin
      loop
         if Pos > Tokens.Last_Index then
            Terminator := Empty_Terminator;
            return;
         end if;

         declare
            Tok : constant Token := Tokens (Pos);
         begin
            case Tok.Kind is

               when Text_Token =>
                  Nodes.Append
                    (new Node'(Kind => Node_Text, Text => Tok.Text));
                  Pos := Pos + 1;

               when Output_Token =>
                  Nodes.Append
                    (new Node'
                       (Kind => Node_Output,
                        Expr => Parse_Expression (To_String (Tok.Source))));
                  Pos := Pos + 1;

               when Tag_Token =>
                  Pos := Pos + 1;

                  declare
                     Trimmed : constant String :=
                       Trim (To_String (Tok.Source), Whitespace, Whitespace);
                     Keyword : Unbounded_String;
                     Rest    : Unbounded_String;
                  begin
                     Split_Keyword (Trimmed, Keyword, Rest);

                     if Keyword = "else" or else Keyword = "endif"
                       or else Keyword = "endfor"
                       or else Keyword = "endunless"
                     then
                        Expect_Empty (To_String (Keyword), To_String (Rest));
                        Terminator := Keyword;
                        return;

                     elsif Keyword = "for" then
                        declare
                           Loop_Var   : Unbounded_String;
                           Collection : Expression_Access;
                           Sub_Nodes  : Node_Access_Vectors.Vector;
                           Sub_Term   : Unbounded_String;
                        begin
                           Parse_For_Header
                             (To_String (Rest), Loop_Var, Collection);
                           Parse_Block (Tokens, Pos, Sub_Nodes, Sub_Term);
                           if Sub_Term /= "endfor" then
                              raise Parse_Error
                                with "expected {% endfor %}, got "
                                  & Describe (Sub_Term);
                           end if;
                           Nodes.Append
                             (new Node'
                                (Kind       => Node_For,
                                 Loop_Var   => Loop_Var,
                                 Collection => Collection,
                                 Body_Nodes => Sub_Nodes));
                        end;

                     elsif Keyword = "if" then
                        declare
                           Condition  : constant Expression_Access :=
                             Parse_Expression (To_String (Rest));
                           Then_Nodes : Node_Access_Vectors.Vector;
                           Else_Nodes : Node_Access_Vectors.Vector;
                           Term_1     : Unbounded_String;
                        begin
                           Parse_Block (Tokens, Pos, Then_Nodes, Term_1);
                           if Term_1 = "else" then
                              declare
                                 Term_2 : Unbounded_String;
                              begin
                                 Parse_Block
                                   (Tokens, Pos, Else_Nodes, Term_2);
                                 if Term_2 /= "endif" then
                                    raise Parse_Error
                                      with "expected {% endif %} after "
                                        & "{% else %}, got "
                                        & Describe (Term_2);
                                 end if;
                              end;
                           elsif Term_1 /= "endif" then
                              raise Parse_Error
                                with "expected {% else %} or {% endif %}, "
                                  & "got " & Describe (Term_1);
                           end if;
                           Nodes.Append
                             (new Node'
                                (Kind         => Node_If,
                                 If_Condition => Condition,
                                 Then_Nodes   => Then_Nodes,
                                 Else_Nodes   => Else_Nodes));
                        end;

                     elsif Keyword = "unless" then
                        declare
                           Condition : constant Expression_Access :=
                             Parse_Expression (To_String (Rest));
                           Sub_Nodes : Node_Access_Vectors.Vector;
                           Sub_Term  : Unbounded_String;
                        begin
                           Parse_Block (Tokens, Pos, Sub_Nodes, Sub_Term);
                           if Sub_Term /= "endunless" then
                              raise Parse_Error
                                with "expected {% endunless %}, got "
                                  & Describe (Sub_Term);
                           end if;
                           Nodes.Append
                             (new Node'
                                (Kind             => Node_Unless,
                                 Unless_Condition => Condition,
                                 Unless_Body      => Sub_Nodes));
                        end;

                     elsif Keyword = "assign" then
                        declare
                           Var_Name : Unbounded_String;
                           Value    : Expression_Access;
                        begin
                           Parse_Assign_Body
                             (To_String (Rest), Var_Name, Value);
                           Nodes.Append
                             (new Node'
                                (Kind     => Node_Assign,
                                 Var_Name => Var_Name,
                                 Value    => Value));
                        end;

                     else
                        raise Parse_Error
                          with "unrecognised tag '" & To_String (Keyword)
                            & "'";
                     end if;
                  end;
            end case;
         end;
      end loop;
   end Parse_Block;

   ---------------------------------------------------------------------
   --  Parse  (public)
   ---------------------------------------------------------------------

   function Parse
     (Tokens : Liquid_Subset.Lexer.Token_Vectors.Vector)
      return Liquid_Subset.Ast.Node_Access_Vectors.Vector
   is
      Nodes      : Node_Access_Vectors.Vector;
      Terminator : Unbounded_String;
      Pos        : Positive := 1;
   begin
      if not Tokens.Is_Empty then
         Parse_Block (Tokens, Pos, Nodes, Terminator);
         if Terminator /= Empty_Terminator then
            raise Parse_Error
              with "unexpected " & Describe (Terminator)
                & " with no matching opening tag";
         end if;
      end if;
      return Nodes;
   end Parse;

end Liquid_Subset.Parser;
