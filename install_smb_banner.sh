#!/bin/bash

# Autor: Wesley Marques
# Descrição: Instalar e configurar SAMBA4 para ADDC ou File Server (membro de domínio)
# Versão: 0.9.1
# Licença: MIT License

# Variáveis configuráveis
DEFAULT_SAMBA_VERSION="4.14.7"
SAMBA_VERSION=""
LINK_PACK_SAMBA=""
PACK_SAMBA=""
DIR_UNPACK_SAMBA=""
TIMEZONE="America/Sao_Paulo"
DNS_FORWARDER="8.8.8.8"
LOG_FILE="/var/log/samba-install.log"
SCRIPT_VERSION="0.9.1"
SAMBA_CONF_DIR="/usr/local/samba/etc"
SAMBA_CONF="$SAMBA_CONF_DIR/samba/smb.conf"

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

# Função para perguntar a versão do Samba e validar no FTP
ask_samba_version() {
  log "Solicitando versão do Samba para instalação"
  while true; do
    read -p "Digite a versão do Samba que deseja instalar (ex.: 4.18.1, padrão: $DEFAULT_SAMBA_VERSION): " INPUT_VERSION
    SAMBA_VERSION=${INPUT_VERSION:-$DEFAULT_SAMBA_VERSION}
    # Validar formato da versão (X.Y.Z)
    if [[ ! "$SAMBA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      log "Versão inválida! Use o formato X.Y.Z (ex.: 4.18.1)"
      continue
    fi

    # Construir a URL para verificar
    LINK_PACK_SAMBA="https://download.samba.org/pub/samba/stable/samba-$SAMBA_VERSION.tar.gz"
    PACK_SAMBA="samba-$SAMBA_VERSION.tar.gz"
    DIR_UNPACK_SAMBA="samba-$SAMBA_VERSION"

    # Verificar se o arquivo existe no FTP
    if curl --output /dev/null --silent --head --fail "$LINK_PACK_SAMBA"; then
      log "Versão $SAMBA_VERSION encontrada no FTP. Prosseguindo..."
      break
    else
      log "A versão $SAMBA_VERSION não foi encontrada no FTP (https://download.samba.org/pub/samba/stable/)."
      # Listar algumas versões disponíveis como sugestão
      AVAILABLE_VERSIONS=$(curl -s https://download.samba.org/pub/samba/stable/ | grep -oP 'samba-\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 5)
      if [ -n "$AVAILABLE_VERSIONS" ]; then
        log "Versões disponíveis (últimas 5):"
        echo "$AVAILABLE_VERSIONS" | while read -r version; do
          log "  - $version"
        done
      fi
      log "Por favor, digite uma versão válida."
    fi
  done
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
    winbind libnss-winbind libpam-winbind ipcalc || {
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

  # Garantir que os arquivos de esquema estejam presentes
  log "Verificando arquivos de esquema"
  SCHEMA_DIR="/usr/local/samba/share/setup/ad-schema"
  if [ ! -d "$SCHEMA_DIR" ] || [ ! -f "$SCHEMA_DIR/Windows Server 2012 R2.ldf" ]; then
    log "Arquivos de esquema ausentes. Tentando copiar do diretório de origem..."
    mkdir -p "$SCHEMA_DIR"
    cp -rv /usr/src/"$DIR_UNPACK_SAMBA"/source4/setup/ad-schema/* "$SCHEMA_DIR" || {
      log "Falha ao copiar arquivos de esquema"
      exit 19
    }
  fi

  cp -v /usr/src/"$DIR_UNPACK_SAMBA"/bin/default/packaging/systemd/samba.service /etc/systemd/system/samba-ad-dc.service
  mkdir -pv "$SAMBA_CONF_DIR"
  echo 'SAMBAOPTIONS="-D"' >"$SAMBA_CONF_DIR/sysconfig/samba"
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

  # Remover smb.conf existente em /etc/samba para evitar conflitos
  if [ -f /etc/samba/smb.conf ]; then
    log "Removendo smb.conf existente em /etc/samba para evitar conflitos"
    rm -f /etc/samba/smb.conf || {
      log "Falha ao remover /etc/samba/smb.conf"
      exit 16
    }
  fi

  # Remover smb.conf no destino, se existir
  if [ -f "$SAMBA_CONF" ]; then
    log "Removendo smb.conf existente em $SAMBA_CONF para evitar conflitos"
    rm -f "$SAMBA_CONF" || {
      log "Falha ao remover $SAMBA_CONF"
      exit 16
    }
  fi

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

  # Executar provisionamento sem especificar --configfile
  log "Executando provisionamento do domínio"
  samba-tool domain provision --use-rfc2307 --domain="$NETBIOS" --realm="$FQDN" \
    --dns-backend=SAMBA_INTERNAL || {
    log "Falha no provisionamento"
    exit 9
  }

  # Mover smb.conf gerado para o local desejado
  GENERATED_CONF="/usr/local/samba/etc/smb.conf"
  if [ -f "$GENERATED_CONF" ]; then
    log "Movendo smb.conf gerado para $SAMBA_CONF"
    mkdir -p "$SAMBA_CONF_DIR/samba"
    mv "$GENERATED_CONF" "$SAMBA_CONF" || {
      log "Falha ao mover smb.conf para $SAMBA_CONF"
      exit 18
    }
  else
    log "Arquivo smb.conf não foi gerado pelo provisionamento"
    exit 18
  fi

  # Copiar krb5.conf gerado para /etc
  rm -f /etc/krb5.conf
  cp -v /usr/local/samba/share/setup/krb5.conf /etc/krb5.conf || {
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
    path = /usr/local/samba/var/locks/sysvol/$FQDN/scripts
    read only = No

[sysvol]
    path = /usr/local/samba/var/locks/sysvol
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

  # Remover smb.conf existente em /etc/samba para evitar conflitos
  if [ -f /etc/samba/smb.conf ]; then
    log "Removendo smb.conf existente em /etc/samba para evitar conflitos"
    rm -f /etc/samba/smb.conf || {
      log "Falha ao remover /etc/samba/smb.conf"
      exit 16
    }
  fi

  # Remover smb.conf no destino, se existir
  if [ -f "$SAMBA_CONF" ]; then
    log "Removendo smb.conf existente em $SAMBA_CONF para evitar conflitos"
    rm -f "$SAMBA_CONF" || {
      log "Falha ao remover $SAMBA_CONF"
      exit 16
    }
  fi

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

  # configurar /etc/hosts
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

  # Criar diretório para smb.conf
  mkdir -p "$SAMBA_CONF_DIR/samba"

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
    ask_samba_version
    update_system
    adjust_datetime
    install_dependencies
    install_samba
    provision_addc
    ;;
  2)
    ask_samba_version
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
show_banner
configure_network
show_menu
