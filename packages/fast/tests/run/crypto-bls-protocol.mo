//MOC-FLAG --package fast ../../src --plugin ../../../../dist/bls12-381 --sanity-checks
import Suite "../bls/ProtocolSuite";
Suite.icDomains();
Suite.ethereumDomains();
Suite.proofDomains();
Suite.dstBoundaries();
