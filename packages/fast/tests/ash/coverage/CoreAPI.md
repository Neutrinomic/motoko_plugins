# Core container API compatibility

`CoreAPI.mo` is compiled twice without source changes. Its `containers` package
points to Core 2.5.0 in the reference canister and Fast in the plugin canister.
The six methods therefore produce twelve Ash checks.

| Method suffix | Contract |
| --- | --- |
| `mutable_map_implicit_api` | `toMap`, point operations, iteration, transforms, comparison, exact text; omitted Nat/Nat64 comparators, equality, and formatters. |
| `pure_map_implicit_api_and_parameter_order` | Persistent versions, `toMap`, Core argument order for `filter`, `filterMap`, `equal`, and `compare`; implicit calls and exact text. |
| `mutable_set_implicit_api` | Point and bulk operations, seek, algebra, projection, exact text, and implicit callbacks. |
| `pure_set_implicit_api` | Persistent operations, algebra, transforms, exact text, and implicit callbacks. |
| `core_conversion_types_and_payload_sharing` | Mutable conversions accept/return Core pure types; bindings are independent and record payloads remain shared. |
| `explicit_custom_comparators_keep_their_behavior` | Effectful descending comparators still execute in all four containers; generic forwarding preserves ordering and effects. |

The dedicated module suites cover the remaining operations and larger inputs.
This fixture checks function API compatibility, not representation identity or
automatic migration of stable data.
