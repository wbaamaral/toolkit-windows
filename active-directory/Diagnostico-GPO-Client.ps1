#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Diagnostico de problemas de aplicacao de GPO em client Windows.
.DESCRIPTION
    Verifica canal seguro, conectividade com DC, status de replicacao SYSVOL,
    GPOs aplicadas, erros no Event Log e gera relatorio HTML do gpresult.
.PARAMETER DomainFQDN
    FQDN do dominio (ex: contoso.local). Se omitido, detecta automaticamente.
.PARAMETER DCName
    Nome do DC preferencial. Se omitido, usa o DC logado atualmente.
.PARAMETER SkipReparo
    Nao oferece opcoes de reparo; executa somente leitura.
.PARAMETER Path
    Raiz de relatorios. Se omitido, usa ReportsRoot persistente ou C:\WBA\Relatorios.
#>

[CmdletBinding()]
param(
    [string]$DomainFQDN  = '',
    [string]$DCName      = '',
    [switch]$SkipReparo,
    [Alias('DiretorioSaida')]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
chcp 65001 | Out-Null

$ToolkitRoot = Split-Path -Parent $PSScriptRoot
$ToolkitModulePath = Join-Path $ToolkitRoot 'modules/WbaToolkit.Core/WbaToolkit.Core.psd1'
Import-Module $ToolkitModulePath -Force -ErrorAction Stop

# ---------------------------------------------------------------------------
# Helpers visuais
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Registro de resultados
# ---------------------------------------------------------------------------
$script:Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    [CmdletBinding()]
    param([string]$Etapa, [string]$Status, [string]$Detalhe)
    $script:Results.Add([PSCustomObject]@{
        DataHora = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Etapa    = $Etapa
        Status   = $Status
        Detalhe  = $Detalhe
    }) | Out-Null
}

# ---------------------------------------------------------------------------
# Confirmacao interativa
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Wrapper para executaveis externos
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Preparacao
# ---------------------------------------------------------------------------
$Timestamp  = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$ReportSession = Initialize-ToolkitReportSession -ReportsRoot $Path -ModuleName 'ActiveDirectory' -ExecutionName $Timestamp
$LogDir     = $ReportSession.LogsPath
$LogFile    = Join-Path $LogDir "DiagGPO-$Timestamp.log"
$HtmlReport = Join-Path $ReportSession.Path "GPOResult-$Timestamp.html"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

Start-Transcript -Path $LogFile -Force | Out-Null

# Detecta dominio e DC se nao fornecidos
if ([string]::IsNullOrWhiteSpace($DomainFQDN)) {
    $DomainFQDN = $env:USERDNSDOMAIN
}
if ([string]::IsNullOrWhiteSpace($DCName)) {
    $nlDC = Invoke-ExternalCommand 'nltest' @("/dsgetdc:$DomainFQDN")
    if ($nlDC.Output -match 'DC:\s*\\\\(\S+)') {
        $DCName = $Matches[1]
    }
}

Write-Title "DIAGNOSTICO DE GPO - $env:COMPUTERNAME"
Write-Info  "Dominio  : $DomainFQDN"
Write-Info  "DC atual : $DCName"
Write-Info  "Log      : $LogFile"
Write-Info  "HTML     : $HtmlReport"

# ===========================================================================
# TESTE 1 — Canal seguro com o dominio
# ===========================================================================
Write-Title 'TESTE 1 — Canal seguro (Secure Channel)'

$sc = Invoke-ExternalCommand 'nltest' @("/sc_query:$DomainFQDN")
Write-Info $sc.Output

if ($sc.Output -match 'LOGON_SERVER\\s*:\\s*\\\\\\\\(\S+)') {
    $dcLogon = $Matches[1]
    Write-Ok "Canal seguro ativo — DC: $dcLogon"
    Add-Result 'Canal seguro' 'OK' "DC: $dcLogon"
} elseif ($sc.Output -match 'ERROR_NO_LOGON_SERVERS|Nenhum|not found|0xc000005e|0xc0000022') {
    Write-Fail 'Canal seguro quebrado ou DC indisponivel'
    Add-Result 'Canal seguro' 'FALHA' $sc.Output

    if (Read-YesNo 'Tentar reparar o canal seguro agora?') {
        Write-Info 'Informe credenciais de Administrador do dominio:'
        $cred = Get-Credential
        $repaired = Test-ComputerSecureChannel -Repair -Credential $cred
        if ($repaired) {
            Write-Ok 'Canal seguro reparado com sucesso'
            Add-Result 'Reparo canal seguro' 'OK' 'Reparado via Test-ComputerSecureChannel'
        } else {
            Write-Fail 'Reparo do canal seguro falhou — verifique conectividade e credenciais'
            Add-Result 'Reparo canal seguro' 'FALHA' 'Test-ComputerSecureChannel retornou False'
        }
    }
} else {
    Write-Warn 'Nao foi possivel determinar o estado do canal seguro'
    Add-Result 'Canal seguro' 'AVISO' $sc.Output
}

