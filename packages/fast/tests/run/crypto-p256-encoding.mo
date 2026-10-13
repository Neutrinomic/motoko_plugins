//MOC-FLAG --package fast ../../src --package core ../../.mops/core@2.5.0/src --plugin ../../../../dist/p256 --sanity-checks
import Tests "../lib/P256EncodingTests";

Tests.derLengthsAndPadding();
Tests.sec1CanonicalCoordinates();
Tests.sec1TagsAndLengths();
