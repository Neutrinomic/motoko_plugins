//! Independent protected-factory and consumer checks through the native ABI.
#![allow(dead_code)]
#[path = "../../../../plugins/bls12-381/runtime/src/lib.rs"]
mod runtime;

fn hex(value: &str) -> Vec<u8> {
    value.as_bytes().chunks_exact(2).map(|b| u8::from_str_radix(core::str::from_utf8(b).unwrap(), 16).unwrap()).collect()
}
fn pool() -> Vec<Vec<u8>> { include_str!("blobs.tsv").lines().map(hex).collect() }
fn guarded(value: &[u8]) -> Vec<u8> {
    let mut result = vec![0x51; 17];
    result.extend_from_slice(value);
    result.extend_from_slice(&[0xa3; 19]);
    result
}
fn call(op: u32, args: [&[u8]; 3], size: usize, fill: u8) -> (u32, Vec<u8>) {
    let inputs: Vec<_> = args.iter().map(|x| guarded(x)).collect();
    let saved = inputs.clone();
    let mut output = vec![fill; size + 36];
    let code = unsafe {
        runtime::bls_call(op,
            inputs[0].as_ptr().add(17), args[0].len(),
            inputs[1].as_ptr().add(17), args[1].len(),
            inputs[2].as_ptr().add(17), args[2].len(),
            output.as_mut_ptr().add(17))
    };
    assert_eq!(inputs, saved, "immutable inputs, op {op}");
    assert_eq!(&output[..17], &[fill; 17], "output prefix, op {op}");
    assert_eq!(&output[17+size..], &[fill; 19], "output suffix, op {op}");
    if code != 0 { assert!(output.iter().all(|b| *b == fill), "failed operation modified output, op {op}"); }
    (code, output[17..17+size].to_vec())
}
fn keys(pool: &[Vec<u8>]) -> Vec<[Vec<u8>; 6]> {
    include_str!("key-indices.tsv").lines().map(|line| {
        let ids: Vec<usize> = line.split('\t').map(|x| x.parse().unwrap()).collect();
        let ic = &pool[ids[0]]; let eth = &pool[ids[1]]; let proof = &pool[ids[2]];
        let (a, prepared_ic) = call(22, [ic, &[], &[]], 19680, 0x65);
        let (b, prepared_eth) = call(23, [eth, &[], &[]], 144, 0x65);
        let (c, prepared_pop) = call(24, [eth, proof, &[]], 144, 0x65);
        assert_eq!((a,b,c), (0,0,0));
        [ic.clone(), eth.clone(), proof.clone(), prepared_ic, prepared_eth, prepared_pop]
    }).collect()
}

#[test]
fn audit_prepared_factories_guarded_and_fully_initialized() {
    let pool = pool(); let mut count = 0;
    for line in include_str!("factories.tsv").lines() {
        let f: Vec<_> = line.split('\t').collect(); let op: u32 = f[1].parse().unwrap();
        let key = &pool[f[2].parse::<usize>().unwrap()]; let proof = &pool[f[3].parse::<usize>().unwrap()];
        let expected: u32 = f[4].parse().unwrap(); let size = if op==22 {19680} else {144};
        let (code, output) = call(op, [key, proof, &[]], size, 0x25);
        assert_eq!(code, expected, "{}", f[0]);
        if code == 0 {
            let (again, output2) = call(op, [key, proof, &[]], size, 0xda);
            assert_eq!(again, 0); assert_eq!(output, output2, "uninitialized/nondeterministic bytes: {}", f[0]);
            assert_eq!(&output[..key.len()], key, "canonical bytes {}", f[0]);
        }
        count += 1;
    }
    eprintln!("prepared factory cases: {count}");
}

#[test]
fn audit_prepared_single_signatures_and_direct_parity() {
    let pool = pool(); let keys = keys(&pool); let mut count = 0;
    for line in include_str!("singles.tsv").lines() {
        let f: Vec<_> = line.split('\t').collect(); let op: u32 = f[1].parse().unwrap();
        let key = &keys[f[2].parse::<usize>().unwrap()];
        let message = &pool[f[3].parse::<usize>().unwrap()]; let signature = &pool[f[4].parse::<usize>().unwrap()];
        let status: u32 = f[5].parse().unwrap(); let value: u8 = f[6].parse().unwrap();
        let result = call(op, [&key[if op==25 {3} else {4}], message, signature], 1, 0x6d);
        assert_eq!(result.0, status, "{}", f[0]);
        if status==0 { assert_eq!(result.1, [value], "{}", f[0]); }
        let direct = call(if op==25 {14} else {15}, [&key[if op==25 {0} else {1}], message, signature], 1, 0x6d);
        assert_eq!(result, direct, "direct parity {}", f[0]);
        count += 1;
    }
    eprintln!("prepared single cases: {count}");
}

