# Terraform Valheim Discord

Infraestrutura Terraform para criar uma EC2 `t3.large` em `sa-east-1`, controlada por `/valheim start`, `/valheim ip` e `/valheim stop` no Discord.

O Terraform cria a infraestrutura. O estado operacional da EC2 fica fora do Terraform e e controlado pela Lambda.

## O Que E Criado

- EC2 Ubuntu Server 24.04 LTS usando a VPC default da regiao
- Security group com UDP `2456-2457` aberto para Valheim e sem SSH inbound
- IAM instance profile com `AmazonSSMManagedInstanceCore` para acesso via Session Manager
- Lambda Function URL publica para receber interactions do Discord
- IAM da Lambda para iniciar, parar e consultar a EC2

Nao ha Elastic IP por padrao. O IPv4 publico muda depois de stop/start.

## Uso Terraform

Copie o exemplo de variaveis:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edite `terraform.tfvars` com os IDs e a public key do app do Discord.

Inicialize e aplique:

```powershell
terraform init
terraform fmt
terraform validate
terraform apply
```

Configure o output `lambda_function_url` como Interactions Endpoint URL no Discord Developer Portal.

Registre o comando no servidor:

```powershell
.\scripts\register-discord-commands.bat
```

Ou exporte as variaveis manualmente:

```powershell
$env:DISCORD_APPLICATION_ID="000000000000000000"
$env:DISCORD_GUILD_ID="000000000000000000"
$env:DISCORD_BOT_TOKEN="token_do_bot"
$env:DISCORD_COMMAND_NAME="valheim"
node scripts/register-discord-commands.mjs
```

## Comandos Discord

- `/valheim start`: liga a EC2 e retorna o IPv4 publico novo
- `/valheim ip`: mostra o IPv4 publico atual se a EC2 estiver rodando
- `/valheim stop`: para a EC2

## Layout Na EC2

- binarios do servidor: `/opt/valheim`
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
- instala o Valheim Dedicated Server em `/opt/valheim`
- cria `/etc/valheim/valheim.env`
- cria o servico `systemd` `valheim.service`
- gera um `start-valheim.sh` que carrega BepInEx automaticamente se os arquivos de mod existirem em `/opt/valheim`

## Configurar Mundo

Arquivos do mundo no Windows: veja [scripts/valheim-world-paths.md](C:/Users/Zo/Documents/GitHub/AWSValhein/scripts/valheim-world-paths.md)

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

Extraia o zip diretamente em `/opt/valheim` na EC2, por exemplo depois de baixar para `/tmp`:

```bash
sudo systemctl stop valheim
sudo unzip /tmp/valheim-server-mods.zip -d /opt/valheim
sudo chown -R valheim:valheim /opt/valheim/BepInEx /opt/valheim/doorstop_libs
sudo systemctl restart valheim
sudo systemctl status valheim
```

Nao existe um segundo script para mods. O mesmo `start-valheim.sh` gerado pelo instalador detecta BepInEx e ativa Doorstop automaticamente.

## Acesso Ao Servidor

Use AWS Systems Manager Session Manager com o instance ID mostrado no output `ssm_instance_target`.

Nao ha porta 22 aberta.

## Observacoes

- Esta base suporta jogo vanilla e modado com o mesmo servico `systemd`
- `terraform destroy` remove a EC2 e pode apagar dados se nao houver backup/snapshot
- o root EBS persiste em stop/start
