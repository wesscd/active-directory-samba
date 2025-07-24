#!/bin/bash

# Autor: Wesley Marques
# Descrição: Instalar e configurar SAMBA4 para ADDC ou File Server (membro de domínio) usando APT
# Versão: 1.0
# Licença: MIT License

# Variáveis configuráveis
TIMEZONE="America/Sao_Paulo"
DNS_FORWARDER="8.8.8.8"
LOG_FILE="/var/log/samba-install.log"
SCRIPT_VERSION="1.0"
SAMBA_CONF="/etc/samba/smb.conf"

# Função para registrar logs
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
check_os_compatibility() {
  if ! command -v apt >/dev/null 2>&1; then
    log "Seu sistema operacional não é compatível com este script"
    exit 2
  fi
  if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu\|Debian"; then
    log "Este script foi projetado para Ubuntu/Debian"
    exit 2
  fi
}

# Função para exibir o banner
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
  netmask)
    if [[ ! $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      log "Máscara de sub-rede inválida! Use o formato xxx.xxx.xxx.xxx"
      return 1
    fi
    valid_masks=("0.0.0.0" "128.0.0.0" "192.0.0.0" "224.0.0.0" "240.0.0.0" "248.0.0.0"
      "252.0.0.0" "254.0.0.0" "255.0.0.0" "255.128.0.0" "255.192.0.0"
      "255.224.0.0" "255.240.0.0" "255.248.0.0" "255.252.0.0" "255.254.0.0"
      "255.255.0.0" "255.255.128.0" "255.255.192.0" "255.255.224.0"
      "255.255.240.0" "255.255.248.0" "255.255.252.0" "255.255.254.0"
      "255.255.255.0" "255.255.255.128" "255.255.255.192" "255.255.255.224"
      "255.255.255.240" "255.255.255.248" "255.255.255.252" "255.255.255.254"
      "255.255.255.255")
    if ! printf '%s\n' "${valid_masks[@]}" | grep -Fx "$input" >/dev/null; then
      log "Máscara de sub-rede inválida! Use uma máscara válida (ex.: 255.255.255.0)"
      return 1
    fi
    ;;
  esac
  return 0
}

# Função para configurar a rede
configure_network() {
  log "Iniciando configuração de rede"

  INTERFACE=$(ip link | grep -E '^[0-9]+: (eth|ens|enp|eno|wlan)' | awk '{print $2}' | cut -d':' -f1 | head -n 1)
  if [ -z "$INTERFACE" ]; then
    log "Nenhuma interface de rede detectada"
    exit 13
  fi
  log "Interface de rede detectada: $INTERFACE"

  NETWORK_MANAGER=""
  if command -v nmcli >/dev/null 2>&1 && systemctl is-active NetworkManager >/dev/null 2>&1; then
    NETWORK_MANAGER="NetworkManager"
  elif command -v networkctl >/dev/null 2>&1 && systemctl is-active systemd-networkd >/dev/null 2>&1; then
    NETWORK_MANAGER="systemd-networkd"
  elif [ -f /etc/network/interfaces ]; then
    NETWORK_MANAGER="ifupdown"
  else
    log "Nenhum gerenciador de rede compatível detectado (NetworkManager, systemd-networkd, ifupdown)"
    exit 14
  fi
  log "Gerenciador de rede detectado: $NETWORK_MANAGER"

  while true; do
    read -p "Informe o endereço IP fixo (ex.: 192.168.1.100): " IP_ADDRESS
    validate_network_input "$IP_ADDRESS" ip && break
  done
  while true; do
    read -p "Informe a máscara de sub-rede (ex.: 255.255.255.0): " NETMASK
    validate_network_input "$NETMASK" netmask && break
  done
  while true; do
    read -p "Informe o gateway (ex.: 192.168.1.1): " GATEWAY
    validate_network_input "$GATEWAY" gateway && break
  done
  while true; do
    read -p "Informe o DNS primário (ex.: 8.8.8.8): " DNS1
    validate_network_input "$DNS1" dns && break
  done
  read -p "Informe o DNS secundário (opcional, ex.: 8.8.4.4): " DNS2
  if [ -n "$DNS2" ]; then
    validate_network_input "$DNS2" dns || DNS2=""
  fi

  case $NETWORK_MANAGER in
  NetworkManager)
    log "Configurando rede via NetworkManager"
    nmcli con mod "$INTERFACE" ipv4.addresses "$IP_ADDRESS/$(ipcalc -p "$IP_ADDRESS" "$NETMASK" | grep PREFIX | cut -d'=' -f2)" \
      ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1${DNS2:+,$DNS2}" ipv4.method manual || {
      log "Falha ao configurar NetworkManager"
      exit 15
    }
    nmcli con up "$INTERFACE" || {
      log "Falha ao ativar interface $INTERFACE"
      exit 15
    }
    ;;
  systemd-networkd)
    log "Configurando rede via systemd-networkd"
    cat >/etc/systemd/network/20-wired.network <<EOF
[Match]
Name=$INTERFACE

