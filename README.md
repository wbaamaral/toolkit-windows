# WBA Windows Toolkit

Coleção de ferramentas PowerShell para administração, manutenção, diagnóstico, atualização e automação de ambientes Windows.

## Objetivo

O WBA Windows Toolkit reúne scripts PowerShell desenvolvidos para simplificar tarefas rotineiras de administração de sistemas Microsoft Windows.

O foco do projeto é disponibilizar ferramentas seguras, documentadas e reutilizáveis para ambientes corporativos, laboratórios e uso profissional.

As especificações formais do projeto ficam em um repositório separado, sob o diretório `win/` como raiz comum:

- `spec-win-toolkit/` para especificações, ADRs e backlog
- `wba-windows-toolkit/` para scripts operacionais e módulos reutilizáveis

## Características

- Compatível com Windows PowerShell 5.1
- Compatível com PowerShell 7+
- Suporte completo a UTF-8
- Ajuda integrada via parâmetros
- Logs automáticos de execução
- Relatórios padronizados por módulo em `C:\WBA\Relatorios` ou raiz configurada
- Geração de relatórios HTML autocontidos
- Manual HTML local gerado a partir dos comentários dos scripts e funções
- Autoelevação administrativa
- Tratamento de erros
- Estrutura padronizada
- Comentários e documentação incorporados
- Foco em operações conservadoras e seguras
- Ponto único de entrada via `xtudo.ps1` para descoberta rápida de scripts

## Release e publicação

Antes de publicar uma versão, execute o pré-voo anti-LFS:

```bash
bash tools/release-check.sh
```

Esse rito falha se algum arquivo rastreado por Git LFS, como o PDF do manual,
estiver como ponteiro em vez de binário real no working tree. A publicação da
release usa:

```bash
bash tools/publish-release.sh
```

## Uso diário

Para operar o toolkit sem memorizar pastas, use o launcher:

```powershell
.\xtudo.ps1
```

Ele apresenta atalhos rápidos, aceita busca por palavra-chave e executa os scripts
operacionais mais usados sem exigir navegação pela árvore do repositório.

## Funcionalidades Disponíveis

### Manutenção

- Limpeza segura de arquivos temporários
- Limpeza de logs antigos
- Remoção de minidumps
- Limpeza de cache do Windows Update
- Limpeza de cache de miniaturas

### Integridade do Sistema

- SFC /SCANNOW
- DISM RestoreHealth
- DISM StartComponentCleanup

### Atualização

- Windows Update nativo
- Atualização via Chocolatey
- Verificações básicas de atualização

### Otimização

- CompactOS
- Configuração de Page File
- Desativação de hibernação
- Otimização de volumes

### Diagnóstico

- Coleta de informações do sistema
- Verificação de espaço em disco
- Diagnóstico assistido de disco 100% (`HD100`)
- Diagnóstico de driver gráfico, tela preta, DWM, TDR e eventos relacionados
- Teste de conectividade com internet
- Teste direcionado de IP/nome, protocolo e portas
- Relatórios operacionais

### Inventário

- Inventário completo de hardware e software em HTML
- PDF opcional quando houver navegador compatível
- Resumo enxuto de hardware e drivers ativos em TXT, Markdown e JSON
- Dados úteis para comparar versões de drivers antes/depois de intervenção

## Padrões Utilizados

Todos os scripts seguem as seguintes diretrizes:

### UTF-8

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

chcp 65001 | Out-Null
```

### Relatórios

Por padrão, os relatórios são criados em:

```text
C:\WBA\Relatorios\<Modulo>\<timestamp>\
```

Quando o operador informar um diretório por parâmetro, esse caminho tem prioridade para a execução atual. Quando uma
raiz global estiver configurada com `Set-ToolkitReportsRoot`, os scripts devem usar essa raiz antes do padrão
`C:\WBA\Relatorios`.

Exemplo:

```powershell
Import-Module .\modules\WbaToolkit.Core\WbaToolkit.Core.psd1 -Force
Set-ToolkitReportsRoot -Path "D:\Relatorios\WBA"
Get-ToolkitReportsRoot
```

### Identificação do Script

```powershell
$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
```

## Estrutura do Projeto

```text
wba-windows-toolkit/
├── xtudo.ps1
├── scripts/
├── modules/
├── manuais/
├── experimental/
├── tests/
├── docs/
└── LICENSE
```

## Requisitos

- Windows 10 ou superior
- Windows Server 2016 ou superior
- Windows PowerShell 5.1 ou superior
- Permissões administrativas para algumas operações

## Política de Execução

Caso necessário:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

## Licença

Este projeto está licenciado sob a licença MIT.

Consulte o arquivo LICENSE para mais informações.

## Autor

Welyqrson Bastos Amaral

Administrador de Sistemas | Infraestrutura | Automação | PowerShell
