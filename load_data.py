"""
Подготовка исходных .xlsx к импорту в MySQL.

Читает файлы из data/, приводит типы и выгружает в CSV,
а также генерирует load_data.sql с командами LOAD DATA.

Запуск:
    python load_data.py
    mysql -u root -p --local-infile=1 customer_analytics < load_data.sql
"""

from pathlib import Path

import pandas as pd

DATA_DIR = Path("data")
OUT_DIR = Path("data")


def main() -> None:
    customers = pd.read_excel(DATA_DIR / "customer_info.xlsx")
    transactions = pd.read_excel(DATA_DIR / "transactions_info.xlsx")

    # в CSV пропуски записываем как \N — MySQL прочитает их как NULL
    customers = customers[["Id_client", "Gender", "Age"]].copy()
    # Age хранится как float из-за пропусков — приводим к целому с поддержкой NULL
    customers["Age"] = customers["Age"].astype("Int64")
    customers.to_csv(OUT_DIR / "customers.csv", index=False, na_rep="\\N")

    transactions["date_new"] = pd.to_datetime(transactions["date_new"]).dt.strftime("%Y-%m-%d")
    transactions = transactions[
        ["date_new", "Id_check", "ID_client", "Count_products", "Sum_payment"]
    ]
    transactions.to_csv(OUT_DIR / "transactions.csv", index=False, na_rep="\\N")

    sql = f"""USE customer_analytics;

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE '{(OUT_DIR / "customers.csv").as_posix()}'
INTO TABLE customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\\n'
IGNORE 1 LINES
(Id_client, @Gender, @Age)
SET Gender = NULLIF(@Gender, ''),
    Age    = NULLIF(@Age, '');

LOAD DATA LOCAL INFILE '{(OUT_DIR / "transactions.csv").as_posix()}'
INTO TABLE transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\\n'
IGNORE 1 LINES
(date_new, Id_check, ID_client, Count_products, Sum_payment);
"""
    Path("load_data.sql").write_text(sql, encoding="utf-8")

    print(f"customers.csv:    {len(customers):>7} строк")
    print(f"transactions.csv: {len(transactions):>7} строк")
    print("load_data.sql записан")


if __name__ == "__main__":
    main()
