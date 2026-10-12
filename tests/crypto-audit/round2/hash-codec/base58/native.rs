#[path="candidate.rs"]
mod candidate;
fn unhex(s:&str)->Vec<u8>{s.as_bytes().chunks_exact(2).map(|p|u8::from_str_radix(std::str::from_utf8(p).unwrap(),16).unwrap()).collect()}
fn invoke(decode:bool,input:&[u8],capacity:usize,offset:usize,expected:i64,bytes:Option<&[u8]>) {
 let mut source=vec![0x3d;input.len()+offset+32];source[offset..offset+input.len()].copy_from_slice(input);let original=source.clone();
 let mut output=vec![0xa5;capacity+offset+32];
 let status=unsafe {if decode {candidate::base58_decode(source.as_ptr().add(offset),input.len(),output.as_mut_ptr().add(offset),capacity)} else {candidate::base58_encode(source.as_ptr().add(offset),input.len(),output.as_mut_ptr().add(offset),capacity)}};
 assert_eq!(status,expected,"decode={decode} offset={offset} cap={capacity} inputlen={}",input.len()); assert_eq!(source,original);
 assert!(output[..offset].iter().chain(output[offset+capacity..].iter()).all(|&b|b==0xa5));
 if let Some(bytes)=bytes {assert_eq!(&output[offset..offset+bytes.len()],bytes);assert!(output[offset+bytes.len()..offset+capacity].iter().all(|&b|b==0));}
}
#[test] fn independent_python_bigint_oracle() {
 for line in include_str!("vectors.tsv").lines(){let(a,b)=line.split_once('\t').unwrap();let raw=unhex(a);let text=unhex(b);
  for offset in 0..16 {invoke(false,&raw,raw.len()*138/100+1,offset,text.len() as i64,Some(&text));invoke(true,&text,raw.len()+3,offset,raw.len() as i64,Some(&raw));}
  if !raw.is_empty(){invoke(true,&text,raw.len()-1,3,-1,None);}
  invoke(false,&raw,raw.len()*138/100,1,-1,None);
 }
}
#[test] fn malformed_size_and_capacity_precedence(){
 let alphabet=b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
 for bad in 0..=255u8 {if !alphabet.contains(&bad){for n in [0,1,9,10,11,5652] {let mut text=vec![b'z';n+1];text[n]=bad;for cap in [0,1,4096,4097]{invoke(true,&text,cap,5,-2-n as i64,None);}}}}
 for text in [vec![b'0';5654],vec![b'1';5654],vec![b'z';5654]]{invoke(true,&text,0,1,-1,None);}
 for cap in [0,1,4095,4096,5000] {invoke(true,&vec![b'1';4097],cap,7,-1,None);invoke(true,&vec![b'z';5653],cap,7,-1,None);}
 invoke(false,&vec![0;4097],6000,1,-1,None);
}
#[cfg(target_os="linux")]
unsafe extern "C" {fn mmap(addr:*mut std::ffi::c_void,len:usize,prot:i32,flags:i32,fd:i32,off:isize)->*mut std::ffi::c_void;fn mprotect(addr:*mut std::ffi::c_void,len:usize,prot:i32)->i32;fn munmap(addr:*mut std::ffi::c_void,len:usize)->i32;}
#[cfg(target_os="linux")]
#[test] fn protected_page_edges(){unsafe {
 let size=16384;let source=mmap(std::ptr::null_mut(),size,3,0x22,-1,0)as*mut u8;let dest=mmap(std::ptr::null_mut(),size,3,0x22,-1,0)as*mut u8;assert_ne!(source as isize,-1);assert_ne!(dest as isize,-1);
 assert_eq!(mprotect(source.add(12288).cast(),4096,0),0);assert_eq!(mprotect(dest.add(12288).cast(),4096,0),0);
 for line in include_str!("vectors.tsv").lines().step_by(13){let(a,b)=line.split_once('\t').unwrap();let raw=unhex(a);let text=unhex(b);
  for decode in [false,true]{let input=if decode{&text}else{&raw};let result=if decode{&raw}else{&text};let capacity=if decode{result.len()}else{raw.len()*138/100+1};let ip=source.add(12288-input.len());let op=dest.add(12288-capacity);std::ptr::copy_nonoverlapping(input.as_ptr(),ip,input.len());assert_eq!(mprotect(source.cast(),12288,1),0);std::ptr::write_bytes(op,0xa5,capacity);
   let status=if decode{candidate::base58_decode(ip,input.len(),op,capacity)}else{candidate::base58_encode(ip,input.len(),op,capacity)};assert_eq!(status,result.len()as i64);assert_eq!(std::slice::from_raw_parts(op,result.len()),result);assert_eq!(mprotect(source.cast(),12288,3),0);
  }
 }
 assert_eq!(munmap(source.cast(),size),0);assert_eq!(munmap(dest.cast(),size),0);
}}
