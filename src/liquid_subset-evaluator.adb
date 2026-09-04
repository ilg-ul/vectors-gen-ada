with Ada.Containers; use Ada.Containers;

package body Liquid_Subset.Evaluator is

   ---------------------------------------------------------------------
   --  Assign_Variable
   ---------------------------------------------------------------------

   procedure Assign_Variable (S : in out Scope; Name : String; Val : Value) is
      Target : constant Unbounded_String := To_Unbounded_String (Name);
   begin
      for I in S.Assigned.First_Index .. S.Assigned.Last_Index loop
         if S.Assigned (I).Name = Target then
            S.Assigned (I) := (Name => Target, Val => Val);
            return;
         end if;
      end loop;
      S.Assigned.Append (Named_Value'(Name => Target, Val => Val));
   end Assign_Variable;

   function Lookup_Assigned
     (S : Scope; Name : String; Found : out Boolean) return Value
   is
   begin
      for Item of S.Assigned loop
         if Item.Name = Name then
            Found := True;
            return Item.Val;
         end if;
      end loop;
      Found := False;
      return (Kind => Value_Nil);
   end Lookup_Assigned;

   ---------------------------------------------------------------------
   --  Truthy / Display
   ---------------------------------------------------------------------

   function Truthy (V : Value) return Boolean is
   begin
      case V.Kind is
         when Value_Nil     => return False;
         when Value_Boolean => return V.Bool;
         when others        => return True;
      end case;
   end Truthy;

   function Integer_To_String (N : Integer) return String is
      Img : constant String := Integer'Image (N);
   begin
      --  Integer'Image prefixes non-negative values with a space
      --  (e.g. " 5"); negative values already start with '-'.
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      end if;
      return Img;
   end Integer_To_String;

   function Display (V : Value) return String is
   begin
      case V.Kind is
         when Value_Nil     => return "";
         when Value_String  => return To_String (V.Str);
         when Value_Integer => return Integer_To_String (V.Int);
         when Value_Boolean => return (if V.Bool then "true" else "false");
         when Value_Entry | Value_Handlers =>
            raise Eval_Error
              with "cannot output this value directly "
                & "(missing a .symbol/.comment access?)";
      end case;
   end Display;

   ---------------------------------------------------------------------
   --  Path resolution
   ---------------------------------------------------------------------

   function Resolve_Root
     (Name : String; Context : Render_Context; S : Scope) return Value
   is
   begin
      if S.Loop_Var_Name /= Null_Unbounded_String
        and then To_String (S.Loop_Var_Name) = Name
      then
         return (Kind => Value_Entry, Entry_Val => S.Loop_Var_Value);
      end if;

      if Name = "handlers" then
         return (Kind => Value_Handlers, Handlers_Val => Context.Handlers);
      elsif Name = "libraryFilePath" then
         return (Kind => Value_String, Str => Context.Library_File_Path);
      elsif Name = "isArmArch6m" then
         return (Kind => Value_Boolean, Bool => Context.Is_Arm_Arch_6m);
      elsif Name = "isArmArch8m" then
         return (Kind => Value_Boolean, Bool => Context.Is_Arm_Arch_8m);
      end if;

      declare
         Found : Boolean;
         V     : constant Value := Lookup_Assigned (S, Name, Found);
      begin
         if Found then
            return V;
         end if;
      end;

      raise Eval_Error with "unknown variable '" & Name & "'";
   end Resolve_Root;

   function Dot (Base : Value; Segment : String) return Value is
   begin
      case Base.Kind is
         when Value_Entry =>
            if Segment = "symbol" then
               return (Kind => Value_String, Str => Base.Entry_Val.Symbol);
            elsif Segment = "comment" then
               if Base.Entry_Val.Has_Comment then
                  return
                    (Kind => Value_String, Str => Base.Entry_Val.Comment);
               else
                  return (Kind => Value_Nil);
               end if;
            end if;

         when Value_String =>
            if Segment = "size" then
               return (Kind => Value_Integer, Int => Length (Base.Str));
            end if;

         when others =>
            null;
      end case;

      raise Eval_Error
        with "cannot access '." & Segment & "' on this kind of value";
   end Dot;

   function Evaluate_Path
     (Segments : String_Vectors.Vector;
      Context  : Render_Context;
      S        : Scope) return Value
   is
   begin
      --  Special-cased whole-path recognition for `forloop.last`; no
      --  other `forloop.*` property is used anywhere in
      --  vectors-liquid.c, so nothing more general is built for it.
      if Segments.Length = 2
        and then To_String (Segments (1)) = "forloop"
        and then To_String (Segments (2)) = "last"
      then
         return (Kind => Value_Boolean, Bool => S.Loop_Is_Last);
      end if;

      declare
         Result : Value :=
           Resolve_Root (To_String (Segments (1)), Context, S);
      begin
         for I in 2 .. Segments.Last_Index loop
            Result := Dot (Result, To_String (Segments (I)));
         end loop;
         return Result;
      end;
   end Evaluate_Path;

   ---------------------------------------------------------------------
   --  Equality
   ---------------------------------------------------------------------

   function Values_Equal (A, B : Value) return Boolean is
   begin
      if A.Kind /= B.Kind then
         return False;
      end if;
      case A.Kind is
         when Value_Nil     => return True;
         when Value_String  => return A.Str = B.Str;
         when Value_Integer => return A.Int = B.Int;
         when Value_Boolean => return A.Bool = B.Bool;
         when Value_Entry | Value_Handlers =>
            raise Eval_Error with "cannot compare this kind of value";
      end case;
   end Values_Equal;

   ---------------------------------------------------------------------
   --  Filters
   --
   --  `Apply_Slice` matches liquidjs's own clamping behaviour, checked
   --  directly against liquidjs rather than assumed: a non-positive
   --  Length, or a Start at or past the end of the string, yields "";
   --  a Length that runs past the end of the string is clamped to
   --  what's actually there. Negative Start is not supported (nothing
   --  in vectors-liquid.c ever calls `slice` with one).
   ---------------------------------------------------------------------

   function Apply_Slice
     (S : String; Start : Integer; Slice_Length : Integer) return String
   is
   begin
      if Start < 0 then
         raise Eval_Error with "slice: negative start index not supported";
      end if;
      if Start >= S'Length or else Slice_Length <= 0 then
         return "";
      end if;

      declare
         From          : constant Positive := S'First + Start;
         Available     : constant Natural := S'Last - From + 1;
         Actual_Length : constant Natural :=
           Natural'Min (Slice_Length, Available);
      begin
         return S (From .. From + Actual_Length - 1);
      end;
   end Apply_Slice;

   function Apply_Filter
     (Filter_Name : String;
      Base        : Value;
      Args        : Value_Vectors.Vector) return Value
   is
   begin
      if Filter_Name = "minus" then
         if Base.Kind /= Value_Integer
           or else Args.Length /= 1
           or else Args (1).Kind /= Value_Integer
         then
            raise Eval_Error
              with "'minus' expects an integer base and one integer "
                & "argument";
         end if;
         return (Kind => Value_Integer, Int => Base.Int - Args (1).Int);

      elsif Filter_Name = "slice" then
         if Base.Kind /= Value_String
           or else Args.Length /= 2
           or else Args (1).Kind /= Value_Integer
           or else Args (2).Kind /= Value_Integer
         then
            raise Eval_Error
              with "'slice' expects a string base and two integer "
                & "arguments";
         end if;
         return
           (Kind => Value_String,
            Str  => To_Unbounded_String
                      (Apply_Slice
                         (To_String (Base.Str),
                          Args (1).Int, Args (2).Int)));

      else
         raise Eval_Error with "unsupported filter '" & Filter_Name & "'";
      end if;
   end Apply_Filter;

   ---------------------------------------------------------------------
   --  Evaluate
   ---------------------------------------------------------------------

   function Evaluate
     (Expr    : Expression_Access;
      Context : Render_Context;
      S       : Scope) return Value
   is
   begin
      case Expr.Kind is
         when Expr_String =>
            return (Kind => Value_String, Str => Expr.Str_Value);

         when Expr_Integer =>
            return (Kind => Value_Integer, Int => Expr.Int_Value);

         when Expr_Path =>
            return Evaluate_Path (Expr.Segments, Context, S);

         when Expr_Equals =>
            return
              (Kind => Value_Boolean,
               Bool => Values_Equal
                         (Evaluate (Expr.Left, Context, S),
                          Evaluate (Expr.Right, Context, S)));

         when Expr_Filtered =>
            declare
               Base_Val : constant Value := Evaluate (Expr.Base, Context, S);
               Arg_Vals : Value_Vectors.Vector;
            begin
               for A of Expr.Args loop
                  Arg_Vals.Append (Evaluate (A, Context, S));
               end loop;
               return
                 Apply_Filter
                   (To_String (Expr.Filter_Name), Base_Val, Arg_Vals);
            end;
      end case;
   end Evaluate;

end Liquid_Subset.Evaluator;
