# Como restaurar um backup do banco (crm_db_backup)

Os dumps ficam no volume `crm_db_backups`, dentro do container `crm_db_backup`, organizados em `/backups/daily`, `/backups/weekly` e `/backups/monthly` (arquivos `.sql.gz`).

## 1. Listar os backups disponíveis

Via Portainer, abrir o console do container `crm_db_backup` (ou `docker exec`, se tiver acesso direto ao servidor):

```bash
ls -la /backups/daily
ls -la /backups/weekly
ls -la /backups/monthly
```

## 2. Restaurar num banco de teste (NUNCA direto em produção sem testar antes)

Copie o arquivo `.sql.gz` desejado para fora do container, ou rode direto de dentro dele. Exemplo restaurando no próprio Postgres de produção como um banco **novo e separado**, só para conferir se o dump está íntegro:

```bash
# dentro do container crm_db (ou de um Postgres qualquer com acesso à rede inoovawebpro)
gunzip -c /backups/daily/crm_production-<data>.sql.gz | psql -h crm_db -U crm -d postgres -c "CREATE DATABASE crm_restore_test;"
gunzip -c /backups/daily/crm_production-<data>.sql.gz | psql -h crm_db -U crm -d crm_restore_test
```

Depois de confirmar que os dados estão corretos, apague o banco de teste:

```bash
psql -h crm_db -U crm -d postgres -c "DROP DATABASE crm_restore_test;"
```

## 3. Restaurar de verdade em produção (só em caso de perda de dado real)

**Isso substitui o banco de produção — só fazer com confirmação explícita do usuário.**

```bash
# Parar o backend/worker antes, para não haver escrita durante a restauração
gunzip -c /backups/daily/crm_production-<data>.sql.gz | psql -h crm_db -U crm -d crm_production
```

## Observação

Este backup é **só local no servidor** — protege contra erro humano (registro apagado sem querer, migration ruim) mas **não protege contra perda total do servidor** (disco corrompido, servidor inteiro fora do ar). Se quiser essa proteção extra no futuro, dá para configurar o mesmo container para enviar uma cópia pra um serviço externo tipo Backblaze B2 (é só adicionar `S3_*`/`AWS_*` nas variáveis de ambiente do `crm_db_backup`, sem precisar trocar de banco de dados).
