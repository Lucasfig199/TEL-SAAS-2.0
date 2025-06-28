#!/bin/bash

# =============================================================================
# SCRIPT DE INSTALAÇÃO AUTOMATIZADA - TELEGRAM SAAS MULTI-CONTA v3.0
# =============================================================================
# Autor: Desenvolvido para replicação rápida em VPS Ubuntu 22.04
# Versão: 3.0 (Cria ambiente virtual do zero - Máxima Compatibilidade)
# Data: 28/06/2025
# =============================================================================

set -e  # Parar execução em caso de erro

# Configurar ambiente não-interativo
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log colorido
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para verificar se comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Função para verificar se é Ubuntu 22.04
check_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "22.04" ]]; then
            return 0
        fi
    fi
    return 1
}

# Banner de início
echo -e "${BLUE}"
echo "============================================================================="
echo "    INSTALADOR AUTOMÁTICO - TELEGRAM SAAS MULTI-CONTA v3.0"
echo "    (Cria ambiente virtual do zero - Máxima Compatibilidade)"
echo "============================================================================="
echo -e "${NC}"

# Verificar se é root ou tem sudo
if [[ $EUID -ne 0 ]] && ! command_exists sudo; then
    log_error "Este script precisa ser executado como root ou com sudo disponível"
    exit 1
fi

# Verificar versão do Ubuntu
if ! check_ubuntu_version; then
    log_warning "Este script foi testado apenas no Ubuntu 22.04"
    log_info "Continuando mesmo assim..."
fi

# Definir diretório de instalação
INSTALL_DIR="/root/telegram-saas"
GITHUB_URL="https://github.com/Lucasfig199/TEL-SAAS-2.0/blob/main/telegram-saas.v3.zip"

log_info "Iniciando instalação da plataforma Telegram SaaS..."

# 1. Configurar repositórios e atualizar sistema
log_info "Configurando ambiente não-interativo e atualizando sistema..."

# Configurar debconf para não fazer perguntas
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Configurar para manter configurações locais por padrão
echo 'openssh-server openssh-server/permit-root-login select true' | debconf-set-selections

# Atualizar sistema sem interações
if command_exists sudo; then
    sudo -E apt-get update -qq
    sudo -E apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    sudo -E apt-get install -y -qq python3 python3-pip python3-venv wget unzip curl
else
    apt-get update -qq
    apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    apt-get install -y -qq python3 python3-pip python3-venv wget unzip curl
fi

log_success "Sistema atualizado e dependências instaladas"

# 2. Criar diretório e baixar projeto
log_info "Baixando projeto do GitHub..."
cd /tmp

# Remover arquivo anterior se existir
rm -f telegram-saas.v3.zip

# Baixar com retry em caso de falha
for i in {1..3}; do
    if wget -q --timeout=30 -O telegram-saas.v3.zip "$GITHUB_URL"; then
        break
    else
        log_warning "Tentativa $i falhou, tentando novamente..."
        sleep 2
    fi
done

if [[ ! -f telegram-saas.v3.zip ]]; then
    log_error "Falha ao baixar o projeto do GitHub após 3 tentativas"
    exit 1
fi

log_success "Projeto baixado com sucesso"

# 3. Extrair e preparar diretório
log_info "Extraindo projeto e preparando ambiente..."

# Remover diretório existente se houver
if [[ -d "$INSTALL_DIR" ]]; then
    log_warning "Diretório $INSTALL_DIR já existe. Fazendo backup..."
    mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Remover extração anterior se existir
rm -rf telegram-saas.v3

# Extrair projeto
unzip -q telegram-saas.v3.zip

# Verificar se a extração foi bem-sucedida
if [[ ! -d telegram-saas.v3 ]]; then
    log_error "Falha ao extrair o projeto"
    exit 1
fi

# Criar diretório final
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/static"

# Copiar apenas os arquivos necessários (SEM o venv)
cp telegram-saas.v3/telegram_api_v3.py "$INSTALL_DIR/"
cp telegram-saas.v3/config.json "$INSTALL_DIR/"
cp telegram-saas.v3/static/index.html "$INSTALL_DIR/static/"

