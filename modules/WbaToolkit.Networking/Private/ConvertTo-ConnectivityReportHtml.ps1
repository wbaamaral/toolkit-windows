function ConvertTo-ConnectivityReportHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Report
    )

    # TAILWIND-CSS:BEGIN (gerado por tools/build-report-css.sh — nao editar a mao)
    $tailwindCss = @'
/*! tailwindcss v4.3.2 | MIT License | https://tailwindcss.com */
@layer properties{@supports (((-webkit-hyphens:none)) and (not (margin-trim:inline))) or ((-moz-orient:inline) and (not (color:rgb(from red r g b)))){*,:before,:after,::backdrop{--tw-border-style:solid;--tw-font-weight:initial;--tw-tracking:initial;--tw-shadow:0 0 #0000;--tw-shadow-color:initial;--tw-shadow-alpha:100%;--tw-inset-shadow:0 0 #0000;--tw-inset-shadow-color:initial;--tw-inset-shadow-alpha:100%;--tw-ring-color:initial;--tw-ring-shadow:0 0 #0000;--tw-inset-ring-color:initial;--tw-inset-ring-shadow:0 0 #0000;--tw-ring-inset:initial;--tw-ring-offset-width:0px;--tw-ring-offset-color:#fff;--tw-ring-offset-shadow:0 0 #0000;--tw-leading:initial}}}@layer theme{:root,:host{--font-sans:ui-sans-serif, system-ui, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";--font-mono:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;--color-red-100:oklch(93.6% .032 17.717);--color-amber-100:oklch(96.2% .059 95.617);--color-green-100:oklch(96.2% .044 156.743);--color-blue-100:oklch(93.2% .032 255.585);--color-blue-600:oklch(54.6% .245 262.881);--color-slate-50:oklch(98.4% .003 247.858);--color-slate-200:oklch(92.9% .013 255.508);--color-slate-900:oklch(20.8% .042 265.755);--color-gray-50:oklch(98.5% .002 247.839);--color-gray-100:oklch(96.7% .003 264.542);--color-gray-300:oklch(87.2% .01 258.338);--color-gray-500:oklch(55.1% .027 264.364);--color-gray-800:oklch(27.8% .033 256.848);--color-white:#fff;--spacing:.25rem;--text-xs:.75rem;--text-xs--line-height:calc(1 / .75);--text-sm:.875rem;--text-sm--line-height:calc(1.25 / .875);--text-lg:1.125rem;--text-lg--line-height:calc(1.75 / 1.125);--font-weight-semibold:600;--font-weight-bold:700;--tracking-wider:.05em;--leading-normal:1.5;--radius-md:.375rem;--radius-lg:.5rem;--default-font-family:var(--font-sans);--default-mono-font-family:var(--font-mono)}}@layer base{*,:after,:before,::backdrop{box-sizing:border-box;border:0 solid;margin:0;padding:0}::file-selector-button{box-sizing:border-box;border:0 solid;margin:0;padding:0}html,:host{-webkit-text-size-adjust:100%;tab-size:4;line-height:1.5;font-family:var(--default-font-family,ui-sans-serif, system-ui, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji");font-feature-settings:var(--default-font-feature-settings,normal);font-variation-settings:var(--default-font-variation-settings,normal);-webkit-tap-highlight-color:transparent}hr{height:0;color:inherit;border-top-width:1px}abbr:where([title]){-webkit-text-decoration:underline dotted;text-decoration:underline dotted}h1,h2,h3,h4,h5,h6{font-size:inherit;font-weight:inherit}a{color:inherit;-webkit-text-decoration:inherit;-webkit-text-decoration:inherit;-webkit-text-decoration:inherit;text-decoration:inherit}b,strong{font-weight:bolder}code,kbd,samp,pre{font-family:var(--default-mono-font-family,ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace);font-feature-settings:var(--default-mono-font-feature-settings,normal);font-variation-settings:var(--default-mono-font-variation-settings,normal);font-size:1em}small{font-size:80%}sub,sup{vertical-align:baseline;font-size:75%;line-height:0;position:relative}sub{bottom:-.25em}sup{top:-.5em}table{text-indent:0;border-color:inherit;border-collapse:collapse}:-moz-focusring{outline:auto}progress{vertical-align:baseline}summary{display:list-item}ol,ul,menu{list-style:none}img,svg,video,canvas,audio,iframe,embed,object{vertical-align:middle;display:block}img,video{max-width:100%;height:auto}button,input,select,optgroup,textarea{font:inherit;font-feature-settings:inherit;font-variation-settings:inherit;letter-spacing:inherit;color:inherit;opacity:1;background-color:#0000;border-radius:0}::file-selector-button{font:inherit;font-feature-settings:inherit;font-variation-settings:inherit;letter-spacing:inherit;color:inherit;opacity:1;background-color:#0000;border-radius:0}:where(select:is([multiple],[size])) optgroup{font-weight:bolder}:where(select:is([multiple],[size])) optgroup option{padding-inline-start:20px}::file-selector-button{margin-inline-end:4px}::placeholder{opacity:1}@supports (not ((-webkit-appearance:-apple-pay-button))) or (contain-intrinsic-size:1px){::placeholder{color:currentColor}@supports (color:color-mix(in lab, red, red)){::placeholder{color:color-mix(in oklab, currentcolor 50%, transparent)}}}textarea{resize:vertical}::-webkit-search-decoration{-webkit-appearance:none}::-webkit-date-and-time-value{min-height:1lh;text-align:inherit}::-webkit-datetime-edit{display:inline-flex}::-webkit-datetime-edit-fields-wrapper{padding:0}::-webkit-datetime-edit{padding-block:0}::-webkit-datetime-edit-year-field{padding-block:0}::-webkit-datetime-edit-month-field{padding-block:0}::-webkit-datetime-edit-day-field{padding-block:0}::-webkit-datetime-edit-hour-field{padding-block:0}::-webkit-datetime-edit-minute-field{padding-block:0}::-webkit-datetime-edit-second-field{padding-block:0}::-webkit-datetime-edit-millisecond-field{padding-block:0}::-webkit-datetime-edit-meridiem-field{padding-block:0}::-webkit-calendar-picker-indicator{line-height:1}:-moz-ui-invalid{box-shadow:none}button,input:where([type=button],[type=reset],[type=submit]){appearance:button}::file-selector-button{appearance:button}::-webkit-inner-spin-button{height:auto}::-webkit-outer-spin-button{height:auto}[hidden]:where(:not([hidden=until-found])){display:none!important}h1{--tw-font-weight:var(--font-weight-bold);font-size:28px;font-weight:var(--font-weight-bold);color:var(--color-slate-900);margin:0}h2{margin-top:calc(var(--spacing) * 7);border-bottom-style:var(--tw-border-style);border-bottom-width:1px;border-color:var(--color-gray-300);padding-bottom:calc(var(--spacing) * 2);font-size:var(--text-lg);line-height:var(--tw-leading,var(--text-lg--line-height));--tw-font-weight:var(--font-weight-bold);font-weight:var(--font-weight-bold);color:var(--color-slate-900)}h3{--tw-font-weight:var(--font-weight-bold);font-size:15px;font-weight:var(--font-weight-bold);color:var(--color-slate-900);margin-top:18px}p,li{--tw-leading:var(--leading-normal);line-height:var(--leading-normal)}a{color:var(--color-blue-600);text-decoration-line:none}a:hover{text-decoration-line:underline}code,pre{border-radius:var(--radius-md);border-style:var(--tw-border-style);border-width:1px;border-color:var(--color-gray-300);background-color:var(--color-slate-50)}code{padding-inline:var(--spacing);padding-block:calc(var(--spacing) * .5)}pre{padding:calc(var(--spacing) * 3);white-space:pre-wrap;overflow-x:auto}table{margin-top:calc(var(--spacing) * 3);border-collapse:collapse;width:100%}th,td{border-bottom-style:var(--tw-border-style);border-bottom-width:1px;border-color:var(--color-gray-300);padding-inline:calc(var(--spacing) * 2);padding-block:calc(var(--spacing) * 2);text-align:left;vertical-align:top}th{background-color:var(--color-gray-50);font-size:var(--text-xs);line-height:var(--tw-leading,var(--text-xs--line-height));color:var(--color-gray-500);text-transform:uppercase}nav{margin-top:calc(var(--spacing) * 2);font-size:var(--text-sm);line-height:var(--tw-leading,var(--text-sm--line-height));color:var(--color-gray-500)}footer{margin-top:calc(var(--spacing) * 7);border-top-style:var(--tw-border-style);border-top-width:1px;border-color:var(--color-gray-300);padding-top:calc(var(--spacing) * 3);text-align:center;font-size:var(--text-xs);line-height:var(--tw-leading,var(--text-xs--line-height));color:var(--color-gray-500)}}@layer components;@layer utilities{.static{position:static}.m-0{margin:0}.mx-auto{margin-inline:auto}.my-6{margin-block:calc(var(--spacing) * 6)}.mt-1{margin-top:var(--spacing)}.mt-1\.5{margin-top:calc(var(--spacing) * 1.5)}.mt-2{margin-top:calc(var(--spacing) * 2)}.mt-4{margin-top:calc(var(--spacing) * 4)}.mt-5{margin-top:calc(var(--spacing) * 5)}.mt-6{margin-top:calc(var(--spacing) * 6)}.mb-2\.5{margin-bottom:calc(var(--spacing) * 2.5)}.mb-6{margin-bottom:calc(var(--spacing) * 6)}.mb-7{margin-bottom:calc(var(--spacing) * 7)}.block{display:block}.flex{display:flex}.grid{display:grid}.w-full{width:100%}.max-w-\[1120px\]{max-width:1120px}.border-collapse{border-collapse:collapse}.cursor-pointer{cursor:pointer}.break-inside-avoid{break-inside:avoid}.grid-cols-2{grid-template-columns:repeat(2,minmax(0,1fr))}.grid-cols-5{grid-template-columns:repeat(5,minmax(0,1fr))}.grid-cols-\[repeat\(auto-fit\,minmax\(260px\,1fr\)\)\]{grid-template-columns:repeat(auto-fit,minmax(260px,1fr))}.justify-between{justify-content:space-between}.gap-3{gap:calc(var(--spacing) * 3)}.gap-4{gap:calc(var(--spacing) * 4)}.gap-6{gap:calc(var(--spacing) * 6)}.overflow-hidden{overflow:hidden}.rounded-lg{border-radius:var(--radius-lg)}.border{border-style:var(--tw-border-style);border-width:1px}.border-0{border-style:var(--tw-border-style);border-width:0}.border-t{border-top-style:var(--tw-border-style);border-top-width:1px}.border-b{border-bottom-style:var(--tw-border-style);border-bottom-width:1px}.border-\[\#eef2f7\]{border-color:#eef2f7}.border-gray-300{border-color:var(--color-gray-300)}.bg-amber-100{background-color:var(--color-amber-100)}.bg-blue-100{background-color:var(--color-blue-100)}.bg-blue-600{background-color:var(--color-blue-600)}.bg-gray-50{background-color:var(--color-gray-50)}.bg-gray-100{background-color:var(--color-gray-100)}.bg-green-100{background-color:var(--color-green-100)}.bg-red-100{background-color:var(--color-red-100)}.bg-slate-200{background-color:var(--color-slate-200)}.bg-white{background-color:var(--color-white)}.p-0{padding:0}.p-4{padding:calc(var(--spacing) * 4)}.p-8{padding:calc(var(--spacing) * 8)}.px-2{padding-inline:calc(var(--spacing) * 2)}.px-3\.5{padding-inline:calc(var(--spacing) * 3.5)}.px-4{padding-inline:calc(var(--spacing) * 4)}.py-2\.5{padding-block:calc(var(--spacing) * 2.5)}.py-3{padding-block:calc(var(--spacing) * 3)}.py-3\.5{padding-block:calc(var(--spacing) * 3.5)}.pt-3{padding-top:calc(var(--spacing) * 3)}.pb-4{padding-bottom:calc(var(--spacing) * 4)}.text-center{text-align:center}.text-left{text-align:left}.text-right{text-align:right}.align-top{vertical-align:top}.font-sans{font-family:var(--font-sans)}.text-sm{font-size:var(--text-sm);line-height:var(--tw-leading,var(--text-sm--line-height))}.text-xs{font-size:var(--text-xs);line-height:var(--tw-leading,var(--text-xs--line-height))}.text-\[11px\]{font-size:11px}.text-\[13px\]{font-size:13px}.text-\[26px\]{font-size:26px}.text-\[28px\]{font-size:28px}.font-bold{--tw-font-weight:var(--font-weight-bold);font-weight:var(--font-weight-bold)}.font-semibold{--tw-font-weight:var(--font-weight-semibold);font-weight:var(--font-weight-semibold)}.tracking-wider{--tw-tracking:var(--tracking-wider);letter-spacing:var(--tracking-wider)}.text-gray-500{color:var(--color-gray-500)}.text-gray-800{color:var(--color-gray-800)}.text-slate-900{color:var(--color-slate-900)}.text-white{color:var(--color-white)}.uppercase{text-transform:uppercase}.shadow-\[0_10px_25px_rgba\(15\,23\,42\,0\.08\)\]{--tw-shadow:0 10px 25px var(--tw-shadow-color,#0f172a14);box-shadow:var(--tw-inset-shadow), var(--tw-inset-ring-shadow), var(--tw-ring-offset-shadow), var(--tw-ring-shadow), var(--tw-shadow)}@media print{.print\:m-0{margin:0}.print\:hidden{display:none}.print\:max-w-full{max-width:100%}.print\:p-0{padding:0}.print\:shadow-none{--tw-shadow:0 0 #0000;box-shadow:var(--tw-inset-shadow), var(--tw-inset-ring-shadow), var(--tw-ring-offset-shadow), var(--tw-ring-shadow), var(--tw-shadow)}}}@page{size:A4;margin:15mm}*{-webkit-print-color-adjust:exact!important;print-color-adjust:exact!important}@property --tw-border-style{syntax:"*";inherits:false;initial-value:solid}@property --tw-font-weight{syntax:"*";inherits:false}@property --tw-tracking{syntax:"*";inherits:false}@property --tw-shadow{syntax:"*";inherits:false;initial-value:0 0 #0000}@property --tw-shadow-color{syntax:"*";inherits:false}@property --tw-shadow-alpha{syntax:"<percentage>";inherits:false;initial-value:100%}@property --tw-inset-shadow{syntax:"*";inherits:false;initial-value:0 0 #0000}@property --tw-inset-shadow-color{syntax:"*";inherits:false}@property --tw-inset-shadow-alpha{syntax:"<percentage>";inherits:false;initial-value:100%}@property --tw-ring-color{syntax:"*";inherits:false}@property --tw-ring-shadow{syntax:"*";inherits:false;initial-value:0 0 #0000}@property --tw-inset-ring-color{syntax:"*";inherits:false}@property --tw-inset-ring-shadow{syntax:"*";inherits:false;initial-value:0 0 #0000}@property --tw-ring-inset{syntax:"*";inherits:false}@property --tw-ring-offset-width{syntax:"<length>";inherits:false;initial-value:0}@property --tw-ring-offset-color{syntax:"*";inherits:false;initial-value:#fff}@property --tw-ring-offset-shadow{syntax:"*";inherits:false;initial-value:0 0 #0000}@property --tw-leading{syntax:"*";inherits:false}
'@
    # TAILWIND-CSS:END

    $context = $Report.Context
    $summary  = $Report.Summary
    $results  = @($Report.Results)

    # Cada Color usada abaixo precisa de uma chave correspondente aqui (ver
    # tests/unit/WbaToolkit.Networking.Tests.ps1 — teste de sincronia).
    $cardColorClasses = @{
        slate = 'bg-slate-200'
        green = 'bg-green-100'
        red   = 'bg-red-100'
        amber = 'bg-amber-100'
        blue  = 'bg-blue-100'
    }

    $cards = @(
        @{ Label = 'Total'; Value = $summary.Total; Color = 'slate' },
        @{ Label = 'Sucesso'; Value = $summary.Success; Color = 'green' },
        @{ Label = 'Falhas'; Value = $summary.Failed; Color = 'red' },
        @{ Label = 'Avisos'; Value = $summary.Warning; Color = 'amber' },
        @{ Label = 'Inconclusivo'; Value = $summary.Inconclusive; Color = 'blue' }
    )

    $cardHtml = foreach ($card in $cards) {
        $value = ConvertTo-HtmlSafe -Value $card.Value
        $colorClass = $cardColorClasses[$card.Color]
        @"
        <div class="border border-gray-300 rounded-lg py-3.5 px-4 $colorClass">
          <div class="text-gray-500 text-[11px] uppercase tracking-wider">$($card.Label)</div>
          <div class="text-[26px] font-bold mt-2 text-slate-900">$value</div>
        </div>
"@
    }

    $resultRows = foreach ($result in $results) {
        $target = if ($result.Target) { ConvertTo-HtmlSafe -Value $result.Target } else { '&mdash;' }
        $port   = if ($null -ne $result.Port) { [string]$result.Port } else { '&mdash;' }
        $lat    = if ($null -ne $result.LatencyMs) { '{0:N1} ms' -f $result.LatencyMs } else { '&mdash;' }
        $errMsg = if ($result.ErrorMessage) { ConvertTo-HtmlSafe -Value $result.ErrorMessage } else { '&mdash;' }
        $rec    = if ($result.Recommendation) { ConvertTo-HtmlSafe -Value $result.Recommendation } else { '&mdash;' }

        @"
        <tr>
          <td class="border-b border-[#eef2f7] px-2 py-2.5 align-top">$([string](ConvertTo-HtmlSafe -Value $result.TestName))</td>
          <td class="border-b border-[#eef2f7] px-2 py-2.5 align-top">$([string](ConvertTo-HtmlSafe -Value $result.Protocol))</td>
          <td class="border-b border-[#eef2f7] px-2 py-2.5 align-top">$([string](ConvertTo-HtmlSafe -Value $result.Classification))</td>
          <td class="border-b border-[#eef2f7] px-2 py-2.5 align-top">$target</td>
          <td class="border-b border-[#eef2f7] px-2 py-2.5 align-top">$port</td>
          <td class="border-b border-[#eef2f7] px-2 py-2.5 align-top">$lat</td>
          <td class="border-b border-[#eef2f7] px-2 py-2.5 align-top">$errMsg</td>
          <td class="border-b border-[#eef2f7] px-2 py-2.5 align-top">$rec</td>
        </tr>
"@
    }

    $dnsServers = if ($context.DnsServers) { ($context.DnsServers -join ', ') } else { '&mdash;' }

    @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Relatório de Conectividade</title>
  <style>$tailwindCss</style>
</head>
<body class="font-sans bg-gray-100 text-gray-800 m-0">
  <div class="mx-auto mt-6 max-w-[1120px] text-right print:hidden"><button class="bg-blue-600 text-white border-0 px-3.5 py-2.5 font-bold cursor-pointer" onclick="window.print()">Imprimir relatório</button></div>
  <div class="max-w-[1120px] mx-auto my-6 p-8 bg-white shadow-[0_10px_25px_rgba(15,23,42,0.08)] print:shadow-none print:m-0 print:p-0 print:max-w-full">
    <div class="flex justify-between gap-6 border-b border-gray-300 pb-4 mb-6">
      <div>
        <h1 class="text-[28px] font-bold text-slate-900 m-0">Relatório de Conectividade</h1>
        <div class="text-gray-500 text-[13px] mt-1">Gerado em: $([string](ConvertTo-HtmlSafe -Value $Report.FinishedAt.ToString('dd/MM/yyyy HH:mm:ss')))</div>
      </div>
      <div class="text-right text-[13px] text-gray-500">
        <strong class="text-gray-800 block text-sm">$([string](ConvertTo-HtmlSafe -Value $context.Hostname))</strong>
        Usuário: $([string](ConvertTo-HtmlSafe -Value $context.Username))<br>
        Interface: $([string](ConvertTo-HtmlSafe -Value $context.InterfaceAlias))<br>
        IPv4: $([string](ConvertTo-HtmlSafe -Value $context.IPv4Address))/$([string](ConvertTo-HtmlSafe -Value $context.PrefixLength))<br>
        Gateway: $([string](ConvertTo-HtmlSafe -Value $context.Gateway))
      </div>
    </div>

    <div class="grid grid-cols-5 gap-3 mt-5 mb-7">
$($cardHtml -join "`n")
    </div>

    <div class="border border-gray-300 rounded-lg mt-4 overflow-hidden break-inside-avoid">
      <div class="bg-gray-50 border-b border-gray-300 px-4 py-3 font-bold">Contexto de rede</div>
      <div class="p-4">
        <div class="grid grid-cols-2 gap-4">
          <div>
            <p class="mb-2.5"><span class="text-gray-500 text-xs">Hostname</span><br><span class="font-semibold text-gray-800">$([string](ConvertTo-HtmlSafe -Value $context.Hostname))</span></p>
            <p class="mb-2.5"><span class="text-gray-500 text-xs">Usuário</span><br><span class="font-semibold text-gray-800">$([string](ConvertTo-HtmlSafe -Value $context.Username))</span></p>
            <p class="mb-2.5"><span class="text-gray-500 text-xs">Interface</span><br><span class="font-semibold text-gray-800">$([string](ConvertTo-HtmlSafe -Value $context.InterfaceAlias))</span></p>
          </div>
          <div>
            <p class="mb-2.5"><span class="text-gray-500 text-xs">IPv4</span><br><span class="font-semibold text-gray-800">$([string](ConvertTo-HtmlSafe -Value $context.IPv4Address))/$([string](ConvertTo-HtmlSafe -Value $context.PrefixLength))</span></p>
            <p class="mb-2.5"><span class="text-gray-500 text-xs">Gateway</span><br><span class="font-semibold text-gray-800">$([string](ConvertTo-HtmlSafe -Value $context.Gateway))</span></p>
            <p class="mb-2.5"><span class="text-gray-500 text-xs">DNS</span><br><span class="font-semibold text-gray-800">$dnsServers</span></p>
          </div>
        </div>
      </div>
    </div>

    <div class="border border-gray-300 rounded-lg mt-4 overflow-hidden break-inside-avoid">
      <div class="bg-gray-50 border-b border-gray-300 px-4 py-3 font-bold">Resultados</div>
      <div class="p-0">
        <table class="w-full border-collapse text-[13px]">
          <thead>
            <tr>
              <th class="text-left bg-gray-50 border-b border-gray-300 px-2 py-2.5 text-[11px] uppercase text-gray-500">Teste</th>
              <th class="text-left bg-gray-50 border-b border-gray-300 px-2 py-2.5 text-[11px] uppercase text-gray-500">Proto</th>
              <th class="text-left bg-gray-50 border-b border-gray-300 px-2 py-2.5 text-[11px] uppercase text-gray-500">Status</th>
              <th class="text-left bg-gray-50 border-b border-gray-300 px-2 py-2.5 text-[11px] uppercase text-gray-500">Destino</th>
              <th class="text-left bg-gray-50 border-b border-gray-300 px-2 py-2.5 text-[11px] uppercase text-gray-500">Porta</th>
              <th class="text-left bg-gray-50 border-b border-gray-300 px-2 py-2.5 text-[11px] uppercase text-gray-500">Latência</th>
              <th class="text-left bg-gray-50 border-b border-gray-300 px-2 py-2.5 text-[11px] uppercase text-gray-500">Erro</th>
              <th class="text-left bg-gray-50 border-b border-gray-300 px-2 py-2.5 text-[11px] uppercase text-gray-500">Recomendação</th>
            </tr>
          </thead>
          <tbody>
$($resultRows -join "`n")
          </tbody>
        </table>
      </div>
    </div>

    <div class="mt-4 pt-3 border-t border-gray-300 text-gray-500 text-[11px] text-center">
      Documento gerado internamente - $([string](ConvertTo-HtmlSafe -Value $Report.ReportId))
    </div>
  </div>
</body>
</html>
"@
}
