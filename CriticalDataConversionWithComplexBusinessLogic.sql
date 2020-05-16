
/* Stored proc that was used to convert an entire portfolio of cardholders, accounts, and thier associated demographic data to a new system. */
/* This is the core of a major system integration and the culmination of a lot of business logic that I created in collaboration others in the business. */
/* There are a lot of examples in here of techniques and language features that you might use in a similar data conversion or integration project. */

IF OBJECT_ID('LoadPrepaidBase') is not null DROP PROC LoadPrepaidBase;
GO
CREATE PROC LoadPrepaidBase 
@truncate int, @expDate datetime
AS 


SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

--DECLARE @truncate AS int = 1;

IF @truncate = 1 
BEGIN
	PRINT 'Truncating Prepaid Base...';
	TRUNCATE TABLE Prepaid.dbo.Cardholders
	TRUNCATE TABLE Prepaid.dbo.Accounts
	TRUNCATE TABLE Prepaid.dbo.AccountBalances
	TRUNCATE TABLE Prepaid.dbo.AccountCardholders
	TRUNCATE TABLE Prepaid.dbo.Addresses
	TRUNCATE TABLE Prepaid.dbo.Phones
	TRUNCATE TABLE Prepaid.dbo.Emails
	TRUNCATE TABLE Prepaid.dbo.Cards
	TRUNCATE TABLE Prepaid.dbo.CardCreationHistories
END


--DECLARE @expDate as datetime = '2015-07-01';
DECLARE @diffDate as datetime;

/* All qualifying base plastic accounts */

/* Preserve any previous copies of Qualifying Accounts */

DECLARE @newTable as varchar(100) = 'QualifyingAccounts_COPY_' + CONVERT(varchar(20), getdate(), 120);
IF OBJECT_ID('ADHOC.ConversionShared.QualifyingAccounts_COPY') IS NOT NULL EXEC  ADHOC.sys.sp_rename 'ADHOC.ConversionShared.QualifyingAccounts_COPY', @newTable;

/* Make new "current" copy of Qualifying Accounts */
IF OBJECT_ID('ADHOC.ConversionShared.QualifyingAccounts') is not null
BEGIN
	SELECT * INTO ADHOC.ConversionShared.QualifyingAccounts_COPY FROM ADHOC.ConversionShared.QualifyingAccounts
END
/* drop the current Qualifying accounts table */
IF OBJECT_ID('ADHOC.ConversionShared.QualifyingAccounts') IS NOT NULL DROP TABLE ADHOC.ConversionShared.QualifyingAccounts;

PRINT 'Creating Qualifying Accounts...'

/* Make new Qualifying Accounts table */
SELECT * INTO ADHOC.ConversionShared.QualifyingAccounts 
FROM
(
	
	/* Get all accounts with at least one non-expired card */
	SELECT DISTINCT mch.* FROM TblMasterCardHolders AS mch 
	JOIN TblCards AS c ON c.cardholderid = mch.entryid
	WHERE AccountTypeId = 1 
	AND c.expmonth > 0 
    AND c.expyear > 0 
    AND c.externalcardid > 0 
	AND DATEFROMPARTS (c.expyear, c.expmonth, (DAY(EOMONTH(DATEFROMPARTS(c.expyear, c.expmonth, 1))))) > @expDate --expiring after this date
	AND ssn is not null and ssn <> '' AND ssn <> '999999999' AND ssn <> '123456789' AND firstname <> 'FIRST NAME' --AND ssn NOT LIKE '00%' 
	--AND mch.LastUpdateDate < @restrictdate
	UNION

	/* Get all accounts with a non zero balance */
	SELECT mch.* FROM TblMasterCardHolders AS mch 
	JOIN Transactions.dbo.TblAccountBalances AS ab ON ab.UserAccountID = mch.provideraccountID
	WHERE AccountTypeID = 1 AND ab.UserLedgerBalance <> 0
	AND ssn is not null and ssn <> '' AND ssn <> '999999999' AND ssn <> '123456789' AND firstname <> 'FIRST NAME' --AND ssn NOT LIKE '00%' 
	
	UNION
	
	/* Get the "base" accounts for all goals with a non-zero balance */
	SELECT b.* FROM TblMasterCardHolders AS mch 
	JOIN [TblGoalInformation] AS g ON g.EntryID = mch.entryid --only look at goal accounts
	JOIN Transactions.dbo.TblAccountBalances AS ab ON ab.UserAccountID = mch.provideraccountID --get the balance for the goals
	JOIN TblMasterCardHolders AS b ON b.entryid = g.PayRewardsToEntryID --select the base account
	WHERE ab.UserLedgerBalance <> 0
	AND b.ssn is not null and b.ssn <> '' AND b.ssn <> '999999999' AND b.ssn <> '123456789' AND b.firstname <> 'FIRST NAME' --AND b.ssn NOT LIKE '00%' 
	
) as qa

