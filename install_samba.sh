#!/bin/bash

# Autor: Wesley Marques
# Descrição: Instalar e configurar SAMBA4 para ADDC ou File Server (membro de domínio)
# Versão: 0.4
# Licença: MIT License

# Variáveis configuráveis
DEFAULT_SAMBA_VERSION="4.14.7"
SAMBA_VERSION="$DEFAULT_SAMBA_VERSION"
LINK_PACK_SAMBA="https://download.samba.org/pub/samba/stable/samba-$SAMBA_VERSION.tar.gz"
PACK_SAMBA="samba-$SAMBA_VERSION.tar.gz"
DIR_UNPACK_SAMBA="samba-$SAMBA_VERSION"
TIMEZONE="America/Sao_Paulo"
DNS_FORWARDER="8.8.8.8"
LOG_FILE="/var/log/samba-install.log"

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
  # Verificar versão do Ubuntu/Debian
  if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu\|Debian"; then
    log "Este script foi projetado para Ubuntu/Debian"
    exit 2
  fi
}

# Função para verificar a versão mais recente do Samba
check_samba_version() {
  log "Verificando a versão mais recente do Samba..."
  LATEST_VERSION=$(curl -s https://www.samba.org/samba/ftp/stable/ | grep -oP 'samba-\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1)
  if [ -z "$LATEST_VERSION" ]; then
    log "Não foi possível verificar a versão mais recente. Usando $SAMBA_VERSION."
    return
  fi
  log "Versão mais recente disponível: $LATEST_VERSION"
  read -p "Deseja usar a versão mais recente ($LATEST_VERSION) em vez de $SAMBA_VERSION? (s/n): " USE_LATEST
  if [[ "$USE_LATEST" =~ ^[Ss]$ ]]; then
    SAMBA_VERSION="$LATEST_VERSION"
    LINK_PACK_SAMBA="https://download.samba.org/pub/samba/stable/samba-$SAMBA_VERSION.tar.gz"
    PACK_SAMBA="samba-$SAMBA_VERSION.tar.gz"
    DIR_UNPACK_SAMBA="samba-$SAMBA_VERSION"
    log "Versão atualizada para $SAMBA_VERSION"
  fi
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

# Função para instalar dependências
install_dependencies() {
  log "Instalando dependências"
  apt-get install -y wget acl attr autoconf bind9utils bison build-essential \
    debhelper dnsutils docbook-xml docbook-xsl flex gdb libjansson-dev krb5-user \
    libacl1-dev libaio-dev libarchive-dev libattr1-dev libblkid-dev libbsd-dev \
    libcap-dev libcups2-dev libgnutls28-dev libgpgme-dev libjson-perl libldap2-dev \
    libncurses5-dev libpam0g-dev libparse-yapp-perl libpopt-dev libreadline-dev \
    nettle-dev perl pkg-config python3-dev python3-dnspython python3-gpg python3-markdown \
    xsltproc zlib1g-dev liblmdb-dev lmdb-utils libsystemd-dev libdbus-1-dev libtasn1-bin \
    winbind libnss-winbind libpam-winbind || {
    log "Falha ao instalar dependências"
    exit 5
  }

  apt-get -y autoremove
  apt-get -y autoclean
  apt-get -y clean
}

# Função para preparar e instalar o Samba
install_samba() {
  log "Preparando SAMBA4"
  cd /usr/src/
  wget -c "$LINK_PACK_SAMBA" || {
    log "Falha ao baixar o Samba"
    exit 6
  }
  tar -xf "$PACK_SAMBA" || {
    log "Falha ao extrair o Samba"
    exit 6
  }
  cd "$DIR_UNPACK_SAMBA"

  log "Configurando SAMBA 01/03 - systemd fhs"
  ./configure --with-systemd --prefix=/usr/local/samba --enable-fhs || {
    log "Falha na configuração"
    exit 7
  }

  log "Configurando SAMBA 02/03 - make install"
  make && make install || {
    log "Falha na compilação/instalação"
    exit 7
  }

  log "Configurando SAMBA 03/03 - path"
  echo "PATH=$PATH:/usr/local/samba/bin:/usr/local/samba/sbin" >>/root/.bashrc
  source /root/.bashrc

  cp -v /usr/src/"$DIR_UNPACK_SAMBA"/bin/default/packaging/systemd/samba.service /etc/systemd/system/samba-ad-dc.service
  mkdir -pv /usr/local/samba/etc/sysconfig
  echo 'SAMBAOPTIONS="-D"' >/usr/local/samba/etc/sysconfig/samba
  systemctl daemon-reload
  systemctl enable samba-ad-dc.service
}

# Função para validar entradas do usuário
validate_input() {
  local input=$1
  local type=$2
  case $type in
  fqdn)
    if [[ ! $input =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      log "FQDN inválido!"
      return 1
    fi
    ;;
  netbios | hostname | username)
    if [[ ! $input =~ ^[a-zA-Z0-9-]+$ ]]; then
      log "$type inválido! Use apenas letras, números e hífens."
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

  log "Configurando ADDC"
  while true; do
    read -p "Informe o FQDN (Ex.: addc01.company.local): " FQDN
    validate_input "$FQDN" fqdn && break
  done
  while true; do
    read -p "Informe o NetBIOS (Ex.: addc01): " NETBIOS
    validate_input "$NETBIOS" netbios && break
  done
  while true; do
    read -p "Informe o hostname (Ex.: serveraddc): " HOSTNAME
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

  samba-tool domain provision --use-rfc2307 --domain="$NETBIOS" --realm="$FQDN" || {
    log "Falha no provisionamento"
    exit 9
  }
  rm -f /etc/krb5.conf
  cp -bv /usr/local/samba/var/lib/samba/private/krb5.conf /etc/krb5.conf

  FQDN=${FQDN,,}

  echo "
[global]
    dns forwarder = $DNS_FORWARDER
    netbios name = $NETBIOS
    realm = $FQDN
    server role = active directory domain controller
    workgroup = $NETBIOS
    idmap_ldb:use rfc2307 = yes

[netlogon]
    path = /usr/local/samba/var/lib/samba/${FQDN}/scripts
    read only = No

[sysvol]
    path = /usr/local/samba/var/lib/samba/sysvol
    read only = No
" >/usr/local/samba/etc/samba/smb.conf

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

  log "Configurando File Server"
  while true; do
    read -p "Informe o hostname (Ex.: fileserver): " HOSTNAME
    validate_input "$HOSTNAME" hostname && break
  done
  while true; do
    read -p "Informe o FQDN do domínio (Ex.: company.local): " DOMAIN_FQDN
    validate_input "$DOMAIN_FQDN" fqdn && break
  done
  while true; do
    read -p "Informe o NetBIOS do domínio (Ex.: COMPANY): " DOMAIN_NETBIOS
    validate_input "$DOMAIN_NETBIOS" netbios && break
  done
  read -p "Digite o DNS forwarder (padrão: $DNS_FORWARDER): " INPUT_DNS
  DNS_FORWARDER=${INPUT_DNS:-$DNS_FORWARDER}
  while true; do
    read -p "Informe o usuário administrador do domínio (Ex.: Administrator): " ADMIN_USER
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
  log "Configurando smb.conf"
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
" >/usr/local/samba/etc/samba/smb.conf

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
    check_samba_version
    update_system
    adjust_datetime
    install_dependencies
    install_samba
    provision_addc
    ;;
  2)
    check_samba_version
    update_system
    adjust_datetime
    install_dependencies
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
show_menu
