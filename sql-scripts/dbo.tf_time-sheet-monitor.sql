USE TRAINING
DECLARE @LoDateToCheck VARCHAR(25)
DECLARE @HiDateToCheck VARCHAR(25)
DECLARE @HoursThreshold INT
DECLARE @MessageSubject NVARCHAR(256)
DECLARE @MessageBody NVARCHAR(MAX)
DECLARE @CurrentEmployeeEMail VARCHAR(50)
DECLARE @EntryId BIGINT
DECLARE @EmployeeName VARCHAR(61)
DECLARE @EmployeeEmail VARCHAR(50)
DECLARE @EntryHours DECIMAL
DECLARE @EntryDate DATETIME
DECLARE @DisplayDate VARCHAR(20)
DECLARE @CR VARCHAR(1)
DECLARE @CR2 VARCHAR(2)
DECLARE @Greeting VARCHAR(128)
DECLARE @Salutation VARCHAR(128)

-- Helper variables for constructing the message
SET @CR = CHAR(13)
SET @CR2 = CHAR(13) + CHAR(13)

-- Ensure the DATEFIRST system parameter is set U.S. English default value of 7 or 'Sunday'.
SET DATEFIRST 7;

-- Calculate low and high dates as yesterday and a week yesterday based on current system time.
SET @LoDateToCheck = LEFT(CONVERT(VARCHAR, CONVERT(date, DATEADD(day,-7,SYSDATETIME())), 120), 10)+ ' 00:00:00.000'
SET @HiDateToCheck = LEFT(CONVERT(VARCHAR, CONVERT(date, DATEADD(day,-1,SYSDATETIME())), 120), 10)+ ' 00:00:00.000'
SET @CurrentEmployeeEMail = ''

/*** Editable parameters start ***/
SET @HoursThreshold = 6.5							-- Flag timesheets that are less than this value
SET @MessageSubject = 'Timesheets!'					
SET @Greeting = 'Thank you for completing your time sheets, but you still have time missing for the following days:'
SET @Salutation = 'Thank you,' + @CR2 + 'The Finance Department'
SET @LoDateToCheck = '2014-06-24 00:00:00.000'		-- Testing override. Remove this line in production!
SET @HiDateToCheck = '2014-07-01 00:00:00.000'		-- Testing override. Remove this line in production!
/*** Editable parameters end ***/

-- Prepare a temporary table by removing any previous one
IF OBJECT_ID('tempdb..#TimeSheetTemp') IS NOT NULL DROP TABLE #TimeSheetTemp

-- Select all offending entries into a temporary table
SELECT
	ET_ID AS EntryId,
	EMP_EMAIL AS EmployeeEmail,
	EMP_FNAME + ' ' + EMP_LNAME AS EmployeeName,
	EMP_TOT_HRS AS EntryHours, 
	EMP_TIME.EMP_DATE AS EntryDate
INTO #TimeSheetTemp		
FROM 
	EMPLOYEE_CLOAK
FULL OUTER JOIN 
	EMP_TIME
ON 
	EMP_TIME.EMP_CODE = EMPLOYEE_CLOAK.EMP_CODE
WHERE 
	EMP_TIME.EMP_DATE >= @LoDateToCheck
	AND EMP_TIME.EMP_DATE <= @HiDateToCheck
	-- Uncomment the following two lines in production to enable weekend checking 
	--AND DATEPART(DW, EMP_TIME.EMP_DATE) <> 1
	--AND DATEPART(DW, EMP_TIME.EMP_DATE) <> 
	AND EMP_TIME.FREELANCE <> 1
	AND EMP_TOT_HRS < @HoursThreshold
	AND EMP_EMAIL IS NOT NULL		

-- Setup and open a cursor for #TimeSheetTemp
DECLARE TimeEntryCursor CURSOR FOR
	SELECT 		
		EntryId,
		EmployeeEmail,
		EmployeeName,
		EntryHours, 
		EntryDate	
	FROM 
		#TimeSheetTemp
	ORDER BY
		EmployeeEmail,
		EntryDate

OPEN TimeEntryCursor

-- Seed the iterator
FETCH NEXT FROM TimeEntryCursor INTO
	@EntryId,
	@EmployeeEmail,
	@EmployeeName,
	@EntryHours,
	@EntryDate

-- Iterate the collection	
WHILE @@FETCH_STATUS = 0 BEGIN
	IF @CurrentEmployeeEMail <> @EmployeeEMail BEGIN
	
		-- We have changed names	
		IF @CurrentEmployeeEMail <> '' BEGIN
			-- Finish the message with the salutation
			SET @MessageBody = @MessageBody + @Salutation

			-- Send the email			
			EXEC msdb.dbo.sp_send_dbmail 
				@profile_name = 'TimeSheetProfile',
				@recipients = 'troy.forster@gmail.com',
				--@recipients = @EmployeeEmail
				@subject = @MessageSubject,
				@body =  @MessageBody
				
		END 

		-- Reset the MessageBody		
		SET @MessageBody = @EmployeeName + ',' + @CR2 + @Greeting + @CR2 + (left(convert(varchar, @EntryDate, 100), 11)) + ' you have submitted ' + CAST(@EntryHours AS NVARCHAR(10)) + ' hours. '
		
		-- Set the next Employee Email
		SET @CurrentEmployeeEMail = @EmployeeEmail

		-- Set the next Employee Email
		SET @CurrentEmployeeEMail = @EmployeeEmail

	END ELSE BEGIN
		-- We are still processing the same Employee Email
		SET @MessageBody = @MessageBody + @CR + (left(convert(varchar, @EntryDate, 100), 11)) + ' you have submitted ' + CAST(@EntryHours AS NVARCHAR(10)) + ' hours. ' + @CR2
	END

	-- Select the next iterator
	FETCH NEXT FROM TimeEntryCursor INTO
		@EntryId,
		@EmployeeEmail,
		@EmployeeName,
		@EntryHours,
		@EntryDate
END

-- Cleanup everythig
CLOSE TimeEntryCursor;
DEALLOCATE TimeEntryCursor;
DROP TABLE #TimeSheetTemp