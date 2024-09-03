#!/bin/bash

# Autor: Wesley Marques
# Descrição: Instalar e configurar SAMBA4 para ADDC
# Versão: 0.2
# Licença: MIT License

LINK_PACK_SAMBA="https://download.samba.org/pub/samba/stable/samba-4.14.7.tar.gz"
PACK_SAMBA="samba-4.14.7.tar.gz"
DIR_UNPACK_SAMBA="samba-4.14.7"

# Função para verificar se o usuário tem permissões de root
check_root() {
    if [ "$USER" != 'root' ]; then
        echo "------------------------------------"
        echo "Você precisa de privilégios de administrador"
        echo "------------------------------------"
        exit 1
    fi
}

# Função para verificar a compatibilidade do sistema operacional
check_os_compatibility() {
    command -v apt >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "------------------------------------------"
        echo "Seu sistema operacional não é compatível com este script"
        echo "------------------------------------------"
        exit 2
    fi
}

# Função para atualizar o sistema
update_system() {
    echo "------------------------------------"
    echo "Atualizando repositórios"
    echo "------------------------------------"
    apt update && apt upgrade -y
}

# Função para ajustar data e hora
adjust_datetime() {
    echo "------------------------------------"
    echo "Ajustando data e hora"
    echo "------------------------------------"
    timedatectl set-timezone America/Sao_Paulo
    apt install ntp ntpdate -y
    service ntp stop
    ntpdate a.st1.ntp.br
    service ntp start
}

# Função para instalar dependências
install_dependencies() {
    echo "----------------------------------------"
    echo "Gerando dependências para instalação"
    echo "----------------------------------------"
    apt-get install -y wget acl attr autoconf bind9utils bison build-essential \
        debhelper dnsutils docbook-xml docbook-xsl flex gdb libjansson-dev krb5-user \
        libacl1-dev libaio-dev libarchive-dev libattr1-dev libblkid-dev libbsd-dev \
        libcap-dev libcups2-dev libgnutls28-dev libgpgme-dev libjson-perl libldap2-dev \
        libncurses5-dev libpam0g-dev libparse-yapp-perl libpopt-dev libreadline-dev \
        nettle-dev perl pkg-config python-all-dev python2-dbg python-dev-is-python2 \
        python3-dnspython python3-gpg python3-markdown python3-dev xsltproc zlib1g-dev \
        liblmdb-dev lmdb-utils libsystemd-dev perl-modules-5.30 libdbus-1-dev libtasn1-bin
    
    apt-get -y autoremove
    apt-get -y autoclean
    apt-get -y clean
}

# Função para preparar e instalar o Samba
install_samba() {
    echo "------------------------------------"
    echo "Preparando SAMBA4"
    echo "------------------------------------"
    cd /usr/src/
    wget -c "$LINK_PACK_SAMBA"
    tar -xf "$PACK_SAMBA"
    cd "$DIR_UNPACK_SAMBA"

    echo "-------------------------------------"
    echo "Configurando SAMBA 01/03 - systemd fhs"
    echo "-------------------------------------"
    ./configure --with-systemd --prefix=/usr/local/samba --enable-fhs

    echo "--------------------------------------"
    echo "Configurando SAMBA 02/03 - make install"
    echo "--------------------------------------"
    make && make install

    echo "------------------------------------"
    echo "Configurando SAMBA 03/03 - path"
    echo "------------------------------------"
    echo "PATH=$PATH:/usr/local/samba/bin:/usr/local/samba/sbin" >> /root/.bashrc
    source /root/.bashrc

    cp -v /usr/src/samba-4.14.7/bin/default/packaging/systemd/samba.service /etc/systemd/system/samba-ad-dc.service
    mkdir -v /usr/local/samba/etc/sysconfig
    echo 'SAMBAOPTIONS="-D"' > /usr/local/samba/etc/sysconfig/samba
    systemctl daemon-reload
    systemctl enable samba-ad-dc.service
}

# Função para provisionar o AD
provision_addc() {
    echo "------------------------------------"
    echo "Iniciando o Provisionamento"
    echo "------------------------------------"
    systemctl stop systemd-resolved.service
    systemctl disable systemd-resolved.service

    echo "------------------------------------"
    echo "Configurando ADDC"
    echo "------------------------------------"
    echo "Informe o FQDN (Ex.: addc01.company.local):"
    read -r FQDN
    echo "Informe o NetBIOS (Ex.: addc01):"
    read -r NETBIOS
    echo "Informe o hostname (Ex.: serveraddc):"
    read -r HOSTNAME

    echo "
127.0.0.0 localhost
$IP $FQDN $HOSTNAME" > /etc/hosts

    echo "$HOSTNAME" > /etc/hostname

    samba-tool domain provision --use-rfc2307 --domain="$NETBIOS" --realm="$FQDN"
    rm /etc/krb5.conf
    cp -bv /usr/local/samba/var/lib/samba/private/krb5.conf /etc/krb5.conf

    FQDN=${FQDN,,}

    echo "
[global]
    dns forwarder = 8.8.8.8
    netbios name = $NETBIOS
    realm = $FQDN
    server role = active directory domain controller
    workgroup = $NETBIOS
    idmap_ldb:use rfc2307 = yes
    ldap server require strong auth = No

[netlogon]
    path = /usr/local/samba/var/lib/samba/${FQDN}/scripts
    read only = No

[sysvol]
    path = /usr/local/samba/var/lib/samba/sysvol
    read only = No
" > /usr/local/samba/etc/samba/smb.conf

    systemctl start samba-ad-dc.service
    echo "Serviço SAMBA instalado com sucesso."
}

# Execução das funções
clear
check_root
check_os_compatibility
update_system
adjust_datetime
install_dependencies
install_samba
provision_addc
