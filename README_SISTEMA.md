# 🧸 Sistema de Controle de Estoque de Brinquedos

Aplicação Python completa para gestão de estoque de brinquedos infantis, com interface intuitiva e controle financeiro abrangente.

## ✨ Funcionalidades

### 📊 Dashboard
- Visão geral com cards estatísticos coloridos
- Total de produtos cadastrados
- Valor total em estoque
- Vendas dos últimos 30 dias
- Lucro do período
- Alerta de produtos com estoque baixo
- Gráfico de vendas mensal

### 📦 Gerenciamento de Produtos
- Cadastro completo de produtos com:
  - Nome, categoria, marca
  - Faixa etária recomendada
  - Preço de custo e venda
  - Quantidade em estoque
  - Estoque mínimo para alerta
  - Descrição detalhada
- Edição e exclusão de produtos
- Tabela com status de estoque (OK/BAIXO)

### 💰 Registro de Vendas
- Seleção rápida de produtos
- Controle de quantidade disponível
- Registro de cliente
- Múltiplas formas de pagamento:
  - Dinheiro
  - Cartão de Crédito
  - Cartão de Débito
  - PIX
- Histórico de vendas recentes
- Atualização automática do estoque

### 🛒 Registro de Compras/Entradas
- Entrada de novos produtos no estoque
- Registro de fornecedor
- **Anexo de Nota Fiscal** (PDF, PNG, JPG)
- As notas fiscais são salvas na pasta `anexos_notas/`
- Atualização automática do estoque

### 💵 Controle Financeiro
- Entradas e saídas consolidadas
- Cálculo automático de lucro
- Visualização por período:
  - Mensal
  - Anual
- Gráficos interativos por aba

### 📈 Relatórios Detalhados
- Filtros por período:
  - **Semanal** (últimos 7 dias)
  - **Mensal** (últimos 30 dias)
  - **Anual** (últimos 365 dias)
- Resumo numérico completo:
  - Total de vendas
  - Entradas financeiras
  - Saídas financeiras
  - Lucro líquido
- Tabela detalhada de todas as vendas
- **Exportação para Excel** (.xlsx)

### ⚙️ Configurações
- Troca de tema (Dark/Light/System)
- Backup automático do banco de dados
- Informações do sistema

## 🚀 Instalação

### Pré-requisitos
- Python 3.8 ou superior
- pip (gerenciador de pacotes Python)

### Instalar dependências

```bash
pip install customtkinter pillow pandas matplotlib openpyxl
```

## ▶️ Como Executar

```bash
python controle_estoque_brinquedos.py
```

## 📁 Estrutura do Projeto

```
/workspace/
├── controle_estoque_brinquedos.py    # Aplicação principal
├── estoque_brinquedos.db             # Banco de dados SQLite (criado automaticamente)
├── anexos_notas/                     # Pasta para notas fiscais anexadas
└── README.md                         # Este arquivo
```

## 💾 Banco de Dados

O sistema utiliza SQLite com as seguintes tabelas:

- **produtos**: Cadastro de brinquedos
- **vendas**: Registro de todas as vendas
- **compras**: Registro de entradas/compras
- **movimentacoes_financeiras**: Controle financeiro completo

## 🎨 Interface

A aplicação utiliza **CustomTkinter** para uma interface moderna com:
- Tema escuro padrão (configurável)
- Cards coloridos para estatísticas
- Gráficos matplotlib integrados
- Tabelas organizadas com Treeview
- Menu lateral de navegação

## 🔐 Recursos de Segurança

- Backup manual do banco de dados
- Confirmação antes de excluir registros
- Validação de dados nos formulários
- Controle de estoque mínimo

## 📊 Relatórios Exportáveis

Os relatórios podem ser exportados para Excel com:
- Planilha "Vendas": Detalhamento completo
- Planilha "Resumo": Métricas consolidadas

## 🛠️ Tecnologias Utilizadas

- **Python 3.12**
- **CustomTkinter**: Interface gráfica moderna
- **SQLite**: Banco de dados leve
- **Pandas**: Manipulação de dados
- **Matplotlib**: Gráficos e visualizações
- **Pillow**: Processamento de imagens
- **OpenPyXL**: Exportação para Excel

## 📝 Uso Típico

1. **Cadastro Inicial**: Registre todos os produtos na tela "Produtos"
2. **Entradas**: Ao receber mercadoria, use "Compras" e anexe a NF
3. **Vendas Diárias**: Registre cada venda em "Vendas"
4. **Acompanhamento**: Consulte o "Dashboard" para visão geral
5. **Relatórios**: Gere relatórios semanais/mensais/anuais
6. **Backup**: Faça backup periódico em "Configurações"

## ⚠️ Importante

- Mantenha backups regulares do banco de dados
- A pasta `anexos_notas/` deve ter permissão de escrita
- O sistema é offline - os dados ficam armazenados localmente

## 📞 Suporte

Para questões ou melhorias, consulte o código fonte que está totalmente comentado e estruturado.

---

**Desenvolvido com ❤️ em Python**
