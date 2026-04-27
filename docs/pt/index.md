# Introdução

Um emulador de ZX Spectrum de alta performance integrado no Godot 4.3+ através de Rust e GDExtension. Este projeto foi desenhado para ser modular, focado na estabilidade com ficheiros **.tap** e pronto para distribuição standalone (Steam/Itch.io) com suporte total para Gamepads.

## Índice da Documentação

*   [Como Compilar](build.md)
*   [Guia de Uso e Funcionalidades](guide.md)
*   [Teclado e Controlos](controls.md) (Sistema de alternância de mapeamento de setas)
*   [Configuração Standalone](standalone.md) (Exportação de jogo único)

## Especificações Técnicas

*   **Core**: rustzx-core (Rust)
*   **Ponte Godot**: godot-rust (GDExtension)
*   **Versão do Rust**: 1.95.0
*   **Versão do Godot**: 4.3 ou superior
*   **Formatos Suportados**: Exclusivamente **.tap** (Tape)

## Arquitetura Técnica

O projeto utiliza uma arquitetura híbrida de alto desempenho:

*   **Core (Rust)**: O motor de emulação (`rustzx-core`) corre em Rust, gerindo a CPU Z80, vídeo e som.
*   **GDExtension**: O código é compilado numa biblioteca nativa (`.dll`, `.so` ou `.wasm`) que o Godot carrega como um nó `EmulatorNode`.
*   **Frontend (Godot)**: Gere a interface, inputs (incluindo a alternância de mapeamento de setas) e a saída de áudio via `AudioStreamGenerator`.
