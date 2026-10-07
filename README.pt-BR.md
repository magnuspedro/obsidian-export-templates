# Obsidian Export Templates

[English](README.md) · **Português**

Templates pandoc/LaTeX para exportar notas do Obsidian em PDF com o plugin
[Obsidian Enhancing Export](https://github.com/mokeyish/obsidian-enhancing-export).
O formato das pastas segue o
[obsidian-pandoc-templates](https://github.com/DrLeucine/obsidian-pandoc-templates).

| Template | Para quê |
|---|---|
| [compact-print](compact-print/README.pt-BR.md) | Impressão econômica: A4, margens curtas, tudo em preto, tabelas com larguras automáticas |

## Compatibilidade

| Componente | Versão testada |
|---|---|
| Obsidian Enhancing Export | **1.11.3** (`id: obsidian-enhancing-export`) |
| pandoc | 3.12 |
| TeX | BasicTeX 2026 (`pdflatex`), sem pacotes extras |
| macOS | 26 (Darwin 25.3), vault no iCloud |

O `install.py` edita o `main.js` do plugin procurando dois trechos exatos da versão **1.11.3**: o menu `Latex Template` e o argumento `--template` dos tipos PDF e Latex.

- **Outra versão do plugin:** o script avisa. Se os trechos não baterem, ele não altera nada e diz que o `main.js` tem "formato inesperado". Os links continuam sendo criados, então o tipo de exportação próprio (README de cada template) segue funcionando.
- **Versão do pandoc diferente de 3.x:** o template pode precisar de ajustes (ex.: `\pandocbounded`, introduzido no pandoc 3.2).

## Instalação

```
python3 install.py
```

Depois, recarregue o plugin no Obsidian (desligue e religue em Plugins da comunidade).

Para cada template, o script:

1. cria o link `<vault>/.obsidian/plugins/obsidian-enhancing-export/textemplate/<nome>` → `<repo>/<nome>`;
2. adiciona o template ao menu **PDF → Latex Template** do plugin;
3. faz o plugin rodar o filtro `<nome>.lua` quando esse template é escolhido.

O menu do plugin é fixo no `main.js`, por isso o script edita esse arquivo. O original fica salvo como `main.js.orig`, e `python3 install.py --revert` o restaura.

**Atualizar o plugin apaga o patch**: depois de cada atualização, rode `install.py` de novo. O script é idempotente.

O script acha sozinho o vault no iCloud. Opções: `--plugin <vault>/.obsidian/plugins/obsidian-enhancing-export` quando o vault estiver em outro lugar ou houver mais de um; `--revert` para desfazer.

## Criar um template novo

```
nome-do-template/
├─ nome-do-template.tex   # template pandoc (obrigatório; o nome igual ao da pasta)
├─ nome-do-template.lua   # filtro pandoc (obrigatório; use `return {}` se não precisar)
├─ README.md              # inglês; 1ª linha "# Nome Template" vira o nome no menu
├─ README.pt-BR.md        # versão em português
└─ LICENSE
```

Depois de criar a pasta, rode `python3 install.py` e recarregue o plugin.

Cuidados com o plugin:
- Qualquer saída do pandoc no stderr, inclusive um warning, é tratada como erro de exportação.
- O plugin roda o pandoc a partir da pasta da nota. Por isso, os caminhos usados no template ou no filtro precisam ser absolutos, ou relativos ao arquivo do filtro (`PANDOC_SCRIPT_FILE`).
