-- =========================================================
-- SETUP: Produto de Crédito - Schema Realista
-- =========================================================
USE SimDB;
GO

-- ── Tabela de Clientes ──
IF OBJECT_ID('Customers', 'U') IS NOT NULL DROP TABLE Customers;
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY IDENTITY(1,1),
    CPF VARCHAR(11) NOT NULL UNIQUE,
    FullName NVARCHAR(200) NOT NULL,
    Email VARCHAR(100),
    Phone VARCHAR(20),
    BirthDate DATE,
    CreditScore INT,
    MonthlyIncome DECIMAL(12,2),
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    UpdatedAt DATETIME2 DEFAULT GETDATE(),
    INDEX IX_CPF (CPF),
    INDEX IX_CreditScore (CreditScore)
);

-- ── Tabela de Propostas de Crédito ──
IF OBJECT_ID('CreditProposals', 'U') IS NOT NULL DROP TABLE CreditProposals;
CREATE TABLE CreditProposals (
    ProposalID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL,
    RequestedAmount DECIMAL(12,2) NOT NULL,
    ApprovedAmount DECIMAL(12,2),
    InterestRate DECIMAL(5,2),
    InstallmentCount INT,
    Status VARCHAR(50) NOT NULL, -- PENDING, ANALYZING, APPROVED, REJECTED, DISBURSED
    ProposalType VARCHAR(50), -- PERSONAL, PAYROLL, VEHICLE, HOME_EQUITY
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    UpdatedAt DATETIME2 DEFAULT GETDATE(),
    AnalyzedAt DATETIME2,
    AnalyzedBy VARCHAR(100),
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID),
    INDEX IX_Status (Status),
    INDEX IX_CustomerID (CustomerID),
    INDEX IX_CreatedAt (CreatedAt),
    INDEX IX_Status_CreatedAt (Status, CreatedAt)
);

-- ── Tabela de Análise de Crédito (histórico) ──
IF OBJECT_ID('CreditAnalysis', 'U') IS NOT NULL DROP TABLE CreditAnalysis;
CREATE TABLE CreditAnalysis (
    AnalysisID INT PRIMARY KEY IDENTITY(1,1),
    ProposalID INT NOT NULL,
    AnalysisType VARCHAR(50), -- AUTO, MANUAL, FRAUD_CHECK, BUREAU_CHECK
    Score INT,
    RiskLevel VARCHAR(20), -- LOW, MEDIUM, HIGH, CRITICAL
    Recommendation VARCHAR(50), -- APPROVE, REJECT, MANUAL_REVIEW
    Observations NVARCHAR(1000),
    ProcessingTimeMs INT,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    FOREIGN KEY (ProposalID) REFERENCES CreditProposals(ProposalID),
    INDEX IX_ProposalID (ProposalID),
    INDEX IX_CreatedAt (CreatedAt)
);

-- ── Tabela de Contratos de Crédito ──
IF OBJECT_ID('CreditContracts', 'U') IS NOT NULL DROP TABLE CreditContracts;
CREATE TABLE CreditContracts (
    ContractID INT PRIMARY KEY IDENTITY(1,1),
    ProposalID INT NOT NULL,
    ContractNumber VARCHAR(50) NOT NULL UNIQUE,
    PrincipalAmount DECIMAL(12,2) NOT NULL,
    InterestRate DECIMAL(5,2) NOT NULL,
    InstallmentCount INT NOT NULL,
    InstallmentValue DECIMAL(12,2) NOT NULL,
    FirstDueDate DATE,
    Status VARCHAR(50), -- ACTIVE, PAID_OFF, DEFAULTED, RENEGOTIATED
    DisbursedAt DATETIME2,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    FOREIGN KEY (ProposalID) REFERENCES CreditProposals(ProposalID),
    INDEX IX_ContractNumber (ContractNumber),
    INDEX IX_Status (Status),
    INDEX IX_DisbursedAt (DisbursedAt)
);

-- ── Tabela de Parcelas ──
IF OBJECT_ID('Installments', 'U') IS NOT NULL DROP TABLE Installments;
CREATE TABLE Installments (
    InstallmentID INT PRIMARY KEY IDENTITY(1,1),
    ContractID INT NOT NULL,
    InstallmentNumber INT NOT NULL,
    DueDate DATE NOT NULL,
    Amount DECIMAL(12,2) NOT NULL,
    PaidAmount DECIMAL(12,2),
    PaidAt DATETIME2,
    Status VARCHAR(50), -- PENDING, PAID, OVERDUE, PARTIALLY_PAID
    DaysOverdue INT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    FOREIGN KEY (ContractID) REFERENCES CreditContracts(ContractID),
    INDEX IX_ContractID (ContractID),
    INDEX IX_DueDate (DueDate),
    INDEX IX_Status (Status),
    INDEX IX_Status_DueDate (Status, DueDate)
);

-- ── Tabela de Transações/Eventos ──
IF OBJECT_ID('CreditTransactions', 'U') IS NOT NULL DROP TABLE CreditTransactions;
CREATE TABLE CreditTransactions (
    TransactionID INT PRIMARY KEY IDENTITY(1,1),
    ContractID INT,
    TransactionType VARCHAR(50), -- DISBURSEMENT, PAYMENT, FEE, ADJUSTMENT
    Amount DECIMAL(12,2) NOT NULL,
    Description NVARCHAR(500),
    ProcessedBy VARCHAR(100),
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    INDEX IX_ContractID (ContractID),
    INDEX IX_TransactionType (TransactionType),
    INDEX IX_CreatedAt (CreatedAt)
);

