# Como Compilar (Build)

## Compilar para Linux
Execute o script a partir da raiz:
```bash
bash build/linux/build_linux.sh
```

## Compilar para Windows
### A partir do Linux
O script irá verificar e instalar automaticamente o "target" do Rust se necessário:
```bash
bash build/linux/build_windows.sh
```
*Nota: Requer o pacote mingw-w64 instalado no seu sistema.*

### A partir do Windows (Nativo)
Se estiver a desenvolver diretamente numa máquina Windows, utilize o ficheiro batch. Ele realiza as mesmas tarefas que o script de Linux (compila e copia a DLL), mas utilizando comandos nativos do Windows:
```batch
.\build\win\build_windows.bat
```

## Compilar para Web (WASM)
Existem duas formas de compilar para a web. O método via Docker é recomendado, pois gere todas as dependências (Emscripten, Rust na versão fixa em `rust-toolchain.toml`) automaticamente.

### Usando Docker (Recomendado)
Este script compila tanto a versão com threads quanto a versão sem threads:
```bash
bash build/linux/build_web_docker.sh
```
*Dica para Linux: Se receber um erro de permissão, certifique-se de que o seu utilizador está no grupo docker para correr sem `sudo`:*
```bash
sudo usermod -aG docker $USER
# Depois faça logout e login novamente.
```

### Compilação Nativa
Requer Emscripten 4.0.20 instalado no sistema (o Rust é instalado automaticamente na versão fixa em `rust-toolchain.toml`):
```bash
bash build/linux/build_web.sh
```

## Testes automáticos
Os testes correm o núcleo do emulador sem abrir o Godot (não é preciso compilar a extensão nem ter o editor):
```bash
cargo test
```
O que é verificado:
- **TAP** (48K e 128K, com e sem fastload): o jogo `znake.tap` fica carregado na memória.
- **TZX** (48K e 128K): o `znake.tap` é convertido para TZX durante o teste e tem de carregar com fastload. Um TZX com bloco turbo tem de tocar em tempo real.
- **Turbo load**: o detetor de fita a tocar cobre o carregamento todo, desliga-se quando a fita acaba ou pára, e quase não atua com fastload.
- **SZX** (48K e 128K, com e sem compressão zlib): o mesmo estado carregado por SNA e por SZX corre de forma idêntica, frame a frame.
- **SNA**: gravar e repor um jogo a correr (é o formato dos save states).
- **Todos os jogos da pasta `GodotProject/games/`**: cada ficheiro `.tap`, `.tzx`, `.sna` ou `.szx` tem de carregar sem erros e mostrar imagem 20 segundos emulados depois de a fita parar. Ficheiros com `128` no nome correm em modo 128K. Para testar um jogo novo basta copiá-lo para essa pasta.

Os testes estão em `src/tests.rs`.
