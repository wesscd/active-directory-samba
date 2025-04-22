#!/bin/bash

# Autor: Wesley Marques
# Descrição: Verificar e remover completamente uma instalação do Samba
# Versão: 1.0
# Licença: MIT License

# Variáveis configuráveis
LOG_FILE="/var/log/samba-remove.log"
SCRIPT_VERSION="1.0"

# Função para registrar logs
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Função para verificar se o usuário tem permissões de root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log "Você precisa de privilégios de administrador para executar este script"
    exit 1
  fi
}

# Função para exibir o banner
show_banner() {
  clear
  cat <<EOF
    ""
    ""
    "████████╗███████╗ ██████╗██╗  ██╗    ██████╗ ███████╗███╗   ███╗ ██████╗ ████████╗███████╗"
    "╚══██╔══╝██╔════╝██╔════╝██║  ██║    ██╔══██╗██╔════╝████╗ ████║██╔═══██╗╚══██╔══╝██╔====╝"
    "   ██║   █████╗  ██║     ███████║    ██████╔╝████X╗  ██╔████╔██║██║   ██║   ██║   █████╗  "
    "   ██║   ██╔══╝  ██║     ██╔══██║    ██╔══██╗██╔══╝  ██║╚██╔╝██║██║   ██║   ██║   ██╔══╝  "
    "   ██║   ███████╗╚██████╗██║  ██║    ██║  ██║███████╗██║ ╚═╝ ██║╚██████╔╝   ██║   ███████╗"
    "   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝    ╚═╝   ╚══════╝"
    "                                                                                  v$SCRIPT_VERSION"
    ""
    "Bem-vindo ao Samba4 Installer"
    "Este script instalará e configurará o Samba como ADDC ou File Server."
    ""
    "╔═════════════════════════════════════════════════════════════════════════════════════════╗"
    "╠═══════════════════════════════ Informações do Sistema ══════════════════════════════════╣"
    "╚═════════════════════════════════════════════════════════════════════════════════════════╝"
    ""
    "≫ Nome do Host: $HOSTNAME"
    "≫ Sistema Operacional: $OS_NAME"
    "≫ Versão do SO: $OS_VERSION"
    "≫ Processador: $PROCESSOR"
    "≫ Memória RAM: $RAM_GB GB"
    ""
    "Pressione qualquer tecla para continuar..."
EOF
  read -n 1 -s
}

# Função para verificar a instalação do Samba
check_samba_installation() {
  log "Verificando a instalação do Samba..."

  # Verificar serviços em execução
  SERVICES=("samba-ad-dc" "smbd" "nmbd" "winbind")
  SERVICES_RUNNING=false
  for service in "${SERVICES[@]}"; do
    if systemctl is-active "$service" >/dev/null 2>&1; then
      log "Serviço $service está em execução"
      SERVICES_RUNNING=true
    fi
  done

  # Verificar pacotes instalados via APT
  PACKAGES=("samba" "samba-common" "samba-libs" "samba-vfs-modules" "winbind")
  PACKAGES_INSTALLED=false
  for pkg in "${PACKAGES[@]}"; do
    if dpkg -l | grep -qw "$pkg"; then
      log "Pacote $pkg está instalado"
      PACKAGES_INSTALLED=true
    fi
  done

  # Verificar instalação manual em /usr/local/samba
  if [ -d "/usr/local/samba" ]; then
    log "Instalação manual do Samba encontrada em /usr/local/samba"
    SAMBA_MANUAL=true
  else
    SAMBA_MANUAL=false
  fi

  # Verificar arquivos de configuração
  CONFIG_FILES=("/etc/samba/smb.conf" "/usr/local/samba/etc/samba/smb.conf")
  CONFIG_FOUND=false
  for config in "${CONFIG_FILES[@]}"; do
    if [ -f "$config" ]; then
      log "Arquivo de configuração encontrado: $config"
      CONFIG_FOUND=true
    fi
  done

  # Verificar diretórios de dados e logs
  DATA_DIRS=("/var/lib/samba" "/var/log/samba" "/usr/local/samba/var")
  DATA_FOUND=false
  for dir in "${DATA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
      log "Diretório de dados/logs encontrado: $dir"
      DATA_FOUND=true
    fi
  done

  # Resumo
  if ! $SERVICES_RUNNING && ! $PACKAGES_INSTALLED && ! $SAMBA_MANUAL && ! $CONFIG_FOUND && ! $DATA_FOUND; then
    log "Nenhuma instalação do Samba foi encontrada no sistema"
    exit 0
  else
    log "Instalação do Samba detectada. Prosseguindo com a remoção..."
  fi
}

