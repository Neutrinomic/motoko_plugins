//MOC-FLAG --package fast ../../src --package core $MOTOKO_CORE --plugin ../../../../dist/indexed-priority-queue --sanity-checks -A M0236
import Cases "../lib/IndexedPriorityQueueCases";
Cases.scalarOrders();
Cases.genericReferences();
Cases.comparatorCallbacks();
Cases.comparatorRepairTrace();
Cases.comparatorReadConsistency();
Cases.peekPriorityContracts();
Cases.mixedDispatchDuplicates();
