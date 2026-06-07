# Terraform Valheim Control

Infraestrutura Terraform para criar uma EC2 em `sa-east-1`, controlada por um painel web estatico servido por S3 Website.

O Terraform cria a infraestrutura. O estado operacional da EC2 fica fora do Terraform e e controlado pela Lambda do painel.

## O Que E Criado

- EC2 Ubuntu Server 24.04 LTS usando a VPC default da regiao
- Security group com UDP `2456-2457` aberto para Valheim e sem SSH inbound
- IAM instance profile com `AmazonSSMManagedInstanceCore` para acesso via Session Manager
- Bucket S3 para backup automatico do mundo ativo do Valheim
- Lambda Function URL publica para a API do painel
- S3 Website para hospedar o painel web

Nao ha Elastic IP por padrao. O IPv4 publico muda depois de stop/start.

## Uso Terraform

Copie o exemplo de variaveis:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Gere o hash SHA-256 da senha do painel:

```powershell
$password = "troque-essa-senha"
$bytes = [Text.Encoding]::UTF8.GetBytes($password)
$hash = [Security.Cryptography.SHA256]::HashData($bytes)
[Convert]::ToHexString($hash).ToLower()
```

Edite `terraform.tfvars` e coloque o resultado em `control_password_hash`.

Inicialize e aplique:

```powershell
terraform init
terraform fmt
terraform validate
terraform apply
```

Abra o output `control_site_url`. O painel pede a senha, mostra status do servidor e permite ligar ou fazer backup + parar.

## Painel Web

O painel mostra:

- estado atual da EC2
- IP publico e porta do servidor
- ha quanto tempo a instancia esta ligada
- estimativa de custo da sessao em USD e BRL
- ultima mensagem da operacao

A estimativa usa os valores manuais `session_hourly_usd` e `usd_to_brl_rate`. Se `session_hourly_usd` ficar `0`, o painel mostra `configure` no custo.

## Layout Na EC2

- binarios do servidor: `/srv/valheim/server`
- mundos: `/srv/valheim/worlds_local`
- config do servidor: `/etc/valheim/valheim.env`
- home/estado do usuario de servico: `/var/lib/valheim`

## Instalar O Servidor Valheim

Entre na EC2 por SSM:

```powershell
aws ssm start-session --target INSTANCE_ID
```

Copie `scripts/install-valheim-server.sh` para a instancia e execute como root:

```bash
sudo bash install-valheim-server.sh
```

O script:

- instala SteamCMD e dependencias do Ubuntu
- instala `unzip` e a AWS CLI v2
- instala o Valheim Dedicated Server em `/srv/valheim/server`
- cria `/etc/valheim/valheim.env`
- cria o servico `systemd` `valheim.service`
- instala o helper `/usr/local/bin/backup-valheim-world.sh`
- gera um `start-valheim.sh` que carrega BepInEx automaticamente se os arquivos de mod existirem em `/srv/valheim/server`

## Configurar Mundo

Arquivos do mundo no Windows: veja `scripts/valheim-world-paths.md`.

Destino na EC2:

```text
/srv/valheim/worlds_local
```

Arquivos necessarios:

- `NomeDoMundo.db`
- `NomeDoMundo.fwl`

Depois ajuste `/etc/valheim/valheim.env`:

```bash
SERVER_NAME="Nome do servidor"
WORLD_NAME="NomeDoMundo"
SERVER_PORT="2456"
SERVER_PASSWORD="UmaSenhaBoa"
SERVER_PUBLIC="1"
```

Suba o mundo, ajuste dono se necessario e inicie:

```bash
sudo chown valheim:valheim /srv/valheim/worlds_local/NomeDoMundo.db /srv/valheim/worlds_local/NomeDoMundo.fwl
sudo systemctl restart valheim
sudo systemctl status valheim
sudo journalctl -u valheim -n 100 --no-pager
```

## Mods Com r2modman

Para gerar um pacote com os arquivos de servidor do seu perfil do r2modman:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\package-r2modman-server-profile.ps1
```

Isso gera `valheim-server-mods.zip` na Desktop com:

- `BepInEx/plugins`
- `BepInEx/config`
- `doorstop_libs`
- `.doorstop_version`
- `doorstop_config.ini`
- `start_server_bepinex.sh`

## Baixar Arquivos Do S3 Na EC2

A EC2 tem permissao IAM para baixar objetos do bucket de backup. Dentro da instancia, liste os arquivos:

```bash
aws s3 ls s3://NOME_DO_BUCKET/ --recursive
```

Para baixar arquivos para a pasta atual:

```bash
aws s3 cp s3://NOME_DO_BUCKET/valheim-server-mods.zip .
aws s3 cp s3://NOME_DO_BUCKET/Vultur-world-backup-20260606-053031.tar.tar .
```

Confira:

```bash
ls -lh
```

Para extrair `.zip`:

```bash
unzip -o valheim-server-mods.zip -d /srv/valheim/server
```

Para extrair `.tar`, `.tar.gz` ou backup compactado:

```bash
tar -xf Vultur-world-backup-20260606-053031.tar.tar -C /srv/valheim/worlds_local
```

Depois de extrair arquivos do servidor ou mundo, ajuste permissao:

```bash
sudo chown -R valheim:valheim /srv/valheim/server /srv/valheim/worlds_local
```

## Instalar Mods No Servidor

Extraia o zip diretamente em `/srv/valheim/server` na EC2. Sempre pare o servico antes de atualizar mods e inicie novamente depois:

```bash
sudo systemctl stop valheim
sudo unzip /tmp/valheim-server-mods.zip -d /srv/valheim/server
sudo chown -R valheim:valheim /srv/valheim/server/BepInEx /srv/valheim/server/doorstop_libs
sudo systemctl start valheim
sudo systemctl status valheim
```

Nao existe um segundo script para mods. O mesmo `start-valheim.sh` gerado pelo instalador detecta BepInEx e ativa Doorstop automaticamente.

## Backups Do Mundo

O projeto cria um bucket S3 dedicado para backups do mundo ativo. O botao `Backup + parar` primeiro executa backup do mundo configurado em `WORLD_NAME` e so depois para a EC2.

O backup automatico usa:

- helper: `/usr/local/bin/backup-valheim-world.sh`
- origem: `/srv/valheim/worlds_local`
- temporario local: `/tmp/valheim-backups`
- destino S3: `s3://BACKUP_BUCKET/backups/worlds/`

O helper salva somente os arquivos do mundo ativo:

- `WORLD_NAME.db`
- `WORLD_NAME.fwl`

Para testar backup manualmente na EC2:

```bash
sudo BACKUP_BUCKET_NAME="NOME_DO_BUCKET" BACKUP_PREFIX="backups/worlds" /usr/local/bin/backup-valheim-world.sh
```

O nome do bucket aparece no output `backup_bucket_name` do Terraform.

## Acesso Ao Servidor

Use AWS Systems Manager Session Manager com o instance ID mostrado no output `ssm_instance_target`.

Nao ha porta 22 aberta.

## Observacoes

- Esta base suporta jogo vanilla e modado com o mesmo servico `systemd`
- `terraform destroy` remove a EC2 e apaga os dados locais se nao houver backup/snapshot
- stop/start da EC2 preserva o root EBS e os arquivos em `/srv/valheim`