[Network]
Address=$IP_ADDRESS/$(ipcalc -p "$IP_ADDRESS" "$NETMASK" | grep PREFIX | cut -d'=' -f2)
Gateway=$GATEWAY
DNS=$DNS1
${DNS2:+DNS=$DNS2}
EOF
    systemctl restart systemd-networkd || {
      log "Falha ao reiniciar systemd-networkd"
      exit 15
    }
    ;;
  ifupdown)
    log "Configurando rede via ifupdown"
    cat >/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDRESS
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS1${DNS2:+ $DNS2}
EOF
    ifdown "$INTERFACE" && ifup "$INTERFACE" || {
      log "Falha ao reiniciar interface $INTERFACE"
      exit 15
    }
    ;;
  esac

  log "Configuração de rede aplicada com sucesso"
}

# Função para atualizar o sistema
update_system() {
  log "Atualizando repositórios"
  apt update && apt upgrade -y || {
    log "Falha na atualização do sistema"
    exit 3
  }
}

# Função para ajustar data e hora
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
  ntpdate pool.ntp.org || {
    log "Falha ao sincronizar hora"
    exit 4
  }
  service ntp start
}

# Função para instalar o Samba via APT
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
provision_addc() {
  log "Iniciando o Provisionamento do ADDC"
  systemctl stop systemd-resolved.service
  systemctl disable systemd-resolved.service

  # Remover smb.conf existente para evitar conflitos
  if [ -f "$SAMBA_CONF" ]; then
    log "Removendo smb.conf existente em $SAMBA_CONF para evitar conflitos"
    rm -f "$SAMBA_CONF" || {
      log "Falha ao remover $SAMBA_CONF"
      exit 16
    }
  fi

  log "Configurando ADDC"
  while true; do
    read -p "Informe o domínio (ex.: laboratorio.local): " DOMAIN
    validate_input "$DOMAIN" domain && break
  done
  while true; do
    read -p "Informe o NetBIOS do domínio (ex.: addc, apenas letras e hífens, sem números, máx. 15 caracteres): " NETBIOS
    validate_input "$NETBIOS" netbios && break
  done
  # Construir o FQDN como NETBIOS.DOMAIN
  FQDN="${NETBIOS}.${DOMAIN}"
  log "FQDN gerado: $FQDN"
  while true; do
    read -p "Informe o hostname (ex.: serveraddc, pode conter números): " HOSTNAME
    validate_input "$HOSTNAME" hostname && break
  done
  read -p "Digite o DNS forwarder (padrão: $DNS_FORWARDER): " INPUT_DNS
  DNS_FORWARDER=${INPUT_DNS:-$DNS_FORWARDER}

  # Detectar IP local
  IP=$(ip addr show | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1)
  if [ -z "$IP" ]; then
    log "Não foi possível detectar o IP local"
    exit 8
  fi

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

  # Copiar krb5.conf gerado para /etc
  rm -f /etc/krb5.conf
  cp -v /usr/share/samba/setup/krb5.conf /etc/krb5.conf || {
    log "Falha ao copiar krb5.conf"
    exit 17
  }

  FQDN=${FQDN,,}

  # Atualizar smb.conf com configurações adicionais
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

  # Ajustar permissões do diretório
  chown root:root "$SAMBA_CONF"
  chmod 644 "$SAMBA_CONF"

  systemctl start samba-ad-dc.service || {
    log "Falha ao iniciar o serviço Samba"
    exit 10
  }
  log "Serviço SAMBA (ADDC) instalado com sucesso."
}

# Função para provisionar o File Server como membro de domínio
provision_fileserver() {
  log "Iniciando o Provisionamento do File Server (Membro de Domínio)"
  systemctl stop systemd-resolved.service
  systemctl disable systemd-resolved.service

  # Remover smb.conf existente para evitar conflitos
  if [ -f "$SAMBA_CONF" ]; then
    log "Removendo smb.conf existente em $SAMBA_CONF para evitar conflitos"
    rm -f "$SAMBA_CONF" || {
      log "Falha ao remover $SAMBA_CONF"
      exit 16
    }
  fi

  log "Configurando File Server"
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
  while true; do
    read -p "Informe o usuário administrador do domínio (ex.: Administrator): " ADMIN_USER
    validate_input "$ADMIN_USER" username && break
  done
  read -s -p "Informe a senha do administrador: " ADMIN_PASS
  echo

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
  chown ":$DOMAIN_NETBIOS\\Domain Users" /srv/samba/share
  chmod 770 /srv/samba/share

  # Ingressar no domínio
  log "Ingressando no domínio"
  net ads join -U "$ADMIN_USER%$ADMIN_PASS" || {
    log "Falha ao ingressar no domínio"
    exit 12
  }

  # Iniciar serviços
  log "Iniciando serviços"
  systemctl start samba-ad-dc.service || {
    log "Falha ao iniciar o serviço Samba"
    exit 10
  }
  systemctl start winbind.service || {
    log "Falha ao iniciar o serviço Winbind"
    exit 10
  }

  log "Serviço SAMBA (File Server - Membro de Domínio) instalado com sucesso."
}

# Função para exibir o menu
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
    log "Opção inválida!"
    sleep 2
    show_menu
    ;;
  esac
}

# Execução principal
exec > >(tee -a "$LOG_FILE") 2>&1
clear
check_root
check_os_compatibility
show_banner
configure_network
show_menu