# ===========================================================================
# TESTE 2 — Conectividade com o DC (ping + porta 389 LDAP)
# ===========================================================================
Write-Title 'TESTE 2 — Conectividade com o DC'

if (-not [string]::IsNullOrWhiteSpace($DCName)) {
    # Ping
    $ping = Test-Connection -ComputerName $DCName -Count 2 -ErrorAction SilentlyContinue
    if ($ping) {
        $rtt = ($ping | Measure-Object -Property ResponseTime -Average).Average
        Write-Ok "Ping para $DCName — RTT medio: $([math]::Round($rtt,1)) ms"
        Add-Result "Ping DC ($DCName)" 'OK' "RTT medio $([math]::Round($rtt,1)) ms"
    } else {
        Write-Fail "Sem resposta de ping para $DCName"
        Add-Result "Ping DC ($DCName)" 'FALHA' 'Sem resposta ICMP'
    }

    # Porta LDAP 389
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($DCName, 389)
        $tcp.Close()
        Write-Ok "Porta LDAP 389 acessivel em $DCName"
        Add-Result 'Porta LDAP 389' 'OK' "DC: $DCName"
    } catch {
        Write-Fail "Porta LDAP 389 inacessivel em $DCName"
        Add-Result 'Porta LDAP 389' 'FALHA' $_.Exception.Message
    }

    # Porta SMB 445 (necessaria para SYSVOL)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($DCName, 445)
        $tcp.Close()
        Write-Ok "Porta SMB 445 acessivel em $DCName (SYSVOL/NETLOGON)"
        Add-Result 'Porta SMB 445' 'OK' "DC: $DCName"
    } catch {
        Write-Fail "Porta SMB 445 inacessivel em $DCName — GPO nao sera aplicada"
        Add-Result 'Porta SMB 445' 'FALHA' $_.Exception.Message
    }
} else {
    Write-Warn 'DC nao identificado — pulando testes de conectividade'
    Add-Result 'Conectividade DC' 'AVISO' 'DC nao identificado'
}

# ===========================================================================
# TESTE 3 — Acesso ao SYSVOL e NETLOGON
# ===========================================================================
Write-Title 'TESTE 3 — Acesso ao SYSVOL e NETLOGON'

