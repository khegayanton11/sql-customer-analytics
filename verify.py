"""
Проверка финального queries.sql: каждый запрос транслируется в диалект
SQLite и выполняется на реальных данных. Цель — убедиться, что файл
синтаксически корректен, все запросы отрабатывают и возвращают именно
те числа, которые записаны в комментариях и README.
"""
import re
import sqlite3
import pandas as pd

cust = pd.read_excel("data/customer_info.xlsx")
tx = pd.read_excel("data/transactions_info.xlsx")
tx["date_new"] = pd.to_datetime(tx["date_new"])

con = sqlite3.connect(":memory:")
cust.to_sql("customers", con, index=False)
tx.assign(date_new=tx.date_new.dt.strftime("%Y-%m-%d")).to_sql("transactions", con, index=False)

sql_text = open("queries.sql", encoding="utf-8").read()

# убрать блочные комментарии и USE
sql_text = re.sub(r"/\*.*?\*/", "", sql_text, flags=re.S)
sql_text = re.sub(r"(?m)^USE .*?;$", "", sql_text)

statements = [s.strip() for s in sql_text.split(";") if s.strip()]
# отбросить обрывки, состоящие только из строчных комментариев
statements = [s for s in statements
              if any(not l.strip().startswith("--") and l.strip() for l in s.splitlines())]


def to_sqlite(q: str) -> str:
    q = re.sub(r"DATE_FORMAT\(\s*([\w.]+)\s*,\s*'%Y-%m'\s*\)", r"substr(\1,1,7)", q)
    q = re.sub(r"YEAR\(\s*([\w.]+)\s*\)", r"substr(\1,1,4)", q)
    q = re.sub(
        r"QUARTER\(\s*([\w.]+)\s*\)",
        r"(CASE WHEN substr(\1,6,2) IN ('01','02','03') THEN '1' "
        r"WHEN substr(\1,6,2) IN ('04','05','06') THEN '2' "
        r"WHEN substr(\1,6,2) IN ('07','08','09') THEN '3' ELSE '4' END)",
        q,
    )
    q = re.sub(r"CONCAT\(([^()]*?)\)", lambda m: " || ".join(p.strip() for p in m.group(1).split(",")), q)
    q = re.sub(r"DAY\(\s*([\w.]+)\s*\)", r"CAST(substr(\1,9,2) AS INTEGER)", q)
    q = re.sub(r"CONCAT_WS\('\|',\s*([^)]*)\)", lambda m: " || '|' || ".join(
        p.strip() for p in m.group(1).split(",")), q)
    # MySQL: SUM(bool) → SQLite: SUM(CASE WHEN ... THEN 1 ELSE 0 END)
    q = re.sub(r"SUM\(([\w.]+ IS NULL)\)", r"SUM(CASE WHEN \1 THEN 1 ELSE 0 END)", q)
    q = re.sub(r"SUM\(([\w.]+\s*[<>=]+\s*[\w']+)\)", r"SUM(CASE WHEN \1 THEN 1 ELSE 0 END)", q)
    q = re.sub(r"SUM\(([\w.]+\s*<>\s*[\w']+)\)", r"SUM(CASE WHEN \1 THEN 1 ELSE 0 END)", q)
    q = re.sub(r"SUM\((\w+ = 12)\)", r"SUM(CASE WHEN \1 THEN 1 ELSE 0 END)", q)
    return q


results = {}
failed = []
for i, st in enumerate(statements, 1):
    label = next((l.strip("- ").strip() for l in st.splitlines()
                  if l.strip().startswith("--")), f"запрос {i}")
    try:
        df = pd.read_sql_query(to_sqlite(st), con)
        results[label] = df
        print(f"[OK ] {label[:70]:70s} → {len(df):>6} строк")
    except Exception as e:
        failed.append((label, e))
        print(f"[FAIL] {label[:70]:70s} → {e}")

print(f"\nВыполнено: {len(results)} / {len(statements)}; ошибок: {len(failed)}")
assert not failed, failed

# ---- сверка ключевых чисел с тем, что записано в комментариях и README ----
print("\n=== СВЕРКА ЗАЯВЛЕННЫХ ЧИСЕЛ ===")


def find(fragment):
    for k, v in results.items():
        if fragment.lower() in k.lower():
            return v
    raise KeyError(fragment)


checks = []

d = tx[(tx.date_new >= "2015-06-01") & (tx.date_new < "2016-06-01")]

v = find("Дубликаты ключа")
checks.append(("дубликатов в справочнике нет", len(v), 0))

v = find("Коэффициент размножения")
checks.append(("коэффициент размножения = 1.0", float(v.rows_per_unique_client[0]), 1.0))

v = find("Транзакции с клиентом")
checks.append(("осиротевших строк 0", int(v.orphan_rows[0]), 0))

v = find("Полнота справочника")
checks.append(("клиентов в справочнике 2429", int(v.clients_total[0]), 2429))
checks.append(("Gender не заполнен у 64", int(v.gender_missing[0]), 64))
checks.append(("Age не заполнен у 35", int(v.age_missing[0]), 35))
checks.append(("Age максимум 88", float(v.age_max[0]), 88.0))

