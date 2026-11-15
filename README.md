# Godot ZX Spectrum Emulator (Rust GDExtension)

[![CI](https://github.com/pedrobaratafernandes/godot-zx/actions/workflows/ci.yml/badge.svg)](https://github.com/pedrobaratafernandes/godot-zx/actions/workflows/ci.yml)
[![Docs](https://github.com/pedrobaratafernandes/godot-zx/actions/workflows/deploy_docs.yml/badge.svg)](https://pedrobaratafernandes.github.io/godot-zx/)
[![Release](https://img.shields.io/github/v/release/pedrobaratafernandes/godot-zx?include_prereleases&sort=semver)](https://github.com/pedrobaratafernandes/godot-zx/releases)
[![License: MIT](https://img.shields.io/github/license/pedrobaratafernandes/godot-zx)](LICENSE)
![Godot](https://img.shields.io/badge/Godot-4.7.2-478cbf?logo=godotengine&logoColor=white)
![Rust](https://img.shields.io/badge/Rust-1.97.1-orange?logo=rust)
![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20Linux%20%7C%20Web-informational)

A high-performance ZX Spectrum emulator integrated into Godot 4.7.2 using Rust and GDExtension.

## Documentation
The full documentation is available at:
- [Online Manual (GitHub Pages)](https://pedrobaratafernandes.github.io/godot-zx/)
    - [Build Instructions](docs/en/build.md)
    - [User Guide](docs/en/guide.md)
    - [Keyboard & Controls](docs/en/controls.md)

---

Emulador de ZX Spectrum de alta performance para Godot 4.7.2.

## Documentação
O manual completo está disponível em:
- [Manual Online (GitHub Pages)](https://pedrobaratafernandes.github.io/godot-zx/)
    - [Como Compilar](docs/pt/build.md)
    - [Guia de Uso](docs/pt/guide.md)
    - [Teclado e Controlos](docs/pt/controls.md)

## Quick Start / Início Rápido
- **Linux:** `bash build/linux/build_linux.sh`
- **Windows:** `.\build\win\build_windows.bat`
- **Web (Docker):** `bash build/linux/build_web_docker.sh`

## Credits
- **Engine:** [Godot Engine 4.7](https://godotengine.org/) — MIT license.
- **Rust bindings:** [godot-rust](https://github.com/godot-rust/gdext) (`godot` crate 0.5.5) — MPL-2.0.
- **ZX Spectrum emulator core:** [rustzx](https://github.com/rustzx/rustzx) by Vladislav Nikonov — MIT license. Used as `rustzx-core` / `rustzx-z80` from the [ArjunNair fork](https://github.com/ArjunNair/rustzx), which adds TZX and SZX support.
- **ZX Spectrum ROMs:** © Amstrad plc. The 48K ROM built into `rustzx-core` is distributed under Amstrad's permission for use with emulators; it is not covered by this project's license.
- **On-screen controls icons:** [Input Prompts](https://kenney.nl/assets/input-prompts) by Kenney — CC0 1.0 (public domain). Files in `GodotProject/assets/`.

## License
MIT © Pedro Fernandes — see [LICENSE](LICENSE).

---

## Créditos
- **Motor:** [Godot Engine 4.7](https://godotengine.org/) — licença MIT.
- **Bindings Rust:** [godot-rust](https://github.com/godot-rust/gdext) (crate `godot` 0.5.5) — MPL-2.0.
- **Núcleo do emulador ZX Spectrum:** [rustzx](https://github.com/rustzx/rustzx) de Vladislav Nikonov — licença MIT. Usado como `rustzx-core` / `rustzx-z80` a partir do [fork de ArjunNair](https://github.com/ArjunNair/rustzx), que acrescenta suporte para TZX e SZX.
- **ROMs do ZX Spectrum:** © Amstrad plc. A ROM 48K incluída no `rustzx-core` é distribuída ao abrigo da autorização da Amstrad para uso em emuladores; não está abrangida pela licença deste projecto.
- **Ícones dos controlos no ecrã:** [Input Prompts](https://kenney.nl/assets/input-prompts) de Kenney — CC0 1.0 (domínio público). Ficheiros em `GodotProject/assets/`.

## Licença
MIT © Pedro Fernandes — ver [LICENSE](LICENSE).