/* Goals are not nessesarily tied to an account other than the one which gets paid rewards...that account can change. So I brought over ALL goal accounts belonging to ANY qualifying accounts. */ 
INSERT INTO ADHOC.ConversionShared.QualifyingAccounts 
( entryid, programid, clientkey, providercreationtime, providerkey, firstname, lastname, address1, address2, address3, address4, city, state, country, zip, email, telephone, ssn, dob, password, accountstatus, created, availablebalance, ledgerbalance, sex, activateddate, fraudrating, CreateDate, LastUpdateDate, LastUpdateUser, customReferralID, EmailVerified, celltel, provideraccountID, RetailStatusID, OriginalCardIssuanceID, ActiveCardID, LastFeePlanChangeID, AccountTypeId, PreferredLanguage ) 
SELECT mch.* FROM TblMastercardholders AS mch 
JOIN ( SELECT ssn FROM ADHOC.ConversionShared.QualifyingAccounts GROUP BY ssn) AS qch ON qch.ssn = mch.ssn AND mch.AccountTypeId = 2


/* Exclude closed accounts that have a zero balance */
DELETE qa
FROM ADHOC.ConversionShared.QualifyingAccounts AS qa
LEFT JOIN Transactions.dbo.TblAccountBalances AS ab ON ab.UserAccountID = qa.provideraccountID
WHERE accountstatus = 6 AND ISNULL(ab.UserAvailableBalance, 0) = 0 AND ISNULL(ab.UserLedgerBalance, 0) = 0 

/* Mark accounts that no longer qualify as closed. */
IF OBJECT_ID('ADHOC.ConversionShared.QualifyingAccounts_COPY') is not null
BEGIN
	IF OBJECT_ID('ADHOC.ConversionShared.AccountsToClose') IS NOT NULL DROP TABLE ADHOC.ConversionShared.AccountsToClose;
	SELECT qac.entryid INTO ADHOC.ConversionShared.AccountsToClose
	FROM ADHOC.ConversionShared.QualifyingAccounts_COPY AS qac
	LEFT JOIN ADHOC.ConversionShared.QualifyingAccounts AS qa ON qa.entryid = qac.entryid
	WHERE qa.entryid is null
	
	PRINT 'Marking dropped accounts as closed...';

	UPDATE ppa SET [Status] = 40 FROM ADHOC.dbo.Accounts AS ppa
	JOIN ADHOC.ConversionShared.AccountsToClose AS atc ON atc.entryid = ppa.id
END


PRINT 'Deleting junk from Qualifying Accounts...';

DELETE FROM ADHOC.ConversionShared.QualifyingAccounts 
--OUTPUT DELETED.* INTO ADHOC.ConversionShared.QualifyingAccounts_BAD_DOB
WHERE dob is null

DELETE FROM ADHOC.ConversionShared.QualifyingAccounts 
--OUTPUT DELETED.* INTO ADHOC.ConversionShared.QualifyingAccounts_BAD_ProviderKey
WHERE LTRIM(RTRIM(providerkey)) = '' OR TRY_CONVERT(bigint, providerkey) is null 


PRINT 'Ranking Qualified Accounts...';

IF OBJECT_ID('ADHOC.ConversionShared.QualifyingAccountsRanked') is not null DROP TABLE ADHOC.ConversionShared.QualifyingAccountsRanked;
SELECT *, 
ROW_NUMBER() OVER (PARTITION BY ssn ORDER BY accounttypeid, accountstatus, ActivatedDate DESC, CreateD) AS 'ContactRank'
INTO ADHOC.ConversionShared.QualifyingAccountsRanked
FROM ADHOC.ConversionShared.QualifyingAccounts 

CREATE CLUSTERED INDEX ix_QualifyingAccounts_entryid ON ADHOC.ConversionShared.QualifyingAccountsRanked (entryid)
CREATE NONCLUSTERED INDEX ix_QualifyingAccounts_ssn ON ADHOC.ConversionShared.QualifyingAccountsRanked (ssn)


PRINT 'Creating DDID Lookup...';
/* Create DDID Lookup Table each time */

IF OBJECT_ID('tempdb..#tempDDID') is not null DROP TABLE #tempDDID;
IF OBJECT_ID('ADHOC.ConversionShared.DDID_Lookup') is null 
BEGIN

	CREATE TABLE ADHOC.ConversionShared.DDID_Lookup (
		entryid bigint PRIMARY KEY, 
		ShortDepositId varchar(20), 
		FullDepositID varchar(20), 
		EncryptedDepositID varchar(128), 
		CreateDate datetime 
	)
END;

