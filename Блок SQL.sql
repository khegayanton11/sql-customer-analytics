# 1 Вопрос
#список клиентов с непрерывной историей за год, то есть каждый месяц на регулярной основе без пропусков за указанный годовой период
SELECT
    ID_client,
    COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) AS active_months
FROM transactions
WHERE date_new >= '2015-06-01'
  AND date_new < '2016-06-01'
GROUP BY ID_client
HAVING COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) = 12;
#средний чек за период с 01.06.2015 по 01.06.2016
SELECT
    ROUND(AVG(check_sum), 2) AS avg_check
FROM (
    SELECT
        Id_check,
        SUM(Sum_payment) AS check_sum
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new < '2016-06-01'
    GROUP BY Id_check
) t;

#средняя сумма покупок за месяц
SELECT
    ROUND(AVG(month_sum), 2) AS avg_month_purchase
FROM (
    SELECT
        ID_client,
        DATE_FORMAT(date_new, '%Y-%m') AS month,
        SUM(Sum_payment) AS month_sum
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new < '2016-06-01'
    GROUP BY
        ID_client,
        DATE_FORMAT(date_new, '%Y-%m')
) t;

#количество всех операций по клиенту за период
SELECT
    ID_client,
    COUNT(DISTINCT Id_check) AS total_operations
FROM transactions
WHERE date_new >= '2015-06-01'
  AND date_new < '2016-06-01'
GROUP BY ID_client;

# 2 Вопрос
#Средняя сумма чека в месяц
SELECT
    month,
    ROUND(AVG(check_sum), 2) AS avg_check
FROM (
    SELECT
        DATE_FORMAT(date_new, '%Y-%m') AS month,
        Id_check,
        SUM(Sum_payment) AS check_sum
    FROM transactions
    GROUP BY
        DATE_FORMAT(date_new, '%Y-%m'),
        Id_check
) t
GROUP BY month
ORDER BY month;

#среднее количество операций в месяц
SELECT
    DATE_FORMAT(date_new, '%Y-%m') AS month,
    COUNT(DISTINCT Id_check) AS operations_count
FROM transactions
GROUP BY DATE_FORMAT(date_new, '%Y-%m')
ORDER BY month;

#среднее количество клиентов, которые совершали операции
SELECT
    DATE_FORMAT(date_new, '%Y-%m') AS month,
    COUNT(DISTINCT ID_client) AS clients_count
FROM transactions
GROUP BY DATE_FORMAT(date_new, '%Y-%m')
ORDER BY month;

#долю от общего количества операций за год и долю в месяц от общей суммы операций
SELECT
    DATE_FORMAT(date_new, '%Y-%m') AS month,

    ROUND(SUM(Sum_payment), 2) AS month_sum,

    COUNT(DISTINCT Id_check) AS operations_count,

    COUNT(DISTINCT ID_client) AS clients_count,

    ROUND(SUM(Sum_payment) / COUNT(DISTINCT Id_check), 2) AS avg_check,

    ROUND(
        COUNT(DISTINCT Id_check) * 100.0 /
        SUM(COUNT(DISTINCT Id_check)) OVER (),
        2
    ) AS operations_share_percent,

    ROUND(
        SUM(Sum_payment) * 100.0 /
        SUM(SUM(Sum_payment)) OVER (),
        2
    ) AS sum_share_percent

FROM transactions
WHERE date_new >= '2015-06-01'
  AND date_new < '2016-06-01'
GROUP BY DATE_FORMAT(date_new, '%Y-%m')
ORDER BY month;

#вывести % соотношение M/F/NA в каждом месяце с их долей затрат
SELECT
    DATE_FORMAT(t.date_new, '%Y-%m') AS month,

    COALESCE(c.Gender, 'NA') AS gender_group,

    COUNT(DISTINCT t.ID_client) AS clients_count,

    ROUND(
        COUNT(DISTINCT t.ID_client) * 100.0 /
        SUM(COUNT(DISTINCT t.ID_client)) OVER (
            PARTITION BY DATE_FORMAT(t.date_new, '%Y-%m')
        ),
        2
    ) AS clients_share_percent,

    ROUND(SUM(t.Sum_payment), 2) AS gender_sum_payment,

    ROUND(
        SUM(t.Sum_payment) * 100.0 /
        SUM(SUM(t.Sum_payment)) OVER (
            PARTITION BY DATE_FORMAT(t.date_new, '%Y-%m')
        ),
        2
    ) AS payment_share_percent