foreach ($share in @('SYSVOL', 'NETLOGON')) {
    if (-not [string]::IsNullOrWhiteSpace($DCName)) {
        $sharePath = "\\$DCName\$share"
    } else {
        $sharePath = "\\$DomainFQDN\$share"
    }

    if (Test-Path $sharePath) {
        Write-Ok "Acesso OK: $sharePath"
        Add-Result "Share $share" 'OK' $sharePath

        $gpoCount = (Get-ChildItem $sharePath -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Info "  Itens em ${share}: $gpoCount"
    } else {
        Write-Fail "Sem acesso: $sharePath — GPOs nao serao aplicadas"
        Add-Result "Share $share" 'FALHA' "Caminho inacessivel: $sharePath"
    }
}

# ===========================================================================
# TESTE 4 — Status do servico WinRM / Client Side Extensions
# ===========================================================================
Write-Title 'TESTE 4 — Servicos essenciais para aplicacao de GPO'

$servicos = @(
    @{ Nome = 'gpsvc';   Descricao = 'Group Policy Client'      },
    @{ Nome = 'Netlogon'; Descricao = 'Netlogon'                },
    @{ Nome = 'Dnscache'; Descricao = 'DNS Client'              },
    @{ Nome = 'W32Time';  Descricao = 'Windows Time (Kerberos)' }
)

foreach ($svc in $servicos) {
    $s = Get-Service -Name $svc.Nome -ErrorAction SilentlyContinue
    if ($null -eq $s) {
        Write-Warn "Servico nao encontrado: $($svc.Nome)"
        Add-Result "Servico $($svc.Descricao)" 'AVISO' 'Servico nao encontrado'
    } elseif ($s.Status -eq 'Running') {
        Write-Ok "$($svc.Descricao) ($($svc.Nome)) — Rodando"
        Add-Result "Servico $($svc.Descricao)" 'OK' 'Running'
    } else {
        Write-Fail "$($svc.Descricao) ($($svc.Nome)) — $($s.Status)"
        Add-Result "Servico $($svc.Descricao)" 'FALHA' $s.Status

        if (Read-YesNo "Iniciar o servico $($svc.Nome) agora?") {
            try {
                Start-Service -Name $svc.Nome -ErrorAction Stop
                Write-Ok "Servico $($svc.Nome) iniciado"
                Add-Result "Iniciar $($svc.Descricao)" 'OK' 'Iniciado via Start-Service'
            } catch {
                Write-Fail "Falha ao iniciar $($svc.Nome): $($_.Exception.Message)"
                Add-Result "Iniciar $($svc.Descricao)" 'FALHA' $_.Exception.Message
            }
        }
    }
}

# ===========================================================================
# TESTE 5 — Sincronizacao de horario (Kerberos depende de NTP)
# ===========================================================================
Write-Title 'TESTE 5 — Sincronizacao de horario (NTP / Kerberos)'

$w32 = Invoke-ExternalCommand 'w32tm' @('/query', '/status')
Write-Info $w32.Output

if (-not [string]::IsNullOrWhiteSpace($DCName)) {
    $timeDiff = Invoke-ExternalCommand 'w32tm' @('/stripchart', "/computer:$DCName", '/samples:3', '/dataonly')
    Write-Info $timeDiff.Output

    # Extrai offset maximo (Kerberos tolera ate 5 minutos)
    $offsets = [regex]::Matches($timeDiff.Output, '[+-]\d+\.\d+s') | ForEach-Object {
        [double]($_.Value -replace 's','')
    }
    if ($offsets.Count -gt 0) {
        $maxOff = ($offsets | Measure-Object -Maximum).Maximum
        if ([math]::Abs($maxOff) -le 300) {
            Write-Ok "Offset de horario: $maxOff s (dentro do limite Kerberos de 300 s)"
            Add-Result 'Sincronizacao NTP' 'OK' "Offset: $maxOff s"
        } else {
            Write-Fail "Offset de horario: $maxOff s — acima de 5 min; Kerberos ira falhar"
            Add-Result 'Sincronizacao NTP' 'FALHA' "Offset: $maxOff s"

            if (Read-YesNo 'Forcar sincronizacao de horario agora?') {
                Invoke-ExternalCommand 'w32tm' @('/resync', '/force') | Out-Null
                Write-Ok 'Sincronizacao forcada executada'
                Add-Result 'Reparo NTP' 'OK' 'w32tm /resync /force'
            }
        }
    } else {
        Write-Warn 'Nao foi possivel calcular o offset de horario'
        Add-Result 'Sincronizacao NTP' 'AVISO' 'Offset nao calculado'
    }
} else {
    Write-Warn 'DC nao identificado — pulando verificacao de offset NTP'
    Add-Result 'Sincronizacao NTP' 'AVISO' 'DC nao identificado'
}

# ===========================================================================
# TESTE 6 — gpresult: GPOs aplicadas e filtradas
# ===========================================================================
Write-Title 'TESTE 6 — GPOs aplicadas (gpresult)'

$gprText = Invoke-ExternalCommand 'gpresult' @('/r', '/scope', 'computer')
Write-Info $gprText.Output
Add-Result 'gpresult /r' 'INFO' ($gprText.Output | Select-Object -First 5 | Out-String)

# Gera relatorio HTML
$gprHtml = Invoke-ExternalCommand 'gpresult' @('/h', $HtmlReport, '/f')
if (Test-Path $HtmlReport) {
    Write-Ok "Relatorio HTML gerado: $HtmlReport"
    Add-Result 'gpresult HTML' 'OK' $HtmlReport
} else {
    Write-Warn "Relatorio HTML nao gerado (ExitCode: $($gprHtml.ExitCode))"
    Add-Result 'gpresult HTML' 'AVISO' $gprHtml.Output
}

# GPOs filtradas por WMI ou seguranca
if ($gprText.Output -match 'filtrada|denied|filtered|WMI') {
    Write-Warn 'GPOs com filtro detectadas — verifique o relatorio HTML para detalhes'
    Add-Result 'GPOs filtradas' 'AVISO' 'Ver relatorio HTML'
}

# ===========================================================================
# TESTE 7 — Event Log: erros de GPO nas ultimas 24h
# ===========================================================================
Write-Title 'TESTE 7 — Eventos de GPO no Event Log (ultimas 24 h)'

$eventIds = @(1085, 1086, 1087, 1088, 1096, 1097, 1098, 1006, 1030, 1058)
$since    = (Get-Date).AddHours(-24)

$events = Get-WinEvent -FilterHashtable @{
    LogName   = 'System', 'Application', 'Microsoft-Windows-GroupPolicy/Operational'
    Id        = $eventIds
    StartTime = $since
} -ErrorAction SilentlyContinue

if ($events) {
    Write-Fail "$($events.Count) evento(s) de erro de GPO nas ultimas 24h:"
    $events | Select-Object TimeCreated, Id, LevelDisplayName,
        @{ N = 'Mensagem'; E = { $_.Message -replace '\r?\n', ' ' | Select-Object -First 1 } } |
        Format-Table -AutoSize -Wrap
    Add-Result 'Eventos GPO' 'FALHA' "$($events.Count) evento(s) de erro encontrado(s)"
} else {
    Write-Ok 'Nenhum evento de erro de GPO nas ultimas 24h'
    Add-Result 'Eventos GPO' 'OK' 'Nenhum erro encontrado'
}

# Eventos especificos de NETLOGON
$netlogonEvt = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = @(5805, 5723, 5722)
    StartTime = $since
} -ErrorAction SilentlyContinue

