#!/bin/bash

# Autor: Wesley Marques
# Descrição: Instalar e configurar SAMBA4 para ADDC ou File Server (membro de domínio) usando APT
# Versão: 0.8.2
# Licença: MIT License
# Notas: Este script assume que o endereçamento IP já está configurado no sistema.

# Variáveis configuráveis
TIMEZONE="America/Sao_Paulo"
DNS_FORWARDER="8.8.8.8"
LOG_FILE="/var/log/samba-install.log"
SCRIPT_VERSION="0.8.2"
SAMBA_CONF="/etc/samba/smb.conf"

# Função para registrar logs
# Registra mensagens com carimbo de data/hora no console e em arquivo
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Função para verificar se o usuário tem permissões de root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log "Você precisa de privilégios de administrador"
    exit 1
  fi
}

# Função para verificar a compatibilidade do sistema operacional
# Verifica se o sistema usa APT e é Ubuntu/Debian
check_os_compatibility() {
  if ! command -v apt >/dev/null 2>&1; then
    log "Seu sistema operacional não é compatível com este script"
    exit 2
  fi
  if ! command -v lsb_release >/dev/null 2>&1; then
    log "lsb_release não encontrado. Instalando..."
    apt install lsb-release -y || { log "Falha ao instalar lsb-release"; exit 18; }
  fi
  if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu\|Debian"; then
    log "Este script foi projetado para Ubuntu/Debian"
    exit 2
  fi
}

# Função para verificar dependências gerais
# Garante que ferramentas necessárias estejam instaladas
check_dependencies() {
  log "Verificando dependências"
  for cmd in ipcalc lscpu samba-tool; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "$cmd não encontrado. Instalando..."
      case $cmd in
        ipcalc)
          apt install ipcalc -y || { log "Falha ao instalar ipcalc"; exit 18; }
          ;;
        lscpu)
          apt install lscpu -y || { log "Falha ao instalar lscpu"; exit 18; }
          ;;
        samba-tool)
          apt install samba -y || { log "Falha ao instalar samba-tool"; exit 18; }
          ;;
      esac
    fi
  done
}

