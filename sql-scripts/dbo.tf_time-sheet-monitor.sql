SET DATEFIRST 7;                       -- Ensure Sunday has an index of 7

DECLARE @MessageBody NVARCHAR(MAX)
DECLARE @DisplayDate VARCHAR(20)
DECLARE @ToAddress VARCHAR(50)
DECLARE @CR VARCHAR(1);                SET @CR = CHAR(13)
DECLARE @CR2 VARCHAR(2);               SET @CR2 = CHAR(13) + CHAR(13)

DECLARE @IgnoreWeekends BIT;           SET @IgnoreWeekends = 1       -- true to skip processing Saturdays and Sundays
DECLARE @Debug BIT;                    SET @Debug = 1                -- true for verbose console output
DECLARE @Mode INT;                     SET @Mode = 0                 -- 0 = no email, 1 = test email, 2 = employee emails

DECLARE @TestEmailAccount VARCHAR(50)  SET @TestEmailAccount = 'troy.forster@gmail.com'
DECLARE @HoursThreshold INT;           SET @HoursThreshold = 6.5
DECLARE @MessageSubject NVARCHAR(256); SET @MessageSubject = 'Timesheets!'					
DECLARE @Greeting VARCHAR(128);        SET @Greeting = 'Thank you for completing your time sheets, but you still have time missing for the following days:' + @CR2
DECLARE @Valediction VARCHAR(128);     SET @Valediction = @CR + 'Thank you,' + @CR2 + 'The Finance Department'

-- Calculate low and high dates as yesterday and a week yesterday based on current system time.
DECLARE @LoDateToCheck VARCHAR(25);    SET @LoDateToCheck = LEFT(CONVERT(VARCHAR, CONVERT(date, DATEADD(day, -7, SYSDATETIME())), 120), 10) + ' 00:00:00.000'
DECLARE @HiDateToCheck VARCHAR(25);    SET @HiDateToCheck = LEFT(CONVERT(VARCHAR, CONVERT(date, DATEADD(day, -1, SYSDATETIME())), 120), 10) + ' 00:00:00.000'

IF(@Debug = 1) PRINT 'Processing for ' + CONVERT(char(10), @LoDateToCheck,126) + ' to ' + CONVERT(char(10), @HiDateToCheck,126)

/******************************************************************************
 * Get list of all employees into temporary table
 *
 * Note: Schema does not imply how to differentiate between current and past
 * employees.
 *****************************************************************************/
IF OBJECT_ID('tempdb..#CurrentEmployees') IS NOT NULL DROP TABLE #CurrentEmployees
SELECT 
	EMP_CODE, 
	EMP_EMAIL,
	EMP_FNAME + ' ' + EMP_LNAME AS EmployeeName
INTO
	#CurrentEmployees	
FROM
	EMPLOYEE_CLOAK
WHERE
	FREELANCE = 0
	AND EMP_EMAIL IS NOT NULL

/******************************************************************************
 * Outer cursor to iterate each employee
 *
 *****************************************************************************/
DECLARE @EMP_CODE VARCHAR(6)
DECLARE @EMP_EMAIL VARCHAR(50)
DECLARE @EmployeeName VARCHAR(61)

DECLARE EmployeeCursor CURSOR FOR
	SELECT 		
		EMP_CODE, 
		EMP_EMAIL,
		EmployeeName
	FROM 
		#CurrentEmployees
	ORDER BY
		EMP_EMAIL

