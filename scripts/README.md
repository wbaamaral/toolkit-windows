# Scripts

Camada plana de entrada operacional do `Xtudo`.

Cada arquivo aqui usa um nome verbal curto e contém o fluxo operacional atual do MVP.
Os diretórios em `experimental/` continuam guardando o backlog e os fluxos ainda não promovidos.

Regra prática:

- operador entra por `.\xtudo.ps1`
- scripts em `scripts/` são a superfície oficial do MVP
- `experimental/` fica para o que ainda não foi promovido
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

### `Inventario-Hardware-Software.ps1`

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
.\scripts\Inventario-Hardware-Software.ps1
.\scripts\Inventario-Hardware-Software.ps1 -NaoPDF
.\scripts\Inventario-Hardware-Software.ps1 -GerarResumoHardwareDrivers
.\scripts\Inventario-Hardware-Software.ps1 -SomenteHardwareDrivers
```