FROM transactions t
LEFT JOIN customers c
    ON t.ID_client = c.Id_client

WHERE t.date_new >= '2015-06-01'
  AND t.date_new < '2016-06-01'

GROUP BY
    DATE_FORMAT(t.date_new, '%Y-%m'),
    COALESCE(c.Gender, 'NA')

ORDER BY
    month,
    gender_group;

#возрастные группы клиентов с шагом 10 лет и отдельно клиентов, у которых нет данной информации, 
#с параметрами сумма и количество операций за весь период, и поквартально - средние показатели и %.
SELECT
    CASE
        WHEN c.Age IS NULL THEN 'NA'
        WHEN c.Age < 20 THEN '0-19'
        WHEN c.Age BETWEEN 20 AND 29 THEN '20-29'
        WHEN c.Age BETWEEN 30 AND 39 THEN '30-39'
        WHEN c.Age BETWEEN 40 AND 49 THEN '40-49'
        WHEN c.Age BETWEEN 50 AND 59 THEN '50-59'
        WHEN c.Age BETWEEN 60 AND 69 THEN '60-69'
        ELSE '70+'
    END AS age_group,

    ROUND(SUM(t.Sum_payment), 2) AS total_sum,

    COUNT(DISTINCT t.Id_check) AS operations_count,

    ROUND(
        SUM(t.Sum_payment) * 100.0 /
        SUM(SUM(t.Sum_payment)) OVER (),
        2
    ) AS sum_share_percent,

    ROUND(
        COUNT(DISTINCT t.Id_check) * 100.0 /
        SUM(COUNT(DISTINCT t.Id_check)) OVER (),
        2
    ) AS operations_share_percent

FROM transactions t
LEFT JOIN customers c
    ON t.ID_client = c.Id_client

WHERE t.date_new >= '2015-06-01'
  AND t.date_new < '2016-06-01'

GROUP BY age_group

ORDER BY age_group;



# поквартально
SELECT
    CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new)) AS quarter,

    CASE
        WHEN c.Age IS NULL THEN 'NA'
        WHEN c.Age < 20 THEN '0-19'
        WHEN c.Age BETWEEN 20 AND 29 THEN '20-29'
        WHEN c.Age BETWEEN 30 AND 39 THEN '30-39'
        WHEN c.Age BETWEEN 40 AND 49 THEN '40-49'
        WHEN c.Age BETWEEN 50 AND 59 THEN '50-59'
        WHEN c.Age BETWEEN 60 AND 69 THEN '60-69'
        ELSE '70+'
    END AS age_group,

    ROUND(SUM(t.Sum_payment), 2) AS quarter_sum,

    COUNT(DISTINCT t.Id_check) AS operations_count,

    ROUND(SUM(t.Sum_payment) / COUNT(DISTINCT t.Id_check), 2) AS avg_check,

    ROUND(
        SUM(t.Sum_payment) * 100.0 /
        SUM(SUM(t.Sum_payment)) OVER (
            PARTITION BY CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new))
        ),
        2
    ) AS quarter_sum_share_percent,

    ROUND(
        COUNT(DISTINCT t.Id_check) * 100.0 /
        SUM(COUNT(DISTINCT t.Id_check)) OVER (
            PARTITION BY CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new))
        ),
        2
    ) AS quarter_operations_share_percent

FROM transactions t
LEFT JOIN customers c
    ON t.ID_client = c.Id_client

WHERE t.date_new >= '2015-06-01'
  AND t.date_new < '2016-06-01'

GROUP BY
    quarter,
    age_group

ORDER BY
    quarter,
    age_group;











