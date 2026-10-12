//! Independent audit of the exported byte-buffer ABI. Expected digest bytes
//! come from upstream BLAKE3 vectors or Python's OpenSSL-backed hashlib;
//! conversions use a deliberately different bit-string model.
#![allow(dead_code)]

#[path = "../../../plugins/blake3/runtime/src/lib.rs"]
mod blake3_runtime;
#[path = "../../../plugins/sha512/runtime/src/lib.rs"]
mod sha512_runtime;
#[path = "../../../plugins/ripemd160/runtime/src/lib.rs"]
mod ripemd160_runtime;
#[path = "../../../plugins/bech32/runtime/src/lib.rs"]
mod bech32_runtime;
#[path = "../../../plugins/base58/runtime/src/lib.rs"]
mod base58_runtime;
#[path = "../../../plugins/hmac-sha2/runtime/src/lib.rs"]
mod hmac_runtime;

fn unhex(s: &str) -> Vec<u8> {
    s.as_bytes().chunks_exact(2).map(|pair| {
        let text = core::str::from_utf8(pair).unwrap();
        u8::from_str_radix(text, 16).unwrap()
    }).collect()
}
fn guarded<F: FnOnce(*mut u8) -> u64>(len: usize, f: F) -> (u64, Vec<u8>) {
    let mut output = vec![0xa5; len + 34];
    let status = f(unsafe { output.as_mut_ptr().add(17) });
    assert!(output[..17].iter().all(|&b| b == 0xa5));
    assert!(output[len + 17..].iter().all(|&b| b == 0xa5));
    (status, output[17..len + 17].to_vec())
}
fn sha_init(size: usize) -> Vec<u8> {
    guarded(216, |out| unsafe {
        if size == 48 { sha512_runtime::sha512_init384(out) }
        else { sha512_runtime::sha512_init(out) };
        1
    }).1
}
fn sha_update(state: &[u8], input: &[u8]) -> (u64, Vec<u8>) {
    guarded(216, |out| unsafe {
        sha512_runtime::sha512_update(state.as_ptr(), state.len(), input.as_ptr(), input.len(), out) as u64
    })
}
fn sha_sum(state: &[u8], size: usize) -> (u64, Vec<u8>) {
    guarded(size, |out| unsafe {
        if size == 48 { sha512_runtime::sha512_sum384(state.as_ptr(), state.len(), out) as u64 }
        else { sha512_runtime::sha512_sum(state.as_ptr(), state.len(), out) as u64 }
    })
}
fn ripe_init() -> Vec<u8> {
    guarded(104, |out| unsafe { ripemd160_runtime::ripemd160_init(out); 1 }).1
}
fn ripe_update(state: &[u8], input: &[u8]) -> (u64, Vec<u8>) {
    guarded(104, |out| unsafe {
        ripemd160_runtime::ripemd160_update(state.as_ptr(), state.len(), input.as_ptr(), input.len(), out) as u64
    })
}
fn ripe_sum(state: &[u8]) -> (u64, Vec<u8>) {
    guarded(20, |out| unsafe {
        ripemd160_runtime::ripemd160_finalize(state.as_ptr(), state.len(), out) as u64
    })
}

#[test]
fn audit_openssl_hash_vectors_and_immutable_streaming() {
    for line in include_str!("openssl-hash-vectors.tsv").lines() {
        let parts: Vec<_> = line.split('\t').collect();
        let name = parts[0];
        let len: usize = parts[1].parse().unwrap();
        let input: Vec<u8> = (0..len).map(|i| (i * 29 + 157) as u8).collect();
        let saved = input.clone();
        let expected = unhex(parts[2]);
        let size = expected.len();
        let digest = guarded(size, |out| unsafe {
            match name {
                "sha384" => sha512_runtime::sha512_digest384(input.as_ptr(), input.len(), out),
                "sha512" => sha512_runtime::sha512_digest(input.as_ptr(), input.len(), out),
                _ => ripemd160_runtime::ripemd160_digest(input.as_ptr(), input.len(), out),
            };
            1
        }).1;
        assert_eq!(digest, expected, "{name}, len={len}, one-shot");
        for stride in [1, 13, 55, 63, 64, 111, 127, 128, 129, 1021] {
            let mut state = if size == 20 { ripe_init() } else { sha_init(size) };
            for chunk in input.chunks(stride) {
                let previous = state.clone();
                let (ok, next) = if size == 20 { ripe_update(&state, chunk) } else { sha_update(&state, chunk) };
                assert_eq!(ok, 1);
                assert_eq!(state, previous);
                state = next;
            }
            let before = state.clone();
            let (ok, actual) = if size == 20 { ripe_sum(&state) } else { sha_sum(&state, size) };
            assert_eq!(ok, 1);
            assert_eq!(actual, expected, "{name}, len={len}, stride={stride}");
            assert_eq!(state, before);
            let (ok, next) = if size == 20 { ripe_update(&state, &[]) } else { sha_update(&state, &[]) };
            assert_eq!(ok, 1);
            assert_eq!(next, state);
        }
        assert_eq!(input, saved);
    }
}

