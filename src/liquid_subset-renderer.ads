--  liquid_subset-renderer.ads
--
--  Walks the statement tree (Liquid_Subset.Ast.Node_Access_Vectors)
--  produced by Liquid_Subset.Parser, evaluating expressions via
--  Liquid_Subset.Evaluator, and produces the final output text. This
--  is where `{% for %}` actually iterates, `{% if %}`/`{% unless %}`
--  actually branch, and `{% assign %}` actually mutates the running
--  Scope -- Liquid_Subset.Evaluator only resolves a single expression
--  given a Scope, it doesn't drive control flow.

with Liquid_Subset.Ast;

package Liquid_Subset.Renderer is

   Render_Error : exception;

   function Render
     (Nodes   : Liquid_Subset.Ast.Node_Access_Vectors.Vector;
      Context : Render_Context) return String;
   --  Renders Nodes against Context, starting from a fresh
   --  (Liquid_Subset.Evaluator.Empty_Scope) scope.
   --
   --  Raises Liquid_Subset.Evaluator.Eval_Error for anything
   --  expression-evaluation-related (unknown variable, unsupported
   --  filter, and so on -- see that package), and Render_Error if a
   --  `{% for %}` loop's collection expression doesn't evaluate to a
   --  list of handlers.

end Liquid_Subset.Renderer;
