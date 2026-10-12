use super::secp;
#[test]
fn canonical_and_malformed_sec1_fast_paths() {
    let rows: serde_json::Value = serde_json::from_str(include_str!("vectors.json")).unwrap();
    for (index,row) in rows.as_array().unwrap().iter().enumerate() {
        let key=super::bytes(row["key"].as_str().unwrap());
        let saved=key.clone();
        for (op,field,capacity) in [(1,"compressed",33),(2,"uncompressed",65),(12,"x",32)] {
            let mut output=[0xa5;74];
            let result=unsafe { secp::secp256k1_call(op,key.as_ptr(),key.len(),key.as_ptr(),0,key.as_ptr(),0,output.as_mut_ptr().add(1)) };
            if let Some(value)=row[field].as_str() {
                let expected=super::bytes(value);
                assert_eq!(result,expected.len() as i64,"case {index} op {op}");
                assert_eq!(&output[1..1+expected.len()],expected,"case {index} op {op}");
            } else {
                assert_eq!(result,-2,"case {index} op {op}");
                assert!(output[1..1+capacity].iter().all(|&x|x==0));
            }
            assert_eq!(output[0],0xa5);
            assert!(output[1+capacity..].iter().all(|&x|x==0xa5),"overrun case {index} op {op}");
            assert_eq!(key,saved);
        }
    }
}
