//! Independent FFI checks against Python affine/table/RFC6979/BIP340 vectors.
#[cfg(test)]
#[path = "../../../../../../plugins/secp256k1/runtime/src/lib.rs"]
mod runtime;

#[cfg(test)]
mod audit {
    use super::runtime::secp256k1_call;
    fn hex(s: &str) -> Vec<u8> {
        s.as_bytes().chunks_exact(2).map(|p| u8::from_str_radix(core::str::from_utf8(p).unwrap(),16).unwrap()).collect()
    }
    fn call(op: usize, a: &[u8], b: &[u8], c: &[u8], capacity: usize) -> (i64, Vec<u8>) {
        let before=(a.to_vec(),b.to_vec(),c.to_vec());
        let mut guarded=vec![0xA5;capacity+32];
        let out=if capacity==0 {core::ptr::null_mut()} else {unsafe {guarded.as_mut_ptr().add(16)}};
        let status=unsafe {secp256k1_call(op,a.as_ptr(),a.len(),b.as_ptr(),b.len(),c.as_ptr(),c.len(),out)};
        assert_eq!((a,b,c),(&before.0[..],&before.1[..],&before.2[..]),"mutated input op {op}");
        assert!(guarded[..16].iter().all(|x|*x==0xA5));
        assert!(guarded[capacity+16..].iter().all(|x|*x==0xA5));
        (status,guarded[16..capacity+16].to_vec())
    }
    #[test]
    fn independently_encoded_factory_caches_and_signatures() {
        let file=std::env::var("SECP_AUDIT_VECTORS").expect("generated Python oracle vectors");
        let capacity:usize=std::env::var("SECP_AUDIT_CACHE_SIZE").unwrap().parse().unwrap();
        assert!(capacity==64||capacity==512||capacity==1024);
        let data=std::fs::read_to_string(file).unwrap();
        let mut retained=Vec::new();
        for (i,line) in data.lines().enumerate() {
            let f:Vec<Vec<u8>>=line.split('\t').map(hex).collect();
            assert_eq!(f.len(),12);
            let (status,key)=call(17,&f[1],&[],&[],capacity);
            assert_eq!(status,capacity as i64,"factory {i}");
            assert_eq!(key,&f[3][..capacity],"canonical odd table {i}");
            assert_eq!(call(17,&f[2],&[],&[],capacity),(status,key.clone()),"compressed/uncompressed {i}");
            let (status,public)=call(19,&f[4],&[],&[],capacity);
            assert_eq!(status,capacity as i64);
            assert_eq!(public,&f[5][..capacity],"even-Y table {i}");
            let (status,secret)=call(21,&f[0],&[],&[],64);
            assert_eq!(status,64);
            assert_eq!(secret,f[6],"normalized scalar/public-x {i}");
            assert_eq!(call(22,&secret,&f[7],&f[8],64),(64,f[9].clone()),"BIP340 oracle {i}");
            assert_eq!(call(13,&f[0],&f[7],&f[8],64),(64,f[9].clone()),"direct BIP340 oracle {i}");
            assert_eq!(call(20,&public,&f[7],&f[9],0).0,1);
            assert_eq!(call(18,&key,&f[10],&f[11],0).0,1);
            assert_eq!(call(8,&f[1],&f[10],&f[11],0).0,1);
            assert_eq!(call(18,&key,&[],&[],0).0,-4);
            assert_eq!(call(18,&key,&f[10],&[],0).0,-5);
            assert_eq!(call(20,&public,&f[7],&[],0).0,-5);
            assert_eq!(call(22,&secret,&f[7],&[],64),(-6,vec![0;64]));
            let mut wrong=f[9].clone(); wrong[63]^=1;
            assert_eq!(call(20,&public,&f[7],&wrong,0).0,0);
            retained.push((key,public,secret,f));
        }
        assert_eq!(retained.len(),32);
        // Revisiting keys in reverse order detects hidden mutable nonce/key state.
        for (key,public,secret,f) in retained.iter().rev() {
            assert_eq!(call(22,secret,&f[7],&f[8],64),(64,f[9].clone()));
            assert_eq!(call(20,public,&f[7],&f[9],0).0,1);
            assert_eq!(call(18,key,&f[10],&f[11],0).0,1);
        }
        for bad in [&[][..],&[0u8;32][..],&[0xffu8;32][..],&[0u8;31][..],&[0u8;33][..]] {
            assert_eq!(call(21,bad,&[],&[],64),(-1,vec![0;64]));
            assert_eq!(call(17,bad,&[],&[],capacity),(-2,vec![0;capacity]));
            assert_eq!(call(19,bad,&[],&[],capacity),(-2,vec![0;capacity]));
        }
    }
}
