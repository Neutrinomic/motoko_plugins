//MOC-FLAG --package fast ../../src --package core $MOTOKO_CORE --plugin ../../../../dist/indexed-priority-queue --sanity-checks -A M0236
import Cases "../lib/IndexedPriorityQueueCases";
Cases.model(1, 600);
Cases.model(991, 600);
Cases.boundaries();
Cases.handleOwners();
