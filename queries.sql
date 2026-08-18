/* ============================================================
   Анализ клиентской базы и транзакций
   СУБД: MySQL 8.0+
   Период: [2015-06-01, 2016-06-01) — 12 месяцев
   Автор: Хегай Антон

   Содержание:
     0. Проверки качества данных
     1. Клиенты с непрерывной историей, средний чек, операции
     2. Помесячная динамика
     3. Соотношение M/F/NA по месяцам
     4. Возрастные группы: период и кварталы
     5. Аномалии, влияющие на выводы
   ============================================================ */

USE customer_analytics;


/* ============================================================
   0. ПРОВЕРКИ КАЧЕСТВА ДАННЫХ
   Выполняются до расчётов: дубликат ключа в справочнике при
   LEFT JOIN размножит строки транзакций и завысит все суммы.
   ============================================================ */

-- 0.1 Дубликаты ключа в справочнике клиентов.
-- Факт: дубликатов нет (2429 строк = 2429 уникальных клиентов).
SELECT
    Id_client,
    COUNT(*) AS rows_per_client
FROM customers
GROUP BY Id_client
HAVING COUNT(*) > 1;

-- 0.2 Коэффициент размножения строк при джойне.
-- Факт: 1.0000 — джойн безопасен.
SELECT
    COUNT(*)                                        AS total_rows,
    COUNT(DISTINCT Id_client)                       AS unique_clients,
    ROUND(COUNT(*) / COUNT(DISTINCT Id_client), 4)  AS rows_per_unique_client
FROM customers;

-- 0.3 Транзакции с клиентом, которого нет в справочнике.
-- Факт: 0 — справочник покрывает все транзакции.
SELECT
    COUNT(*)                    AS orphan_rows,
    COUNT(DISTINCT t.ID_client) AS orphan_clients
FROM transactions t
LEFT JOIN customers c
       ON t.ID_client = c.Id_client
WHERE t.date_new >= '2015-06-01'
  AND t.date_new <  '2016-06-01'
  AND c.Id_client IS NULL;

-- 0.4 Полнота справочника.
-- Факт: Gender не заполнен у 64 клиентов (2.63%), Age — у 35 (1.44%).
SELECT
    COUNT(*)                                                AS clients_total,
    SUM(Gender IS NULL)                                     AS gender_missing,
    ROUND(SUM(Gender IS NULL) * 100.0 / COUNT(*), 2)        AS gender_missing_pct,
    SUM(Age IS NULL)                                        AS age_missing,
    ROUND(SUM(Age IS NULL) * 100.0 / COUNT(*), 2)           AS age_missing_pct,
    MIN(Age)                                                AS age_min,
    MAX(Age)                                                AS age_max,
    SUM(Age < 10)                                           AS age_under_10
FROM customers;

-- 0.5 Гранулярность дат.
-- Факт: 13 уникальных значений date_new, все — первое число месяца.
-- date_new является меткой месяца, а не датой транзакции.
-- Следствие: дневная и недельная динамика на этих данных недоступна.
SELECT
    COUNT(DISTINCT date_new)                AS distinct_dates,
    SUM(DAY(date_new) <> 1)                 AS not_first_of_month,
    MIN(date_new)                           AS date_min,
    MAX(date_new)                           AS date_max
FROM transactions;

-- 0.6 Один ли клиент и одна ли дата у каждого чека.
-- Факт: 0 нарушений — COUNT(DISTINCT Id_check) корректно считает операции.
SELECT
    SUM(clients_per_check > 1) AS checks_with_many_clients,
    SUM(dates_per_check   > 1) AS checks_with_many_dates
FROM (
    SELECT
        Id_check,
        COUNT(DISTINCT ID_client) AS clients_per_check,
        COUNT(DISTINCT date_new)  AS dates_per_check
    FROM transactions
    GROUP BY Id_check
) t;

