# Configuração Standalone

A versão Standalone do projeto foi desenhada para distribuir um único jogo, tornando-a ideal para plataformas como a Steam, onde se pretende que o executável inicie diretamente num título específico.

## Alterar o Caminho do Jogo (Game Path)

Para alterar qual o jogo que a versão standalone carrega ao iniciar, siga estes passos:

### Visão Geral

Na imagem abaixo, pode ver a configuração do Editor Godot para a cena Standalone:

![Alterar o caminho do jogo na versão Standalone](../images/change_path_game.png)

**O que vê na imagem:**

1.  **Árvore de Cena (Scene Tree)**: A cena `Main48K_Standalone.tscn` (ou `Main128K_Standalone.tscn`) está aberta.
2.  **Nó Selecionado**: O nó raiz (Main48K_Standalone) da cena está selecionado na árvore de cena.
3.  **Inspetor (Inspector)**: No painel direito, sob a categoria **Standalone Configuration**, encontram-se as propriedades expostas pelo script.
4.  **Game Path**: Este campo contém o caminho para o ficheiro do jogo (ex: `res://games/znake.tap`).

### Instruções Passo-a-Passo

1.  **Abrir a Cena**: No FileSystem do Godot, navegue até `res://Scenes/Standalone/` e abra `Main48K_Standalone.tscn` ou `Main128K_Standalone.tscn`, dependendo do modelo pretendido.
2.  **Selecionar o Nó Raiz**: Clique no nó do topo na Árvore de Cena (geralmente tem o mesmo nome da cena).
3.  **Localizar Standalone Configuration**: Olhe para o separador **Inspector** no lado direito do editor. Encontre a secção intitulada **Standalone Configuration**.
4.  **Modificar o Game Path**:
    *   Pode escrever o caminho diretamente no campo **Game Path**.
    *   Alternativamente, clique no **Ícone de Pasta** ao lado do campo para abrir um navegador de ficheiros e selecionar o seu ficheiro de jogo (`.tap`).
5.  **Guardar a Cena**: Pressione `Ctrl + S` para guardar as alterações.

!!! tip
    Certifique-se de que o ficheiro do jogo selecionado está localizado dentro da pasta `res://` do projeto (idealmente dentro de `res://games/`) para garantir que é exportado corretamente com o projeto.
