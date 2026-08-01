# Classificação de ShouldProcess

Rastreio: **BCK-054**. A inspeção inicial encontrou 42 avisos
`PSUseShouldProcessForStateChangingFunctions`.

## Operações mutáveis protegidas

As 17 operações abaixo passaram a declarar `SupportsShouldProcess`, chamam
`$PSCmdlet.ShouldProcess()` antes da mutação e usam impacto alto onde a ação é
destrutiva: `Start-ScheduledTaskByName`, `Start-WindowsService`,
`Stop-WindowsService`, `Restart-WindowsService`, `Set-WindowsServiceStartup`,
`New-SshHostKey`, `New-SshUserKey`, `Remove-SshAuthorizedKey`, `Set-SshdConfig`,
`Remove-StartupStoreItem`, `Set-LsaSecret`, `Set-ToolkitReportsRoot`, `New-ToolkitArchive`,
`Set-PtBRUserSettings`, `Set-BrazilTimeZone`, `Remove-Profiles` e
`Remove-HD100StartupItem`.

`configurar-acesso-remoto.ps1` é protegido no ponto de entrada de cada ação de
alto impacto; suas cinco funções internas (`Set-RdpEnabled`,
`Set-RdpPortInternal`, `Set-RdpNlaInternal`, `Set-RdpServiceState` e
`Remove-RdpFirewallRule`) não são API pública e só são chamadas após a decisão
do operador.

## Falsos positivos sem mutação externa

Os 21 avisos restantes de funções `New-*` e de geração de relatório foram
classificados como construção em memória ou serialização de conteúdo:
`New-HtmlReport`, `New-HD100GaugeText`, `New-GfxFinding`,
`New-GfxTextReport`, `New-MemoryTextReport`, `New-MemoryHtmlReport`,
`New-DriverCatalogFromFolders`, `New-DrvTextReport`, `New-DrvHtmlReport`,
`New-KvRow`, `New-DriverInfoObject`, `New-PortalIndexHtml`,
`New-StaticDocsSlug`, `New-ToolkitElevationCommand`,
`New-ToolkitHtmlReport`, `New-ConnectivityResult`, `New-DuplicateIpReport`,
`New-ConnectivityTestPlan`, `New-StartupItemId` e `Set-AdCheckResult`.

Essas funções retornam objetos, texto ou HTML ao chamador; qualquer escrita
posterior é responsabilidade da operação chamadora protegida. O aviso de
`analisar-espaco-disco:New-HtmlReport` segue a mesma classificação.

O contador da regra caiu de 42 para 25. Os 25 residuais são as funções internas
acima, incluindo as cinco rotinas RDP já guardadas pela entrada pública; eles
permanecem rastreáveis pela baseline e não podem aumentar.