-- 0.7 Полные дубликаты строк.
-- Факт: 11 592 строки. Внутри одного чека повтор позиции с той же ценой
-- возможен по смыслу, поэтому строки не удаляются — вопрос к владельцу данных.
SELECT
    COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', date_new, Id_check, ID_client,
                                        Count_products, Sum_payment)) AS duplicate_rows
FROM transactions;

-- 0.8 Объём выборки по месяцам.
-- Факт: 2015-06 содержит 316 чеков против ~3 000 в остальных месяцах.
-- Месяц неполный, что учитывается в выводах.
SELECT
    DATE_FORMAT(date_new, '%Y-%m')  AS month,
    COUNT(*)                        AS rows_cnt,
    COUNT(DISTINCT Id_check)        AS checks_cnt
FROM transactions
GROUP BY DATE_FORMAT(date_new, '%Y-%m')
ORDER BY month;


/* ============================================================
   1. КЛИЕНТЫ С НЕПРЕРЫВНОЙ ИСТОРИЕЙ И ИХ ПОКАЗАТЕЛИ
   ============================================================ */

-- 1.1 Клиенты, совершавшие покупки в каждом из 12 месяцев периода.
-- Факт: 82 клиента из 2 357 активных (3.5%), дают 30.4% выручки.
WITH client_months AS (
    SELECT
        ID_client,
        COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) AS active_months
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY ID_client
)
SELECT
    ID_client,
    active_months
FROM client_months
WHERE active_months = 12
ORDER BY ID_client;

-- 1.2 Полная карточка по каждому клиенту: операции, сумма, средний чек,
-- средняя сумма покупок за месяц и признак непрерывной истории.
WITH client_agg AS (
    SELECT
        ID_client,
        COUNT(DISTINCT Id_check)                        AS operations_count,
        COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m'))  AS active_months,
        SUM(Sum_payment)                                AS total_payment
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY ID_client
)
SELECT
    ID_client,
    operations_count,
    active_months,
    ROUND(total_payment, 2)                             AS total_payment,
    ROUND(total_payment / operations_count, 2)          AS avg_check,
    ROUND(total_payment / active_months, 2)             AS avg_month_payment,
    CASE WHEN active_months = 12 THEN 'Да' ELSE 'Нет' END AS continuous_year
FROM client_agg
ORDER BY total_payment DESC;

-- 1.3 Средний чек за период.
-- Считается в два шага: сумма по каждому чеку, затем среднее по чекам.
-- Прямой AVG(Sum_payment) дал бы 9.48 — среднее по позиции в чеке,
-- то есть занижение в 10 раз, потому что строка таблицы — это позиция.
-- Факт: 94.65
WITH check_totals AS (
    SELECT
        Id_check,
        SUM(Sum_payment) AS check_sum
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY Id_check
)
SELECT
    COUNT(*)                    AS checks_total,
    ROUND(AVG(check_sum), 2)    AS avg_check,
    ROUND(MIN(check_sum), 2)    AS min_check,
    ROUND(MAX(check_sum), 2)    AS max_check
FROM check_totals;

-- 1.4 Средняя сумма покупок клиента за месяц.
-- Факт: 312.02
WITH client_month_totals AS (
    SELECT
        ID_client,
        DATE_FORMAT(date_new, '%Y-%m') AS month,
        SUM(Sum_payment)               AS month_sum
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY ID_client, DATE_FORMAT(date_new, '%Y-%m')
)
SELECT
    ROUND(AVG(month_sum), 2) AS avg_client_month_payment
FROM client_month_totals;

-- 1.5 Распределение количества операций на клиента.
-- Факт: среднее 16.2, медиана 6, максимум 6 677 — распределение
-- сильно скошено, среднее непоказательно (см. раздел 5).
WITH client_ops AS (
    SELECT
        ID_client,
        COUNT(DISTINCT Id_check) AS operations_count
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY ID_client
)
SELECT
    COUNT(*)                            AS clients_total,
    ROUND(AVG(operations_count), 2)     AS avg_operations,
    MIN(operations_count)               AS min_operations,
    MAX(operations_count)               AS max_operations
