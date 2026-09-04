--  liquid_subset.ads
--
--  Root of the small Liquid-template subset used to render
--  vectors-liquid.c. Holds Render_Context: the one type shared across
--  the whole pipeline.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Vector_Table_Parser;

package Liquid_Subset is

   --  Deliberately a plain record with named fields, not a generic
   --  string-keyed map: forgetting to wire a field through here shows
   --  up as a compile error (an unresolved component reference)
   --  rather than as a variable that's silently absent/falsy at
   --  render time. This is the direct fix for the isArmArch8m
   --  plumbing bug this project chased through two rounds in the JS
   --  tool this replaces: there, the same mistake meant the render
   --  context object was just missing a key, and nothing caught it
   --  until the output was diffed by hand.
   type Render_Context is record
      Handlers          : Vector_Table_Parser.Entry_Vectors.Vector;
      Library_File_Path : Unbounded_String;
      Is_Arm_Arch_6m    : Boolean;
      Is_Arm_Arch_8m    : Boolean;
   end record;

end Liquid_Subset;
