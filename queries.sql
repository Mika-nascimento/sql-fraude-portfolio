-- queries.sql
-- Consultas de análise sobre o banco fraud_analytics.db (dados sintéticos).
-- Cada bloco resolve uma pergunta de negócio real do dia a dia de
-- prevenção a fraude / análise de dados, e demonstra uma técnica de SQL
-- diferente (join, agregação, CTE, window function, subquery).
--
-- Como rodar:
--   python3 -c "import sqlite3; sqlite3.connect('fraud_analytics.db').executescript(open('queries.sql').read())"
-- ou abrir fraud_analytics.db em qualquer cliente SQLite (DB Browser, VS Code, etc.)
-- e rodar cada bloco separadamente.


-- 1) JOIN + AGREGAÇÃO
-- Volume total transacionado por produto, considerando só transações aprovadas.
SELECT
    product,
    COUNT(*)            AS qtd_transacoes,
    ROUND(SUM(amount),2) AS volume_total,
    ROUND(AVG(amount),2) AS ticket_medio
FROM transactions
WHERE status = 'approved'
GROUP BY product
ORDER BY volume_total DESC;


-- 2) JOIN entre três tabelas
-- Lista de alertas com o valor e produto da transação e a cidade da conta envolvida.
SELECT
    al.alert_id,
    al.alert_type,
    al.risk_score,
    t.product,
    t.amount,
    a.city,
    a.state
FROM alerts al
JOIN transactions t ON t.transaction_id = al.transaction_id
JOIN accounts a      ON a.account_id = t.account_id
ORDER BY al.risk_score DESC
LIMIT 20;


-- 3) WINDOW FUNCTION (média móvel)
-- Média móvel de 7 dias do volume transacionado por dia, útil pra enxergar
-- picos fora do padrão recente.
WITH volume_diario AS (
    SELECT
        DATE(created_at) AS dia,
        SUM(amount)      AS volume_dia
    FROM transactions
    WHERE status = 'approved'
    GROUP BY DATE(created_at)
)
SELECT
    dia,
    volume_dia,
    ROUND(AVG(volume_dia) OVER (
        ORDER BY dia
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS media_movel_7d
FROM volume_diario
ORDER BY dia;


-- 4) CTE + WINDOW FUNCTION (detecção de pico por conta)
-- Contas cujo valor transacionado num dia ficou muito acima da própria
-- média histórica (possível indício de comportamento atípico).
WITH por_conta_dia AS (
    SELECT
        account_id,
        DATE(created_at) AS dia,
        SUM(amount)      AS valor_dia
    FROM transactions
    WHERE status = 'approved'
    GROUP BY account_id, DATE(created_at)
),
com_media AS (
    SELECT
        account_id,
        dia,
        valor_dia,
        AVG(valor_dia) OVER (
            PARTITION BY account_id
            ORDER BY dia
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS media_historica
    FROM por_conta_dia
)
SELECT *
FROM com_media
WHERE media_historica IS NOT NULL
  AND valor_dia > 3 * media_historica
ORDER BY valor_dia DESC
LIMIT 20;


-- 5) SUBQUERY (CNPJ recente)
-- Transações cujo destinatário é uma conta PJ criada há menos de 30 dias
-- em relação à data da transação — sinal de atenção clássico.
SELECT
    t.transaction_id,
    t.created_at,
    t.amount,
    t.counterparty_id,
    a.cnpj_age_days
FROM transactions t
JOIN accounts a ON a.account_id = t.counterparty_id
WHERE a.account_type = 'PJ'
  AND a.cnpj_age_days IS NOT NULL
  AND a.cnpj_age_days < 30
  AND t.amount > (SELECT AVG(amount) FROM transactions)
ORDER BY t.amount DESC;


-- 6) WINDOW FUNCTION (ranking)
-- Ranking das contas com maior volume transacionado dentro de cada estado.
WITH volume_por_conta AS (
    SELECT
        a.state,
        t.account_id,
        SUM(t.amount) AS volume_total
    FROM transactions t
    JOIN accounts a ON a.account_id = t.account_id
    WHERE t.status = 'approved'
    GROUP BY a.state, t.account_id
),
ranking AS (
    SELECT
        state,
        account_id,
        volume_total,
        RANK() OVER (PARTITION BY state ORDER BY volume_total DESC) AS rank_no_estado
    FROM volume_por_conta
)
SELECT *
FROM ranking
WHERE rank_no_estado <= 3
ORDER BY state, rank_no_estado;
-- Observação: em Postgres/BigQuery/Snowflake essa filtragem por rank poderia
-- usar QUALIFY rank_no_estado <= 3 direto, sem precisar da CTE extra. O
-- SQLite não suporta QUALIFY, então o filtro é feito envolvendo a window
-- function numa CTE e aplicando WHERE na consulta externa, como acima.


-- 7) TAXA DE RESOLUÇÃO DE ALERTAS
-- Percentual de alertas por tipo que foram confirmados como fraude de fato,
-- métrica clássica de qualidade de regra/alerta.
SELECT
    alert_type,
    COUNT(*)                                              AS total_alertas,
    SUM(CASE WHEN resolution = 'fraud_confirmed' THEN 1 ELSE 0 END) AS confirmados,
    ROUND(100.0 * SUM(CASE WHEN resolution = 'fraud_confirmed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS taxa_precisao_pct
FROM alerts
GROUP BY alert_type
ORDER BY taxa_precisao_pct DESC;


-- 8) HABITUALIDADE (múltiplos produtos no mesmo dia)
-- Contas que transacionaram em mais de um produto no mesmo dia com valor
-- total acima de um limite — combinação usada pra avaliar habitualidade.
SELECT
    account_id,
    DATE(created_at)         AS dia,
    COUNT(DISTINCT product)  AS produtos_distintos,
    SUM(amount)              AS valor_total_dia
FROM transactions
WHERE status = 'approved'
GROUP BY account_id, DATE(created_at)
HAVING produtos_distintos > 1
   AND valor_total_dia > 5000
ORDER BY valor_total_dia DESC
LIMIT 20;
