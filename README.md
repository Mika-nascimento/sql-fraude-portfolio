# Análise de Fraude Transacional em SQL

Projeto de portfólio que simula um cenário real de prevenção a fraude em
meios de pagamento (Pix, P2P, Boleto, IPVA), com consultas SQL cobrindo
join, agregação, CTE, window function e subquery.

O contexto de negócio é inspirado na minha atuação como Analista de
Prevenção à Fraude em uma fintech. Os dados aqui são **100% sintéticos**,
gerados aleatoriamente , nenhuma informação real, confidencial ou de
cliente é usada.

## Estrutura

```
sql-portfolio/
├── generate_data.py   # gera o banco fraud_analytics.db com dados fictícios
├── queries.sql        # consultas de análise, comentadas
└── README.md
```

## Modelo de dados

- **accounts**: contas (PF ou PJ), cidade, estado, data de criação
- **transactions**: transações entre contas, por produto, valor e status
- **alerts**: alertas de fraude vinculados a transações, com tipo,
  score de risco e resolução final

## Como rodar

```bash
python3 generate_data.py       # cria fraud_analytics.db
python3 -c "import sqlite3; sqlite3.connect('fraud_analytics.db').executescript(open('queries.sql').read())"
```

Ou abra `fraud_analytics.db` em qualquer cliente SQLite (DB Browser for
SQLite, extensão do VS Code, etc.) e rode cada consulta de `queries.sql`
separadamente.

## O que cada consulta demonstra

| # | Pergunta de negócio | Técnica |
|---|---|---|
| 1 | Volume e ticket médio por produto | Agregação simples |
| 2 | Alertas com maior score, com dados da transação e da conta | Join entre 3 tabelas |
| 3 | Média móvel de 7 dias do volume transacionado | Window function (`AVG() OVER`) |
| 4 | Contas com pico de valor muito acima da própria média histórica | CTE encadeada + window function |
| 5 | Transações para CNPJs abertos há menos de 30 dias, acima do valor médio | Subquery escalar |
| 6 | Top 3 contas por volume dentro de cada estado | Window function (`RANK() OVER`) |
| 7 | Taxa de confirmação de fraude por tipo de alerta | Agregação condicional (`CASE WHEN`) |
| 8 | Contas com múltiplos produtos e valor alto no mesmo dia (habitualidade) | `GROUP BY` + `HAVING` |

## Por que esse projeto

Trabalho todos os dias com investigação de alertas e decisão de risco
baseada em evidência. Esse projeto recria, com dados fictícios, o tipo de
pergunta que eu resolvo no dia a dia , só que aqui, do início ao fim, incluindo
a modelagem dos dados e a escrita das consultas.