FROM client_ops;


/* ============================================================
   2. ПОМЕСЯЧНАЯ ДИНАМИКА
   ============================================================ */

-- 2.1 Витрина по месяцам: выручка, операции, клиенты, средний чек,
-- доля месяца в годовых операциях и в годовой выручке.
WITH monthly AS (
    SELECT
        DATE_FORMAT(date_new, '%Y-%m')  AS month,
        SUM(Sum_payment)                AS month_sum,
        COUNT(DISTINCT Id_check)        AS operations_count,
        COUNT(DISTINCT ID_client)       AS clients_count
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY DATE_FORMAT(date_new, '%Y-%m')
)
SELECT
    month,
    ROUND(month_sum, 2)                                                 AS month_sum,
    operations_count,
    clients_count,
    ROUND(month_sum / operations_count, 2)                              AS avg_check,
    ROUND(operations_count * 1.0 / clients_count, 2)                          AS ops_per_client,
    ROUND(operations_count * 100.0 / SUM(operations_count) OVER (), 2)  AS operations_share_pct,
    ROUND(month_sum * 100.0 / SUM(month_sum) OVER (), 2)                AS sum_share_pct
FROM monthly
ORDER BY month;

-- 2.2 Средние помесячные показатели за период.
-- Это один агрегат по 12 месяцам, а не значение в каждом месяце.
-- Факт: средняя выручка 301 153.10, операций 3 181.92, клиентов 965.17.
WITH monthly AS (
    SELECT
        DATE_FORMAT(date_new, '%Y-%m')  AS month,
        SUM(Sum_payment)                AS month_sum,
        COUNT(DISTINCT Id_check)        AS operations_count,
        COUNT(DISTINCT ID_client)       AS clients_count
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY DATE_FORMAT(date_new, '%Y-%m')
)
SELECT
    COUNT(*)                                AS months_in_period,
    ROUND(AVG(month_sum), 2)                AS avg_month_sum,
    ROUND(AVG(operations_count), 2)         AS avg_month_operations,
    ROUND(AVG(clients_count), 2)            AS avg_month_clients
FROM monthly;

-- 2.3 Прирост месяц к месяцу.
WITH monthly AS (
    SELECT
        DATE_FORMAT(date_new, '%Y-%m')  AS month,
        SUM(Sum_payment)                AS month_sum
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY DATE_FORMAT(date_new, '%Y-%m')
)
SELECT
    month,
    ROUND(month_sum, 2)                                         AS month_sum,
    ROUND(LAG(month_sum) OVER (ORDER BY month), 2)              AS prev_month_sum,
    ROUND(
        (month_sum - LAG(month_sum) OVER (ORDER BY month))
        * 100.0 / LAG(month_sum) OVER (ORDER BY month),
        2
    )                                                           AS mom_growth_pct
FROM monthly
ORDER BY month;


/* ============================================================
   3. СООТНОШЕНИЕ M / F / NA ПО МЕСЯЦАМ
   Клиенты без заполненного пола образуют группу 'NA'.
   ============================================================ */

-- 3.1 Доли по клиентам и по затратам внутри каждого месяца.
-- Факт за период: F — 66.0% клиентов и 72.2% выручки,
-- M — 31.4% и 25.2%, NA — 2.6% и 2.6%.
WITH tx AS (
    SELECT
        DATE_FORMAT(t.date_new, '%Y-%m')    AS month,
        COALESCE(c.Gender, 'NA')            AS gender_group,
        t.ID_client,
        t.Id_check,
        t.Sum_payment
    FROM transactions t
    LEFT JOIN customers c
           ON t.ID_client = c.Id_client
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new <  '2016-06-01'
),
by_gender AS (
    SELECT
        month,
        gender_group,
        COUNT(DISTINCT ID_client)   AS clients_count,
        COUNT(DISTINCT Id_check)    AS operations_count,
        SUM(Sum_payment)            AS gender_sum
    FROM tx
    GROUP BY month, gender_group
)
SELECT
    month,
    gender_group,
    clients_count,
    ROUND(
        clients_count * 100.0 / SUM(clients_count) OVER (PARTITION BY month),
        2
    )                                                   AS clients_share_pct,
    ROUND(gender_sum, 2)                                AS gender_sum,
    ROUND(
        gender_sum * 100.0 / SUM(gender_sum) OVER (PARTITION BY month),
        2
    )                                                   AS payment_share_pct,
    ROUND(gender_sum / operations_count, 2)             AS avg_check
