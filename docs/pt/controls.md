# Teclado e Controlos

O emulador utiliza um mapeamento físico rigoroso de 1 para 1 das 40 teclas originais. Para facilitar a organização, o **Input Map do Godot** está ordenado da seguinte forma: **Alfabeto (A-Z)** → **Números (0-9)** → **Teclas Especiais**.

![Layout do Teclado ZX Spectrum](../images/zx_keyboard.jpg)

### Mapeamento de Teclado
| Tecla PC | Tecla Spectrum | Nota |
| :--- | :--- | :--- |
| **Left Shift** | `CAPS SHIFT` | Usado para símbolos de topo e funções secundárias. |
| **Ctrl (Control)** | `SYMBOL SHIFT` | Usado para símbolos a vermelho (ex: `,`, `.`, `;`). |
| **Setas** | `5, 6, 7, 8` | Mapeadas para as teclas de cursor do Spectrum. |
| **Backspace** | `0` (+ Caps Shift) | Mapeado para a função `DELETE` (Shift + 0). |
| **Enter** | `ENTER` | Enter padrão do Spectrum. |
| **Space** | `SPACE` | Barra de espaço padrão. |

**Símbolos Comuns:**
*   **Vírgula (`,`)**: Segurar `Ctrl` + `N`
*   **Ponto (`.`)**: Segurar `Ctrl` + `M`
*   **Ponto e vírgula (`;`)**: Segurar `Ctrl` + `O`
*   **Aspas (`"`)**: Segurar `Ctrl` + `P`

### Periféricos (Joystick e Rato)
*   **Kempston Joystick**: Mapeado para os botões **A** e **B** do comando (Ação: `zx_fire`).
*   **Kempston Mouse**: O **Clique Esquerdo** do rato atua como o botão de tiro principal.
*   **Sinclair Joystick**: Utilize as teclas numéricas (6-0 para a Porta 1, 1-5 para a Porta 2).

---

## Exportação Desktop (Windows / Linux)
1. Vá a **Project > Export** e adicione um preset (Windows Desktop ou Linux/X11).
2. Garanta que a biblioteca nativa está em `bin/` (`godot_zx.dll` para Win, `godot_zx.so` para Linux).
3. Defina a **Main Scene** desejada (Launcher ou Standalone) nas definições do projeto.
4. Exporte o projeto.
    *   **Dica**: Marque a opção **"Embed Pck"** nas definições de exportação para gerar um **único ficheiro executável**, o que é muito mais limpo para distribuição.