# Função para remover a instalação do Samba
remove_samba() {
  log "Iniciando remoção do Samba..."

  # Parar e desativar serviços
  log "Parando e desativando serviços do Samba..."
  SERVICES=("samba-ad-dc" "smbd" "nmbd" "winbind")
  for service in "${SERVICES[@]}"; do
    if systemctl is-active "$service" >/dev/null 2>&1; then
      systemctl stop "$service" || log "Falha ao parar o serviço $service"
    fi
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
      systemctl disable "$service" || log "Falha ao desativar o serviço $service"
    fi
    # Remover arquivos de serviço, se existirem
    if [ -f "/etc/systemd/system/$service.service" ]; then
      rm -f "/etc/systemd/system/$service.service" || log "Falha ao remover /etc/systemd/system/$service.service"
    fi
  done
  systemctl daemon-reload

  # Remover pacotes instalados via APT
  log "Removendo pacotes do Samba instalados via APT..."
  apt-get purge -y samba samba-common samba-libs samba-vfs-modules winbind || {
    log "Falha ao remover pacotes do Samba via APT"
  }
  apt-get autoremove -y || log "Falha ao remover dependências não utilizadas"
  apt-get autoclean || log "Falha ao limpar o cache do APT"

  # Remover instalação manual em /usr/local/samba
  if [ -d "/usr/local/samba" ]; then
    log "Removendo instalação manual do Samba em /usr/local/samba..."
    rm -rf /usr/local/samba || {
      log "Falha ao remover /usr/local/samba"
      exit 2
    }
  fi

  # Remover arquivos de configuração
  log "Removendo arquivos de configuração..."
  CONFIG_FILES=("/etc/samba" "/usr/local/samba/etc")
  for config in "${CONFIG_FILES[@]}"; do
    if [ -d "$config" ]; then
      rm -rf "$config" || log "Falha ao remover $config"
    fi
  done

  # Remover diretórios de dados e logs
  log "Removendo diretórios de dados e logs..."
  DATA_DIRS=("/var/lib/samba" "/var/log/samba" "/usr/local/samba/var" "/srv/samba")
  for dir in "${DATA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
      rm -rf "$dir" || log "Falha ao remover $dir"
    fi
  done

  # Limpar entradas no PATH do root, se existirem
  if grep -q "/usr/local/samba" /root/.bashrc; then
    log "Removendo entradas do Samba no PATH do /root/.bashrc..."
    sed -i '/\/usr\/local\/samba/d' /root/.bashrc || log "Falha ao limpar o PATH no /root/.bashrc"
  fi

  # Limpar entradas no nsswitch.conf, se existirem
  if grep -q "winbind" /etc/nsswitch.conf; then
    log "Removendo entradas do Winbind no /etc/nsswitch.conf..."
    sed -i '/winbind/d' /etc/nsswitch.conf || log "Falha ao limpar o /etc/nsswitch.conf"
    # Restaurar configurações padrão
    echo "passwd: compat" >>/etc/nsswitch.conf
    echo "group: compat" >>/etc/nsswitch.conf
    echo "shadow: compat" >>/etc/nsswitch.conf
  fi

  log "Remoção do Samba concluída com sucesso"
}

# Execução principal
exec > >(tee -a "$LOG_FILE") 2>&1
clear
check_root
show_banner
check_samba_installation
remove_samba