-- ── Tabela de Logs de Auditoria ──
IF OBJECT_ID('AuditLog', 'U') IS NOT NULL DROP TABLE AuditLog;
CREATE TABLE AuditLog (
    LogID BIGINT PRIMARY KEY IDENTITY(1,1),
    EntityType VARCHAR(50), -- PROPOSAL, CONTRACT, CUSTOMER
    EntityID INT,
    Action VARCHAR(100),
    UserService VARCHAR(100),
    Changes NVARCHAR(MAX), -- JSON com as mudanças
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    INDEX IX_EntityType_EntityID (EntityType, EntityID),
    INDEX IX_CreatedAt (CreatedAt)
);

-- ── Populando dados iniciais ──
PRINT 'Inserindo clientes...';
DECLARE @i INT = 1;
WHILE @i <= 10000
BEGIN
    INSERT INTO Customers (CPF, FullName, Email, Phone, BirthDate, CreditScore, MonthlyIncome)
    VALUES (
        RIGHT('00000000000' + CAST(@i AS VARCHAR), 11),
        'Cliente ' + CAST(@i AS VARCHAR),
        'cliente' + CAST(@i AS VARCHAR) + '@example.com',
        '11' + RIGHT('000000000' + CAST(@i AS VARCHAR), 9),
        DATEADD(YEAR, -20 - (@i % 40), GETDATE()),
        300 + (@i % 600),
        1500 + (@i % 15000)
    );
    SET @i = @i + 1;
END

PRINT 'Inserindo propostas...';
SET @i = 1;
WHILE @i <= 50000
BEGIN
    DECLARE @status VARCHAR(50) = CASE (@i % 10)
        WHEN 0 THEN 'PENDING'
        WHEN 1 THEN 'ANALYZING'
        WHEN 2 THEN 'APPROVED'
        WHEN 3 THEN 'REJECTED'
        WHEN 4 THEN 'DISBURSED'
        ELSE 'APPROVED'
    END;
    
    DECLARE @customerID INT = 1 + (@i % 10000);
    
    INSERT INTO CreditProposals (CustomerID, RequestedAmount, ApprovedAmount, InterestRate, InstallmentCount, Status, ProposalType, CreatedAt)
    VALUES (
        @customerID,
        1000 + (@i % 50000),
        CASE WHEN @status IN ('APPROVED', 'DISBURSED') THEN 1000 + (@i % 50000) * 0.9 ELSE NULL END,
        2.5 + (@i % 5),
        12 * (1 + (@i % 4)),
        @status,
        CASE (@i % 4)
            WHEN 0 THEN 'PERSONAL'
            WHEN 1 THEN 'PAYROLL'
            WHEN 2 THEN 'VEHICLE'
            ELSE 'HOME_EQUITY'
        END,
        DATEADD(MINUTE, -(@i % 43200), GETDATE()) -- últimas 30 dias
    );
    SET @i = @i + 1;
END

PRINT 'Inserindo análises...';
INSERT INTO CreditAnalysis (ProposalID, AnalysisType, Score, RiskLevel, Recommendation, ProcessingTimeMs, CreatedAt)
SELECT 
    ProposalID,
    CASE (ProposalID % 4)
        WHEN 0 THEN 'AUTO'
        WHEN 1 THEN 'MANUAL'
        WHEN 2 THEN 'FRAUD_CHECK'
        ELSE 'BUREAU_CHECK'
    END,
    400 + (ProposalID % 400),
    CASE 
        WHEN (ProposalID % 400) < 100 THEN 'CRITICAL'
        WHEN (ProposalID % 400) < 200 THEN 'HIGH'
        WHEN (ProposalID % 400) < 300 THEN 'MEDIUM'
        ELSE 'LOW'
    END,
    CASE 
        WHEN (ProposalID % 400) < 150 THEN 'REJECT'
        WHEN (ProposalID % 400) < 200 THEN 'MANUAL_REVIEW'
        ELSE 'APPROVE'
    END,
    50 + (ProposalID % 2000),
    DATEADD(MINUTE, -(ProposalID % 43200), GETDATE())
FROM CreditProposals
WHERE Status IN ('ANALYZING', 'APPROVED', 'REJECTED', 'DISBURSED');

PRINT 'Setup completo!';

-- Contagem de registros
DECLARE @CustomerCount INT, @ProposalCount INT, @AnalysisCount INT;
SELECT @CustomerCount = COUNT(*) FROM Customers;
SELECT @ProposalCount = COUNT(*) FROM CreditProposals;
SELECT @AnalysisCount = COUNT(*) FROM CreditAnalysis;

PRINT 'Total de clientes: ' + CAST(@CustomerCount AS VARCHAR);
PRINT 'Total de propostas: ' + CAST(@ProposalCount AS VARCHAR);
PRINT 'Total de análises: ' + CAST(@AnalysisCount AS VARCHAR);
GO
