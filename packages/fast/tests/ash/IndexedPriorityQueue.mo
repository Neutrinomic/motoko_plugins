import Test "mo:test";
import Cases "../lib/IndexedPriorityQueueCases";

persistent actor {
  public query func test_array_oracle_seed_one() : async Test.Metrics {Test.test(func() {Cases.model(1, 600)})};
  public query func test_array_oracle_seed_two() : async Test.Metrics {Test.test(func() {Cases.model(991, 600)})};
  public query func test_heap_growth_shrink_boundaries() : async Test.Metrics {Test.test(Cases.boundaries)};
  public query func test_handle_owners_and_staleness() : async Test.Metrics {Test.test(Cases.handleOwners)};
  public query func test_peek_priority_contracts() : async Test.Metrics {Test.test(Cases.peekPriorityContracts)};
  public query func test_scalar_and_custom_orders() : async Test.Metrics {Test.test(Cases.scalarOrders)};
  public query func test_generic_reference_payloads() : async Test.Metrics {Test.test(Cases.genericReferences)};
  public query func test_comparator_repair_trace() : async Test.Metrics {Test.test(Cases.comparatorRepairTrace)};
  public query func test_comparator_handle_reads() : async Test.Metrics {Test.test(Cases.comparatorReadConsistency)};
  public query func test_mixed_dispatch_duplicates() : async Test.Metrics {Test.test(Cases.mixedDispatchDuplicates)};
  public query func test_allocating_nested_comparator() : async Test.Metrics {Test.test(Cases.comparatorCallbacks)};
}