log_success "Arquivos do projeto copiados para $INSTALL_DIR"

# 4. Criar ambiente virtual do zero
log_info "Criando ambiente virtual Python do zero..."
cd "$INSTALL_DIR"

# Remover venv antigo se existir
rm -rf venv

# Criar novo ambiente virtual
python3 -m venv venv

# Ativar ambiente virtual e instalar dependências
source venv/bin/activate
pip install --upgrade pip
pip install telethon flask requests

# Verificar se as dependências foram instaladas corretamente
if ! python -c "import telethon, flask, requests" 2>/dev/null; then
    log_error "Falha ao instalar dependências Python"
    exit 1
fi

deactivate

log_success "Ambiente virtual criado e dependências instaladas"

# 5. Limpar arquivos de configuração para nova instalação
log_info "Limpando configurações para nova instalação..."
rm -f accounts.json
rm -f session_*.session

# Criar arquivo config.json padrão (sem webhook configurado)
cat > config.json << 'EOF'
{
  "webhook_url": ""
}
EOF

log_success "Configurações limpas para nova instalação"

# 6. Verificar se o ambiente está funcionando
log_info "Testando ambiente Python..."
if "$INSTALL_DIR/venv/bin/python" -c "import telethon, flask, requests; print('✅ Todas as dependências OK')" 2>/dev/null; then
    log_success "Ambiente Python verificado e funcionando"
else
    log_error "Problema com o ambiente Python"
    exit 1
fi

# 7. Criar arquivos de serviço systemd
log_info "Configurando serviços systemd..."

# Parar serviço se já estiver rodando
systemctl stop telegram-api 2>/dev/null || true

# Serviço da API
cat > /etc/systemd/system/telegram-api.service << EOF
[Unit]
Description=Telegram API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python telegram_api_v3.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=telegram-api
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

log_success "Serviços systemd configurados"

# 8. Recarregar systemd e habilitar serviços
log_info "Habilitando e iniciando serviços..."
systemctl daemon-reload
systemctl enable telegram-api

# 9. Iniciar serviço
log_info "Iniciando serviço telegram-api..."
systemctl start telegram-api

# Aguardar alguns segundos para o serviço inicializar
sleep 8

# 10. Verificar status do serviço com retry
log_info "Verificando status do serviço..."
for i in {1..5}; do
    if systemctl is-active --quiet telegram-api; then
        log_success "Serviço telegram-api iniciado com sucesso"
        break
    else
        if [[ $i -eq 5 ]]; then
            log_error "Falha ao iniciar o serviço telegram-api"
            log_info "Verificando logs do serviço..."
            systemctl status telegram-api --no-pager -l
            journalctl -u telegram-api --no-pager -l -n 20
            exit 1
        else
            log_info "Aguardando serviço inicializar... (tentativa $i/5)"
            sleep 3
        fi
    fi
done

# 11. Obter IP da VPS
log_info "Obtendo IP da VPS..."
VPS_IP=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || curl -s --max-time 10 ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}' || echo "SEU_IP_VPS")

# 12. Testar se a API está respondendo
log_info "Testando conectividade da API..."
sleep 3
if curl -s --max-time 10 "http://localhost:5000/api/status" >/dev/null 2>&1; then
    log_success "API está respondendo corretamente"
else
    log_warning "API pode não estar respondendo ainda (aguardando mais alguns segundos...)"
    sleep 5
    if curl -s --max-time 10 "http://localhost:5000/api/status" >/dev/null 2>&1; then
        log_success "API está respondendo corretamente"
    else
        log_warning "API ainda não está respondendo - verifique os logs"
    fi
fi

# 13. Criar script de gerenciamento
log_info "Criando script de gerenciamento..."
cat > /usr/local/bin/telegram-saas << 'EOF'
#!/bin/bash

