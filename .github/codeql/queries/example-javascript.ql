/**
 * @name Insecure string concatenation in SQL query (demo)
 * @description Flags string concatenation that looks like SQL query building.
 * @kind problem
 * @problem.severity warning
 * @precision medium
 * @id js/insecure-sql-concat-demo
 * @tags security; external/cwe/cwe-89
 */

import javascript
import DataFlow::PathGraph

from FunctionCall call, Expr arg
where
  call.getCallee().getName().matches("%query%") and
  exists(StringConcat sc | arg = sc and sc.toString().regexpMatch("(?i)select|insert|update|delete"))
select arg, "Potential SQL built via string concatenation. Prefer parameterized queries."