fn aggregate(op: u32, inputs: &[[&[u8]; 3]], signature: &[u8]) -> (u32, u8) {
    let payloads: Vec<_> = inputs.iter().flat_map(|r| r.iter().map(|b| guarded(b))).collect();
    let saved = payloads.clone(); let mut rows = vec![0x73; 3];
    for bytes in &payloads {
        rows.extend_from_slice(&(unsafe {bytes.as_ptr().add(17)} as usize).to_ne_bytes());
        rows.extend_from_slice(&(bytes.len()-36).to_ne_bytes());
    }
    rows.extend_from_slice(&[0x73; 7]); let saved_rows = rows.clone();
    let signature = guarded(signature); let saved_signature = signature.clone();
    let mut out = [0x59; 37];
    let status = unsafe { runtime::bls_aggregate(op, rows.as_ptr().add(3).cast(), inputs.len(),
        signature.as_ptr().add(17), signature.len()-36, out.as_mut_ptr().add(17)) };
    assert_eq!(payloads, saved); assert_eq!(rows, saved_rows); assert_eq!(signature, saved_signature);
    let value = out[17]; if status==0 {out[17]=0x59;}
    assert_eq!(out, [0x59; 37], "aggregate bounds/error mutation, op {op}");
    (status, value)
}

#[test]
fn audit_prepared_aggregates_and_direct_parity() {
    let pool = pool(); let keys = keys(&pool); let mut count = 0;
    for line in include_str!("aggregates.tsv").lines() {
        let f: Vec<_> = line.split('\t').collect(); let op: u32 = f[1].parse().unwrap();
        let ids: Vec<usize> = f[2].split(';').map(|x| x.parse().unwrap()).collect();
        let messages: Vec<&[u8]> = f[3].split(';').map(|x| &pool[x.parse::<usize>().unwrap()][..]).collect();
        let signature = &pool[f[4].parse::<usize>().unwrap()];
        let prepared: Vec<[&[u8]; 3]> = ids.iter().zip(&messages).map(|(id,m)| [&keys[*id][if op==27 {3} else {5}][..], &[][..], *m]).collect();
        let result = aggregate(op, &prepared, signature);
        assert_eq!(result.0, f[5].parse::<u32>().unwrap(), "{}", f[0]);
        if result.0==0 {assert_eq!(result.1, f[6].parse::<u8>().unwrap(), "{}", f[0]);}
        let direct: Vec<[&[u8]; 3]> = ids.iter().zip(&messages).map(|(id,m)| [&keys[*id][if op==27 {0} else {1}][..], if op==27 {&[][..]} else {&keys[*id][2][..]}, *m]).collect();
        assert_eq!(result, aggregate(op-8, &direct, signature), "direct parity {}", f[0]);
        count += 1;
    }
    eprintln!("prepared aggregate cases: {count}");
}

#[test]
fn audit_prepared_native_bounds() {
    for (op,count,want) in [(27,0,6),(28,0,6),(29,0,6),(27,128,5),(28,128,5),(29,129,5),(27,usize::MAX,5)] {
        let status = unsafe {runtime::bls_aggregate(op, core::ptr::null(), count, core::ptr::null(), usize::MAX, core::ptr::null_mut())};
        assert_eq!(status, want);
    }
}

#[test]
fn audit_prepared_tables_match_upstream_arithmetic() {
    use bls12_381::{G1Affine, G1Projective, G2Affine, G2Prepared, Scalar};
    use bls12_381::plugin_prepared::{G2PreparedSource, G2_PREPARED_BYTES, multi_miller_loop, write_g2_prepared};
    let mut generator = [0u8; G2_PREPARED_BYTES];
    assert!(write_g2_prepared(&G2Affine::generator(), &mut generator));
    assert_eq!(&generator[..], include_bytes!("../../../../plugins/bls12-381/runtime/vectors/g2-generator-prepared.bin"));
    let pool = pool(); let keys = keys(&pool);
    for key in &keys {
        let point = G2Affine::from_compressed(key[0].as_slice().try_into().unwrap()).unwrap();
        let ordinary = G2Prepared::from(point);
        let mut table = [0u8; G2_PREPARED_BYTES];
        assert!(write_g2_prepared(&point, &mut table));
        assert_eq!(&key[3][96..], &table[..]);
        for scalar in [0u64,1,2,42,43,u64::MAX] {
            let p = G1Affine::from(G1Projective::generator() * Scalar::from(scalar));
            let expected = bls12_381::multi_miller_loop(&[(&p,&ordinary)]).final_exponentiation();
            assert_eq!(multi_miller_loop(&[(&p,G2PreparedSource::TrustedBytes(&table))]).final_exponentiation(), expected);
            let negative = -p;
            assert_eq!(multi_miller_loop(&[(&p,G2PreparedSource::TrustedBytes(&table)),(&negative,G2PreparedSource::Owned(&ordinary))]).final_exponentiation(), bls12_381::Gt::identity());
        }
    }
}
