//! Independently specified aggregate byte-ABI validation and safety checks.
#![allow(dead_code)]
#[path = "../../../../plugins/bls12-381/runtime/src/lib.rs"]
mod runtime;
fn hex(s: &str) -> Vec<u8> {
    assert_eq!(s.len() % 2, 0);
    s.as_bytes().chunks_exact(2).map(|p| u8::from_str_radix(core::str::from_utf8(p).unwrap(),16).unwrap()).collect()
}
#[test]
fn audit_aggregate_guarded_validation_matrix() {
    let pool:Vec<_>=include_str!("blobs.tsv").lines().map(hex).collect();
    let list=|s:&str| -> Vec<usize> {if s.is_empty(){vec![]}else{s.split(';').map(|n|n.parse().unwrap()).collect()}};
    let mut count=0;
    for line in include_str!("cases.tsv").lines() {
        let fields:Vec<_>=line.split('\t').collect();
        let op:u32=fields[1].parse().unwrap();
        let keys=list(fields[2]);let proofs=list(fields[3]);let messages=list(fields[4]);
        let sig:&[u8]=&pool[fields[5].parse::<usize>().unwrap()];
        let mut sources:Vec<Vec<u8>>=vec![];
        for (i,key) in keys.iter().enumerate() {
            for data in [&pool[*key][..],if op==19 {&[][..]} else {&pool[proofs[i]][..]},&pool[messages[i]][..]] {
                let mut guarded=vec![0x35;17];guarded.extend_from_slice(data);guarded.extend_from_slice(&[0xa9;19]);sources.push(guarded);
            }
        }
        let saved=sources.clone();
        // Descriptor base is deliberately unaligned. Payloads are all guarded.
        let mut rows=vec![0xd7;3];
        for s in &sources {
            let len=s.len()-36;
            let pointer=if len==0{0}else{(unsafe{s.as_ptr().add(17)}) as usize};
            rows.extend_from_slice(&pointer.to_ne_bytes());rows.extend_from_slice(&len.to_ne_bytes());
        }
        rows.extend_from_slice(&[0xd7;5]);let saved_rows=rows.clone();
        let mut out=[0xc5;35];let saved_sig=sig.to_vec();
        let status=unsafe{runtime::bls_aggregate(op,rows.as_ptr().add(3).cast(),keys.len(),sig.as_ptr(),sig.len(),out.as_mut_ptr().add(17))};
        assert_eq!(status,fields[6].parse::<u32>().unwrap(),"{}",fields[0]);
        assert_eq!(rows,saved_rows,"descriptor mutation {}",fields[0]);
        assert_eq!(sources,saved,"input mutation {}",fields[0]);assert_eq!(sig,saved_sig);
        if status==0 {
            assert_eq!(out[17],fields[7].parse::<u8>().unwrap(),"{}",fields[0]);
            out[17]=0xc5;
        }
        assert_eq!(out,[0xc5;35],"output bounds / error modified output {}",fields[0]);count+=1;
    }
    eprintln!("independent aggregate ABI cases: {count}");
}
#[test]
fn audit_bounds_fail_before_descriptor_or_output_access() {
    // Invalid op/count is rejected without reading any caller memory.
    for (op,count,want) in [(99,1,10),(19,0,6),(20,0,6),(21,0,6),(19,128,5),(20,128,5),(21,129,5),(19,usize::MAX,5)] {
        let code=unsafe{runtime::bls_aggregate(op,core::ptr::null(),count,core::ptr::null(),usize::MAX,core::ptr::null_mut())};
        assert_eq!(code,want);
    }
}