#[test]
fn audit_hash_malformed_states_leave_abi_usable() {
    for size in [20, 48, 64] {
        let initial = if size == 20 { ripe_init() } else { sha_init(size) };
        let offsets: &[usize] = if size == 20 { &[0, 3, 4, 7, 15, 36, 39, 40, 103] }
            else { &[0, 3, 4, 5, 7, 72, 88, 215] };
        let mut bads = vec![vec![], vec![0; initial.len()], initial[..initial.len()-1].to_vec()];
        let mut long = initial.clone(); long.push(0); bads.push(long);
        for &offset in offsets {
            let mut malformed = initial.clone(); malformed[offset] ^= 0xff; bads.push(malformed);
        }
        for bad in bads {
            let (ok, out) = if size == 20 { ripe_update(&bad, b"abc") } else { sha_update(&bad, b"abc") };
            assert_eq!(ok, 0);
            assert!(out.iter().all(|&b| b == 0));
            let (ok, out) = if size == 20 { ripe_sum(&bad) } else { sha_sum(&bad, size) };
            assert_eq!(ok, 0);
            assert!(out.iter().all(|&b| b == 0));
            let (ok, next) = if size == 20 { ripe_update(&initial, b"abc") } else { sha_update(&initial, b"abc") };
            assert_eq!(ok, 1);
            assert_eq!(next.len(), initial.len());
        }
        if size != 20 {
            assert_eq!(sha_sum(&initial, if size == 48 { 64 } else { 48 }).0, 0);
        }
    }
}

#[test]
fn audit_sha_short_states_require_matching_iv() {
    for size in [48,64] {
        let initial=sha_init(size);
        for offset in 8..72 {
            let mut bad=initial.clone(); bad[offset]^=1;
            assert_eq!(sha_update(&bad,b"x").0,0,"size={size},offset={offset}");
            assert_eq!(sha_sum(&bad,size).0,0);
        }
        let mut bad=initial.clone(); bad[4]=if size==48 {64} else {48};
        assert_eq!(sha_update(&bad,b"").0,0);
    }
}

#[test]
fn audit_hash_length_limits_preserve_original_state() {
    for size in [20, 48, 64] {
        let mut maximal = if size == 20 { ripe_init() } else { sha_init(size) };
        if size == 20 {
            maximal[8..16].copy_from_slice(&((1u64 << 61) - 1).to_le_bytes());
        } else {
            maximal[72..88].copy_from_slice(&((1u128 << 125) - 1).to_be_bytes());
        }
        let saved = maximal.clone();
        let (ok, same) = if size == 20 { ripe_update(&maximal, b"") }
            else { sha_update(&maximal, b"") };
        assert_eq!(ok, 1);
        assert_eq!(same, maximal);
        let (ok, rejected) = if size == 20 { ripe_update(&maximal, b"x") }
            else { sha_update(&maximal, b"x") };
        assert_eq!(ok, 0);
        assert!(rejected.iter().all(|&b| b == 0));
        assert_eq!(maximal, saved);
        let (ok, _) = if size == 20 { ripe_sum(&maximal) } else { sha_sum(&maximal, size) };
        assert_eq!(ok, 1);
    }
}

