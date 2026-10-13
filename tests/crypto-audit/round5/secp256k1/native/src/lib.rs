//! Production FFI tests. Rare tests require a disposable, explicitly instrumented hash provider.
#[cfg(test)]
#[path = "../../../../../../plugins/secp256k1/runtime/src/lib.rs"]
mod runtime;

#[cfg(all(test, feature = "injected-hashes"))]
mod rare;

#[cfg(test)]
fn hex(s: &str) -> Vec<u8> {
    s.as_bytes().chunks_exact(2).map(|p| u8::from_str_radix(core::str::from_utf8(p).unwrap(), 16).unwrap()).collect()
}

#[cfg(test)]
fn call(op: usize, a: &[u8], b: &[u8], c: &[u8], capacity: usize) -> (i64, Vec<u8>) {
    let before = (a.to_vec(), b.to_vec(), c.to_vec());
    // Deliberately use an odd byte offset: the ABI promises byte alignment only.
    let mut guarded = vec![0xa5; capacity + 18];
    let output = if capacity == 0 { core::ptr::null_mut() } else { unsafe { guarded.as_mut_ptr().add(9) } };
    let status = unsafe { runtime::secp256k1_call(op, a.as_ptr(), a.len(), b.as_ptr(), b.len(), c.as_ptr(), c.len(), output) };
    assert_eq!((a, b, c), (&before.0[..], &before.1[..], &before.2[..]), "mutated input op {op}");
    assert!(guarded[..9].iter().all(|&b| b == 0xa5), "prefix op {op}");
    assert!(guarded[capacity + 9..].iter().all(|&b| b == 0xa5), "suffix op {op}");
    let bytes = guarded[9..capacity + 9].to_vec();
    if status < 0 { assert!(bytes.iter().all(|&b| b == 0), "error output op {op}"); }
    (status, bytes)
}

#[cfg(all(test, not(feature = "injected-hashes")))]
mod audit;
