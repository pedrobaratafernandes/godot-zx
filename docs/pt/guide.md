# Guia de Uso

## Versões do Projeto
O projeto suporta dois fluxos de trabalho principais:

1. **Versão Launcher (Multi-jogo)**: Utilize `Scenes/Launcher/Launcher.tscn` como cena principal. Permite navegar nos jogos da pasta `Games/`.
2. **Versão Standalone (Jogo único)**: Desenhada para a distribuição de um jogo específico (ex: Steam).
    *   **Configuração**: Veja o guia detalhado de [Configuração Standalone](standalone.md) para instruções sobre como definir o `Game Path` no Inspector.
    *   **Cena Principal**: Para iniciar diretamente no jogo, **deve** definir a cena Standalone como **Main Scene** em `Project > Project Settings > Application > Run`.

## Previews de Jogos (Capas)
Para mostrar uma capa ou screenshot dos teus jogos no Launcher:

1.  Coloca um ficheiro de imagem (**PNG**, **JPG**) ou um ficheiro de ecrã do Spectrum (**SCR**) na pasta `res://games/`.
2.  Garante que a imagem tem o **mesmo nome exato** que o ficheiro do jogo (ex: `manic_miner.tap` e `manic_miner.png`).
3.  O Launcher deteta e mostra a imagem automaticamente quando o jogo é selecionado.

## Componentes Principais

### Emulador (Main48K / Main128K)
Este é o coração do projeto. Integra a biblioteca em Rust para gerir:

- **Renderização de Vídeo**: Converte o buffer de memória do Spectrum numa `Texture2D` do Godot em tempo real.
- **Áudio Dinâmico**: Utiliza o `AudioStreamGenerator` do Godot para processar amostras de som de alta fidelidade geradas pelo core em Rust.
- **Mapeamento de Input**: Traduz as ações de input do Godot (teclado, comando ou rato) para a matriz de teclas clássica do ZX Spectrum e suporta emulação completa de rato via interface Kempston Mouse.

### GameMenu (Overlay)
Uma camada de interface intuitiva que aparece quando o jogo é pausado. Oferece:

- **Gestão de Estados**: Salve ou carregue instantaneamente o progresso do jogo (snapshots).
- **Controlo de Áudio**: Ajuste de volume em tempo real através de sliders.
- **Navegação**: Acesso rápido para retomar o jogo, voltar ao Launcher ou sair da aplicação.

### Configuração do Sistema (Config.gd)
A classe estática centralizada **Config** gere:

- Verificação automática de pastas ao iniciar.
- Caminhos globais para ROMs e Jogos.
- Troca de dados entre o Launcher e o Emulador.

## Funcionalidades Extras
- Gamepad Ready: Todos os menus e o emulador são mapeáveis através do Input Map do Godot.
- Suporte a Rato: Suporte completo para input de rato (emulação Kempston Mouse) em jogos e menus.
- Steam Ready: Estrutura preparada para gerar executáveis únicos (.exe / .x86_64) com um jogo embutido usando a cena Standalone.
- Save States: Sistema de snapshots para salvar e carregar o progresso do jogo instantaneamente.
- Persistência Web: Saves gravados em `user://` (IndexedDB) para não perder o progresso no navegador.
- ROMs Customizadas: Suporte para ficheiros `.rom` via Inspector. Modelos 128K requerem as ROMs de 128K e 48K.