fn hmac_init(bits:usize,key:&[u8])->Vec<u8> {
    guarded(if bits==256 {136}else{272},|out|unsafe{
        if bits==256 {hmac_runtime::hmac_sha256_init(key.as_ptr(),key.len(),out)}
        else {hmac_runtime::hmac_sha512_init(key.as_ptr(),key.len(),out)};0
    }).1
}
fn hmac_update(bits:usize,state:&[u8],input:&[u8])->Vec<u8> {
    guarded(if bits==256 {136}else{272},|out|unsafe{
        if bits==256 {hmac_runtime::hmac_sha256_update(state.as_ptr(),state.len(),input.as_ptr(),input.len(),out)}
        else {hmac_runtime::hmac_sha512_update(state.as_ptr(),state.len(),input.as_ptr(),input.len(),out)};0
    }).1
}
fn hmac_sum(bits:usize,state:&[u8])->Vec<u8> {
    guarded(bits/8,|out|unsafe{
        if bits==256 {hmac_runtime::hmac_sha256_sum(state.as_ptr(),state.len(),out)}
        else {hmac_runtime::hmac_sha512_sum(state.as_ptr(),state.len(),out)};0
    }).1
}
#[test]
fn audit_hmac_openssl_vectors_streaming_prepared_and_reuse() {
    for line in include_str!("openssl-hmac-vectors.tsv").lines() {
        let p:Vec<_>=line.split('\t').collect();
        let bits:usize=if p[0]=="sha256" {256}else{512};
        let key:Vec<_>=(0..p[1].parse::<usize>().unwrap()).map(|i|(i*83+97)as u8).collect();
        let input:Vec<_>=(0..p[2].parse::<usize>().unwrap()).map(|i|(i*29+157)as u8).collect();
        let key_before=key.clone();let input_before=input.clone();let expected=unhex(p[3]);
        let (_,actual)=guarded(bits/8,|out|unsafe{
            if bits==256 {hmac_runtime::hmac_sha256(key.as_ptr(),key.len(),input.as_ptr(),input.len(),out)}
            else {hmac_runtime::hmac_sha512(key.as_ptr(),key.len(),input.as_ptr(),input.len(),out)};0
        });assert_eq!(actual,expected);
        let initial=hmac_init(bits,&key);let saved=initial.clone();
        for _ in 0..2 {
            let (_,actual)=guarded(bits/8,|out|unsafe{
                if bits==256 {hmac_runtime::hmac_sha256_prepared(initial.as_ptr(),initial.len(),input.as_ptr(),input.len(),out)}
                else {hmac_runtime::hmac_sha512_prepared(initial.as_ptr(),initial.len(),input.as_ptr(),input.len(),out)};0
            });assert_eq!(actual,expected);assert_eq!(initial,saved);
        }
        for stride in [1,63,64,127,128,129] {
            let mut state=initial.clone();
            for chunk in input.chunks(stride) {
                let saved=state.clone();let next=hmac_update(bits,&state,chunk);assert_eq!(state,saved);state=next;
            }
            let saved=state.clone();assert_eq!(hmac_sum(bits,&state),expected);assert_eq!(hmac_sum(bits,&state),expected);
            assert_eq!(state,saved);assert_eq!(hmac_update(bits,&state,b""),state);
        }
        assert_eq!(key,key_before);assert_eq!(input,input_before);
    }
}

#[test]
fn audit_base58_bitcoin_vectors_and_malformed_boundaries() {
    for line in include_str!("base58-bitcoin-core.tsv").lines() {
        let (bytes,text)=line.split_once('\t').unwrap();let input=unhex(bytes);
        let saved=input.clone();let cap=input.len()*138/100+1;
        let (size,out)=guarded(cap,|out|unsafe{base58_runtime::base58_encode(input.as_ptr(),input.len(),out,cap)as u64});
        assert_eq!(&out[..size as usize],text.as_bytes());assert_eq!(input,saved);
        let (size,out)=guarded(input.len(),|out|unsafe{base58_runtime::base58_decode(text.as_ptr(),text.len(),out,input.len())as u64});
        assert_eq!(size,input.len()as u64);assert_eq!(out,input);
    }
    for n in [0,1,7,8,31,32,33,78,82,4096] {
        let input=vec![0;n];let cap=n*138/100+1;
        let (size,out)=guarded(cap,|out|unsafe{base58_runtime::base58_encode(input.as_ptr(),n,out,cap)as u64});
        assert_eq!(size,n as u64);assert_eq!(&out[..n],vec![b'1';n]);
    }
    for bad in ["0","O","I","l"," ","\n","é","😀","\0"] {
        let input=format!("123456789{bad}");
        let (code,_)=guarded(64,|out|unsafe{base58_runtime::base58_decode(input.as_ptr(),input.len(),out,64)as u64});
        assert_eq!(code as i64,-11);
    }
    for n in [4097,5653,5654] {
        let input=vec![b'1';n];
        let (code,_)=guarded(4096,|out|unsafe{base58_runtime::base58_decode(input.as_ptr(),n,out,4096)as u64});
        assert_eq!(code as i64,-1);
    }
}