FROM by_gender
ORDER BY month, gender_group;


/* ============================================================
   4. ВОЗРАСТНЫЕ ГРУППЫ
   Шаг 10 лет, отдельная группа 'NA' для клиентов без возраста.
   ============================================================ */

-- 4.1 Показатели по возрастным группам за весь период.
WITH tx AS (
    SELECT
        CASE
            WHEN c.Age IS NULL  THEN 'NA'
            WHEN c.Age < 20     THEN '0-19'
            WHEN c.Age < 30     THEN '20-29'
            WHEN c.Age < 40     THEN '30-39'
            WHEN c.Age < 50     THEN '40-49'
            WHEN c.Age < 60     THEN '50-59'
            WHEN c.Age < 70     THEN '60-69'
            ELSE '70+'
        END                     AS age_group,
        t.Id_check,
        t.ID_client,
        t.Sum_payment
    FROM transactions t
    LEFT JOIN customers c
           ON t.ID_client = c.Id_client
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new <  '2016-06-01'
),
by_age AS (
    SELECT
        age_group,
        COUNT(DISTINCT ID_client)   AS clients_count,
        COUNT(DISTINCT Id_check)    AS operations_count,
        SUM(Sum_payment)            AS total_sum
    FROM tx
    GROUP BY age_group
)
SELECT
    age_group,
    clients_count,
    operations_count,
    ROUND(operations_count * 1.0 / clients_count, 2)                          AS ops_per_client,
    ROUND(total_sum, 2)                                                 AS total_sum,
    ROUND(total_sum / operations_count, 2)                              AS avg_check,
    ROUND(total_sum * 100.0 / SUM(total_sum) OVER (), 2)                AS sum_share_pct,
    ROUND(operations_count * 100.0 / SUM(operations_count) OVER (), 2)  AS operations_share_pct
FROM by_age
ORDER BY age_group;

-- 4.2 Возрастные группы поквартально: средний чек и доли внутри квартала.
WITH tx AS (
    SELECT
        CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new)) AS quarter,
        CASE
            WHEN c.Age IS NULL  THEN 'NA'
            WHEN c.Age < 20     THEN '0-19'
            WHEN c.Age < 30     THEN '20-29'
            WHEN c.Age < 40     THEN '30-39'
            WHEN c.Age < 50     THEN '40-49'
            WHEN c.Age < 60     THEN '50-59'
            WHEN c.Age < 70     THEN '60-69'
            ELSE '70+'
        END                     AS age_group,
        t.Id_check,
        t.ID_client,
        t.Sum_payment
    FROM transactions t
    LEFT JOIN customers c
           ON t.ID_client = c.Id_client
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new <  '2016-06-01'
),
by_quarter_age AS (
    SELECT
        quarter,
        age_group,
        COUNT(DISTINCT ID_client)   AS clients_count,
        COUNT(DISTINCT Id_check)    AS operations_count,
        SUM(Sum_payment)            AS quarter_sum
    FROM tx
    GROUP BY quarter, age_group
)
SELECT
    quarter,
    age_group,
    clients_count,
    operations_count,
    ROUND(quarter_sum, 2)                                       AS quarter_sum,
    ROUND(quarter_sum / operations_count, 2)                    AS avg_check,
    ROUND(quarter_sum / clients_count, 2)                       AS avg_per_client,
    ROUND(
        quarter_sum * 100.0 / SUM(quarter_sum) OVER (PARTITION BY quarter),
        2
    )                                                           AS quarter_sum_share_pct,
    ROUND(
        operations_count * 100.0
        / SUM(operations_count) OVER (PARTITION BY quarter),
        2
    )                                                           AS quarter_ops_share_pct
