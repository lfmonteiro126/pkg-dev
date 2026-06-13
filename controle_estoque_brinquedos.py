#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sistema de Controle de Estoque de Brinquedos
Com interface intuitiva, controle financeiro completo, anexo de notas fiscais
e relatórios semanais, mensais e anuais.
"""

import customtkinter as ctk
from tkinter import filedialog, messagebox, ttk
from PIL import Image
import sqlite3
import os
import shutil
from datetime import datetime, timedelta
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import json

# Configuração inicial do CustomTkinter
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

class DatabaseManager:
    """Gerenciador do banco de dados SQLite"""
    
    def __init__(self, db_path="estoque_brinquedos.db"):
        self.db_path = db_path
        self.init_database()
    
    def init_database(self):
        """Inicializa o banco de dados com as tabelas necessárias"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Tabela de produtos
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS produtos (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                nome TEXT NOT NULL,
                categoria TEXT,
                marca TEXT,
                faixa_etaria TEXT,
                preco_custo REAL,
                preco_venda REAL,
                quantidade_estoque INTEGER,
                estoque_minimo INTEGER,
                descricao TEXT,
                data_cadastro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                ativo BOOLEAN DEFAULT 1
            )
        ''')
        
        # Tabela de vendas
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS vendas (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                produto_id INTEGER,
                quantidade INTEGER,
                preco_unitario REAL,
                total REAL,
                data_venda TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                cliente_nome TEXT,
                forma_pagamento TEXT,
                FOREIGN KEY (produto_id) REFERENCES produtos(id)
            )
        ''')
        
        # Tabela de compras/entradas
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS compras (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                produto_id INTEGER,
                quantidade INTEGER,
                preco_unitario REAL,
                total REAL,
                data_compra TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                fornecedor_nome TEXT,
                nota_fiscal_path TEXT,
                FOREIGN KEY (produto_id) REFERENCES produtos(id)
            )
        ''')
        
        # Tabela de movimentações financeiras
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS movimentacoes_financeiras (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tipo TEXT, -- 'entrada' ou 'saida'
                descricao TEXT,
                valor REAL,
                data_movimentacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                categoria TEXT,
                relacionado_id INTEGER,
                relacionado_tipo TEXT -- 'venda', 'compra', etc.
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def execute_query(self, query, params=()):
        """Executa uma query e retorna os resultados"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute(query, params)
        result = cursor.fetchall()
        conn.commit()
        last_id = cursor.lastrowid
        conn.close()
        return result, last_id
    
    def add_produto(self, nome, categoria, marca, faixa_etaria, preco_custo, 
                    preco_venda, quantidade, estoque_minimo, descricao=""):
        """Adiciona um novo produto"""
        query = '''
            INSERT INTO produtos (nome, categoria, marca, faixa_etaria, 
                                  preco_custo, preco_venda, quantidade_estoque,
                                  estoque_minimo, descricao)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        '''
        params = (nome, categoria, marca, faixa_etaria, preco_custo, 
                  preco_venda, quantidade, estoque_minimo, descricao)
        return self.execute_query(query, params)
    
    def update_produto(self, id_produto, **kwargs):
        """Atualiza um produto existente"""
        fields = []
        values = []
        for key, value in kwargs.items():
            fields.append(f"{key} = ?")
            values.append(value)
        values.append(id_produto)
        
        query = f"UPDATE produtos SET {', '.join(fields)} WHERE id = ?"
        return self.execute_query(query, tuple(values))
    
    def get_all_produtos(self, ativos_only=True):
        """Retorna todos os produtos"""
        if ativos_only:
            query = "SELECT * FROM produtos WHERE ativo = 1"
        else:
            query = "SELECT * FROM produtos"
        return self.execute_query(query)
    
    def delete_produto(self, id_produto):
        """Marca um produto como inativo"""
        query = "UPDATE produtos SET ativo = 0 WHERE id = ?"
        return self.execute_query(query, (id_produto,))
    
    def registrar_venda(self, produto_id, quantidade, preco_unitario, 
                       cliente_nome="", forma_pagamento="Dinheiro"):
        """Registra uma venda"""
        total = quantidade * preco_unitario
        
        # Inserir venda
        query_venda = '''
            INSERT INTO vendas (produto_id, quantidade, preco_unitario, 
                               total, cliente_nome, forma_pagamento)
            VALUES (?, ?, ?, ?, ?, ?)
        '''
        _, venda_id = self.execute_query(query_venda, 
            (produto_id, quantidade, preco_unitario, total, 
             cliente_nome, forma_pagamento))
        
        # Atualizar estoque
        query_update = "UPDATE produtos SET quantidade_estoque = quantidade_estoque - ? WHERE id = ?"
        self.execute_query(query_update, (quantidade, produto_id))
        
        # Registrar movimentação financeira
        query_fin = '''
            INSERT INTO movimentacoes_financeiras 
            (tipo, descricao, valor, categoria, relacionado_id, relacionado_tipo)
            VALUES (?, ?, ?, ?, ?, ?)
        '''
        self.execute_query(query_fin, 
            ('entrada', f'Venda de produto ID {produto_id}', total, 
             'Vendas', venda_id, 'venda'))
        
        return venda_id
    
    def registrar_compra(self, produto_id, quantidade, preco_unitario,
                        fornecedor_nome="", nota_fiscal_path=None):
        """Registra uma compra/entrada de produto"""
        total = quantidade * preco_unitario
        
        # Inserir compra
        query_compra = '''
            INSERT INTO compras (produto_id, quantidade, preco_unitario, 
                                total, fornecedor_nome, nota_fiscal_path)
            VALUES (?, ?, ?, ?, ?, ?)
        '''
        _, compra_id = self.execute_query(query_compra,
            (produto_id, quantidade, preco_unitario, total,
             fornecedor_nome, nota_fiscal_path))
        
        # Atualizar estoque
        query_update = "UPDATE produtos SET quantidade_estoque = quantidade_estoque + ? WHERE id = ?"
        self.execute_query(query_update, (quantidade, produto_id))
        
        # Registrar movimentação financeira
        query_fin = '''
            INSERT INTO movimentacoes_financeiras 
            (tipo, descricao, valor, categoria, relacionado_id, relacionado_tipo)
            VALUES (?, ?, ?, ?, ?, ?)
        '''
        self.execute_query(query_fin,
            ('saida', f'Compra de produto ID {produto_id}', total,
             'Compras', compra_id, 'compra'))
        
        return compra_id
    
    def get_relatorio_periodo(self, periodo='mensal'):
        """Gera relatório de vendas por período"""
        now = datetime.now()
        
        if periodo == 'semanal':
            start_date = now - timedelta(days=7)
        elif periodo == 'mensal':
            start_date = now - timedelta(days=30)
        else:  # anual
            start_date = now - timedelta(days=365)
        
        start_date_str = start_date.strftime('%Y-%m-%d %H:%M:%S')
        
        # Vendas no período
        query_vendas = '''
            SELECT v.data_venda, p.nome, v.quantidade, v.preco_unitario, v.total
            FROM vendas v
            JOIN produtos p ON v.produto_id = p.id
            WHERE v.data_venda >= ?
            ORDER BY v.data_venda DESC
        '''
        vendas, _ = self.execute_query(query_vendas, (start_date_str,))
        
        # Total de vendas
        query_total = '''
            SELECT SUM(total) FROM vendas WHERE data_venda >= ?
        '''
        total_result, _ = self.execute_query(query_total, (start_date_str,))
        total_vendas = total_result[0][0] if total_result[0][0] else 0
        
        # Movimentações financeiras
        query_fin = '''
            SELECT tipo, SUM(valor) FROM movimentacoes_financeiras 
            WHERE data_movimentacao >= ?
            GROUP BY tipo
        '''
        fin_result, _ = self.execute_query(query_fin, (start_date_str,))
        
        entradas = sum(r[1] for r in fin_result if r[0] == 'entrada')
        saidas = sum(r[1] for r in fin_result if r[0] == 'saida')
        
        return {
            'vendas': vendas,
            'total_vendas': total_vendas,
            'entradas': entradas,
            'saidas': saidas,
            'lucro': entradas - saidas
        }
    
    def get_estoque_atual(self):
        """Retorna o estoque atual de todos os produtos"""
        query = '''
            SELECT id, nome, categoria, quantidade_estoque, 
                   preco_custo, preco_venda, estoque_minimo
            FROM produtos WHERE ativo = 1
        '''
        return self.execute_query(query)
    
    def get_produtos_baixo_estoque(self):
        """Retorna produtos com estoque abaixo do mínimo"""
        query = '''
            SELECT id, nome, quantidade_estoque, estoque_minimo
            FROM produtos 
            WHERE quantidade_estoque <= estoque_minimo AND ativo = 1
        '''
        return self.execute_query(query)


class App(ctk.CTk):
    """Aplicação principal"""
    
    def __init__(self):
        super().__init__()
        
        self.db = DatabaseManager()
        self.title("Controle de Estoque de Brinquedos")
        self.geometry("1200x800")
        
        # Configurar grid principal
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)
        
        # Criar menu lateral
        self.criar_menu_lateral()
        
        # Criar área principal
        self.area_principal = ctk.CTkFrame(self)
        self.area_principal.grid(row=0, column=1, sticky="nsew", padx=10, pady=10)
        
        # Mostrar tela inicial
        self.mostrar_dashboard()
    
    def criar_menu_lateral(self):
        """Cria o menu lateral de navegação"""
        self.menu = ctk.CTkFrame(self, width=200, corner_radius=0)
        self.menu.grid(row=0, column=0, sticky="nsew")
        self.menu.grid_rowconfigure(8, weight=1)
        
        # Logo/Título
        titulo = ctk.CTkLabel(self.menu, text="🧸 Brinquedos\nEstoque", 
                              font=ctk.CTkFont(size=20, weight="bold"))
        titulo.grid(row=0, column=0, pady=20, padx=10)
        
        # Botões de navegação
        botoes = [
            ("📊 Dashboard", self.mostrar_dashboard),
            ("📦 Produtos", self.mostrar_produtos),
            ("💰 Vendas", self.mostrar_vendas),
            ("🛒 Compras", self.mostrar_compras),
            ("💵 Financeiro", self.mostrar_financeiro),
            ("📈 Relatórios", self.mostrar_relatorios),
            ("⚙️ Configurações", self.mostrar_configuracoes),
        ]
        
        for i, (texto, comando) in enumerate(botoes, start=1):
            btn = ctk.CTkButton(self.menu, text=texto, command=comando,
                               anchor="w", height=40)
            btn.grid(row=i, column=0, pady=5, padx=10, sticky="ew")
    
    def limpar_area_principal(self):
        """Limpa a área principal"""
        for widget in self.area_principal.winfo_children():
            widget.destroy()
    
    def mostrar_dashboard(self):
        """Mostra o dashboard com resumo geral"""
        self.limpar_area_principal()
        
        # Título
        titulo = ctk.CTkLabel(self.area_principal, text="Dashboard - Visão Geral",
                             font=ctk.CTkFont(size=24, weight="bold"))
        titulo.pack(pady=20)
        
        # Frame para cards de resumo
        cards_frame = ctk.CTkFrame(self.area_principal)
        cards_frame.pack(fill="x", padx=20, pady=10)
        
        # Obter dados do banco
        produtos_data, _ = self.db.get_all_produtos()
        estoque_data = self.db.get_estoque_atual()
        baixo_estoque = self.db.get_produtos_baixo_estoque()
        relatorio_mensal = self.db.get_relatorio_periodo('mensal')
        
        # Cards de estatísticas
        stats = [
            ("Total de Produtos", len(produtos_data), "#3498db"),
            ("Valor em Estoque", f"R$ {sum(p[4]*p[3] for p in estoque_data):.2f}", "#2ecc71"),
            ("Vendas (30 dias)", f"R$ {relatorio_mensal['total_vendas']:.2f}", "#e74c3c"),
            ("Lucro (30 dias)", f"R$ {relatorio_mensal['lucro']:.2f}", "#f39c12"),
            ("Baixo Estoque", len(baixo_estoque), "#9b59b6"),
        ]
        
        for i, (titulo, valor, cor) in enumerate(stats):
            card = ctk.CTkFrame(cards_frame, fg_color=cor)
            card.grid(row=0, column=i, padx=10, pady=10, sticky="ew")
            cards_frame.grid_columnconfigure(i, weight=1)
            
            lbl_titulo = ctk.CTkLabel(card, text=titulo, font=ctk.CTkFont(size=14))
            lbl_titulo.pack(pady=(10, 5))
            
            lbl_valor = ctk.CTkLabel(card, text=str(valor), 
                                    font=ctk.CTkFont(size=20, weight="bold"))
            lbl_valor.pack(pady=(0, 10))
        
        # Gráfico de vendas
        grafico_frame = ctk.CTkFrame(self.area_principal)
        grafico_frame.pack(fill="both", expand=True, padx=20, pady=10)
        
        self.criar_grafico_vendas_periodo(grafico_frame, 'mensal')
        
        # Alertas de estoque baixo
        if baixo_estoque:
            alertas_frame = ctk.CTkFrame(self.area_principal, fg_color="#e74c3c")
            alertas_frame.pack(fill="x", padx=20, pady=10)
            
            lbl_alerta = ctk.CTkLabel(alertas_frame, 
                                     text=f"⚠️ {len(baixo_estoque)} produto(s) com estoque baixo!",
                                     font=ctk.CTkFont(size=16, weight="bold"))
            lbl_alerta.pack(pady=10)
    
    def criar_grafico_vendas_periodo(self, parent, periodo):
        """Cria um gráfico de vendas por período"""
        relatorio = self.db.get_relatorio_periodo(periodo)
        
        # Processar dados para o gráfico
        vendas_df = pd.DataFrame(relatorio['vendas'], 
                                 columns=['data', 'produto', 'qtd', 'preco', 'total'])
        
        if not vendas_df.empty:
            vendas_df['data'] = pd.to_datetime(vendas_df['data'])
            
            if periodo == 'semanal':
                vendas_df['periodo'] = vendas_df['data'].dt.day_name()
            elif periodo == 'mensal':
                vendas_df['periodo'] = vendas_df['data'].dt.day
            else:
                vendas_df['periodo'] = vendas_df['data'].dt.month
            
            vendas_por_periodo = vendas_df.groupby('periodo')['total'].sum()
            
            # Criar figura matplotlib
            fig, ax = plt.subplots(figsize=(8, 4))
            ax.bar(range(len(vendas_por_periodo)), vendas_por_periodo.values)
            ax.set_xlabel('Período')
            ax.set_ylabel('Valor Vendido (R$)')
            ax.set_title(f'Vendas por {periodo.capitalize()}')
            ax.set_xticks(range(len(vendas_por_periodo)))
            ax.set_xticklabels([str(x) for x in vendas_por_periodo.index], rotation=45)
            
            plt.tight_layout()
            
            # Embed no tkinter
            canvas = FigureCanvasTkAgg(fig, master=parent)
            canvas.draw()
            canvas.get_tk_widget().pack(fill="both", expand=True)
    
    def mostrar_produtos(self):
        """Mostra a tela de gerenciamento de produtos"""
        self.limpar_area_principal()
        
        # Título
        titulo = ctk.CTkLabel(self.area_principal, text="Gerenciar Produtos",
                             font=ctk.CTkFont(size=24, weight="bold"))
        titulo.pack(pady=10)
        
        # Frame de formulário
        form_frame = ctk.CTkFrame(self.area_principal)
        form_frame.pack(fill="x", padx=20, pady=10)
        
        # Campos do formulário
        campos = [
            ("Nome:", "entry"),
            ("Categoria:", "entry"),
            ("Marca:", "entry"),
            ("Faixa Etária:", "entry"),
            ("Preço Custo:", "entry"),
            ("Preço Venda:", "entry"),
            ("Quantidade:", "entry"),
            ("Estoque Mínimo:", "entry"),
            ("Descrição:", "text"),
        ]
        
        self.campos_produto = {}
        
        for i, (label, tipo) in enumerate(campos):
            row = i // 4
            col = (i % 4) * 2
            
            lbl = ctk.CTkLabel(form_frame, text=label)
            lbl.grid(row=row, column=col, padx=5, pady=5, sticky="e")
            
            if tipo == "entry":
                entry = ctk.CTkEntry(form_frame, width=150)
                entry.grid(row=row, column=col+1, padx=5, pady=5, sticky="w")
                self.campos_produto[label[:-1]] = entry
            else:
                text = ctk.CTkTextbox(form_frame, width=300, height=50)
                text.grid(row=row+1, column=0, columnspan=4, padx=5, pady=5, sticky="ew")
                self.campos_produto[label[:-1]] = text
        
        # Botões de ação
        btn_frame = ctk.CTkFrame(form_frame)
        btn_frame.grid(row=3, column=0, columnspan=8, pady=10)
        
        btn_salvar = ctk.CTkButton(btn_frame, text="Salvar Produto", 
                                   command=self.salvar_produto)
        btn_salvar.pack(side="left", padx=5)
        
        btn_limpar = ctk.CTkButton(btn_frame, text="Limpar", 
                                   command=self.limpar_form_produto)
        btn_limpar.pack(side="left", padx=5)
        
        # Tabela de produtos
        tabela_frame = ctk.CTkFrame(self.area_principal)
        tabela_frame.pack(fill="both", expand=True, padx=20, pady=10)
        
        self.tabela_produtos = ttk.Treeview(tabela_frame, 
            columns=("ID", "Nome", "Categoria", "Qtd", "Preço", "Status"),
            show="headings", height=15)
        
        for col in self.tabela_produtos["columns"]:
            self.tabela_produtos.heading(col, text=col)
            self.tabela_produtos.column(col, width=100)
        
        scrollbar = ttk.Scrollbar(tabela_frame, orient="vertical", 
                                 command=self.tabela_produtos.yview)
        self.tabela_produtos.configure(yscrollcommand=scrollbar.set)
        
        self.tabela_produtos.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Carregar produtos
        self.carregar_produtos_tabela()
        
        # Botões de ação na tabela
        acoes_frame = ctk.CTkFrame(self.area_principal)
        acoes_frame.pack(fill="x", padx=20, pady=10)
        
        btn_editar = ctk.CTkButton(acoes_frame, text="Editar Selecionado",
                                   command=self.editar_produto_selecionado)
        btn_editar.pack(side="left", padx=5)
        
        btn_excluir = ctk.CTkButton(acoes_frame, text="Excluir Selecionado",
                                    command=self.excluir_produto_selecionado,
                                    fg_color="#e74c3c")
        btn_excluir.pack(side="left", padx=5)
    
    def carregar_produtos_tabela(self):
        """Carrega os produtos na tabela"""
        for item in self.tabela_produtos.get_children():
            self.tabela_produtos.delete(item)
        
        produtos, _ = self.db.get_all_produtos()
        
        for prod in produtos:
            status = "OK" if prod[7] >= prod[8] else "BAIXO"
            self.tabela_produtos.insert("", "end", 
                values=(prod[0], prod[1], prod[2], prod[7], 
                       f"R$ {prod[6]:.2f}", status))
    
    def salvar_produto(self):
        """Salva um novo produto"""
        try:
            nome = self.campos_produto["Nome"].get()
            if not nome:
                messagebox.showerror("Erro", "Nome é obrigatório!")
                return
            
            self.db.add_produto(
                nome=nome,
                categoria=self.campos_produto["Categoria"].get(),
                marca=self.campos_produto["Marca"].get(),
                faixa_etaria=self.campos_produto["Faixa Etária"].get(),
                preco_custo=float(self.campos_produto["Preço Custo"].get() or 0),
                preco_venda=float(self.campos_produto["Preço Venda"].get() or 0),
                quantidade=int(self.campos_produto["Quantidade"].get() or 0),
                estoque_minimo=int(self.campos_produto["Estoque Mínimo"].get() or 5),
                descricao=self.campos_produto["Descrição"].get("1.0", "end-1c")
            )
            
            messagebox.showinfo("Sucesso", "Produto salvo com sucesso!")
            self.limpar_form_produto()
            self.carregar_produtos_tabela()
            
        except ValueError as e:
            messagebox.showerror("Erro", f"Verifique os valores numéricos: {e}")
    
    def limpar_form_produto(self):
        """Limpa o formulário de produto"""
        for campo in self.campos_produto.values():
            if isinstance(campo, ctk.CTkTextbox):
                campo.delete("1.0", "end")
            else:
                campo.delete(0, "end")
    
    def editar_produto_selecionado(self):
        """Carrega dados do produto selecionado para edição"""
        selecionado = self.tabela_produtos.selection()
        if not selecionado:
            messagebox.showwarning("Atenção", "Selecione um produto!")
            return
        
        item = self.tabela_produtos.item(selecionado[0])
        id_produto = item["values"][0]
        
        # Buscar dados completos
        produtos, _ = self.db.get_all_produtos()
        produto = next((p for p in produtos if p[0] == id_produto), None)
        
        if produto:
            self.limpar_form_produto()
            self.campos_produto["Nome"].insert(0, produto[1])
            self.campos_produto["Categoria"].insert(0, produto[2])
            self.campos_produto["Marca"].insert(0, produto[3])
            self.campos_produto["Faixa Etária"].insert(0, produto[4])
            self.campos_produto["Preço Custo"].insert(0, str(produto[5]))
            self.campos_produto["Preço Venda"].insert(0, str(produto[6]))
            self.campos_produto["Quantidade"].insert(0, str(produto[7]))
            self.campos_produto["Estoque Mínimo"].insert(0, str(produto[8]))
            self.campos_produto["Descrição"].insert("1.0", produto[9] or "")
    
    def excluir_produto_selecionado(self):
        """Exclui o produto selecionado"""
        selecionado = self.tabela_produtos.selection()
        if not selecionado:
            messagebox.showwarning("Atenção", "Selecione um produto!")
            return
        
        if messagebox.askyesno("Confirmar", "Deseja realmente excluir este produto?"):
            item = self.tabela_produtos.item(selecionado[0])
            id_produto = item["values"][0]
            self.db.delete_produto(id_produto)
            self.carregar_produtos_tabela()
            messagebox.showinfo("Sucesso", "Produto excluído!")
    
    def mostrar_vendas(self):
        """Mostra a tela de vendas"""
        self.limpar_area_principal()
        
        titulo = ctk.CTkLabel(self.area_principal, text="Registrar Venda",
                             font=ctk.CTkFont(size=24, weight="bold"))
        titulo.pack(pady=10)
        
        # Frame de formulário
        form_frame = ctk.CTkFrame(self.area_principal)
        form_frame.pack(fill="x", padx=20, pady=10)
        
        # Selecionar produto
        lbl_prod = ctk.CTkLabel(form_frame, text="Produto:")
        lbl_prod.grid(row=0, column=0, padx=5, pady=5, sticky="e")
        
        self.combo_produtos = ctk.CTkComboBox(form_frame, width=300)
        self.combo_produtos.grid(row=0, column=1, padx=5, pady=5, sticky="w")
        
        # Carregar produtos no combo
        produtos, _ = self.db.get_all_produtos()
        self.produtos_dict = {f"{p[1]} (Qtd: {p[7]})": p for p in produtos}
        self.combo_produtos.configure(values=list(self.produtos_dict.keys()))
        
        # Quantidade
        lbl_qtd = ctk.CTkLabel(form_frame, text="Quantidade:")
        lbl_qtd.grid(row=0, column=2, padx=5, pady=5, sticky="e")
        
        self.entry_qtd = ctk.CTkEntry(form_frame, width=100)
        self.entry_qtd.grid(row=0, column=3, padx=5, pady=5, sticky="w")
        self.entry_qtd.insert(0, "1")
        
        # Cliente
        lbl_cliente = ctk.CTkLabel(form_frame, text="Cliente:")
        lbl_cliente.grid(row=1, column=0, padx=5, pady=5, sticky="e")
        
        self.entry_cliente = ctk.CTkEntry(form_frame, width=300)
        self.entry_cliente.grid(row=1, column=1, padx=5, pady=5, sticky="w")
        
        # Forma de pagamento
        lbl_pgto = ctk.CTkLabel(form_frame, text="Pagamento:")
        lbl_pgto.grid(row=1, column=2, padx=5, pady=5, sticky="e")
        
        self.combo_pgto = ctk.CTkComboBox(form_frame, width=150,
                                          values=["Dinheiro", "Cartão Crédito", 
                                                  "Cartão Débito", "PIX"])
        self.combo_pgto.grid(row=1, column=3, padx=5, pady=5, sticky="w")
        self.combo_pgto.set("Dinheiro")
        
        # Botão registrar venda
        btn_vender = ctk.CTkButton(form_frame, text="Registrar Venda",
                                   command=self.registrar_venda,
                                   fg_color="#2ecc71", height=40)
        btn_vender.grid(row=2, column=0, columnspan=4, pady=20)
        
        # Histórico de vendas recentes
        historico_frame = ctk.CTkFrame(self.area_principal)
        historico_frame.pack(fill="both", expand=True, padx=20, pady=10)
        
        lbl_historico = ctk.CTkLabel(historico_frame, text="Vendas Recentes")
        lbl_historico.pack(pady=5)
        
        self.tabela_vendas = ttk.Treeview(historico_frame,
            columns=("ID", "Produto", "Qtd", "Total", "Data"),
            show="headings", height=10)
        
        for col in self.tabela_vendas["columns"]:
            self.tabela_vendas.heading(col, text=col)
        
        self.tabela_vendas.pack(fill="both", expand=True, padx=5, pady=5)
        self.carregar_vendas_recentes()
    
    def registrar_venda(self):
        """Registra uma venda"""
        produto_sel = self.combo_produtos.get()
        
        if not produto_sel:
            messagebox.showerror("Erro", "Selecione um produto!")
            return
        
        try:
            qtd = int(self.entry_qtd.get())
            if qtd <= 0:
                raise ValueError("Quantidade inválida")
        except ValueError:
            messagebox.showerror("Erro", "Quantidade inválida!")
            return
        
        produto = self.produtos_dict[produto_sel]
        id_produto = produto[0]
        estoque_atual = produto[7]
        preco_venda = produto[6]
        
        if qtd > estoque_atual:
            messagebox.showerror("Erro", f"Estoque insuficiente! Disponível: {estoque_atual}")
            return
        
        # Registrar venda
        self.db.registrar_venda(
            produto_id=id_produto,
            quantidade=qtd,
            preco_unitario=preco_venda,
            cliente_nome=self.entry_cliente.get(),
            forma_pagamento=self.combo_pgto.get()
        )
        
        messagebox.showinfo("Sucesso", f"Venda registrada!\nTotal: R$ {qtd * preco_venda:.2f}")
        
        # Atualizar interface
        self.combo_produtos.set("")
        self.entry_qtd.delete(0, "end")
        self.entry_qtd.insert(0, "1")
        self.entry_cliente.delete(0, "end")
        
        self.carregar_vendas_recentes()
    
    def carregar_vendas_recentes(self):
        """Carrega vendas recentes na tabela"""
        for item in self.tabela_vendas.get_children():
            self.tabela_vendas.delete(item)
        
        relatorio = self.db.get_relatorio_periodo('semanal')
        
        for venda in relatorio['vendas'][:20]:  # Últimas 20 vendas
            self.tabela_vendas.insert("", "end",
                values=(venda[0].split()[0], venda[1], venda[2], 
                       f"R$ {venda[4]:.2f}", venda[0]))
    
    def mostrar_compras(self):
        """Mostra a tela de compras/entradas"""
        self.limpar_area_principal()
        
        titulo = ctk.CTkLabel(self.area_principal, text="Registrar Compra/Entrada",
                             font=ctk.CTkFont(size=24, weight="bold"))
        titulo.pack(pady=10)
        
        # Frame de formulário
        form_frame = ctk.CTkFrame(self.area_principal)
        form_frame.pack(fill="x", padx=20, pady=10)
        
        # Selecionar produto
        lbl_prod = ctk.CTkLabel(form_frame, text="Produto:")
        lbl_prod.grid(row=0, column=0, padx=5, pady=5, sticky="e")
        
        self.combo_produtos_compra = ctk.CTkComboBox(form_frame, width=300)
        self.combo_produtos_compra.grid(row=0, column=1, padx=5, pady=5, sticky="w")
        
        produtos, _ = self.db.get_all_produtos()
        self.produtos_compra_dict = {p[1]: p for p in produtos}
        self.combo_produtos_compra.configure(values=list(self.produtos_compra_dict.keys()))
        
        # Quantidade
        lbl_qtd = ctk.CTkLabel(form_frame, text="Quantidade:")
        lbl_qtd.grid(row=0, column=2, padx=5, pady=5, sticky="e")
        
        self.entry_qtd_compra = ctk.CTkEntry(form_frame, width=100)
        self.entry_qtd_compra.grid(row=0, column=3, padx=5, pady=5, sticky="w")
        
        # Preço unitário
        lbl_preco = ctk.CTkLabel(form_frame, text="Preço Unitário:")
        lbl_preco.grid(row=1, column=0, padx=5, pady=5, sticky="e")
        
        self.entry_preco_compra = ctk.CTkEntry(form_frame, width=150)
        self.entry_preco_compra.grid(row=1, column=1, padx=5, pady=5, sticky="w")
        
        # Fornecedor
        lbl_forn = ctk.CTkLabel(form_frame, text="Fornecedor:")
        lbl_forn.grid(row=1, column=2, padx=5, pady=5, sticky="e")
        
        self.entry_fornecedor = ctk.CTkEntry(form_frame, width=200)
        self.entry_fornecedor.grid(row=1, column=3, padx=5, pady=5, sticky="w")
        
        # Nota fiscal
        lbl_nf = ctk.CTkLabel(form_frame, text="Nota Fiscal:")
        lbl_nf.grid(row=2, column=0, padx=5, pady=5, sticky="e")
        
        self.nota_fiscal_path = None
        self.lbl_arquivo_nf = ctk.CTkLabel(form_frame, text="Nenhum arquivo selecionado")
        self.lbl_arquivo_nf.grid(row=2, column=1, padx=5, pady=5, sticky="w")
        
        btn_anexar = ctk.CTkButton(form_frame, text="Anexar NF",
                                   command=self.anexar_nota_fiscal)
        btn_anexar.grid(row=2, column=2, padx=5, pady=5, sticky="w")
        
        # Botão registrar compra
        btn_comprar = ctk.CTkButton(form_frame, text="Registrar Entrada",
                                    command=self.registrar_compra,
                                    fg_color="#3498db", height=40)
        btn_comprar.grid(row=3, column=0, columnspan=4, pady=20)
    
    def anexar_nota_fiscal(self):
        """Anexa arquivo de nota fiscal"""
        filetypes = [
            ("PDF files", "*.pdf"),
            ("Image files", "*.png *.jpg *.jpeg"),
            ("All files", "*.*")
        ]
        
        filename = filedialog.askopenfilename(title="Selecionar Nota Fiscal",
                                              filetypes=filetypes)
        
        if filename:
            self.nota_fiscal_path = filename
            self.lbl_arquivo_nf.configure(text=os.path.basename(filename))
    
    def registrar_compra(self):
        """Registra uma compra/entrada"""
        produto_sel = self.combo_produtos_compra.get()
        
        if not produto_sel:
            messagebox.showerror("Erro", "Selecione um produto!")
            return
        
        try:
            qtd = int(self.entry_qtd_compra.get())
            preco = float(self.entry_preco_compra.get())
        except ValueError:
            messagebox.showerror("Erro", "Valores inválidos!")
            return
        
        produto = self.produtos_compra_dict[produto_sel]
        id_produto = produto[0]
        
        # Copiar nota fiscal para pasta de anexos
        nf_path = None
        if self.nota_fiscal_path:
            pasta_anexos = "anexos_notas"
            os.makedirs(pasta_anexos, exist_ok=True)
            
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            ext = os.path.splitext(self.nota_fiscal_path)[1]
            novo_nome = f"NF_{id_produto}_{timestamp}{ext}"
            novo_path = os.path.join(pasta_anexos, novo_nome)
            
            shutil.copy2(self.nota_fiscal_path, novo_path)
            nf_path = novo_path
        
        # Registrar compra
        self.db.registrar_compra(
            produto_id=id_produto,
            quantidade=qtd,
            preco_unitario=preco,
            fornecedor_nome=self.entry_fornecedor.get(),
            nota_fiscal_path=nf_path
        )
        
        messagebox.showinfo("Sucesso", "Entrada registrada com sucesso!")
        
        # Limpar formulário
        self.combo_produtos_compra.set("")
        self.entry_qtd_compra.delete(0, "end")
        self.entry_preco_compra.delete(0, "end")
        self.entry_fornecedor.delete(0, "end")
        self.nota_fiscal_path = None
        self.lbl_arquivo_nf.configure(text="Nenhum arquivo selecionado")
    
    def mostrar_financeiro(self):
        """Mostra a tela de controle financeiro"""
        self.limpar_area_principal()
        
        titulo = ctk.CTkLabel(self.area_principal, text="Controle Financeiro",
                             font=ctk.CTkFont(size=24, weight="bold"))
        titulo.pack(pady=10)
        
        # Cards de resumo financeiro
        cards_frame = ctk.CTkFrame(self.area_principal)
        cards_frame.pack(fill="x", padx=20, pady=10)
        
        # Obter dados financeiros
        relatorio_mensal = self.db.get_relatorio_periodo('mensal')
        relatorio_anual = self.db.get_relatorio_periodo('anual')
        
        stats = [
            ("Entradas (Mês)", f"R$ {relatorio_mensal['entradas']:.2f}", "#2ecc71"),
            ("Saídas (Mês)", f"R$ {relatorio_mensal['saidas']:.2f}", "#e74c3c"),
            ("Lucro (Mês)", f"R$ {relatorio_mensal['lucro']:.2f}", "#3498db"),
            ("Lucro (Ano)", f"R$ {relatorio_anual['lucro']:.2f}", "#f39c12"),
        ]
        
        for i, (titulo, valor, cor) in enumerate(stats):
            card = ctk.CTkFrame(cards_frame, fg_color=cor)
            card.grid(row=0, column=i, padx=10, pady=10, sticky="ew")
            cards_frame.grid_columnconfigure(i, weight=1)
            
            lbl_titulo = ctk.CTkLabel(card, text=titulo, font=ctk.CTkFont(size=14))
            lbl_titulo.pack(pady=(10, 5))
            
            lbl_valor = ctk.CTkLabel(card, text=valor, 
                                    font=ctk.CTkFont(size=18, weight="bold"))
            lbl_valor.pack(pady=(0, 10))
        
        # Gráficos financeiros
        graficos_frame = ctk.CTkFrame(self.area_principal)
        graficos_frame.pack(fill="both", expand=True, padx=20, pady=10)
        
        # Criar abas para diferentes períodos
        tabview = ctk.CTkTabview(graficos_frame)
        tabview.pack(fill="both", expand=True, padx=5, pady=5)
        
        tab_semanal = tabview.add("Semanal")
        tab_mensal = tabview.add("Mensal")
        tab_anual = tabview.add("Anual")
        
        self.criar_grafico_vendas_periodo(tab_semanal, 'semanal')
        self.criar_grafico_vendas_periodo(tab_mensal, 'mensal')
        self.criar_grafico_vendas_periodo(tab_anual, 'anual')
    
    def mostrar_relatorios(self):
        """Mostra a tela de relatórios detalhados"""
        self.limpar_area_principal()
        
        titulo = ctk.CTkLabel(self.area_principal, text="Relatórios Detalhados",
                             font=ctk.CTkFont(size=24, weight="bold"))
        titulo.pack(pady=10)
        
        # Seleção de período
        periodo_frame = ctk.CTkFrame(self.area_principal)
        periodo_frame.pack(fill="x", padx=20, pady=10)
        
        lbl_periodo = ctk.CTkLabel(periodo_frame, text="Período:")
        lbl_periodo.pack(side="left", padx=5)
        
        self.combo_periodo_rel = ctk.CTkComboBox(periodo_frame,
                                                 values=["Semanal", "Mensal", "Anual"])
        self.combo_periodo_rel.pack(side="left", padx=5)
        self.combo_periodo_rel.set("Mensal")
        
        btn_gerar = ctk.CTkButton(periodo_frame, text="Gerar Relatório",
                                  command=self.gerar_relatorio)
        btn_gerar.pack(side="left", padx=5)
        
        # Área de resultados
        self.resultados_frame = ctk.CTkFrame(self.area_principal)
        self.resultados_frame.pack(fill="both", expand=True, padx=20, pady=10)
        
        # Gerar relatório inicial
        self.gerar_relatorio()
    
    def gerar_relatorio(self):
        """Gera relatório baseado no período selecionado"""
        # Limpar resultados anteriores
        for widget in self.resultados_frame.winfo_children():
            widget.destroy()
        
        periodo_map = {
            "Semanal": "semanal",
            "Mensal": "mensal",
            "Anual": "anual"
        }
        
        periodo = periodo_map[self.combo_periodo_rel.get()]
        relatorio = self.db.get_relatorio_periodo(periodo)
        
        # Resumo numérico
        resumo_frame = ctk.CTkFrame(self.resultados_frame)
        resumo_frame.pack(fill="x", padx=10, pady=10)
        
        dados_resumo = [
            ("Total Vendas", f"R$ {relatorio['total_vendas']:.2f}"),
            ("Entradas", f"R$ {relatorio['entradas']:.2f}"),
            ("Saídas", f"R$ {relatorio['saidas']:.2f}"),
            ("Lucro Líquido", f"R$ {relatorio['lucro']:.2f}"),
        ]
        
        for i, (label, valor) in enumerate(dados_resumo):
            frame = ctk.CTkFrame(resumo_frame)
            frame.grid(row=0, column=i, padx=5, pady=5, sticky="ew")
            resumo_frame.grid_columnconfigure(i, weight=1)
            
            ctk.CTkLabel(frame, text=label).pack()
            ctk.CTkLabel(frame, text=valor, 
                        font=ctk.CTkFont(weight="bold", size=16)).pack()
        
        # Tabela de vendas detalhadas
        tabela_frame = ctk.CTkFrame(self.resultados_frame)
        tabela_frame.pack(fill="both", expand=True, padx=10, pady=10)
        
        ctk.CTkLabel(tabela_frame, text="Detalhamento de Vendas",
                    font=ctk.CTkFont(weight="bold")).pack(pady=5)
        
        tree = ttk.Treeview(tabela_frame,
            columns=("Data", "Produto", "Qtd", "Preço Unit.", "Total"),
            show="headings", height=15)
        
        for col in tree["columns"]:
            tree.heading(col, text=col)
        
        tree.pack(fill="both", expand=True)
        
        for venda in relatorio['vendas']:
            tree.insert("", "end",
                values=(venda[0], venda[1], venda[2], 
                       f"R$ {venda[3]:.2f}", f"R$ {venda[4]:.2f}"))
        
        # Botão exportar
        btn_exportar = ctk.CTkButton(self.resultados_frame,
                                     text="Exportar para Excel",
                                     command=lambda: self.exportar_relatorio_excel(relatorio, periodo))
        btn_exportar.pack(pady=10)
    
    def exportar_relatorio_excel(self, relatorio, periodo):
        """Exporta relatório para Excel"""
        filename = filedialog.asksaveasfilename(
            defaultextension=".xlsx",
            filetypes=[("Excel files", "*.xlsx")],
            initialfile=f"relatorio_{periodo}_{datetime.now().strftime('%Y%m%d')}.xlsx"
        )
        
        if filename:
            try:
                df = pd.DataFrame(relatorio['vendas'],
                                 columns=['Data', 'Produto', 'Quantidade', 
                                         'Preco_Unitario', 'Total'])
                
                with pd.ExcelWriter(filename, engine='openpyxl') as writer:
                    df.to_excel(writer, sheet_name='Vendas', index=False)
                    
                    # Adicionar resumo
                    resumo_df = pd.DataFrame({
                        'Métrica': ['Total Vendas', 'Entradas', 'Saídas', 'Lucro'],
                        'Valor': [relatorio['total_vendas'], relatorio['entradas'],
                                 relatorio['saidas'], relatorio['lucro']]
                    })
                    resumo_df.to_excel(writer, sheet_name='Resumo', index=False)
                
                messagebox.showinfo("Sucesso", "Relatório exportado com sucesso!")
            except Exception as e:
                messagebox.showerror("Erro", f"Erro ao exportar: {e}")
    
    def mostrar_configuracoes(self):
        """Mostra a tela de configurações"""
        self.limpar_area_principal()
        
        titulo = ctk.CTkLabel(self.area_principal, text="Configurações",
                             font=ctk.CTkFont(size=24, weight="bold"))
        titulo.pack(pady=20)
        
        config_frame = ctk.CTkFrame(self.area_principal)
        config_frame.pack(fill="x", padx=50, pady=20)
        
        # Tema
        lbl_tema = ctk.CTkLabel(config_frame, text="Tema:")
        lbl_tema.grid(row=0, column=0, padx=10, pady=10, sticky="e")
        
        combo_tema = ctk.CTkComboBox(config_frame,
                                     values=["Dark", "Light", "System"],
                                     command=self.mudar_tema)
        combo_tema.grid(row=0, column=1, padx=10, pady=10, sticky="w")
        combo_tema.set(ctk.get_appearance_mode())
        
        # Backup
        lbl_backup = ctk.CTkLabel(config_frame, text="Backup:")
        lbl_backup.grid(row=1, column=0, padx=10, pady=10, sticky="e")
        
        btn_backup = ctk.CTkButton(config_frame, text="Fazer Backup",
                                   command=self.fazer_backup)
        btn_backup.grid(row=1, column=1, padx=10, pady=10, sticky="w")
        
        # Informações
        info_frame = ctk.CTkFrame(self.area_principal)
        info_frame.pack(fill="x", padx=50, pady=20)
        
        ctk.CTkLabel(info_frame, text="Sistema de Controle de Estoque de Brinquedos",
                    font=ctk.CTkFont(weight="bold")).pack()
        ctk.CTkLabel(info_frame, text="Versão 1.0").pack()
        ctk.CTkLabel(info_frame, text="Desenvolvido em Python com CustomTkinter").pack()
    
    def mudar_tema(self, tema):
        """Muda o tema da aplicação"""
        ctk.set_appearance_mode(tema.lower())
    
    def fazer_backup(self):
        """Faz backup do banco de dados"""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_path = f"backup_estoque_{timestamp}.db"
            shutil.copy2(self.db.db_path, backup_path)
            messagebox.showinfo("Sucesso", f"Backup realizado:\n{backup_path}")
        except Exception as e:
            messagebox.showerror("Erro", f"Erro ao fazer backup: {e}")


if __name__ == "__main__":
    app = App()
    app.mainloop()
