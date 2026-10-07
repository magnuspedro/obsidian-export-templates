# Compact Print Template

[English](README.md) · **Português**

## Descrição

Template para **imprimir notas do Obsidian gastando pouco papel** sem perder a legibilidade. Gera PDF via pandoc + pdflatex e compila com o BasicTeX puro, sem pacotes extras.

Numa nota de teste com muitas tabelas, o PDF padrão do Enhancing Export ocupava 12 páginas Letter; com este template, cabe em 3 páginas A4.

O que muda em relação ao PDF padrão:

- A4 com margens de 10–13 mm, Times 10 pt e microtype. O rodapé de uma linha leva o título e "página / total"; não há cabeçalho.
- Não há página de rosto: o título vira uma linha no topo, tirado do YAML `title`, de um único `# H1` no início da nota ou do nome do arquivo.
- Títulos, listas, parágrafos e fórmulas têm espaçamento curto. Uma fórmula `$$…$$` sozinha no parágrafo não abre linha vazia acima.
- **Tabelas:**
  - O filtro Lua escolhe as larguras de coluna que minimizam a altura total da tabela, então colunas curtas (números, IDs) não desperdiçam espaço.
  - O cabeçalho sai em negrito e se repete em cada página, e as linhas são listradas.
  - A fonte é `\small`.
- Uma imagem `![[img.png|200]]` respeita a largura do Obsidian e fica no fluxo do texto, sem virar "Figura 1: 200". As demais imagens ficam limitadas a 45 % da altura da página.
- **Recursos do Obsidian:**
  - callouts `> [!note] Título` viram um bloco com rótulo;
  - `%%comentários%%` não são impressos;
  - `==marcado==` e `~~riscado~~` funcionam mesmo sem o pacote `soul`;
  - `---` vira um fio fino.
- Tudo sai em preto, inclusive títulos, links, rodapé e código (o destaque de sintaxe fica só em negrito e itálico). Só as listras das tabelas são cinza (desligue com `zebra: false`). Para colorir, troque `accent` em `compact-print.tex`.
- O idioma padrão é pt-BR (hifenização, "Sumário"); para trocar, use `lang: en`.
- Nomes de arquivo com acento vindos do macOS/iCloud (Unicode decomposto, NFD) são recompostos (`nfc.lua`); sem isso o pdflatex falha com "Unicode character ̧ (U+0327)".

## Instalação (Obsidian Enhancing Export)

Rode `python3 install.py` na raiz do repositório (veja o [README principal](../README.pt-BR.md)) e recarregue o plugin. O template aparece em **PDF → Latex Template → Compact Print**.

Também é possível criar um tipo de exportação próprio, sem depender do menu (sobrevive a atualizações do plugin):

1. Abra **Configurações → Enhancing Export → Editar modelo de comando → +**.
2. Escolha o modelo **PDF** e dê um nome a ele.
3. Use estes **Argumentos**:

   ```
   -f ${fromFormat}+mark --resource-path="${currentDir}" --resource-path="${attachmentFolderPath}" --lua-filter="${luaDir}/pdf.lua" --lua-filter="${pluginDir}/textemplate/compact-print/compact-print.lua" --template="${pluginDir}/textemplate/compact-print/compact-print.tex" -o "${outputPath}" -t pdf
   ```

Se instalar pacotes extras, o template passa a usá-los sozinho:

- `sudo tlmgr install newtx` → fonte newtx no lugar de mathptmx;
- `sudo tlmgr install soul` → marcação nativa.

Só pandoc no terminal:

```
pandoc nota.md -f markdown+wikilinks_title_after_pipe+mark \
  --lua-filter=compact-print.lua --template=compact-print.tex \
  --pdf-engine=pdflatex -o nota.pdf
```

## YAML opcional

Todos os campos são opcionais. Sem YAML, o título vem do nome do arquivo.

```
---
title: Título que aparece no topo e no rodapé
author: Seu Nome
date: 2026-10-07
lang: pt-BR            # en para notas em inglês
fontsize: 10pt         # 11pt ou 12pt para mais conforto
papersize: a4          # ou letter
geometry: [top=10mm, bottom=13mm, left=12mm, right=12mm, footskip=6mm]
table-fontsize: \small # \footnotesize aperta mais
zebra: false           # tabelas sem listras (economiza tinta)
image-max-height: 0.3  # altura máxima das imagens (fração da página)
toc: true              # sumário compacto em 2 colunas
numbersections: true
footer: false          # sem rodapé
---
```

## Limitações

- O template é feito para `pdflatex`; xelatex/lualatex não foram testados.
- Uma imagem ausente faz o pandoc avisar no stderr, e o Enhancing Export trata isso como erro de exportação (o mesmo vale para o PDF padrão).
- As larguras de coluna são estimadas pelo número de caracteres. Uma célula muito estreita pode quebrar uma linha a mais.