if ($netlogonEvt) {
    Write-Warn "$($netlogonEvt.Count) evento(s) NETLOGON criticos (canal seguro/autenticacao):"
    $netlogonEvt | Select-Object TimeCreated, Id, Message | Format-Table -AutoSize -Wrap
    Add-Result 'Eventos NETLOGON' 'AVISO' "$($netlogonEvt.Count) evento(s)"
} else {
    Write-Ok 'Nenhum evento critico de NETLOGON nas ultimas 24h'
    Add-Result 'Eventos NETLOGON' 'OK' 'Sem eventos criticos'
}

# ===========================================================================
# TESTE 8 — Forcando gpupdate (opcional)
# ===========================================================================
Write-Title 'TESTE 8 — Atualizar GPO agora (gpupdate /force)'

if (Read-YesNo 'Executar gpupdate /force agora para testar a aplicacao?' $false) {
    Write-Info 'Executando gpupdate /force — aguarde...'
    $gpu = Invoke-ExternalCommand 'gpupdate' @('/force')
    Write-Info $gpu.Output

    if ($gpu.ExitCode -eq 0) {
        Write-Ok 'gpupdate /force concluido com sucesso'
        Add-Result 'gpupdate /force' 'OK' $gpu.Output
    } else {
        Write-Fail "gpupdate /force retornou codigo $($gpu.ExitCode)"
        Add-Result 'gpupdate /force' 'FALHA' $gpu.Output
    }
} else {
    Add-Result 'gpupdate /force' 'IGNORADO' 'Nao executado pelo operador'
}

# ===========================================================================
# TESTE 9 — RSoP: CSEs executadas e GPOs negadas por filtro/seguranca
# ===========================================================================
Write-Title 'TESTE 9 — RSoP (Resultant Set of Policy)'

$RsopXml = Join-Path $LogDir "RSoP-$Timestamp.xml"
$gprXmlResult = Invoke-ExternalCommand 'gpresult' @('/x', $RsopXml, '/scope', 'computer', '/f')

