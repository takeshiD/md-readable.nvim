# Installation

Lumen ships as a single binary. Pick the method that suits your system.

| Platform | Command                        |
| -------- | ------------------------------ |
| macOS    | `brew install lumen`           |
| Linux    | `nix profile install lumen`    |
| Windows  | `winget install lumen`         |
| Cargo    | `cargo install lumen-cli`      |

## Verify the installation

```sh
lumen --version
# lumen 2.4.0
```

## Shell completion

Lumen can generate completion scripts for bash, zsh and fish:

```sh
lumen completions zsh > ~/.zfunc/_lumen
```
