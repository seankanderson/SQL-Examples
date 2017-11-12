
-- Takes email data obtained from SendGrid and dynamically creates a category column 
-- for each row from category text in a single column of the original data and marks each 
-- row for all of the columns to which that row belongs.  

-- Accounts for all of the custom category data used in emails created by users of the SendGrid 
-- platform but does not handle new categories.  If new categories are added then the entire dataset 
-- must be updated.  

USE SendGrid;


IF OBJECT_ID('tempdb..#temp') is not null drop table #temp
 


SELECT e.id, e.Event, e.Email, e.DealerCode, e.EventDate, e.Status, e.Response, e.Reason, e.Attempt, e.Cert_Err, e.TLS, c.Category
into #temp
  FROM [SendGrid].[dbo].[Events] AS e
  join SendGrid.[dbo].[EventCategories] AS ec on ec.event_id = e.id
  join SendGrid.[dbo].[Categories] as c on c.id = ec.category_id
  --LEFT JOIN SendGrid.[dbo].[FlattenedEvents] as fe ON fe.id = e.id
  --WHERE fe.id is null
  
  CREATE CLUSTERED INDEX idx_t ON #temp (id)

  

 DECLARE @cols AS NVARCHAR(MAX)
 DECLARE @query  AS NVARCHAR(MAX)

 IF OBJECT_ID('tempdb..##cats') IS NOT NULL DROP TABLE ##cats;

-- create a column list (dynamic) of all categories found in the original rows queried above  
SET @cols = STUFF((SELECT ','+ QUOTENAME(Category) 
                    from #temp
                    group by Category  --crush out the duplicate rows
                    order by Category
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)') 
        ,1,1,'')


	
-- Use dynamic SQL to create a pivot table from the dynamically generated column names associated to each category.
-- Notice the use of COUNT(Category) that marks a number 1 in each column for the particular category each row belongs to.
-- All these gymnastics serve to take single rows belonging to multiple categories and make it easy for a 
-- visualization tool to deal with.  The users now have an easy way to filter data without accidentally getting 
-- bad numbers from duplicate rows or erroneous aggregation.
SET @query = 'SELECT id,' + @cols + 'INTO ##cats from 
             (
                SELECT id, Event, Email, DealerCode, EventDate, Status, Response, Reason, Attempt, Cert_Err, TLS, Category
                from #temp
            ) x
            pivot 
            (
                COUNT(Category)
                for Category in (' + @cols + ')
            ) p';


	
IF (@query  IS NOT NULL)


-- Run everything to produce the consumable data model!
BEGIN 
    execute(@query)

    CREATE CLUSTERED INDEX idx_c ON ##cats (id)

    INSERT INTO SendGrid.dbo.FlattenedEvents
    SELECT Event, Email, DealerCode, EventDate, Status, Response, Reason, Attempt, Cert_Err, TLS, c.* 
    FROM #temp as t 
    JOIN ##cats AS c on c.id = t.id

END
