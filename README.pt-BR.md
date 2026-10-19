# Text to Speech by Ciro Cesar Maciel

**Selecione um texto em qualquer app do Mac, aperte um atalho e ouça o texto lido em voz alta.**

Um dos [seis apps de Mac grátis e de código aberto](#mais-de-ciro-cesar-maciel) de [Ciro Cesar Maciel](https://ciromaciel.click/?ref=oss-text-to-speech).

Duas vozes: o Rafael, uma voz natural em português do Brasil do [Fish Audio](https://fish.audio), pela internet; ou o [Piper](https://github.com/rhasspy/piper), que roda no seu Mac sem rede nenhuma. Um player pequeno flutua na tela, mostra a palavra que está sendo dita e some quando a leitura acaba. Sem conta, sem telemetria. Um app da barra de menus feito com Tauri e Rust.

[English](README.md)

![Text to Speech: a janela de ajustes, na tela Voz, com o Rafael, o Piper e a velocidade](docs/overview.pt-BR.webp)

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
- As duas vozes falam português do Brasil: texto em outra língua sai com sotaque. A interface é em inglês e em português do Brasil, seguindo o idioma do Mac.
- A voz pela internet depende do servidor público e do Fish Audio; quando um deles está ocupado, uma parte pode falhar. O Piper sempre funciona sem rede.

## Contribuir

Issues e pull requests são bem-vindos. Veja o [CONTRIBUTING.md](CONTRIBUTING.md).

## Licença

[MIT](LICENSE). Piper, espeak-ng, a voz do Piper, Montserrat e os ícones têm as próprias licenças: veja o [NOTICE](NOTICE).

---

## Mais de Ciro Cesar Maciel

Eu construo software sozinho, com uma equipe de agentes de IA, e abro o que dá para abrir. São seis apps nativos para Mac, todos grátis, MIT, assinados e notarizados pela Apple, em inglês e português do Brasil:

| App | O que faz |
| --- | --- |
| [Cleaner](https://github.com/ciro-maciel/cleaner) | O limpador de Mac que mostra tudo antes de apagar qualquer coisa |
| [Screenshots](https://github.com/ciro-maciel/screenshots) | Captura, anotação e gravação de tela, sem nada sair do Mac |
| [Speech to Text](https://github.com/ciro-maciel/speech-to-text) | Ditado por atalho, com o Whisper rodando no Mac |
| [Assistant](https://github.com/ciro-maciel/voice-assistant) | O Claude Code por voz: chame pelo nome, peça, ouça a resposta |
| [Windows](https://github.com/ciro-maciel/windows) | Janelas no lugar com um atalho ou levando até a borda |
| [Text to Speech](https://github.com/ciro-maciel/text-to-speech) | Selecione um texto em qualquer app e ouça · **este** |

Além dos apps: [ferramentas grátis no navegador](https://ciromaciel.click/tools?ref=oss-text-to-speech), [livros](https://ciromaciel.click/books?ref=oss-text-to-speech) e o [Infrastructure](https://myinfrastructure.click/?ref=oss-text-to-speech), a infraestrutura que os agentes já sabem operar.

**Toda semana, por e-mail:** as [Cartas do Ciro](https://ciromaciel.click/?ref=oss-text-to-speech), o que estou construindo e aprendendo.

**Acompanhe.** [Siga @ciro-maciel](https://github.com/ciro-maciel) para os próximos apps abertos, clique em **Watch → Custom → Releases** aqui em cima para saber de cada versão nova, e veja como tudo é feito no [YouTube](https://www.youtube.com/@ciro-maciel).