if (Test-Path $RsopXml) {
    try {
        [xml]$rsop = Get-Content $RsopXml -Encoding UTF8 -ErrorAction Stop

        # --- GPOs aplicadas vs negadas ---
        $gpoNodes = $rsop.Rsop.ComputerResults.GPO
        if ($null -ne $gpoNodes) {
            $aplicadas = @($gpoNodes | Where-Object {
                $_.Enabled -eq 'true' -and $_.FilterAllowed -eq 'true' -and $_.AccessDenied -ne 'true'
            })
            $negadas = @($gpoNodes | Where-Object {
                $_.FilterAllowed -eq 'false' -or $_.AccessDenied -eq 'true'
            })

            Write-Ok "GPOs aplicadas ao computador : $($aplicadas.Count)"
            $aplicadas | ForEach-Object { Write-Info "  [APLICADA] $($_.Name)" }

            if ($negadas.Count -gt 0) {
                Write-Warn "GPOs negadas / filtradas     : $($negadas.Count)"
                $negadas | ForEach-Object {
                    $motivo = if ($_.AccessDenied -eq 'true') { 'Sem permissao de leitura' }
                              elseif ($_.FilterAllowed -eq 'false') { 'Filtro WMI ou seguranca' }
                              else { 'Desconhecido' }
                    Write-Warn "  [NEGADA] $($_.Name) — $motivo"
                }
                Add-Result 'RSoP GPOs negadas' 'AVISO' "$($negadas.Count) GPO(s) nao aplicadas — verificar filtros WMI e permissoes ACL"
            } else {
                Add-Result 'RSoP GPOs negadas' 'OK' 'Nenhuma GPO negada'
            }
            Add-Result 'RSoP GPOs aplicadas' 'OK' "$($aplicadas.Count) GPO(s) efetivas"
        } else {
            Write-Warn 'Nenhum node de GPO encontrado no XML do RSoP'
            Add-Result 'RSoP GPOs' 'AVISO' 'Nenhum node GPO no XML'
        }

        # --- CSEs (Client Side Extensions): status de cada extensao ---
        $cseNodes = $rsop.Rsop.ComputerResults.ExtensionStatus
        if ($null -ne $cseNodes) {
            Write-Host ''
            Write-Info 'Status das Client Side Extensions (CSEs):'
            $cseErros = 0
            foreach ($cse in $cseNodes) {
                $nome     = $cse.Name
                $status   = $cse.LastError
                $tempoMs  = $cse.ElapsedTime

                if ($status -eq '0' -or [string]::IsNullOrWhiteSpace($status)) {
                    Write-Ok "  CSE OK: $nome ($tempoMs ms)"
                } else {
                    Write-Fail "  CSE ERRO: $nome — codigo $status"
                    $cseErros++
                }
            }
            if ($cseErros -gt 0) {
                Add-Result 'RSoP CSEs' 'FALHA' "$cseErros CSE(s) com erro — GPOs desse tipo nao foram aplicadas"
            } else {
                Add-Result 'RSoP CSEs' 'OK' "$($cseNodes.Count) CSE(s) sem erros"
            }
        } else {
            Write-Warn 'Nenhuma informacao de CSE no XML (pode nao haver GPOs de computador)'
            Add-Result 'RSoP CSEs' 'AVISO' 'Sem dados de CSE no RSoP'
        }

        Write-Info "Arquivo RSoP XML salvo em: $RsopXml"
    } catch {
        Write-Fail "Erro ao parsear RSoP XML: $($_.Exception.Message)"
        Add-Result 'RSoP' 'FALHA' $_.Exception.Message
    }
} else {
    Write-Fail "gpresult /x falhou (ExitCode: $($gprXmlResult.ExitCode))"
    Write-Info $gprXmlResult.Output
    Add-Result 'RSoP XML' 'FALHA' $gprXmlResult.Output
}

# ===========================================================================
# TESTE 10 — Heranca de GPO bloqueada na hierarquia de OUs
# ===========================================================================
Write-Title 'TESTE 10 — Heranca de GPO na hierarquia de OUs'

$gpModulo = Get-Module -Name GroupPolicy -ListAvailable -ErrorAction SilentlyContinue
$adModulo = Get-Module -Name ActiveDirectory -ListAvailable -ErrorAction SilentlyContinue

