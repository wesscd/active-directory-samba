# Scripts de Instalação do Samba 4

Este repositório contém scripts para instalar e configurar o Samba 4 no Debian e em distribuições baseadas em Debian, como o Ubuntu.

## Scripts Disponíveis

*   `install_samba_unified.sh`: Um script completo para instalar o Samba 4 como um Active Directory Domain Controller (ADDC) ou como um File Server membro de um domínio.
*   `uninstall_samba.sh`: Um script para remover completamente uma instalação do Samba.

## Como Usar

### Pré-requisitos

*   Um sistema operacional Debian ou baseado em Debian (como o Ubuntu).
*   Acesso root ou privilégios de superusuário (sudo).
*   Conexão com a internet.

### Instalação

1.  **Clone o repositório:**

    ```bash
    git clone https://github.com/seu-usuario/seu-repositorio.git
    cd seu-repositorio
    ```

2.  **Torne o script de instalação executável:**

    ```bash
    chmod +x install_samba_unified.sh
    ```

3.  **Execute o script:**

    ```bash
    ./install_samba_unified.sh
    ```

    O script irá guiá-lo através do processo de instalação, solicitando as informações necessárias para configurar o Samba como um ADDC ou um File Server.

### Desinstalação

1.  **Torne o script de desinstalação executável:**

    ```bash
    chmod +x uninstall_samba.sh
    ```

2.  **Execute o script:**

    ```bash
    ./uninstall_samba.sh
    ```

    O script irá remover completamente o Samba do seu sistema.

## Contribuições

Contribuições são bem-vindas! Se você encontrar um bug ou tiver uma sugestão de melhoria, por favor, abra uma issue ou envie um pull request.

## Licença

Este projeto está licenciado sob a Licença MIT. Veja o arquivo `LICENSE` para mais detalhes.
