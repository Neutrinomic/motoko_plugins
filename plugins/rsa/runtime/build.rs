use std::{env, fs, path::{Path, PathBuf}, process::Command};
fn run(command: &mut Command) {
    let status = command.status().expect("could not execute RSA C toolchain");
    assert!(status.success(), "RSA C toolchain failed: {command:?}");
}
fn sources(path: &Path, output: &mut Vec<PathBuf>) {
    let mut paths: Vec<_> = fs::read_dir(path).unwrap().map(|p| p.unwrap().path()).collect();
    paths.sort();
    for path in paths {
        if path.is_dir() { sources(&path, output); }
        else if path.extension().is_some_and(|v| v == "c") { output.push(path); }
    }
}
// Nix host wrappers inject flags for the host architecture even with a Wasm
// target. Respect explicit selection, otherwise use their documented original
// compiler path. Non-Nix environments keep the clang found on PATH.
fn wasm_compiler() -> String {
    if let Ok(compiler) = env::var("RSA_CLANG") { return compiler; }
    if let Some(paths) = env::var_os("PATH") {
        for directory in env::split_paths(&paths) {
            let candidate = directory.join("clang");
            if !candidate.is_file() { continue; }
            let candidate = candidate.canonicalize().unwrap_or(candidate);
            if let Some(package) = candidate.parent().and_then(Path::parent) {
                if let Ok(original) = fs::read_to_string(package.join("nix-support/orig-cc")) {
                    let compiler = Path::new(original.trim()).join("bin/clang");
                    if compiler.is_file() { return compiler.to_string_lossy().into_owned(); }
                }
            }
            return candidate.to_string_lossy().into_owned();
        }
    }
    "clang".into()
}
fn main() {
    let wasm = env::var("CARGO_CFG_TARGET_ARCH").unwrap() == "wasm64";
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let compiler = if wasm { wasm_compiler() } else { env::var("CC").unwrap_or_else(|_| "cc".into()) };
    let ar = env::var("RSA_AR").unwrap_or_else(|_| if wasm { "llvm-ar" } else { "ar" }.into());
    println!("cargo:rerun-if-env-changed=RSA_CLANG");
    println!("cargo:rerun-if-env-changed=RSA_AR");
    println!("cargo:rerun-if-env-changed=CC");
    println!("cargo:rerun-if-env-changed=PATH");
    println!("cargo:rerun-if-changed=vendor");
    println!("cargo:rerun-if-changed=shim");
    println!("cargo:rerun-if-changed=src/rsa.c");
    let mut files = vec![PathBuf::from("src/rsa.c")];
    sources(Path::new("vendor/bearssl/src"), &mut files);
    let mut objects = Vec::new();
    for (i, file) in files.iter().enumerate() {
        let object = out.join(format!("rsa-{i}.o"));
        let mut command = Command::new(&compiler);
        command.args(["-std=c99", "-O3", "-fPIC", "-ffunction-sections", "-fdata-sections", "-fno-strict-aliasing", "-fvisibility=hidden",
          "-DBR_MAX_RSA_SIZE=3072", "-DBR_MAX_RSA_FACTOR=1536", "-Ivendor/bearssl/inc", "-Ivendor/bearssl/src"]);
        if wasm { command.args(["--target=wasm64-unknown-unknown", "-ffreestanding", "-mbulk-memory", "-mno-multivalue", "-Ishim"]); }
        command.arg("-c").arg(file).arg("-o").arg(&object);
        run(&mut command); objects.push(object);
    }
    let library = out.join("libmotoko_rsa_bearssl.a");
    let mut command = Command::new(ar); command.arg("crs").arg(library).args(objects); run(&mut command);
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=motoko_rsa_bearssl");
}