case "$1" in
    start)
        systemctl start telegram-api
        echo "Serviço iniciado"
        ;;
    stop)
        systemctl stop telegram-api
        echo "Serviço parado"
        ;;
    restart)
        systemctl restart telegram-api
        echo "Serviço reiniciado"
        ;;
    status)
        systemctl status telegram-api --no-pager
        ;;
    logs)
        journalctl -u telegram-api -f
        ;;
    dashboard)
        VPS_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
        echo "Dashboard disponível em: http://$VPS_IP:5000"
        ;;
    test)
        echo "Testando API..."
        if curl -s --max-time 10 "http://localhost:5000/api/status" >/dev/null 2>&1; then
            echo "✅ API está funcionando"
        else
            echo "❌ API não está respondendo"
        fi
        ;;
    install-deps)
        echo "Reinstalando dependências Python..."
        cd /root/telegram-saas
        source venv/bin/activate
        pip install --upgrade telethon flask requests
        deactivate
        echo "Dependências reinstaladas"
        ;;
    *)
        echo "Uso: telegram-saas {start|stop|restart|status|logs|dashboard|test|install-deps}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/telegram-saas

log_success "Script de gerenciamento criado em /usr/local/bin/telegram-saas"

# 14. Configurar firewall se ufw estiver ativo
if command_exists ufw && ufw status | grep -q "Status: active"; then
    log_info "Configurando firewall para porta 5000..."
    ufw allow 5000/tcp >/dev/null 2>&1 || true
    log_success "Firewall configurado"
fi

# 15. Criar arquivo requirements.txt para referência
cat > "$INSTALL_DIR/requirements.txt" << 'EOF'
telethon
flask
requests
EOF

# 16. Limpeza
log_info "Limpando arquivos temporários..."
rm -f /tmp/telegram-saas.v3.zip
rm -rf /tmp/telegram-saas.v3

# 17. Exibir informações finais
echo
echo -e "${GREEN}============================================================================="
echo "    INSTALAÇÃO v3.0 CONCLUÍDA COM SUCESSO!"
echo "=============================================================================${NC}"
echo
echo -e "${BLUE}📋 INFORMAÇÕES DA INSTALAÇÃO:${NC}"
echo "   • Diretório: $INSTALL_DIR"
echo "   • Serviço: telegram-api.service"
echo "   • Dashboard: http://$VPS_IP:5000"
echo "   • Status: $(systemctl is-active telegram-api)"
echo "   • Ambiente Virtual: Criado do zero nesta máquina"
echo
echo -e "${BLUE}🚀 COMANDOS ÚTEIS:${NC}"
echo "   • telegram-saas start        - Iniciar serviço"
echo "   • telegram-saas stop         - Parar serviço"
echo "   • telegram-saas restart      - Reiniciar serviço"
echo "   • telegram-saas status       - Ver status"
echo "   • telegram-saas logs         - Ver logs em tempo real"
echo "   • telegram-saas dashboard    - Mostrar URL do dashboard"
echo "   • telegram-saas test         - Testar se API está funcionando"
echo "   • telegram-saas install-deps - Reinstalar dependências Python"
echo
echo -e "${BLUE}📱 PRÓXIMOS PASSOS:${NC}"
echo "   1. Acesse o dashboard: http://$VPS_IP:5000"
echo "   2. Vá para a aba 'Contas'"
echo "   3. Conecte suas contas Telegram"
echo "   4. Configure o webhook se necessário"
echo
echo -e "${YELLOW}⚠️  IMPORTANTE:${NC}"
echo "   • Certifique-se de que a porta 5000 está aberta no firewall"
echo "   • Use 'telegram-saas logs' para monitorar problemas"
echo "   • Use 'telegram-saas test' para verificar se a API está funcionando"
echo "   • O arquivo de configuração está em: $INSTALL_DIR/config.json"
echo "   • Dependências Python: $INSTALL_DIR/requirements.txt"
echo
echo -e "${GREEN}✅ Instalação v3.0 finalizada! Ambiente virtual criado do zero.${NC}"

# 18. Teste final
echo
log_info "Executando teste final..."
sleep 2
telegram-saas test

echo

