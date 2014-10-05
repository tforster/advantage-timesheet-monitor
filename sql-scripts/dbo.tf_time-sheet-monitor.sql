DECLARE @DateToCheck VARCHAR(25)
DECLARE @HoursThreshold INT
DECLARE @Id BIGINT
DECLARE @MaxId BIGINT
DECLARE @Query NVARCHAR(1024)
DECLARE @EMP_EMAIL VARCHAR(50)
DECLARE @SUBJECT NVARCHAR(256)
DECLARE @BODY NVARCHAR(MAX)
DECLARE @EMP_TOTAL_HRS DECIMAL
DECLARE @EMP_DATE DATETIME
DECLARE @EMP_FULLNAME VARCHAR(61)

-- Calculate "yesterday" based on current system time. Assumption: This is run once every 24 hours.
SET @DateToCheck =  LEFT(CONVERT(VARCHAR, CONVERT(date, DATEADD(day,-1,SYSDATETIME())), 120), 10)+ ' 00:00:00.000'

/*** Editable parameters start ***/
SET @HoursThreshold = 6.5						-- Flag timesheets that are less than this value
SET @SUBJECT = 'Timesheets!'					-- Email subject
SET @DateToCheck = '2014-07-01 00:00:00.000'    -- Testing override. Remove this line in production!
/*** Editable parameters end ***/

/******************************************************************************
 * Calculate the range of EMP_TIME Ids (ET_ID) to process.
 *****************************************************************************/
SELECT 
	@Id=MIN([ET_ID]), @MaxId=MAX([ET_ID])
FROM 
	[TRAINING].[dbo].[EMPLOYEE_CLOAK]  
FULL OUTER JOIN 
	[TRAINING].[dbo].[EMP_TIME]
ON 
	[TRAINING].[dbo].[EMP_TIME].[EMP_CODE] = [TRAINING].[dbo].[EMPLOYEE_CLOAK].[EMP_CODE]  
WHERE 
	[TRAINING].[dbo].[EMP_TIME].[EMP_DATE] > @DateToCheck
	AND [TRAINING].[dbo].[EMP_TIME].[FREELANCE] <> 1
	AND [EMP_TOT_HRS] < @HoursThreshold
	-- Testing override. Remove this line in production!
	AND [TRAINING].[dbo].[EMPLOYEE_CLOAK].[EMP_FNAME] = 'Ola';

/******************************************************************************
 * Iterate from minimum EMP_TIME Id (@Id) to maximum EMP_TIME Id (@MaxId). Note
 * that we add 1 to @MaxId otherwise if there is only one record then 
 * @Id = @MaxId and the loop does not execute.
 *****************************************************************************/
WHILE @Id < @MaxId + 1 BEGIN
	-- Select necessary fields for @Id
	SELECT
		@EMP_EMAIL = [EMP_EMAIL],
		@EMP_TOTAL_HRS = [EMP_TOT_HRS], 
		@EMP_DATE = [TRAINING].[dbo].[EMP_TIME].[EMP_DATE],		
		@BODY = [EMP_FNAME] + ' ' + [EMP_LNAME] + ' you have only logged ' + CAST([EMP_TOT_HRS] AS NVARCHAR(10)) + ' hours for ' + CAST(@EMP_DATE AS NVARCHAR(20)) + '. Please update your timesheet.'
	FROM 
		[TRAINING].[dbo].[EMPLOYEE_CLOAK]
	FULL OUTER JOIN 
		[TRAINING].[dbo].[EMP_TIME]
	ON 
		[TRAINING].[dbo].[EMP_TIME].[EMP_CODE] = [TRAINING].[dbo].[EMPLOYEE_CLOAK].[EMP_CODE]  
	WHERE 
		[ET_ID] = @Id
	
	-- Construct the parameters and execute the email sproc
	EXEC msdb.dbo.sp_send_dbmail 
		@profile_name = 'TimeSheetProfile',
		@recipients = 'troy.forster@gmail.com',
		--@recipients = @EMP_EMAIL,
		@subject = @SUBJECT,
		@body =  @BODY

	-- Select the next sequential available ET_ID.
	SELECT 
		@Id=MIN([ET_ID]) 
	FROM 
		[TRAINING].[dbo].[EMPLOYEE_CLOAK]  
	FULL OUTER JOIN 
		[TRAINING].[dbo].[EMP_TIME]
	ON 
		[TRAINING].[dbo].[EMP_TIME].[EMP_CODE] = [TRAINING].[dbo].[EMPLOYEE_CLOAK].[EMP_CODE]  
	WHERE 
		[TRAINING].[dbo].[EMP_TIME].[EMP_DATE] > @DateToCheck
		AND [TRAINING].[dbo].[EMP_TIME].[FREELANCE] <> 1
		AND [EMP_TOT_HRS] < @HoursThreshold
		AND [ET_ID]> @Id
		-- Testing override. Remove this line in production!
		AND [TRAINING].[dbo].[EMPLOYEE_CLOAK].[EMP_FNAME] = 'Ola'
END