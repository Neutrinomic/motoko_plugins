
    // Inserted into a generated copy of the runtime's native-test module.
    // The counter measures cumulative scratch allocations: Wasm's ephemeral
    // allocator cannot reclaim intermediate buffers until a later Motoko GC.
    fn audit_key_allocation(suffix: &str) {
        const DEPTH: usize = 64;
        let input = Box::leak(
            format!(
                "{}{{\"{}{suffix}\":null}}{}",
                "[".repeat(DEPTH),
                "x".repeat(256 * 1024),
                "]".repeat(DEPTH),
            )
            .into_boxed_str(),
        );
        let mut c = context(input);
        let allocated = allocated_by(|| {
            // Follow the generated visitor's repeated count-then-decode
            // descent, rather than merely scanning the outer array once.
            for _ in 0..DEPTH {
                assert!(c.enter());
                assert_eq!(c.array_start(), 1);
            }
            c.skip();
            assert!(c.error.is_none());
        });
        println!("suffix={suffix:?} input_bytes={} allocated_bytes={allocated}", input.len());
        assert!(allocated < 1024 * 1024, "pre-scans allocated {allocated} bytes");
    }

    #[test]
    fn audit_nested_object_keys_allocation() {
        audit_key_allocation("");
    }

    #[test]
    fn audit_nested_escaped_object_keys_allocation() {
        audit_key_allocation("\\u0078");
    }

    #[test]
    fn audit_json_acceptance_python_oracle() {
        let mut cases = 0;
        for line in include_str!("oracle.tsv").lines() {
            let (expected, encoded) = line.split_once('\t').unwrap();
            let input: Vec<u8> = encoded.as_bytes().chunks(2).map(|pair| {
                let digit = |byte: u8| if byte <= b'9' { byte - b'0' } else { byte - b'a' + 10 };
                digit(pair[0]) * 16 + digit(pair[1])
            }).collect();
            let input = Box::leak(input.into_boxed_slice());
            let mut c = Context::new(input);
            c.skip();
            unsafe { json_finish(&mut c as *mut Context as usize); }
            assert_eq!(
                c.error.is_none(), expected == "1",
                "input={:?} kind={:?}", core::str::from_utf8(input),
                c.error.as_ref().map(|error| error.kind),
            );
            cases += 1;
        }
        println!("JSON syntax cases checked: {cases}");
    }
