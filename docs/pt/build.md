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
Existem duas formas de compilar para a web. O método via Docker é recomendado, pois gere todas as dependências (Emscripten, Rust Nightly) automaticamente.

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
Requer Rust Nightly e Emscripten instalados no sistema:
```bash
bash build/linux/build_web.sh
```
