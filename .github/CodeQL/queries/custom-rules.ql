/**
 * @name Insecure Deserialization in Python
 * @description Detects potentially unsafe deserialization of user input
 * @kind path-problem
 * @problem.severity error
 * @precision high
 * @id py/insecure-deserialization
 * @tags security
 *       external/cwe/cwe-502
 */

import python
import DataFlow::PathGraph

class InsecureDeserializationConfig extends TaintTracking::Configuration {
  InsecureDeserializationConfig() { this = "InsecureDeserializationConfig" }
  
  override predicate isSource(DataFlow::Node source) {
    exists(CallNode call |
      call.getFunction().toString() in ["request.POST", "request.GET", "request.data"] and
      source.asExpr() = call
    )
  }
  
  override predicate isSink(DataFlow::Node sink) {
    exists(CallNode call |
      call.getFunction().toString() in ["pickle.loads", "yaml.load"] and
      sink.asExpr() = call.getArg(0)
    )
  }
}

from InsecureDeserializationConfig config, DataFlow::PathNode source, DataFlow::PathNode sink
where config.hasFlowPath(source, sink)
select sink, source, sink, "Insecure deserialization of user data"