WITH DDIDCTE AS (
SELECT DISTINCT

	ddid.Entryid, 
	ddid.ShortDepositID,
	ddid.FullDepositID, 
	ddid.EncryptedDepositID, 
	ddid.DDID_Used,
	ADHOC.dbo.ToUtcTime(ddid.createdate) AS 'CreateDate', 
	ddid.UseRank
	
FROM TblDepositIDNumbers AS x 
	JOIN 
	(
		SELECT 
		ddid.Entryid,
		ddid.ShortDepositID, 
		ddid.FullDepositID, 
		ddid.EncryptedDepositID, 
		used.DDID_Used,
		ddid.createdate, 
		DENSE_RANK() OVER (Partition by ddid.entryid order by used.ddid_used DESC) AS UseRank
		FROM TblDepositIDNumbers AS ddid
		JOIN --get those with multiple ddid
		( 
			SELECT did.Entryid FROM TblMasterCardHolders AS mch
			JOIN TblDepositIDNumbers AS did ON did.Entryid = mch.entryid
			GROUP BY did.entryid 
			HAVING COUNT(*) > 1
		) AS multiples ON multiples.Entryid = ddid.Entryid
		OUTER APPLY  --count how many times as ddid has been used for each entryid
		(
			SELECT COUNT(*) AS 'DDID_Used' FROM TblDirectDepositDetailRecord WHERE ddid.EncryptedDepositID = dfiaccountno GROUP BY dfiaccountno
		) as used

	) AS ddid ON ddid.Entryid = x.Entryid

)

SELECT *, ROW_NUMBER() OVER (PARTITION BY entryid ORDER BY DDID_Used DESC) AS OfUseRank 
INTO #tempDDID
FROM DDIDCTE 

INSERT INTO ADHOC.ConversionShared.DDID_Lookup 
(entryid, ShortDepositId, FullDepositID, EncryptedDepositID, CreateDate )
SELECT t.entryid, t.ShortDepositId, t.FullDepositID, t.EncryptedDepositID, t.CreateDate 
FROM #tempDDID AS t
LEFT JOIN ADHOC.ConversionShared.DDID_Lookup as d ON d.entryid = t.Entryid
WHERE OfUseRank = 1 AND d.entryid is null

CREATE CLUSTERED INDEX ix_entryid ON #tempDDID (entryid)