# Função para exibir o banner
# Exibe informações do sistema em formato visual
show_banner() {
  HOSTNAME=$(hostname)
  OS_NAME=$(lsb_release -d | cut -f2-)
  OS_VERSION=$(lsb_release -r | cut -f2)
  PROCESSOR=$(lscpu | grep "Model name" | cut -d':' -f2 | sed 's/^\s*//')
  RAM_GB=$(free -m | grep Mem | awk '{printf "%.1f", $2/1024}')

  clear
  cat <<EOF
    ""
    ""
    "████████╗███████╗ ██████╗██╗  ██╗    ██████╗ ███████╗███╗   ███╗ ██████╗ ████████╗███████╗"
    "╚══██╔══╝██╔════╝██╔════╝██║  ██║    ██╔══██╗██╔════╝████╗ ████║██╔═══██╗╚══██╔══╝██╔════╝"
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

# Função para validar endereços IP, máscara, gateway e DNS
validate_network_input() {
  local input=$1
  local type=$2
  case $type in
  ip | gateway | dns)
    if [[ ! $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      log "$type inválido! Use o formato xxx.xxx.xxx.xxx"
      return 1
    fi
    IFS='.' read -r -a octets <<<"$input"
    for octet in "${octets[@]}"; do
      if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
        log "$type inválido! Cada octeto deve estar entre 0 e 255"
        return 1
      fi
    done
    ;;
  esac
  return 0
}

# Função para configurar o firewall
# Abre portas necessárias para o Samba (445, 139, 88, 53)
configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    log "Configurando firewall com ufw"
    ufw allow Samba >/dev/null 2>&1
    ufw allow 88/tcp >/dev/null 2>&1
    ufw allow 53/tcp >/dev/null 2>&1
    ufw allow 53/udp >/dev/null 2>&1
    log "Regras de firewall aplicadas com sucesso"
  else
    log "ufw não encontrado, firewall não configurado"
  fi
}

# Função para atualizar o sistema
# Atualiza repositórios e pacotes
update_system() {
  log "Atualizando repositórios"
  apt update && apt upgrade -y || {
    log "Falha na atualização do sistema"
    exit 3
  }
}

# Função para ajustar data e hora
# Configura fuso horário e sincroniza com servidores NTP
adjust_datetime() {
  log "Ajustando data e hora"
  read -p "Digite o fuso horário (padrão: $TIMEZONE): " INPUT_TIMEZONE
  TIMEZONE=${INPUT_TIMEZONE:-$TIMEZONE}
  timedatectl set-timezone "$TIMEZONE"
  apt install ntp ntpdate -y || {
    log "Falha ao instalar NTP"
    exit 4
  }
  service ntp stop
  ntpdate pool.ntp.org || ntpdate time.google.com || {
    log "Falha ao sincronizar hora com todos os servidores NTP"
    exit 4
  }
  service ntp start
}

# Função para instalar o Samba via APT
# Instala pacotes necessários e configura serviços
install_samba() {
  log "Instalando SAMBA4 via APT"
  apt install -y samba samba-common samba-libs samba-vfs-modules winbind libnss-winbind libpam-winbind \
    krb5-user krb5-config || {
    log "Falha ao instalar o Samba via APT"
    exit 5
  }

  apt-get -y autoremove
  apt-get -y autoclean
  apt-get -y clean

  systemctl stop samba-ad-dc smbd nmbd winbind
  systemctl enable samba-ad-dc
}

# Função para validar entradas do usuário
# Valida domínio, NetBIOS, hostname e usuário
validate_input() {
  local input=$1
  local type=$2
  case $type in
  domain)
    if [[ ! $input =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      log "Domínio inválido! Use o formato dominio.local"
      return 1
    fi
    ;;
  netbios)
    if [[ ! $input =~ ^[a-zA-Z][a-zA-Z-]*$ ]]; then
      log "NetBIOS inválido! Use apenas letras e hífens, sem números."
      return 1
    fi
    if [ ${#input} -gt 15 ]; then
      log "NetBIOS inválido! Deve ter no máximo 15 caracteres."
      return 1
    fi
    ;;
  hostname)
    if [[ ! $input =~ ^[a-zA-Z0-9-]+$ ]]; then
      log "Hostname inválido! Use apenas letras, números e hífens."
      return 1
    fi
    ;;
  username)
    if [[ ! $input =~ ^[a-zA-Z0-9-]+$ ]]; then
      log "Usuário inválido! Use apenas letras, números e hífens."
      return 1
    fi
    ;;
  esac
  return 0
}

# Função para provisionar o AD
# Configura o Samba como Active Directory Domain Controller
provision_addc() {
  log "Iniciando o Provisionamento do ADDC"
  systemctl stop systemd-resolved.service
  systemctl disable systemd-resolved.service

  # Fazer backup de smb.conf existente
  if [ -f "$SAMBA_CONF" ]; then
    log "Fazendo backup de $SAMBA_CONF"
    cp "$SAMBA_CONF" "$SAMBA_CONF.bak" || {
      log "Falha ao fazer backup de $SAMBA_CONF"
      exit 16
    }
    log "Removendo smb.conf existente em $SAMBA_CONF para evitar conflitos"
    rm -f "$SAMBA_CONF" || {
      log "Falha ao remover $SAMBA_CONF"
      exit 16
    }
  fi

  log "Configurando ADDC"
  # Suporte a modo não interativo via variáveis de ambiente
  if [ -n "$SAMBA_DOMAIN" ] && [ -n "$SAMBA_NETBIOS" ] && [ -n "$SAMBA_HOSTNAME" ] && [ -n "$SAMBA_DNS" ]; then
    DOMAIN="$SAMBA_DOMAIN"
    NETBIOS="$SAMBA_NETBIOS"
    HOSTNAME="$SAMBA_HOSTNAME"
    DNS_FORWARDER="$SAMBA_DNS"
    validate_input "$DOMAIN" domain || exit 19
    validate_input "$NETBIOS" netbios || exit 19
    validate_input "$HOSTNAME" hostname || exit 19
    validate_network_input "$DNS_FORWARDER" dns || {
      log "DNS forwarder inválido"
      exit 19
    }
  else
    while true; do
      read -p "Informe o domínio (ex.: laboratorio.local): " DOMAIN
      validate_input "$DOMAIN" domain && break
    done
    while true; do
      read -p "Informe o NetBIOS do domínio (ex.: addc, apenas letras e hífens, sem números, máx. 15 caracteres): " NETBIOS
      validate_input "$NETBIOS" netbios && break
    done
    while true; do
      read -p "Informe o hostname (ex.: serveraddc, pode conter números): " HOSTNAME
      validate_input "$HOSTNAME" hostname && break
    done
    read -p "Digite o DNS forwarder (padrão: $DNS_FORWARDER): " INPUT_DNS
    DNS_FORWARDER=${INPUT_DNS:-$DNS_FORWARDER}
    validate_network_input "$DNS_FORWARDER" dns || {
      log "DNS forwarder inválido"
      exit 19
    }
  fi

  # Construir o FQDN
  FQDN="${NETBIOS}.${DOMAIN}"
  log "FQDN gerado: $FQDN"

  # Detectar IP local
  IP=$(ip addr show | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1)
  if [ -z "$IP" ]; then
    log "Não foi possível detectar o IP local"
    exit 8
  fi

  # Configurar /etc/hosts
  echo "
127.0.0.1 localhost
$IP $FQDN $HOSTNAME" >/etc/hosts

  echo "$HOSTNAME" >/etc/hostname

  # Executar provisionamento
  log "Executando provisionamento do domínio"
  samba-tool domain provision --use-rfc2307 --domain="$NETBIOS" --realm="$FQDN" \
    --dns-backend=SAMBA_INTERNAL || {
    log "Falha no provisionamento"
    exit 9
  }

  # Copiar krb5.conf gerado
  rm -f /etc/krb5.conf
  cp -v /usr/share/samba/setup/krb5.conf /etc/krb5.conf || {
    log "Falha ao copiar krb5.conf"
    exit 17
  }

  FQDN=${FQDN,,}

  # Atualizar smb.conf
  log "Atualizando smb.conf em $SAMBA_CONF"
  cat >"$SAMBA_CONF" <<EOF
[global]
    dns forwarder = $DNS_FORWARDER
    netbios name = $NETBIOS
    realm = $FQDN
    server role = active directory domain controller
    workgroup = $NETBIOS
    idmap_ldb:use rfc2307 = yes

[netlogon]
    path = /var/lib/samba/sysvol/$FQDN/scripts
    read only = No

[sysvol]
    path = /var/lib/samba/sysvol
    read only = No
EOF

  # Ajustar permissões
  chown root:root "$SAMBA_CONF"
  chmod 644 "$SAMBA_CONF"

  # Configurar firewall
  configure_firewall

  # Reiniciar serviço
  systemctl restart samba-ad-dc.service || {
    log "Falha ao reiniciar o serviço Samba"
    exit 10
  }
  log "Serviço SAMBA (ADDC) instalado com sucesso."
}

# Função para provisionar o File Server
# Configura o Samba como membro de domínio com compartilhamento de arquivos
provision_fileserver() {
  log "Iniciando o Provisionamento do File Server (Membro de Domínio)"
  systemctl stop systemd-resolved.service
  systemctl disable systemd-resolved.service

  # Fazer backup de smb.conf existente
  if [ -f "$SAMBA_CONF" ]; then
    log "Fazendo backup de $SAMBA_CONF"
    cp "$SAMBA_CONF" "$SAMBA_CONF.bak" || {
      log "Falha ao fazer backup de $SAMBA_CONF"
      exit 16
    }
    log "Removendo smb.conf existente em $SAMBA_CONF para evitar conflitos"
    rm -f "$SAMBA_CONF" || {
      log "Falha ao remover $SAMBA_CONF"
      exit 16
    }
  fi

  log "Configurando File Server"
  # Suporte a modo não interativo
  if [ -n "$SAMBA_HOSTNAME" ] && [ -n "$SAMBA_DOMAIN_FQDN" ] && [ -n "$SAMBA_DOMAIN_NETBIOS" ] && [ -n "$SAMBA_ADMIN_USER" ] && [ -n "$SAMBA_ADMIN_PASS" ] && [ -n "$SAMBA_DNS" ]; then
    HOSTNAME="$SAMBA_HOSTNAME"
    DOMAIN_FQDN="$SAMBA_DOMAIN_FQDN"
    DOMAIN_NETBIOS="$SAMBA_DOMAIN_NETBIOS"
    ADMIN_USER="$SAMBA_ADMIN_USER"
    ADMIN_PASS="$SAMBA_ADMIN_PASS"
    DNS_FORWARDER="$SAMBA_DNS"
    validate_input "$HOSTNAME" hostname || exit 19
    validate_input "$DOMAIN_FQDN" domain || exit 19
    validate_input "$DOMAIN_NETBIOS" netbios || exit 19
    validate_input "$ADMIN_USER" username || exit 19
    validate_network_input "$DNS_FORWARDER" dns || { log "DNS forwarder inválido"; exit 19; }
    if [ ${#ADMIN_PASS} -lt 8 ]; then
      log "A senha deve ter pelo menos 8 caracteres"
      exit 22
    fi
  else
    while true; do
      read -p "Informe o hostname (ex.: fileserver, pode conter números): " HOSTNAME
      validate_input "$HOSTNAME" hostname && break
    done
    while true; do
      read -p "Informe o FQDN do domínio (ex.: company.local): " DOMAIN_FQDN
      validate_input "$DOMAIN_FQDN" domain && break
    done
    while true; do
      read -p "Informe o NetBIOS do domínio (ex.: COMPANY, apenas letras e hífens, sem números, máx. 15 caracteres): " DOMAIN_NETBIOS
      validate_input "$DOMAIN_NETBIOS" netbios && break
    done
    read -p "Digite o DNS forwarder (padrão: $DNS_FORWARDER): " INPUT_DNS
    DNS_FORWARDER=${INPUT_DNS:-$DNS_FORWARDER}
    validate_network_input "$DNS_FORWARDER" dns || {
      log "DNS forwarder inválido"
      exit 19
    }
    while true; do
      read -p "Informe o usuário administrador do domínio (ex.: Administrator): " ADMIN_USER
      validate_input "$ADMIN_USER" username && break
    done
    read -s -p "Informe a senha do administrador: " ADMIN_PASS
    echo
    if [ ${#ADMIN_PASS} -lt 8 ]; then
      log "A senha deve ter pelo menos 8 caracteres"
      exit 22
    fi
  fi

  # Detectar IP local
  IP=$(ip addr show | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1)
  if [ -z "$IP" ]; then
    log "Não foi possível detectar o IP local"
    exit 8
  fi

  # Configurar /etc/hosts
  echo "
127.0.0.1 localhost
$IP $HOSTNAME" >/etc/hosts

  echo "$HOSTNAME" >/etc/hostname

  # Testar conectividade com o controlador de domínio
  log "Testando conectividade com o controlador de domínio"
  if ! ping -c 2 "$DOMAIN_FQDN" >/dev/null 2>&1; then
    log "Não foi possível alcançar o controlador de domínio $DOMAIN_FQDN"
    exit 21
  fi

  # Configurar Kerberos
  log "Configurando Kerberos"
  echo "
[libdefaults]
    default_realm = ${DOMAIN_FQDN^^}
    dns_lookup_realm = true
    dns_lookup_kdc = true

[realms]
    ${DOMAIN_FQDN^^} = {
        kdc = ${DOMAIN_FQDN,,}
        admin_server = ${DOMAIN_FQDN,,}
    }

[domain_realm]
    .${DOMAIN_FQDN,,} = ${DOMAIN_FQDN^^}
    ${DOMAIN_FQDN,,} = ${DOMAIN_FQDN^^}
" >/etc/krb5.conf

  # Testar Kerberos
  log "Testando autenticação Kerberos"
  echo "$ADMIN_PASS" | kinit "$ADMIN_USER@$DOMAIN_FQDN" || {
    log "Falha na autenticação Kerberos"
    exit 11
  }
  kdestroy

  # Configurar Winbind
  log "Configurando Winbind"
  echo "
passwd: compat winbind
group: compat winbind
shadow: compat
" >>/etc/nsswitch.conf

  # Configurar smb.conf
  log "Configurando smb.conf em $SAMBA_CONF"
  echo "
[global]
    workgroup = $DOMAIN_NETBIOS
    security = ads
    realm = $DOMAIN_FQDN
    netbios name = $HOSTNAME
    dns forwarder = $DNS_FORWARDER
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config $DOMAIN_NETBIOS : backend = rid
    idmap config $DOMAIN_NETBIOS : range = 10000-999999
    winbind use default domain = yes
    winbind offline logon = false
    winbind nss info = rfc2307
    winbind enum users = yes
    winbind enum groups = yes
    template shell = /bin/bash
    template homedir = /home/%U

[share]
    path = /srv/samba/share
    read only = no
    browsable = yes
    writable = yes
    valid users = @$DOMAIN_NETBIOS\\Domain\ Users
" >"$SAMBA_CONF"

  # Ajustar permissões do smb.conf
  chown root:root "$SAMBA_CONF"
  chmod 644 "$SAMBA_CONF"

  # Criar diretório de compartilhamento
  log "Criando diretório de compartilhamento"
  mkdir -p /srv/samba/share
  if ! getent group "$DOMAIN_NETBIOS\\Domain Users" >/dev/null; then
    log "Grupo $DOMAIN_NETBIOS\\Domain Users não encontrado"
    exit 20
  fi
  chown ":$DOMAIN_NETBIOS\\Domain Users" /srv/samba/share
  chmod 770 /srv/samba/share

  # Ingressar no domínio
  log "Ingressando no domínio"
  net ads join -U "$ADMIN_USER%$ADMIN_PASS" || {
    log "Falha ao ingressar no domínio"
    exit 12
  }

  # Configurar firewall
  configure_firewall

  # Reiniciar serviços
  log "Reiniciando serviços"
  systemctl restart samba-ad-dc.service || {
    log "Falha ao reiniciar o serviço Samba"
    exit 10
  }
  systemctl restart winbind.service || {
    log "Falha ao reiniciar o serviço Winbind"
    exit 10
  }

  log "Serviço SAMBA (File Server - Membro de Domínio) instalado com sucesso."
}

# Função para exibir o menu
# Apresenta opções para ADDC, File Server ou sair
show_menu() {
  clear
  echo "====================================="
  echo " Instalador SAMBA4"
  echo "====================================="
  echo "1. Instalar como Active Directory (ADDC)"
  echo "2. Instalar como File Server (Membro de Domínio)"
  echo "3. Sair"
  echo "====================================="
  read -p "Escolha uma opção (1-3): " choice
  case $choice in
  1)
    update_system
    adjust_datetime
    install_samba
    provision_addc
    ;;
  2)
    update_system
    adjust_datetime
    install_samba
    provision_fileserver
    ;;
  3)
    log "Saindo..."
    exit 0
    ;;
  *)
    log personaje "Opção inválida!"
    sleep 2
    show_menu
    ;;
  esac
}

# Execução principal
# Verifica pré-requisitos e inicia o processo
exec > >(tee -a "$LOG_FILE") 2>&1
clear
check_root
check_os_compatibility
check_dependencies
show_banner
show_menu
