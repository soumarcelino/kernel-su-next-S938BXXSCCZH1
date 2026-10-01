# SM-S938B / S938BXXSCCZH1 target

This target builds KernelSU Next v3.4.0 as a late-loadable LKM for Samsung firmware **S938BXXSCCZH1**.

## Exact kernel contract

- Model: `SM-S938B`
- Firmware: `S938BXXSCCZH1`
- Kernel: `6.6.98-android15-8-pd6ff1cd-abogkiS938BXXSCCZH1-4k`
- Architecture: `aarch64`, 4 KiB pages
- Toolchain: Android Clang `r510928`
- DDK image digest: `sha256:51159bc935c75a282fc65bc87e02f16bd098d1cdf55dc558c4fdd0fcf7a132e2`

Samsung compatibility is enabled for KDP, RKP, DEFEX and no-patch-text operation. The target kernel adds `android_vendor_data2` to `task_struct`; the build script reproduces that vendor ABI before compiling the module.

## Native shell build

Install standard build tools, Rust/Cargo, `pahole`, `kmod`, Go and Android NDK r28c, then run:

```bash
export ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/28.2.13676358"
./scripts/build-s938b-cczh1.sh
```

Docker and root privileges are not required. The script downloads the pinned DDK OCI filesystem with `crane`, builds the LKM, embeds it in `ksud`, and writes both artifacts plus `SHA256SUMS` to `out/S938BXXSCCZH1/`.

Do not load this module on another model, firmware or kernel release.
