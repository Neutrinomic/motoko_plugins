//MOC-FLAG --package fast ../../src --package core ../../.mops/core@2.5.0/src --plugin ../../../../dist/ed25519 --sanity-checks
import Suite "../ed25519/PreparedSuite";
Suite.vectors(0, 5);
Suite.vectors(5, 15);
Suite.malformed();
Suite.aliasesAndImmutability();
