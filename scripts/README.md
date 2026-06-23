# Scripts

Camada plana de entrada operacional do `Xtudo`.

Cada arquivo aqui usa um nome verbal curto e chama o fluxo operacional atual.
Os scripts legados foram movidos para `experimental/`.

Regra prática:

- operador entra por `.\xtudo.ps1`
- scripts em `scripts/` são os atalhos oficiais do MVP
- tudo fora do MVP fica em `experimental/`

Exemplos:

```powershell
.\xtudo.ps1
.\scripts\limpar-windows.ps1
.\scripts\diagnosticar-memoria.ps1
.\scripts\atualizar-windows.ps1
```