INSERT INTO ADHOC.ConversionShared.DDID_Lookup (entryid, ShortDepositID, FullDepositID, EncryptedDepositID, did.CreateDate)
	SELECT mch.entryid,did.ShortDepositID, did.Fulldepositid, did.EncryptedDepositID, did.CreateDate
		FROM TblMasterCardHolders AS mch 
		JOIN TblDepositIDNumbers AS did ON did.Entryid = mch.entryid
		LEFT JOIN ADHOC.ConversionShared.DDID_Lookup AS d ON d.entryid = mch.entryid 
	WHERE mch.entryid not in (SELECT entryid FROM #tempDDID) AND d.entryid is null  



/* CardHolders */
IF OBJECT_ID('tempdb..#currentCH') IS NOT NULL DROP TABLE #currentCH;

SELECT Ssn_Number INTO #currentCH FROM Prepaid.dbo.Cardholders;

CREATE CLUSTERED INDEX IDX_Id ON #currentCH(ssn_number);

PRINT 'Loading CardHolders...';

/* Preserve any previous copies of Qualifying Cardholders */

SET @newTable = 'Cardholders_COPY_' + CONVERT(varchar(20), getdate(), 120);
IF OBJECT_ID('ADHOC.ConversionShared.Cardholders_COPY') IS NOT NULL EXEC ADHOC.sys.sp_rename 'ADHOC.ConversionShared.Cardholders_COPY', @newTable;

/* Make new "current" copy of Qualifying Cardholders */
IF OBJECT_ID('ADHOC.ConversionShared.Cardholders') IS NOT NULL SELECT * INTO ADHOC.ConversionShared.Cardholders_COPY FROM ADHOC.ConversionShared.Cardholders



/* let diff */
SET IDENTITY_INSERT ADHOC.dbo.CardHolders  ON;
/* CardHolders are diffed by the abscense of providerkey in the current prepaid cardholder table*/
INSERT INTO ADHOC.dbo.CardHolders WITH (TABLOCK) ( Id, Created, Modified, IsBlocked, Ssn_Number, Name_First, Name_Last, DateOfBirth ) 
SELECT 
	   CONVERT(bigint, mch.providerkey) AS 'Id',
	   ADHOC.dbo.ToUtcTime(mch.created) AS 'Created', 
       ADHOC.dbo.ToUtcTime(mch.LastUpdateDate) AS 'Modified',  
	   0 AS 'IsBlocked',
	   CONVERT(nvarchar(16), mch.ssn) AS 'Ssn_Number',
	   CONVERT(nvarchar(32), mch.firstname) AS 'Name_First',
	   CONVERT(nvarchar(32), mch.lastname) AS 'Name_Last',
	   COALESCE(TRY_CONVERT(datetime, try_convert(varchar, ma.year)+'-'+try_convert(varchar, ma.month)+'-'+try_convert(varchar,ma.day)), mch.dob) AS 'DateOfBirth'
FROM ADHOC.ConversionShared.QualifyingAccountsRanked AS mch 
--LEFT JOIN #currentCH as cch ON cch.ssn_number = mch.ssn
OUTER APPLY (SELECT TOP 1 [year], [month], [day] FROM UniMaster.UNISCREEN.TblMasterApplications WHERE clientkey = mch.clientkey AND [status] = 7 ORDER BY submitted DESC) AS ma
WHERE mch.ContactRank = 1 AND cch.Ssn_Number is null

--drop table #currentCH;
SET IDENTITY_INSERT ADHOC.dbo.CardHolders  OFF;

/* drop the current qualifying cardholders table */
IF OBJECT_ID('ADHOC.ConversionShared.Cardholders') IS NOT NULL DROP TABLE ADHOC.ConversionShared.Cardholders;
SELECT pc.* INTO ADHOC.ConversionShared.Cardholders FROM Prepaid.dbo.CardHolders AS pc



/* Set diffdate for account related queries */
--SET NOCOUNT ON;
--DECLARE @diffDate as datetime;

SET @diffDate = (SELECT ADHOC.dbo.ToLocalTime(MAX(Modified)) FROM Prepid.dbo.Accounts);
IF @diffDate is null SET @diffDate = '1900-01-01'; 

PRINT 'diffDate ' + CONVERT(varchar, @diffdate);

PRINT 'Deleteing updateable Accounts...';

/* Delete accounts to be updated */

DELETE FROM Prepaid.dbo.Accounts WHERE Id in 
(
	SELECT entryid FROM TblMasterCardholders WHERE LastUpdateDate > @diffDate
)


PRINT 'Loading Accounts...';

/* Accounts */
SET IDENTITY_INSERT ADHOC.dbo.Accounts  ON;
INSERT INTO ADHOC.dbo.Accounts WITH (TABLOCK) 
( Id, Created, Modified, Status, ActivationDate, DepositNumber, [Type_Id], AccountBalance_Id, ApplicationId, IsFraud, StatusChangeReason, LimitPackage) 

SELECT 
mch.entryid AS 'Id', 
ADHOC.dbo.ToUtcTime(mch.CreateDate) AS 'Created',
ADHOC.dbo.ToUtcTime(mch.LastUpdateDate) AS 'Modified',
CASE WHEN mch.accountstatus = 6 THEN 40 ELSE 10 END AS 'Status',
ADHOC.dbo.ToUtcTime(mch.activateddate) AS 'ActivationDate',
CONVERT(nvarchar(16), LEFT(d.FullDepositID, 16)) AS 'DepositNumber',

CASE 
WHEN fpc.FeePlanID = 1 OR fpc.FeePlanID = 5 THEN 1 --PAYGO
WHEN fpc.FeePlanID = 9 OR fpc.FeePlanID = 2 OR fpc.FeePlanID = 6 THEN 2 --Unlimited
WHEN fpc.FeePlanID = 7 THEN 3 --Goal
WHEN fpc.FeePlanID = 3 THEN 4  --VIP
ELSE 1
END AS 'Type_Id',

mch.entryid AS 'AccountBalance_Id',
ma.applicationid AS 'ApplicationId',
0 AS 'IsFraud',

CASE WHEN mch.accountstatus = 6 THEN 44 ELSE 10 END AS 'StatusChangeReason', 

1 AS 'LimitPackage_Id'

  FROM ADHOC.ConversionShared.QualifyingAccountsRanked AS mch
  LEFT JOIN UniMaster.pyp.TblFeePlanChanges AS fpc ON fpc.FeePlanChangeID = mch.LastFeePlanChangeID
  LEFT JOIN ADHOC.ConversionShared.DDID_Lookup AS d ON d.Entryid = mch.entryid 
  OUTER APPLY (SELECT TOP 1 applicationid FROM UniMaster.UNISCREEN.TblMasterApplications WHERE clientkey = mch.clientkey ORDER BY applicationid DESC) AS ma
  WHERE mch.LastUpdateDate > @diffDate
 
  
SET IDENTITY_INSERT ADHOC.dbo.Accounts  OFF;


  /* Delete balances to be updated */
PRINT 'Deleting Updateable Balances...';
--DECLARE @diffDate as datetime='1900-01-01';
DECLARE @tranDiffDate as datetime =  (SELECT ADHOC.dbo.ToLocalTime(MAX(EffectiveDate)) FROM Prepaid.dbo.AccountBalances);
IF @tranDiffDate is null SET @diffDate = '1900-01-01'; 

DELETE ab FROM ADHOC.dbo.AccountBalances ab
JOIN ADHOC.ConversionShared.QualifyingAccountsRanked AS mch ON mch.entryid = ab.Id
JOIN Transactions.dbo.TblAccountBalances AS tb ON tb.UserAccountID = mch.provideraccountID 
WHERE tb.Transactiontime > @tranDiffDate;


/* Account Balances */


PRINT 'tranDiffDate ' + CONVERT(varchar, @tranDiffdate);
PRINT 'Loading Blanaces...';

IF OBJECT_ID('tempdb..#Balances') is null 
	BEGIN
		CREATE TABLE #balances (
			Id bigint not null,
			Created datetime NOT NULL,
			Modified datetime NOT NULL,
			AvailableBalance decimal(18,2) NOT NULL,
			LedgerBalance decimal (18,2) NOT NULL,
			EffectiveDate datetime NOT NULL	
		)
	END