fn b3(op: u64, a: &[u8], b: &[u8], seek: u64, size: usize) -> (u64, Vec<u8>) {
    guarded(size, |out| unsafe {
        // Route the unchanged logical operations through the candidate's
        // dedicated fixed-output native ABI; all independent oracles remain.
        match op {
            0 => { blake3_runtime::blake3_digest(a.as_ptr(), a.len(), out); 0 },
            1 => blake3_runtime::blake3_keyed_hash(a.as_ptr(), a.len(), b.as_ptr(), b.len(), out),
            2 => blake3_runtime::blake3_derive_key(a.as_ptr(), a.len(), b.as_ptr(), b.len(), out),
            _ => blake3_runtime::blake3_run(op, a.as_ptr(), a.len(), b.as_ptr(), b.len(), seek, out, size),
        }
    })
}
#[test]
fn audit_blake3_upstream_vectors_all_modes_and_seek() {
    let key = b"whats the Elvish word for friend";
    let context = b"BLAKE3 2019-12-27 16:29:52 test vectors context";
    for line in include_str!("blake3-official.tsv").lines() {
        let parts: Vec<_> = line.split('\t').collect();
        let n: usize = parts[0].parse().unwrap();
        let input: Vec<_> = (0..n).map(|i| (i % 251) as u8).collect();
        for mode in 0..3 {
            let expected = unhex(parts[mode + 1]);
            let (ok, initial) = match mode { 0 => b3(4,&[],&[],0,2816), 1 => b3(5,key,&[],0,2816), _ => b3(6,context,&[],0,2816) };
            assert_eq!(ok,0);
            for stride in [7, 61, 257, 997, 1024, 1027] {
                let mut state = initial.clone();
                for chunk in input.chunks(stride) {
                    let saved = state.clone();
                    let (ok, next) = b3(7, &state, chunk, 0, 2816);
                    assert_eq!(ok, 0); assert_eq!(state,saved); state=next;
                }
                let saved=state.clone();
                for (seek,size) in [(0,expected.len()),(1,1),(31,33),(63,64),(64,65),(131,0)] {
                    let (ok,out)=b3(8,&state,&[],seek as u64,size);
                    assert_eq!(ok,0);
                    assert_eq!(out, expected[seek..seek+size], "len={n}, mode={mode}, stride={stride}, seek={seek}");
                }
                assert_eq!(state,saved);
                assert_eq!(b3(7,&state,&[],0,2816),(0,state));
            }
        }
    }
}

#[test]
fn audit_blake3_limits_and_canonical_state() {
    let initial = b3(4,&[],&[],0,2816).1;
    for position in [0,4,5,7,8,39,40,47,49,50,51,63,64,1087,1088,2815] {
        let mut bad=initial.clone(); bad[position]=0xff;
        let (code,out)=b3(7,&bad,b"x",0,2816); assert_eq!(code,2,"offset={position}");
        assert!(out.iter().all(|&b|b==0));
        assert_eq!(b3(8,&bad,&[],0,32).0,2);
        assert_eq!(b3(7,&initial,b"x",0,2816).0,0);
    }
    for n in [0,1,31,33,64] { assert_eq!(b3(1,&vec![0;n],b"",0,32).0,1); }
    assert_eq!(b3(3,b"abc",&[],u64::MAX,1).0,5);
    assert_eq!(b3(8,&initial,&[],u64::MAX,0),(0,vec![]));
    assert_ne!(b3(2,b"context one",b"material",0,32).1,b3(2,b"context two",b"material",0,32).1);
    let mut maximal=initial.clone();
    maximal[40..48].copy_from_slice(&((1u64<<54)-1).to_le_bytes());
    maximal[48..50].copy_from_slice(&1023u16.to_le_bytes()); maximal[50]=54;
    assert_eq!(b3(7,&maximal,b"",0,2816).0,0);
    assert_eq!(b3(7,&maximal,b"x",0,2816).0,4);
    maximal[48..50].copy_from_slice(&1024u16.to_le_bytes());
    assert_eq!(b3(8,&maximal,&[],0,32).0,2);
}

fn bitstring_model(input: &[u8], from: usize, to: usize, pad: bool) -> Result<Vec<u8>,i64> {
    if input.iter().any(|&v| usize::from(v) >= 1usize<<from) { return Err(-6); }
    let mut bits: String = input.iter().map(|v|format!("{v:0from$b}")).collect();
    let tail=bits.len()%to;
    if pad && tail!=0 { bits.extend(std::iter::repeat_n('0',to-tail)); }
    if !pad {
        if tail >= from || bits[bits.len()-tail..].contains('1') { return Err(-7); }
        bits.truncate(bits.len()-tail);
    }
    Ok(bits.as_bytes().chunks_exact(to).map(|v| u8::from_str_radix(core::str::from_utf8(v).unwrap(),2).unwrap()).collect())
}
#[test]
fn audit_bech32_conversion_independent_bitstring_model() {
    for from in 1..=8 { for to in 1..=8 { for pad in [false,true] { for n in 0..33 {
        for salt in 0..4 {
            let input:Vec<u8>=(0..n).map(|i|((i*79+salt*47)&((1<<from)-1)) as u8).collect();
            let expected=bitstring_model(&input,from,to,pad);
            let length=unsafe { bech32_runtime::bech32_convert_size(input.as_ptr(),input.len(),from as u64,to as u64,pad as u64) };
            match expected {
                Err(code)=>assert_eq!(length,code,"from={from},to={to},pad={pad},n={n}"),
                Ok(expected)=>{
                    assert_eq!(length,expected.len() as i64);
                    let (_,actual)=guarded(expected.len(),|out| unsafe {
                        bech32_runtime::bech32_convert(input.as_ptr(),input.len(),from as u64,to as u64,pad as u64,out);0
                    });
                    assert_eq!(actual,expected);
                }
            }
        }
    } } } }
}
