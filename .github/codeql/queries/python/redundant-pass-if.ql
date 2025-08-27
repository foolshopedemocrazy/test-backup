/**
 * @name Redundant 'if ...: pass'
 * @id py/custom/redundant-pass-if
 * @kind problem
 * @problem.severity warning
 * @tags maintainability
 */
import python
from IfStmt s
where s.getThen().isPass()
select s, "Redundant 'if ...: pass' statement."
