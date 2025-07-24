#!/bin/bash

# Autor: Seu Nome
# Descrição: Script para gerenciar compartilhamentos do Samba de forma dinâmica.
# Versão: 0.1
# Licença: MIT License

# --- Variáveis e Funções Globais ---

# Cores para a saída
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/samba-manage-shares.log"
SAMBA_CONF="/etc/samba/smb.conf"

# Função para registrar logs com cores
log() {
  local message=$1
  local level=${2:-INFO}
  local color=$NC

  case $level in
    SUCCESS) color=$GREEN ;;
    WARN) color=$YELLOW ;;
    ERROR) color=$RED ;;
    INFO) color=$CYAN ;;
  esac

  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] ${message}${NC}" | tee -a "$LOG_FILE"
}

# Função para criar backup de um arquivo
backup_file() {
  local file=$1
  if [ -f "$file" ]; then
    local backup_file="${file}.backup_$(date +%F-%T)"
    log "Criando backup de $file em $backup_file"
    cp "$file" "$backup_file" || log "AVISO: Falha ao criar backup de $file" "WARN"
  fi
}

# Função para verificar se o usuário tem permissões de root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log "Este script precisa ser executado com privilégios de administrador (root)." "ERROR"
    exit 1
  fi
}

# --- Funções de Gerenciamento de Compartilhamentos ---

create_share() {
    log "Iniciando a criação de um novo compartilhamento..." "INFO"

    # --- Coletar Informações ---
    read -p "Digite o nome do novo compartilhamento (ex: Documentos): " share_name
    if [ -z "$share_name" ]; then
        log "O nome do compartilhamento não pode ser vazio." "ERROR"
        sleep 2
        return
    fi

    read -p "Digite o caminho completo para o diretório (ex: /srv/samba/docs): " share_path
    if [ -z "$share_path" ]; then
        log "O caminho do diretório não pode ser vazio." "ERROR"
        sleep 2
        return
    fi

    # --- Criar Diretório ---
    if [ -d "$share_path" ]; then
        log "O diretório '$share_path' já existe. Usando o diretório existente." "WARN"
    else
        log "Criando o diretório '$share_path'..."
        mkdir -p "$share_path"
        if [ $? -ne 0 ]; then
            log "Não foi possível criar o diretório '$share_path'." "ERROR"
            sleep 2
            return
        fi
        log "Diretório criado com sucesso." "SUCCESS"
    fi

    # --- Coletar Informações de Permissão ---
    log "A seguir, vamos configurar as permissões."
    read -p "O compartilhamento será somente leitura para todos? (s/n): " is_read_only

    # --- Configurar Permissões e Atualizar smb.conf ---
    read -p "Digite o nome do grupo do AD que terá acesso principal (ex: Domain Users): " owner_group

    local read_only_param="no"
    local write_list_param=""

    if [[ "$is_read_only" =~ ^[Ss]$ ]]; then
        read_only_param="yes"
        log "Configurando como somente leitura para todos."
        chmod -R 755 "$share_path"
    else
        read -p "Deseja permitir escrita apenas para um grupo específico? (s/n): " specific_write_group
        if [[ "$specific_write_group" =~ ^[Ss]$ ]]; then
            read -p "Digite o nome do grupo com permissão de escrita: " write_group
            write_list_param="@$write_group"
            log "Acesso de escrita restrito ao grupo '$write_group'."
        else
            log "Acesso de escrita permitido para todos os usuários válidos."
        fi
        chmod -R 775 "$share_path"
    fi

    chown -R "root:$owner_group" "$share_path"
    log "Proprietário do diretório definido como 'root:$owner_group'."

    # --- Atualizar smb.conf ---
    log "Adicionando configuração ao $SAMBA_CONF..."
    backup_file "$SAMBA_CONF"

    cat >> "$SAMBA_CONF" << EOF

[${share_name}]
    path = ${share_path}
    read only = ${read_only_param}
    browsable = yes
    valid users = @${owner_group}
    write list = ${write_list_param}
EOF

    log "Configuração do compartilhamento '$share_name' adicionada com sucesso." "SUCCESS"

    # --- Recarregar Configuração do Samba ---
    log "Recarregando a configuração do Samba para aplicar as alterações..."
    smbcontrol all reload-config
    if [ $? -eq 0 ]; then
        log "Configuração do Samba recarregada com sucesso." "SUCCESS"
    else
        log "Falha ao recarregar a configuração do Samba. Reinicie o serviço manualmente." "ERROR"
    fi

    read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
}

list_shares() {
    log "Listando compartilhamentos existentes..." "INFO"

    # Usar testparm para validar e exibir a configuração dos compartilhamentos
    # O grep filtra para mostrar apenas as seções de compartilhamento
    samba-tool testparm -s --suppress-prompt | grep -E "\[.*\]"

    if [ $? -ne 0 ]; then
        log "Nenhum compartilhamento encontrado ou erro ao ler a configuração." "WARN"
    fi

    echo ""
    read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
}

# --- Menu Principal ---
show_menu() {
    clear
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}   Gerenciador de Compartilhamentos Samba    ${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo "1. Criar um novo compartilhamento"
    echo "2. Listar compartilhamentos existentes"
    echo "3. Sair"
    echo -e "${CYAN}=============================================${NC}"
    read -p "Escolha uma opção (1-3): " choice

    case $choice in
        1) create_share ;;
        2) list_shares ;;
        3) log "Saindo do script." "INFO"; exit 0 ;;
        *) log "Opção inválida!" "ERROR"; sleep 2 ;;
    esac
}


# --- Execução Principal ---
exec > >(tee -a "$LOG_FILE") 2>&1
clear
check_root

log "Script de Gerenciamento de Compartilhamentos Samba iniciado."

while true; do
    show_menu
done
