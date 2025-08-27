/**
 * @name TODO comments in JS/TS
 * @id js/custom/todo-comment
 * @kind problem
 * @problem.severity warning
 * @tags maintainability
 */
import javascript
from Comment c
where c.getText().regexpMatch("(?i)\\bTODO\\b")
select c, "TODO comment found."
