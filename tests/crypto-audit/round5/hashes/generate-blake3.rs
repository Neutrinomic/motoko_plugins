//! Standalone generator: rustc --edition=2024 generate-blake3.rs -o /tmp/generate-blake3
#[path = "blake3_reference.rs"]
mod reference;
fn main() {
    for context in [
        String::new(),
        "a\0b".into(),
        "é".repeat(32),
        "é".repeat(512),
        format!("{}z", "é".repeat(512)),
    ] {
        let mut oracle = reference::Hasher::new_derive_key(&context);
        let input: Vec<_> = (0..4097).map(|i| (i % 251) as u8).collect();
        oracle.update(&input);
        let mut expected = [0; 131];
        oracle.finalize(&mut expected);
        let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();
        println!("{}\t{}", hex(context.as_bytes()), hex(&expected));
    }
}
