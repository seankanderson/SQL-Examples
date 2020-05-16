


/* Delete multiples for an entryid that have never been used...leaving one ddid per entryid */
DELETE x FROM TblDepositIDNumbers AS x 
JOIN (
SELECT 
ddid.Entryid, 
ddid.FullDepositID, 
ddid.EncryptedDepositID, 
used.DDID_Used,
ddid.createdate, 
DENSE_RANK() OVER (Partition by ddid.entryid order by used.ddid_used DESC) AS UseRank,
DENSE_RANK() OVER (Partition by ddid.entryid order by ddid.FullDepositID DESC ) AS DDIDRank
FROM TblDepositIDNumbers AS ddid
JOIN --get those with multiple ddid
( 
	SELECT did.Entryid  FROM TblMasterCardHolders AS mch
	JOIN TblDepositIDNumbers AS did ON did.Entryid = mch.entryid
	GROUP BY did.entryid 
	HAVING COUNT(*) > 1
) AS multiples ON multiples.Entryid = ddid.Entryid
OUTER APPLY  --count how many times ddid has been used for each entryid
(
	SELECT COUNT(*) AS 'DDID_Used' FROM TblDirectDepositDetailRecord WHERE ddid.EncryptedDepositID = dfiaccountno GROUP BY dfiaccountno
) as used
) as ddid ON ddid.Entryid = x.Entryid
WHERE ddid.DDID_Used is null AND ddid.DDIDRank > 1  --some have more than two DDID and more than one unused DDID, this query gets us down to one NULL or two unused/used DDID



/* Delete doubles that are used less or null */ 

DELETE x FROM TblDepositIDNumbers AS x 
JOIN (
SELECT 
ddid.Entryid, 
ddid.FullDepositID, 
ddid.EncryptedDepositID, 
used.DDID_Used,
ddid.createdate, 
DENSE_RANK() OVER (Partition by ddid.entryid order by used.ddid_used DESC) AS UseRank,
DENSE_RANK() OVER (Partition by ddid.entryid order by ddid.FullDepositID DESC ) AS DDIDRank
FROM TblDepositIDNumbers AS ddid
JOIN --get those with multiple ddid
( 
	SELECT did.Entryid  FROM TblMasterCardHolders AS mch
	JOIN TblDepositIDNumbers AS did ON did.Entryid = mch.entryid
	GROUP BY did.entryid 
	HAVING COUNT(*) > 1
) AS multiples ON multiples.Entryid = ddid.Entryid
OUTER APPLY  --count how many times as ddid has been used for each entryid
(
	SELECT COUNT(*) AS 'DDID_Used' FROM TblDirectDepositDetailRecord WHERE ddid.EncryptedDepositID = dfiaccountno GROUP BY dfiaccountno
) as used
) as ddid ON ddid.Entryid = x.Entryid
WHERE ddid.UseRank > 1 OR (ddid.UseRank = 1 AND ddid.DDIDRank > 1)