ELSE 
	BEGIN 
		TRUNCATE TABLE #balances
	END

INSERT INTO #balances

SELECT a.id,
		ADHOC.dbo.ToUtcTime(ab.CreateDate) AS 'Created',
       ADHOC.dbo.ToUtcTime(ab.LastUpdateDate) AS 'Modified',
	   UserAvailableBalance * .01 AS 'AvailableBalance',
	   UserLedgerBalance * .01 AS 'LedgerBalance',	   
	   ADHOC.dbo.ToUtcTime(TransactionTime) AS 'EffectiveDate'
 FROM ADHOC.dbo.Accounts AS a 
	   JOIN ADHOC.[ConversionShared].[QualifyingAccountsRanked] AS mch ON mch.entryid = a.id
	   LEFT JOIN Transactions.dbo.TblAccountBalances AS ab ON ab.UserAccountID = mch.provideraccountID
	   WHERE ab.TransactionID is not null AND ab.TransactionTime > @tranDiffDate

INSERT INTO #balances 
	SELECT 
		a.id,
	   getutcdate(),
       getutcdate(),
	   0.00,
	   0.00,	   
	   getutcdate()
	   FROM ADHOC.dbo.Accounts AS a 
	   JOIN ADHOC.[ConversionShared].[QualifyingAccountsRanked] AS mch ON mch.entryid = a.id
	   LEFT JOIN Transactions.dbo.TblAccountBalances AS ab ON ab.UserAccountID = mch.provideraccountID
	   WHERE ab.TransactionID is null

SET IDENTITY_INSERT ADHOC.dbo.AccountBalances  ON;

INSERT INTO ADHOC.dbo.AccountBalances WITH (TABLOCK) ( Id, Created, Modified, AvailableBalance, LedgerBalance, EffectiveDate )
SELECT Id, Created, Modified, AvailableBalance, LedgerBalance, EffectiveDate FROM #balances
SET IDENTITY_INSERT ADHOC.dbo.AccountBalances  OFF;

DROP TABLE #balances


PRINT 'Loading AccountCardHolders...';
/* Account to CardHolder mapping */

IF OBJECT_ID('tempdb..#AccountCardholders ') is not null DROP TABLE #AccountCardholders;
SELECT * INTO #AccountCardholders 
FROM Prepaid.dbo.AccountCardHolders



INSERT INTO ADHOC.dbo.AccountCardholders WITH (TABLOCK) (Account_id, Cardholder_id)
SELECT acct.id, ch.Id 
FROM ADHOC.dbo.Accounts AS acct 
LEFT JOIN #AccountCardholders AS ach ON ach.Account_Id = acct.Id
JOIN ADHOC.ConversionShared.QualifyingAccounts AS mch ON mch.entryid = acct.id
JOIN ADHOC.dbo.Cardholders as ch ON ch.ssn_number = mch.ssn
WHERE ach.Account_Id is null

DROP TABLE #AccountCardholders




/* Delete contact info for CardHolder that is to be updated */

PRINT 'Deleteing updateable CardHolder contact info....';

IF OBJECT_ID('tempdb..#chInfo') is not null DROP TABLE #chInfo;


SELECT ch.Id INTO #chInfo  
FROM PrePaid.dbo.CardHolders AS ch
JOIN ADHOC.ConversionShared.QualifyingAccountsRanked AS mch ON mch.ssn = ch.Ssn_Number AND mch.ContactRank = 1
WHERE mch.LastUpdateDate > @diffDate


DELETE addresses FROM ADHOC.dbo.Addresses as addresses 
JOIN #chInfo as ch ON ch.id = addresses.CardHolder_Id

DELETE emails FROM ADHOC.dbo.emails as emails 
JOIN #chInfo as ch ON ch.id = emails.CardHolder_Id

DELETE phones FROM ADHOC.dbo.Phones as phones 
JOIN #chInfo as ch ON ch.id = phones.CardHolder_Id



PRINT 'Loading Addresses....';
/* CardHolder Addresses */


INSERT INTO ADHOC.dbo.Addresses WITH (TABLOCK) ( Created, Modified, Type, Address1, Address2, Address3, City, State, PostalCode, Country, Program_Id, CardHolder_Id )
SELECT 