if (-not $gpModulo) {
    Write-Warn 'Modulo GroupPolicy (RSAT-GPMC) nao instalado — pulando verificacao de heranca'
    Add-Result 'Heranca OU' 'AVISO' 'Modulo GroupPolicy ausente — instale RSAT-GPMC'
} elseif (-not $adModulo) {
    Write-Warn 'Modulo ActiveDirectory (RSAT-AD) nao instalado — pulando verificacao de heranca'
    Add-Result 'Heranca OU' 'AVISO' 'Modulo ActiveDirectory ausente — instale RSAT-AD-PowerShell'
} else {
    Import-Module GroupPolicy   -ErrorAction SilentlyContinue
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    try {
        # Obtem o DN do computador no AD
        $compDN = (Get-ADComputer -Identity $env:COMPUTERNAME -Properties DistinguishedName `
                    -ErrorAction Stop).DistinguishedName
        Write-Info "DN do computador: $compDN"

        # Extrai a hierarquia de OUs do DN (do mais proximo ao dominio)
        # Ex: CN=PC01,OU=Estacoes,OU=TI,DC=contoso,DC=local
        #     -> 'OU=Estacoes,OU=TI,DC=contoso,DC=local'
        #     -> 'OU=TI,DC=contoso,DC=local'
        $partes = $compDN -split '(?<!\\),'
        $ouList = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $partes.Count; $i++) {
            if ($partes[$i] -match '^OU=') {
                $ouDN = ($partes[$i..($partes.Count - 1)]) -join ','
                $ouList.Add($ouDN) | Out-Null
            }
        }

        if ($ouList.Count -eq 0) {
            Write-Warn 'Computador esta no container raiz (Computers) — sem OUs para verificar'
            Add-Result 'Heranca OU' 'AVISO' 'Computador no container padrao, sem hierarquia de OU'
        } else {
            $bloqueioEncontrado = $false
            Write-Info "Verificando $($ouList.Count) nivel(is) de OU:"

            foreach ($ouDN in $ouList) {
                try {
                    $heranca = Get-GPInheritance -Target $ouDN -ErrorAction Stop
                    $nomeOU  = ($ouDN -split ',')[0] -replace '^OU=',''

                    if ($heranca.GpoInheritanceBlocked) {
                        Write-Fail "  HERANCA BLOQUEADA em: $nomeOU"
                        Write-Info "    DN: $ouDN"

                        # Lista GPOs que AINDA se aplicam (enforced / forcado)
                        $gposEnforced = @($heranca.InheritedGpoLinks | Where-Object { $_.Enforced -eq $true })
                        if ($gposEnforced.Count -gt 0) {
                            Write-Warn "    GPOs Enforced (passam o bloqueio):"
                            $gposEnforced | ForEach-Object { Write-Warn "      - $($_.DisplayName)" }
                        } else {
                            Write-Warn '    Nenhuma GPO Enforced — apenas GPOs vinculadas acima desta OU sao ignoradas'
                        }

                        Add-Result "Heranca OU $nomeOU" 'FALHA' "Bloqueio ativo em $ouDN — GPOs de OUs superiores nao herdam"
                        $bloqueioEncontrado = $true
                    } else {
                        Write-Ok "  Heranca OK: $nomeOU"

                        # Lista GPOs efetivamente herdadas nesta OU
                        $gposHerdadas = @($heranca.InheritedGpoLinks)
                        if ($gposHerdadas.Count -gt 0) {
                            $gposHerdadas | ForEach-Object {
                                $enfTag = if ($_.Enforced) { ' [ENFORCED]' } else { '' }
                                Write-Info "    - $($_.DisplayName)$enfTag (ordem: $($_.Order))"
                            }
                        }
                        Add-Result "Heranca OU $nomeOU" 'OK' "$($gposHerdadas.Count) GPO(s) herdadas"
                    }
                } catch {
                    Write-Warn "  Nao foi possivel verificar heranca de '$ouDN': $($_.Exception.Message)"
                    Add-Result "Heranca OU" 'AVISO' "Erro ao verificar $ouDN — $($_.Exception.Message)"
                }
            }

            if (-not $bloqueioEncontrado) {
                Write-Ok 'Nenhum bloqueio de heranca encontrado na hierarquia de OUs'
            }
        }
    } catch {
        Write-Fail "Erro ao consultar AD: $($_.Exception.Message)"
        Add-Result 'Heranca OU' 'FALHA' $_.Exception.Message
    }
}

# ===========================================================================
# RESUMO FINAL
# ===========================================================================
Write-Title 'RESUMO DO DIAGNOSTICO'

$script:Results | Format-Table -AutoSize -Wrap

$falhas = $script:Results | Where-Object { $_.Status -eq 'FALHA' }
$avisos = $script:Results | Where-Object { $_.Status -eq 'AVISO' }

Write-Host ''
Write-Info "Total de etapas : $($script:Results.Count)"

if ($falhas) {
    Write-Fail "Falhas          : $($falhas.Count)"
    Write-Host ''
    Write-Warn 'Etapas com FALHA:'
    $falhas | ForEach-Object { Write-Fail "  - $($_.Etapa): $($_.Detalhe)" }
} else {
    Write-Ok 'Nenhuma falha detectada'
}

if ($avisos) {
    Write-Warn "Avisos          : $($avisos.Count)"
}

Write-Host ''
Write-Info "Log completo    : $LogFile"
Write-Info "Relatorio HTML  : $HtmlReport"
Write-Host ''

Stop-Transcript | Out-Null
