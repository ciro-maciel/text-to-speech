# Text to Speech by Ciro Cesar Maciel

**Selecione um texto em qualquer app do Mac, aperte um atalho e ouça o texto lido em voz alta.**

Duas vozes: o Rafael, uma voz natural em português do Brasil do [Fish Audio](https://fish.audio), pela internet; ou o [Piper](https://github.com/rhasspy/piper), que roda no seu Mac sem rede nenhuma. Um player pequeno flutua na tela, mostra a palavra que está sendo dita e some quando a leitura acaba. Sem conta, sem telemetria. Um app da barra de menus feito com Tauri e Rust.

[English](README.md)

![Text to Speech: a janela de ajustes, na tela Voz, com o Rafael, o Piper e a velocidade](docs/overview.webp)

## Instalar

```bash
curl -fsSL https://blob.ciromaciel.click/tools/text-to-speech/install.sh | bash
```

O script baixa o `.dmg` mais recente, copia o Text to Speech para `/Applications` e abre o app.

Prefere a imagem de disco? [Baixe o Text-to-Speech-macos.dmg](https://blob.ciromaciel.click/tools/text-to-speech/latest/Text-to-Speech-macos.dmg). Abra e arraste o Text to Speech para Aplicativos. Ele é assinado com Developer ID e notarizado pela Apple, então o macOS abre sem aviso.

O app pede uma permissão, a **Acessibilidade**: ler a seleção manda Cmd + C ao app da frente, e o macOS só deixa um app confiável fazer isso.

## Como funciona

1. Selecione um texto em qualquer lugar: um e-mail, um PDF, uma página, um documento.
2. Aperte **Cmd + Shift + S**. O app copia a seleção, devolve a sua área de transferência como estava e começa a ler.
3. Ouça. O player flutua num canto da tela e fecha quando a leitura acaba.

| Tecla | O que faz |
| --- | --- |
| Cmd + Shift + S | Lê a seleção. Pode ser trocado na janela de ajustes |
| Esc | Para |
| Espaço | Pausa e continua (com o player em foco) |
| Seta esquerda / direita | Volta ou avança uma parte |
| - / + | Mais devagar ou mais rápido |

O texto é lido em partes, em parágrafos inteiros sempre que dá, para a voz não perder o sentido do que lê. A primeira parte é curta, então a voz começa em poucos segundos mesmo num texto longo.

## Privacidade: o que vai para onde

| Voz | Para onde vai o texto |
| --- | --- |
| **Rafael** (padrão) | Cada parte do texto selecionado, e a velocidade, vão por HTTPS ao servidor do Text to Speech (`manager.ciromaciel.click`, o mesmo que a página [ciromaciel.click/tools/text-to-speech](https://ciromaciel.click/tools/text-to-speech?ref=oss-text-to-speech) usa). O servidor manda ao Fish Audio, que gera o áudio, e devolve o MP3 com o tempo de cada palavra. O servidor não guarda o texto. O app não tem nenhuma chave de API |
| **Piper** | Para lugar nenhum. A voz roda no seu Mac. O modelo da voz (cerca de 63 MB) é baixado uma vez do Hugging Face quando você escolhe o Piper |

Nada mais sai do seu Mac: a fonte da interface vem dentro do app, não há analytics, conta nem checagem de atualização. Os ajustes ficam em `~/Library/Application Support/click.ciromaciel.text-to-speech/config.json`.

### Usar o seu próprio servidor

A voz pela internet chama `POST <servidor>/speak-timed` com `{ "text": "...", "speed": 1.0 }` e espera `{ "audio": "<MP3 em base64>", "words": [{ "text", "start", "end" }] }` (`words` pode vir vazio). Para apontar o app para um servidor seu, acrescente uma linha ao `config.json`:

```json
"server_url": "https://seu-servidor.example/text-to-speech"
```

ou defina `TEXT_TO_SPEECH_SERVER` no ambiente do app. Sem nenhum dos dois, o app usa o servidor público.

## Compilar você mesmo

Você precisa das Command Line Tools do Xcode, de [Rust](https://rustup.rs), [Bun](https://bun.sh) e CMake (`brew install cmake`, para o espeak-ng do Piper).

```bash
git clone https://github.com/ciro-maciel/text-to-speech.git
cd text-to-speech
bun install
bun run dev                  # ou: bun run build → /tmp/tts-target/release/bundle
bun test src                 # como um texto vira partes, e o tempo das palavras
```

O build do Rust vai para `/tmp/tts-target` (`src-tauri/.cargo/config.toml`): o espeak-ng, compilado do código para o Piper, falha em caminhos longos.

Para conferir que um build lê em voz alta com as duas vozes, sem janela e sem mexer nos seus ajustes:

```bash
"/tmp/tts-target/release/bundle/macos/Text to Speech.app/Contents/MacOS/text-to-speech" --self-test /tmp/tts-check
afplay /tmp/tts-check/rafael.mp3 && afplay /tmp/tts-check/piper.wav
```

Um build local é assinado ad hoc, então o macOS pede a Acessibilidade de novo a cada build. O build oficial é assinado com Developer ID (`scripts/release/build-mac.sh`).

## Limites

- Publicado para macOS 11 ou mais novo, só em Apple Silicon. O código é Tauri e o lado em Rust compila em outros sistemas, mas ler a seleção está escrito só para o macOS.
- As vozes são em português do Brasil, e a interface está em português por enquanto.
- A voz pela internet depende do servidor público e do Fish Audio; quando um deles está ocupado, uma parte pode falhar. O Piper sempre funciona sem rede.

## Contribuir

Issues e pull requests são bem-vindos. Veja o [CONTRIBUTING.md](CONTRIBUTING.md).

## Licença

[MIT](LICENSE). Piper, espeak-ng, a voz do Piper, Montserrat e os ícones têm as próprias licenças: veja o [NOTICE](NOTICE).

---

Feito por [Ciro Cesar Maciel](https://ciromaciel.click/?ref=oss-text-to-speech). Eu construo ferramentas e mostro como usar: mais [ferramentas grátis](https://ciromaciel.click/tools?ref=oss-text-to-speech) e [a página do Text to Speech](https://ciromaciel.click/tools/text-to-speech?ref=oss-text-to-speech), onde a mesma voz lê qualquer texto no navegador.

**Quer o próximo?** [Siga @ciro-maciel](https://github.com/ciro-maciel) para as próximas ferramentas abertas, e clique em **Watch → Custom → Releases** aqui em cima para saber de cada versão nova.