mch.entryid AS 'id',
ADHOC.dbo.ToUtcTime(mch.CreateDate) AS 'Created', 
ADHOC.dbo.ToUtcTime(mch.LastUpdateDate) AS 'Modified', 
1 AS 'Type', 
CONVERT(nvarchar(40), mch.address1) AS 'Address1', 
CONVERT(nvarchar(40), mch.address2) AS 'Address2', 
CONVERT(nvarchar(40), mch.address3) AS 'Address3',
CONVERT(nvarchar(25), LEFT(mch.city, 25)) AS 'City',
COALESCE(s.id, 999) AS 'State', 
CONVERT(nvarchar(9), LEFT(REPLACE(mch.zip, '-',''), 9)) AS 'PostalCode',
0 AS 'Country',  
1 AS 'Program_Id',
ch.Id AS 'CardHolder_Id'

FROM PrePaid.dbo.CardHolders AS ch
JOIN ADHOC.ConversionShared.QualifyingAccountsRanked AS mch ON mch.ssn = ch.Ssn_Number AND mch.ContactRank = 1
LEFT JOIN Prepaid.dbo.States AS s ON s.value = mch.state
WHERE mch.LastUpdateDate > @diffDate



/* CardHolder Emails */

PRINT 'Loading Emails...';

INSERT INTO ADHOC.dbo.Emails WITH (TABLOCK) ( Created, Modified, [Address], [Type], CardHolder_Id )
SELECT 
mch.entryid AS 'id',
ADHOC.dbo.ToUtcTime(mch.CreateDate) AS 'Created', 
ADHOC.dbo.ToUtcTime(mch.LastUpdateDate) AS 'Modified', 
CONVERT(nvarchar(120), mch.email) AS 'Address', 
1 AS 'Type',
ch.Id AS 'CardHolder_Id'

FROM PrePaid.dbo.CardHolders AS ch
JOIN ADHOC.dbo.QualifyingAccountsRanked AS mch ON mch.ssn = ch.Ssn_Number AND mch.ContactRank = 1
WHERE mch.email is not null and mch.email <> ''
AND mch.LastUpdateDate > @diffDate



/* CardHolder Phones */

PRINT 'Loading Phones...';

INSERT INTO ADHOC.dbo.Phones WITH (TABLOCK) ( Created, Modified, [Type], Digits, CardHolder_Id )
SELECT 
mch.entryid AS 'id',
ADHOC.dbo.ToUtcTime(mch.CreateDate) AS 'Created', 
ADHOC.dbo.ToUtcTime(mch.LastUpdateDate) 'Modified', 
1 AS 'Type', 
CONVERT(nvarchar(16), LEFT(mch.telephone, 16)) AS 'Digits', 
ch.Id AS 'CardHolder_Id'

FROM PrePaid.dbo.CardHolders AS ch
JOIN ADHOC.dbo.QualifyingAccountsRanked AS mch ON mch.ssn = ch.Ssn_Number AND mch.ContactRank = 1
WHERE mch.telephone is not null and mch.telephone <> ''
AND mch.LastUpdateDate > @diffDate

UNION ALL

SELECT 
mch.entryid AS 'id',
ADHOC.dbo.ToUtcTime(mch.CreateDate) AS 'Created', 
ADHOC.dbo.ToUtcTime(mch.LastUpdateDate) AS 'Modified', 
2 AS 'Type', 
CONVERT(nvarchar(16), LEFT(mch.celltel, 16)) AS 'Digits', 
ch.Id AS 'CardHolder_Id'

FROM PrePaid.dbo.CardHolders AS ch
JOIN ADHOC.dbo.QualifyingAccountsRanked AS mch ON mch.ssn = ch.Ssn_Number AND mch.ContactRank = 1
WHERE mch.celltel is not null and mch.celltel <> ''
AND mch.LastUpdateDate > @diffDate


PRINT 'Deleteing updateable Cards...'
/* Delete cards to be updated */
--DECLARE @diffDate as datetime='1900-01-01';
SET @diffDate = (SELECT ADHOC.dbo.ToLocalTime(MAX(Modified)) FROM Prepaid.dbo.Cards);
IF @diffDate is null SET @diffDate = '1900-01-01'; 

DELETE cards from ADHOC.dbo.Cards AS cards
JOIN TblCards AS c ON c.cardid = cards.Id 
WHERE c.LastUpdateDate > @diffDate

/* Cards */
PRINT 'Loading Cards...';

SET IDENTITY_INSERT ADHOC.dbo.Cards  ON;

