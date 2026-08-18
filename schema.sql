/* ============================================================
   Схема данных проекта
   СУБД: MySQL 8.0+
   ============================================================ */

CREATE DATABASE IF NOT EXISTS customer_analytics
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE customer_analytics;

DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS customers;

/* Справочник клиентов: одна строка на клиента.
   Gender и Age допускают NULL — в исходных данных они заполнены
   не у всех клиентов (2.63% и 1.44% пропусков соответственно). */
CREATE TABLE customers (
    Id_client   INT         NOT NULL,
    Gender      CHAR(1)     NULL,
    Age         TINYINT     NULL,
    PRIMARY KEY (Id_client)
) ENGINE = InnoDB;

/* Транзакции: одна строка на ПОЗИЦИЮ в чеке, а не на чек.
   Один Id_check объединяет несколько строк, поэтому количество
   операций считается как COUNT(DISTINCT Id_check).

   date_new в исходных данных содержит только первое число месяца
   и является меткой месяца, а не датой транзакции. */
CREATE TABLE transactions (
    id              INT             NOT NULL AUTO_INCREMENT,
    date_new        DATE            NOT NULL,
    Id_check        INT             NOT NULL,
    ID_client       INT             NOT NULL,
    Count_products  DECIMAL(10,3)   NULL,
    Sum_payment     DECIMAL(12,2)   NOT NULL,
    PRIMARY KEY (id),
    KEY idx_date (date_new),
    KEY idx_client (ID_client),
    KEY idx_check (Id_check),
    CONSTRAINT fk_tx_client FOREIGN KEY (ID_client)
        REFERENCES customers (Id_client)
) ENGINE = InnoDB;
