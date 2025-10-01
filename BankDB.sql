-- ===========================================
-- BANK MANAGEMENT SYSTEM - FINAL CLEAN SCRIPT
-- ===========================================

-- Create Database
CREATE DATABASE IF NOT EXISTS BankDB;
USE BankDB;

-- ========================
-- 1. TABLE CREATION
-- ========================

-- Table: Branch
CREATE TABLE IF NOT EXISTS Branch (
  BranchID INT PRIMARY KEY AUTO_INCREMENT,
  BranchName VARCHAR(100) NOT NULL,
  BranchCity VARCHAR(100) NOT NULL,
  ManagerName VARCHAR(100),
  CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table: Customer
CREATE TABLE IF NOT EXISTS Customer (
  CustomerID INT PRIMARY KEY AUTO_INCREMENT,
  FirstName VARCHAR(50),
  LastName VARCHAR(50),
  Address VARCHAR(200),
  City VARCHAR(100),
  Phone VARCHAR(20),
  Email VARCHAR(100),
  DOB DATE,
  CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table: Account
CREATE TABLE IF NOT EXISTS Account (
  AccountID INT PRIMARY KEY AUTO_INCREMENT,
  CustomerID INT,
  BranchID INT,
  AccountType VARCHAR(20), -- 'Savings', 'Current'
  Balance DECIMAL(15,2) DEFAULT 0.00,
  AccountStatus VARCHAR(20) DEFAULT 'Active',
  OpenDate DATE,
  FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
  FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

-- Table: Transaction
CREATE TABLE IF NOT EXISTS TransactionTable (
  TransactionID INT PRIMARY KEY AUTO_INCREMENT,
  AccountID INT,
  TransactionType VARCHAR(20), -- 'Credit' or 'Debit'
  Amount DECIMAL(15,2),
  TransactionDate DATETIME DEFAULT CURRENT_TIMESTAMP,
  Description VARCHAR(200),
  FOREIGN KEY (AccountID) REFERENCES Account(AccountID)
);

-- Table: Loan
CREATE TABLE IF NOT EXISTS Loan (
  LoanID INT PRIMARY KEY AUTO_INCREMENT,
  CustomerID INT,
  BranchID INT,
  LoanAmount DECIMAL(15,2),
  InterestRate DECIMAL(5,2),
  LoanStatus VARCHAR(20), -- 'Open', 'Closed', 'Default'
  StartDate DATE,
  EndDate DATE,
  FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
  FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

-- ========================
-- 2. SAMPLE DATA INSERTION
-- ========================

INSERT INTO Branch (BranchName, BranchCity, ManagerName) VALUES
('Main Branch','Delhi','Ravi Sharma'),
('Sector 17','Chandigarh','Priya Singh'),
('MG Road','Bengaluru','Amit Kumar');

INSERT INTO Customer (FirstName, LastName, Address, City, Phone, Email, DOB) VALUES
('Mansi','Sharma','Street 1, Delhi','Delhi','9876543210','mansi@example.com','2003-05-10'),
('Rohit','Verma','Street 2, Chandigarh','Chandigarh','9123456780','rohit@example.com','2002-11-20');

INSERT INTO Account (CustomerID, BranchID, AccountType, Balance, OpenDate) VALUES
(1,1,'Savings',50000.00,'2024-01-10'),
(2,2,'Current',150000.00,'2024-03-12');

INSERT INTO TransactionTable (AccountID, TransactionType, Amount, Description) VALUES
(1,'Credit',20000,'Salary deposit'),
(1,'Debit',5000,'ATM withdrawal'),
(2,'Debit',20000,'Online transfer');

-- ========================
-- 3. INDEXES
-- ========================
CREATE INDEX idx_tx_account_date ON TransactionTable (AccountID, TransactionDate);
CREATE INDEX idx_account_balance ON Account (Balance);
CREATE INDEX idx_customer_city ON Customer (City);

-- ========================
-- 4. TRIGGERS
-- ========================
DELIMITER //

-- Prevent overdraft
CREATE TRIGGER trg_before_insert_tx
BEFORE INSERT ON TransactionTable
FOR EACH ROW
BEGIN
  DECLARE curBal DECIMAL(15,2);
  IF NEW.TransactionType = 'Debit' THEN
    SELECT Balance INTO curBal FROM Account WHERE AccountID = NEW.AccountID;
    IF curBal < NEW.Amount THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Insufficient funds - transaction blocked';
    END IF;
  END IF;
END;
//

-- Update account balance after transaction
CREATE TRIGGER trg_after_insert_tx
AFTER INSERT ON TransactionTable
FOR EACH ROW
BEGIN
  IF NEW.TransactionType = 'Credit' THEN
    UPDATE Account SET Balance = Balance + NEW.Amount WHERE AccountID = NEW.AccountID;
  ELSEIF NEW.TransactionType = 'Debit' THEN
    UPDATE Account SET Balance = Balance - NEW.Amount WHERE AccountID = NEW.AccountID;
  END IF;
END;
//

DELIMITER ;

-- ========================
-- 5. PROCEDURES
-- ========================
DELIMITER //

-- Fund Transfer
CREATE PROCEDURE transfer_funds(IN from_acc INT, IN to_acc INT, IN amt DECIMAL(15,2))
BEGIN
  DECLARE from_bal DECIMAL(15,2);
  START TRANSACTION;
  SELECT Balance INTO from_bal FROM Account WHERE AccountID = from_acc FOR UPDATE;
  IF from_bal < amt THEN
    ROLLBACK;
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient funds for transfer';
  ELSE
    UPDATE Account SET Balance = Balance - amt WHERE AccountID = from_acc;
    UPDATE Account SET Balance = Balance + amt WHERE AccountID = to_acc;
    INSERT INTO TransactionTable(AccountID,TransactionType,Amount,Description) 
    VALUES (from_acc,'Debit',amt,CONCAT('Transfer to ',to_acc));
    INSERT INTO TransactionTable(AccountID,TransactionType,Amount,Description) 
    VALUES (to_acc,'Credit',amt,CONCAT('Transfer from ',from_acc));
    COMMIT;
  END IF;
END;
//

-- Customer Statement
CREATE PROCEDURE get_customer_statement(IN cust_id INT, IN from_dt DATETIME, IN to_dt DATETIME)
BEGIN
  SELECT a.AccountID, t.TransactionID, t.TransactionDate, 
         t.TransactionType, t.Amount, t.Description
  FROM Account a
  JOIN TransactionTable t ON a.AccountID = t.AccountID
  WHERE a.CustomerID = cust_id 
    AND t.TransactionDate BETWEEN from_dt AND to_dt
  ORDER BY t.TransactionDate;
END;
//

DELIMITER ;

-- ========================
-- 6. VIEWS
-- ========================

CREATE OR REPLACE VIEW Customer_Transactions AS
SELECT c.CustomerID, CONCAT(c.FirstName,' ',c.LastName) AS CustomerName, 
       a.AccountID, t.TransactionID, t.TransactionDate, 
       t.TransactionType, t.Amount, t.Description
FROM Customer c
JOIN Account a ON c.CustomerID = a.CustomerID
JOIN TransactionTable t ON a.AccountID = t.AccountID;

-- ========================
-- 7. ANALYTICAL QUERIES
-- ========================

-- Top 5 customers by balance
SELECT c.CustomerID, CONCAT(c.FirstName,' ',c.LastName) AS Name,
       SUM(a.Balance) AS TotalBalance
FROM Customer c
JOIN Account a ON c.CustomerID = a.CustomerID
GROUP BY c.CustomerID
ORDER BY TotalBalance DESC
LIMIT 5;

-- Accounts with very high debit transactions in last 24 hours
SELECT AccountID, SUM(Amount) AS TotalDebits
FROM TransactionTable
WHERE TransactionType='Debit' AND TransactionDate >= NOW() - INTERVAL 1 DAY
GROUP BY AccountID
HAVING TotalDebits > 100000;

-- Branch performance (last 3 months deposits)
SELECT b.BranchID, b.BranchName, SUM(t.Amount) AS TotalDeposits
FROM Branch b
JOIN Account a ON b.BranchID = a.BranchID
JOIN TransactionTable t ON a.AccountID = t.AccountID
WHERE t.TransactionType='Credit' 
  AND t.TransactionDate >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
GROUP BY b.BranchID
ORDER BY TotalDeposits DESC;

-- Customers with balance > 1,00,000
SELECT c.CustomerID, CONCAT(c.FirstName,' ',c.LastName) AS Name, 
       SUM(a.Balance) AS TotalBalance
FROM Customer c 
JOIN Account a ON c.CustomerID = a.CustomerID
GROUP BY c.CustomerID
HAVING TotalBalance > 100000;
SELECT * FROM Branch;
SELECT * FROM Customer;
SELECT * FROM Account;
SELECT * FROM TransactionTable;
SELECT * FROM Loan;