FROM by_quarter_age
ORDER BY quarter, age_group;


/* ============================================================
   5. АНОМАЛИИ, ВЛИЯЮЩИЕ НА ВЫВОДЫ
   ============================================================ */

-- 5.1 Клиенты-выбросы по числу операций.
-- Факт: клиент 16052 совершил 6 677 операций при медиане 6 по базе
-- и сформировал 15.03% всей выручки. Профиль не похож на розничного
-- покупателя — вероятно, оптовый или корпоративный аккаунт.
WITH client_ops AS (
    SELECT
        ID_client,
        COUNT(DISTINCT Id_check)    AS operations_count,
        SUM(Sum_payment)            AS total_payment
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new <  '2016-06-01'
    GROUP BY ID_client
)
SELECT
    ID_client,
    operations_count,
    ROUND(total_payment, 2)                                     AS total_payment,
    ROUND(total_payment * 100.0 / SUM(total_payment) OVER (), 2) AS revenue_share_pct
FROM client_ops
ORDER BY operations_count DESC
LIMIT 10;

-- 5.2 Возрастные группы без клиента-выброса.
-- Факт: лидер по выручке меняется с 60-69 (23.45%) на 20-29 (24.12%).
-- Доля группы 60-69 падает с 23.45% до 9.91%.
WITH tx AS (
    SELECT
        CASE
            WHEN c.Age IS NULL  THEN 'NA'
            WHEN c.Age < 20     THEN '0-19'
            WHEN c.Age < 30     THEN '20-29'
            WHEN c.Age < 40     THEN '30-39'
            WHEN c.Age < 50     THEN '40-49'
            WHEN c.Age < 60     THEN '50-59'
            WHEN c.Age < 70     THEN '60-69'
            ELSE '70+'
        END                     AS age_group,
        t.Id_check,
        t.ID_client,
        t.Sum_payment
    FROM transactions t
    LEFT JOIN customers c
           ON t.ID_client = c.Id_client
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new <  '2016-06-01'
      AND t.ID_client <> 16052
),
by_age AS (
    SELECT
        age_group,
        COUNT(DISTINCT ID_client)   AS clients_count,
        COUNT(DISTINCT Id_check)    AS operations_count,
        SUM(Sum_payment)            AS total_sum
    FROM tx
    GROUP BY age_group
)
SELECT
    age_group,
    clients_count,
    operations_count,
    ROUND(total_sum, 2)                                     AS total_sum,
    ROUND(total_sum / operations_count, 2)                  AS avg_check,
    ROUND(total_sum * 100.0 / SUM(total_sum) OVER (), 2)    AS sum_share_pct
FROM by_age
ORDER BY sum_share_pct DESC;

-- 5.3 Чувствительность результата к выбору 12-месячного окна.
-- 2015-06 неполный (0.83% годовых операций), поэтому требование
-- активности в нём отсекает часть клиентов. Альтернативное окно
-- 2015-07..2016-06 даёт 189 клиентов вместо 82.
-- Запрос считает оба варианта для сравнения.
WITH base AS (
    SELECT
        ID_client,
        DATE_FORMAT(date_new, '%Y-%m') AS month
    FROM transactions
),
window_a AS (
    SELECT ID_client, COUNT(DISTINCT month) AS m
    FROM base
    WHERE month BETWEEN '2015-06' AND '2016-05'
    GROUP BY ID_client
),
window_b AS (
    SELECT ID_client, COUNT(DISTINCT month) AS m
    FROM base
    WHERE month BETWEEN '2015-07' AND '2016-06'
    GROUP BY ID_client
)
SELECT
    '2015-06..2016-05' AS period_window,
    SUM(m = 12)        AS continuous_clients
FROM window_a
UNION ALL
SELECT
    '2015-07..2016-06',
    SUM(m = 12)
FROM window_b;