v = find("Гранулярность дат")
checks.append(("уникальных дат 13", int(v.distinct_dates[0]), 13))
checks.append(("дат не первого числа 0", int(v.not_first_of_month[0]), 0))

v = find("Один ли клиент")
checks.append(("чеков с >1 клиентом 0", int(v.checks_with_many_clients[0]), 0))
checks.append(("чеков с >1 датой 0", int(v.checks_with_many_dates[0]), 0))

v = find("Полные дубликаты строк")
checks.append(("полных дублей 11592", int(v.duplicate_rows[0]), 11592))

v = find("Клиенты, совершавшие покупки в каждом")
checks.append(("клиентов с 12/12 месяцев 82", len(v), 82))

v = find("Средний чек за период")
checks.append(("средний чек 94.65", float(v.avg_check[0]), 94.65))
checks.append(("чеков за период 38183", int(v.checks_total[0]), 38183))

v = find("Средняя сумма покупок клиента за месяц")
checks.append(("средняя сумма клиента в месяц 312.02", float(v.avg_client_month_payment[0]), 312.02))

v = find("Распределение количества операций")
checks.append(("активных клиентов 2357", int(v.clients_total[0]), 2357))
checks.append(("среднее операций 16.2", float(v.avg_operations[0]), 16.2))
checks.append(("максимум операций 6677", int(v.max_operations[0]), 6677))

v = find("Средние помесячные показатели")
checks.append(("месяцев 12", int(v.months_in_period[0]), 12))
checks.append(("средняя выручка в месяц 301153.10", round(float(v.avg_month_sum[0]), 2), 301153.10))
checks.append(("среднее операций в месяц 3181.92", float(v.avg_month_operations[0]), 3181.92))
checks.append(("среднее клиентов в месяц 965.17", float(v.avg_month_clients[0]), 965.17))

v = find("Витрина по месяцам")
checks.append(("строк витрины 12", len(v), 12))
checks.append(("сумма долей выручки 100", round(v.sum_share_pct.sum()), 100))
feb = v[v.month == "2016-02"].iloc[0]
checks.append(("февраль 13.35% выручки", float(feb.sum_share_pct), 13.35))
checks.append(("февраль средний чек 103.07", float(feb.avg_check), 103.07))
jun = v[v.month == "2015-06"].iloc[0]
checks.append(("июнь 2015 доля 0.83%", float(jun.sum_share_pct), 0.83))
checks.append(("выручка за период 3613837.21", round(float(v.month_sum.sum()), 2), 3613837.21))

v = find("Показатели по возрастным группам")
checks.append(("возрастных групп 8", len(v), 8))
g69 = v[v.age_group == "60-69"].iloc[0]
checks.append(("60-69 доля выручки 23.45%", float(g69.sum_share_pct), 23.45))
checks.append(("60-69 операций на клиента 43.94", float(g69.ops_per_client), 43.94))
g29 = v[v.age_group == "20-29"].iloc[0]
checks.append(("20-29 доля выручки 20.49%", float(g29.sum_share_pct), 20.49))

v = find("Клиенты-выбросы")
top = v.iloc[0]
checks.append(("топ-клиент 16052", int(top.ID_client), 16052))
checks.append(("его операций 6677", int(top.operations_count), 6677))
checks.append(("его доля выручки 15.03%", float(top.revenue_share_pct), 15.03))

v = find("Возрастные группы без клиента-выброса")
lead = v.iloc[0]
checks.append(("лидер без выброса — 20-29", lead.age_group, "20-29"))
checks.append(("его доля 24.12%", float(lead.sum_share_pct), 24.12))
g69b = v[v.age_group == "60-69"].iloc[0]
checks.append(("60-69 падает до 9.91%", float(g69b.sum_share_pct), 9.91))

v = find("Чувствительность результата")
w = dict(zip(v.period_window, v.continuous_clients))
checks.append(("окно 2015-06..2016-05 → 82", int(w["2015-06..2016-05"]), 82))
checks.append(("окно 2015-07..2016-06 → 189", int(w["2015-07..2016-06"]), 189))

v = find("Доли по клиентам и по затратам")
checks.append(("строк сегментации по полу 36", len(v), 36))
for m in v.month.unique():
    s = v[v.month == m].payment_share_pct.sum()
    assert 99.5 <= s <= 100.5, (m, s)
checks.append(("доли по полу в каждом месяце = 100%", True, True))

bad = 0
for name, got, exp in checks:
    ok = (abs(got - exp) < 0.011) if isinstance(exp, float) else (got == exp)
    print(f"  [{'OK ' if ok else 'ОШИБКА'}] {name}: получено {got}")
    if not ok:
        bad += 1
print(f"\nПроверено значений: {len(checks)}, расхождений: {bad}")
assert bad == 0
print("ВСЕ ЧИСЛА В ФАЙЛЕ ПОДТВЕРЖДЕНЫ")
