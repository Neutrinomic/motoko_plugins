    #[test]
    fn actual_large_error_path_allocation() {
        for suffix in ["", "\\u0078"] {
            let input = Box::leak(format!("{{\"{}{suffix}\":truX}}", "x".repeat(256*1024)).into_boxed_str());
            let mut c = context(input);
            let allocated = allocated_by(|| c.skip());
            let e = c.error.unwrap();
            assert_eq!(e.kind, "type");
            assert!(e.path.starts_with("/x"));
            eprintln!("suffix={suffix:?} input_bytes={} allocated_bytes={allocated} path_bytes={}",input.len(),e.path.len());
        }
    }