INSERT INTO ADHOC.dbo.Cards WITH (TABLOCK) ( Id, Created, Modified, IssueDate, IsPinSet, NameOnCard, CardExpiration_Month, CardExpiration_Year, Status, IssueReason, CardStock_Id, Account_Id, CardHolder_Id, StatusReason, CardNumber_Id, WhenEligibleForFreeReplacementCard, CardCreationHistory_Id )
SELECT 
  c.cardid AS 'Id',
  ADHOC.dbo.ToUtcTime(c.CreateDate) AS 'Created',
  ADHOC.dbo.ToUtcTime(c.LastUpdateDate) AS  'Modified',
  ADHOC.dbo.ToUtcTime(c.IssueDate) AS 'IssueDate',
  CASE WHEN ps.cardid is not null THEN 1 ELSE 0 END AS 'IsPinSet',
  CONVERT(nvarchar(26), LEFT(c.nameoncard, 26)) AS 'NameOnCard',
  c.expmonth AS 'CardExpiration_Month',
  c.expyear AS 'CardExpiration_Year',
  
  CASE --Card Status
  WHEN (c.cardstatus = 1 OR c.cardstatus = 0) AND mch.ActiveCardID = c.cardid THEN 10 --active
  WHEN c.cardstatus = 2 THEN 20  --inactive
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 7 THEN 50 --possible fraud
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 2 THEN 40 --hold possible compromise
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 8 THEN 40 --hold lost, could be found and un-blocked
  WHEN c.cardstatus = 4 THEN 30
  WHEN c.cardstatus = 5 THEN 30  --blocked, replaced
  ELSE 30 END AS 'Status',  
  
  CASE  --Issuance Reason 
  WHEN c.IssuanceState = 1 THEN 1 
  WHEN c.IssuanceState = 3 THEN 2 
  WHEN ISNULL(h.BlockReasonId, 0) = 2 THEN 8
  WHEN ISNULL(h.BlockReasonId, 0) = 8 THEN 6
  WHEN ISNULL(h.BlockReasonId, 0) = 14 THEN 7
  WHEN ISNULL(h.BlockReasonId, 0) = 1 THEN 5
  WHEN c.IssuanceState = 2 THEN 2 --inactive
  WHEN c.IssuanceState = 0 THEN 2 --inactive
  ELSE 6
  END AS 'IssueReason',
  cm.PlasticTypeID AS 'CardStock_Id',  

  ac.Account_Id AS 'Account_Id',
  ac.Cardholder_ID 'CardHolder_Id',
  
  CASE  --Status Change Reason 
  WHEN c.cardstatus = 1 OR c.cardstatus = 0 THEN 10 --active
  WHEN c.cardstatus = 2 THEN 20 --inactive 
  WHEN c.cardstatus = 4 THEN 34 --closed
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 8 THEN 30  --lost
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 14 THEN 80 --stolen
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 7 THEN 100 --possible fraud investigation
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 9 THEN 43 --negative balance
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 2 THEN 90 --possible compromise
  WHEN c.cardstatus = 3 AND ISNULL(h.BlockReasonId, 0) = 4 THEN 34 --closed account
  WHEN c.cardstatus = 3 THEN 30 --closed account
  ELSE 20
  END AS 'StatusReason',

  c.cardid AS 'CardNumber_Id',

  DATEADD(year, 1, ADHOC.dbo.ToUtcTime(c.created))  AS 'WhenEligibleForFreeReplacementCard',

  NULL AS 'CardCreationHistory_Id'
  
  FROM ADHOC.ConversionShared.QualifyingAccountsRanked AS mch
  LEFT JOIN ADHOC.[dbo].[LegacyAccountCardholdersTemp] AS ac ON ac.Account_ID = mch.entryid
  JOIN TblCards AS c ON c.cardholderid = ac.Account_Id
  JOIN TblCardMaterials AS cm ON cm.MaterialID = c.MaterialID
  JOIN UniMaster.PYP.TblPlasticTypes AS pt ON pt.PlasticTypeID = cm.PlasticTypeId
  JOIN UniMaster.PYP.TblFeePlanChanges AS fpc ON fpc.FeePlanChangeId = mch.LastFeePlanChangeID
  OUTER APPLY (SELECT TOP 1 cardid FROM [TblCardPinSet] WHERE cardid = c.cardid ORDER BY asofdate DESC) AS ps
  OUTER APPLY (SELECT TOP 1 blockreasonid FROM [TblCardStatusHistory] WHERE cardid = c.cardid ORDER BY changeddate DESC) AS h
  WHERE c.LastUpdateDate > @diffDate

  SET IDENTITY_INSERT ADHOC.dbo.Cards  OFF;


  /* Card Numbers */
TRUNCATE TABLE Prepaid.dbo.CardNumbers 

  SET IDENTITY_INSERT Prepaid.[dbo].[CardNumbers] ON;

INSERT INTO Prepaid.[dbo].[CardNumbers] WITH (TABLOCK) ( Id, Modified, Created, Number )
SELECT
c.cardid AS 'Id',
/*ToUtcTime is a C#/.NET CLR User Defined function that I wrote/deployed to SQL Server to accurately convert EST to UTC accounting for daylight savings time shifts */
ADHOC.dbo.ToUtcTime(c.LastUpdateDate) AS  'Modified',
ADHOC.dbo.ToUtcTime(c.CreateDate) AS 'Created',
CASE 
	WHEN cn.PAN is not null THEN LEFT(cn.PAN, 16) 
	WHEN cn.PAN is null THEN '410489XXXXXXXXXX'
