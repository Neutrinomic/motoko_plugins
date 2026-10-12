//MOC-FLAG --package fast ../../src --package core $MOTOKO_CORE --plugin ../../../../dist/secp256k1 --sanity-checks
import Cases "../lib/Secp256k1Tests";

// Run the same public API vectors in the interpreter and compiled Wasm.
// Loading only secp256k1 checks that the module has no hidden plugin dependency.
Cases.pointVectors();
Cases.scalarAndPointErrors();
Cases.ecdsaKnownAnswers();
Cases.ecdsaAndDerErrors();
Cases.schnorrKnownAnswers();
Cases.schnorrErrors();
Cases.evaluationAndAliases();
Cases.retainedResults();
