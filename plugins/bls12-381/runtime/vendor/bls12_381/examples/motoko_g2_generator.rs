//! Reproducibly writes the private, nonidentity G2 generator coefficient table.
use bls12_381::{
    plugin_prepared::{write_g2_prepared, G2_PREPARED_BYTES},
    G2Affine,
};
use std::{env, fs, io};

fn main() -> io::Result<()> {
    let paths: Vec<_> = env::args_os().skip(1).collect();
    if paths.len() != 1 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "usage: motoko_g2_generator OUTPUT_PATH",
        ));
    }
    let mut bytes = [0; G2_PREPARED_BYTES];
    assert!(write_g2_prepared(&G2Affine::generator(), &mut bytes));
    fs::write(&paths[0], bytes)
}