END AS 'Number'
FROM ADHOC.dbo.LegacyAccountCardholdersTemp AS ac 
JOIN TblCards AS c ON c.cardholderid = a.id
LEFT JOIN ADHOC.[CAMS].[PansAndPinOffsets] AS cn ON cn.externalcardid = c.externalcardid

SET IDENTITY_INSERT Prepaid.[dbo].[CardNumbers]  OFF;

SET @diffDate = (SELECT ADHOC.dbo.ToLocalTime(MAX(Modified)) FROM Prepaid.dbo.CardCreationHistories);
IF @diffDate is null SET @diffDate = '1900-01-01'; 

IF OBJECT_ID('tempdb..#reqHist') is not null DROP TABLE #reqHist
SELECT ID INTO #reqHist FROM Prepaid.dbo.CardCreationHistories

SET IDENTITY_INSERT ADHOC.dbo.CardCreationHistories ON;
INSERT INTO ADHOC.dbo.CardCreationHistories WITH (tablock)
(Id, Address1, Address2, Address3, City, State, PostalCode, Country, DeliverType, Created, Modified)

SELECT cr.CardRequestID AS 'Id'
      ,CONVERT(nvarchar(40), LEFT(mch.address1, 40)) AS 'Address1'
      ,CASE WHEN RTRIM(LEFT(mch.address2, 40)) = '' THEN NULL ELSE CONVERT(nvarchar(40), LEFT(mch.address2, 40)) END AS 'Address2' 
      ,CASE WHEN RTRIM(LEFT(mch.address3, 40)) = '' THEN NULL ELSE CONVERT(nvarchar(40), LEFT(mch.address3, 40)) END AS 'Address3'
      ,CONVERT(nvarchar(25),LEFT(mch.city, 25)) AS 'city' 
      ,COALESCE(s.id, 999) AS 'State'
      ,CONVERT(nvarchar(9), LEFT(mch.zip, 5)) AS 'PostalCode'
      ,0 AS 'Country'
      ,
	  CASE 
		WHEN cr.DeliveryTypeID = 1 THEN 'Standard'
		WHEN cr.DeliveryTypeID = 2 THEN 'Expedited'
	    ELSE 'UNKNOWN'
	  END AS 'DeliverType'
      ,ADHOC.dbo.ToUtcTime(cr.CreateDate) AS 'Created'
      ,ADHOC.dbo.ToUtcTime(cr.LastUpdateDate) AS 'Modified'
  FROM UniMaster.[PYP].[TblCardRequests] cr
  LEFT JOIN ADHOC.dbo.CardRequestHistoriesTemp AS rh ON rh.id = cr.CardRequestID 
  JOIN TblMasterCardHolders AS mch ON mch.entryid = cr.EntryID
  JOIN ADHOC.dbo.LegacyAccountCardholdersTemp AS ach ON ach.Account_Id = mch.entryid
  LEFT JOIN ADHOC.dbo.States AS s ON s.value = mch.state
  WHERE rh.Id is null
SET IDENTITY_INSERT ADHOC.dbo.CardCreationHistories OFF;

/* Capture accounts to exclude becasue they do not have a PAN for their ActiveCardID */
IF OBJECT_ID('ADHOC.CAMS.AccountsWithoutPAN') is not null DROP TABLE ADHOC.CAMS.AccountsWithoutPAN; 
SELECT qa.* INTO ADHOC.CAMS.AccountsWithoutPAN FROM ADHOC.[ConversionShared].[QualifyingAccountsRanked] AS qa
LEFT JOIN TblCards AS c ON c.cardid = qa.ActiveCardID
LEFT JOIN ADHOC.[CAMS].[PansAndPinOffsets] AS pan ON pan.externalcardid = c.externalcardid
WHERE pan.PAN is null

/* Capture cardholders to exclude because the ranked account does not have a PAN */
IF OBJECT_ID('ADHOC.CAMS.CardholdersWithoutPAN') is not null DROP TABLE ADHOC.CAMS.CardholdersWithoutPAN;
SELECT DISTINCT ch.* INTO ADHOC.CAMS.CardholdersWithoutPAN FROM ADHOC.[ConversionShared].[Cardholders] AS ch
JOIN ADHOC.CAMS.AccountsWithoutPAN AS awp ON awp.providerkey = ch.id
LEFT JOIN ADHOC.[ConversionShared].[QualifyingAccountsRanked] AS qa ON qa.ssn = ch.Ssn_Number

/* Capture all of the other accounts that belong to an exluded cardholder */
INSERT INTO ADHOC.CAMS.AccountsWithoutPAN
SELECT qa.* FROM  ADHOC.[ConversionShared].[QualifyingAccountsRanked] AS qa
JOIN ADHOC.CAMS.CardholdersWithoutPAN AS chwp ON chwp.Ssn_Number = qa.ssn 
LEFT JOIN ADHOC.CAMS.AccountsWithoutPAN AS awp ON awp.entryid = qa.entryid
WHERE awp.entryid is null


PRINT 'Load Comnplete!'

