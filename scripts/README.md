# Scripts

Camada plana de entrada operacional do `Xtudo`.

Cada arquivo aqui usa um nome verbal curto (verbo-objeto, ADR 0022) e contém o fluxo
operacional atual do MVP. Todos os scripts operacionais já vivem aqui em `scripts/`;
`experimental/` mantém apenas o registro de não-validados e material futuro ainda não pronto.

Regra prática:

- operador entra por `.\xtudo.ps1`
- scripts em `scripts/` são a superfície oficial do MVP
- `experimental/nao-validado/` registra scripts ainda sem validação operacional
- parâmetros não precisam ser curtos por obrigação; prefira nomes em português, curtos e com sentido direto do que o parâmetro faz
- mantenha `Comment-Based Help` para explicar nome, uso e efeito de cada parâmetro público
- `-Help` é obrigatório em todos os scripts da superfície oficial e deve exibir a consulta inline de uso
- ver ADR 0021 para o racional dessa padronização

Exemplos:

```powershell
.\xtudo.ps1
.\scripts\limpar-windows.ps1
.\scripts\diagnosticar-memoria.ps1
.\scripts\atualizar-windows.ps1
.\scripts\diagnosticar-ad-cliente.ps1
```

## Inventário

### `inventario-hardware-software.ps1`

**Função:** Gera inventário completo de hardware e software em relatório HTML com conversão opcional para PDF.

**Dependência de módulo:** `WbaToolkit.Inventory` para o mapa de cobertura do escopo e evolução futura do inventário.

**Cobertura atual:**

- sistema operacional;
- processador;
- memória RAM;
- placa-mãe e BIOS;
- armazenamento;
- placa de vídeo;
- rede;
- monitores;
- software instalado;
- atualizações / hotfixes;
- serviços;
- resumo de hardware e drivers em saída enxuta opcional.

**Ainda não coberto como rotina separada:**

- inventário de Active Directory do cliente;
- inventário de impressoras e periféricos dedicados;
- inventário de rede por topologia, VLAN ou switch;
- inventário de usuários, perfis e sessões locais;
- inventário patrimonial/CMDB.

**Exemplos:**

```powershell
.\scripts\inventario-hardware-software.ps1
.\scripts\inventario-hardware-software.ps1 -NaoPDF
.\scripts\inventario-hardware-software.ps1 -GerarResumoHardwareDrivers
.\scripts\inventario-hardware-software.ps1 -SomenteHardwareDrivers
```
