# Configuração Standalone

A versão Standalone do projeto foi desenhada para distribuir um único jogo, tornando-a ideal para plataformas como a Steam ou para criar uma versão Web que carrega um jogo específico automaticamente.

## Alterar o Caminho do Jogo (Game Path)

Para alterar qual o jogo que a versão standalone carrega ao iniciar, siga estes passos:

### Visão Geral do Editor

Na imagem abaixo, pode ver a configuração do Editor Godot para a cena Standalone:

![Alterar o caminho do jogo na versão Standalone](../images/change_path_game.png)

**O que vê na imagem:**

1.  **Árvore de Cena (Scene Tree)**: A cena `Main48K_Standalone.tscn` (ou `Main128K_Standalone.tscn`) está aberta.
2.  **Nó Selecionado**: O nó raiz (**Main48K_Standalone**) está selecionado.
3.  **Inspetor (Inspector)**: No painel direito, sob a categoria **Standalone Configuration**, encontra os campos para configurar o jogo.
4.  **Game Path**: Aqui define o caminho para o ficheiro local (ex: `res://games/znake.tap`).

!!! tip
    Certifique-se de que o ficheiro do jogo selecionado está dentro da pasta `res://` do projeto (ex: em `res://games/`) para que seja incluído no executável final.

---

## Web Autoload (Carregamento Dinâmico)

Esta funcionalidade é ideal para a Web, permitindo trocar o jogo no servidor sem precisar de exportar o projeto novamente.

### Estrutura de Ficheiros no Servidor

Como pode ver na imagem abaixo, para o autoload funcionar, o ficheiro do jogo deve estar na mesma pasta que os ficheiros exportados do Godot:

![Files Autoload Project](../images/files_autoload_project.png)

*   **Ficheiro Principal**: O jogo deve chamar-se obrigatoriamente **`autoload.tap`**.
*   **Localização**: Deve estar na raiz do servidor, ao lado do `index.html` e do `index.pck`.
*   **Servidor**: O ficheiro `server.py` deve estar presente para correr o servidor localmente com as permissões corretas.

### Como Ativar no Godot

No Inspetor, pode alternar entre o modo local e o modo web:

![Enable Web Autoload](../images/enable_autoload.png)

1.  **Ativar Web Autoload**: Clique na caixa **Web Autoload**.
2.  **Efeito Automático**: Assim que ativa esta opção, o campo *Game Path* desaparece e é limpo automaticamente. Isto garante que o emulador dará prioridade ao ficheiro `autoload.tap` que encontrar no servidor.

---

## Servidor Web para Testes (Python)

Para que o export Web funcione corretamente, deve usar um servidor web local. Pode usar o código abaixo:

```python
# Guarde como server.py na pasta de exportação
#!/usr/bin/env python3

import argparse
import contextlib
import os
import socket
import subprocess
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path


# See cpython GH-17851 and GH-17864.
class DualStackServer(HTTPServer):
    def server_bind(self):
        # Suppress exception when protocol is IPv4.
        with contextlib.suppress(Exception):
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        return super().server_bind()


class CORSRequestHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()


def shell_open(url):
    if sys.platform == "win32":
        os.startfile(url)
    else:
        opener = "open" if sys.platform == "darwin" else "xdg-open"
        subprocess.call([opener, url])


def serve(root, port, run_browser):
    os.chdir(root)

    address = ("", port)
    httpd = DualStackServer(address, CORSRequestHandler)

    url = f"http://127.0.0.1:{port}"
    if run_browser:
        # Open the served page in the user's default browser.
        print(f"Opening the served URL in the default browser (use `--no-browser` or `-n` to disable this): {url}")
        shell_open(url)
    else:
        print(f"Serving at: {url}")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nKeyboard interrupt received, stopping server.")
    finally:
        # Clean-up server
        httpd.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--port", help="port to listen on", default=8060, type=int)
    parser.add_argument(
        "-r", "--root", help="path to serve as root (relative to `platform/web/`)", default="../../bin", type=Path
    )
    browser_parser = parser.add_mutually_exclusive_group(required=False)
    browser_parser.add_argument(
        "-n", "--no-browser", help="don't open default web browser automatically", dest="browser", action="store_false"
    )
    parser.set_defaults(browser=True)
    args = parser.parse_args()

    # Change to the directory where the script is located,
    # so that the script can be run from any location.
    os.chdir(Path(__file__).resolve().parent)

    serve(args.root, args.port, args.browser)
```

```python
# Exemplo de como iniciar o servidor com uma porta diferente:
python server.py --port 8070 --root .
```

---

## Solução de Problemas: Limpar Cache no Chrome

Se atualizar o ficheiro `autoload.tap` no servidor mas o browser continuar a carregar o jogo antigo, deve forçar a limpeza da cache:

![Empty Cache and Hard Reload](../images/force_clear_cache.png)

1.  Abra o jogo no browser e pressione **F12**.
2.  Com a janela do F12 aberta, clique com o **botão DIREITO** no ícone de **Atualizar/Recarregar**.
3.  Escolha a opção: **"Esvaziar cache e carregamento forçado"** (Empty cache and hard reload).

!!! tip
    Se o problema persistir, mude a porta no comando do servidor: `python server.py --port 8071 --root .`.