OPEN EmployeeCursor
	FETCH NEXT FROM EmployeeCursor INTO
		@EMP_CODE,
		@EMP_EMAIL,
		@EmployeeName

	WHILE @@FETCH_STATUS = 0 BEGIN
      -- Initialize for the employee
      IF OBJECT_ID('tempdb..#EmployeeEntriesForRange') IS NOT NULL DROP TABLE #EmployeeEntriesForRange
      SET @MessageBody = @EmployeeName + ',' + @CR2 + @Greeting 
      
      SELECT 
         @EmployeeName AS EmployeeName, 
         SerialDates.EntryDate, 
         HoursWorked 
      INTO 
         #EmployeeEntriesForRange
      FROM 
         -- Return a single column result set of serial dates matching the selected range 
         (SELECT 
            DATEADD(DAY, number, @LoDateToCheck) AS EntryDate
         FROM
            (SELECT DISTINCT number 
               FROM 
                  MASTER.dbo.spt_values
               WHERE 
                  name is null
            ) n          
         WHERE 
            DATEADD(DAY, number, @LoDateToCheck) <= @HiDateToCheck
         ) SerialDates
      LEFT JOIN 
         -- Return a column each for date and hours worked for any dates with entries
         (SELECT 
            EMP_TIME.EMP_DATE AS EntryDate,
            ISNULL(EMP_TOT_HRS, 0) AS HoursWorked            
         FROM
            EMP_TIME
         WHERE 
            EMP_TIME.EMP_DATE >= @LoDateToCheck
            AND EMP_TIME.EMP_DATE <= @HiDateToCheck
            AND EMP_TIME.EMP_CODE = @EMP_CODE
            AND (@IgnoreWeekends = 0 OR ( DATEPART(DW, EMP_TIME.EMP_DATE) <> 1 AND DATEPART(DW, EMP_TIME.EMP_DATE) <> 7 ))                        
         ) RecordedEntries
      ON 
         SerialDates.EntryDate = RecordedEntries.EntryDate
      
      /******************************************************************************
      * Inner cursor to iterate dates in each employee range temp table
      *
      *****************************************************************************/
      DECLARE @EntryHours DECIMAL
      DECLARE @EntryDate DATETIME
      DECLARE @EmailRequired BIT; SET @EmailRequired = 0

      DECLARE RangeCursor CURSOR FOR
	      SELECT 		
		      EntryDate,
            HoursWorked 
	      FROM 
		      #EmployeeEntriesForRange
	      ORDER BY
		      EntryDate ASC

      OPEN RangeCursor
	      FETCH NEXT FROM RangeCursor INTO
		      @EntryDate,
		      @EntryHours

	      WHILE @@FETCH_STATUS = 0 BEGIN            
            IF(@EntryHours < @HoursThreshold) BEGIN 
               SET @EmailRequired = 1               
               SET @MessageBody = @MessageBody + CONVERT(char(10), @EntryDate,126) + ' you have submitted ' + CAST(@EntryHours AS NVARCHAR(10)) + ' hours. ' + @CR
            END
            
         	FETCH NEXT FROM 
               RangeCursor 
            INTO
			      @EntryDate,
			      @EntryHours                
         END -- WHILE
         
         -- The @EmailRequired flag is set when one or more missing entries have been identified
         IF @EmailRequired = 1 BEGIN
            SET @MessageBody = @MessageBody + @Valediction
            
            IF(@Debug = 1) BEGIN
               PRINT 'Sending the following message to ' + @EMP_EMAIL + @CR
               PRINT @MessageBody
            END 

            -- Check to see if actual email sending is enabled in the global flags
            IF(@Mode > 0) BEGIN               
               -- Mode also determines whether to use test email address or employee email address
               IF(@Mode = 1) 
                  SET @ToAddress = @TestEmailAccount 
               ELSE 
                  SET @ToAddress = @EMP_EMAIL

               EXEC msdb.dbo.sp_send_dbmail 
                  @profile_name = 'TimeSheetProfile',
                  @recipients = @ToAddress,
                  @subject = @MessageSubject,
                  @body =  @MessageBody
            END
         END

      -- Cleanup the inner cursor 
      CLOSE RangeCursor;
      DEALLOCATE RangeCursor;

      -- Iterate next available outer cursor
		FETCH NEXT FROM 
         EmployeeCursor 
      INTO
			@EMP_CODE,
			@EMP_EMAIL,
			@EmployeeName
	END -- WHILE

-- Cleanup the outer cursor 
CLOSE EmployeeCursor;
DEALLOCATE EmployeeCursor;