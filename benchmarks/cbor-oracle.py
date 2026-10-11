#!/usr/bin/env python3
"""Decode one CBOR item with cbor2; normalize byte strings for JSON comparison."""
import base64
from collections.abc import Mapping
import io
import json
import sys

import cbor2


def normalize(value):
    if isinstance(value, bytes):
        return {'$bytes': value.hex()}
    if isinstance(value, Mapping):
        if not all(isinstance(key, str) for key in value):
            raise ValueError('Benchmark maps must have text keys')
        return {key: normalize(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize(child) for child in value]
    return value


data = io.BytesIO(base64.b64decode(sys.stdin.read(), validate=True))
value = cbor2.CBORDecoder(data).decode()
if data.read(1):
    raise ValueError('Trailing bytes after CBOR value')
json.dump(normalize(value), sys.stdout, ensure_ascii=False, allow_nan=False)
