# provisioning/

Ponto de entrada operacional do `WbaToolkit.Provisioning` (ADR-0033). Fica fora de
`scripts/` porque `Inicializar-Windows.ps1` precisa estar presente na imagem de
referência antes da captura (Sysprep) e é invocado exclusivamente pela tarefa
agendada `\WBA\Provisioning\Inicializar-Windows`, nunca diretamente por um operador
no dia a dia.

Especificação completa: `spec/modulos/provisioning/`.
