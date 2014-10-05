USE master
GO

-- Prepare environment using T-SQL rather than GUI
sp_configure 'show advanced options',1
GO
reconfigure with override
GO
sp_configure 'Database Mail XPs',1
GO
reconfigure
GO

-- Create a DBMail service account using existing email account credentials
EXECUTE msdb.dbo.sysmail_add_account_sp
@account_name = 'TimeSheetEmailAccount',
@description = 'Service account for sending overdue timesheet reminders.',
@email_address = 'troy.forster@gmail.com',
@display_name = 'Timesheet Monitor',
@username='troy.forster@gmail.com',
@password='********',
@mailserver_name = 'smtp.gmail.com',
@port = 587,
@enable_ssl = 1

-- Create a DBMail profile
EXECUTE msdb.dbo.sysmail_add_profile_sp
@profile_name = 'TimeSheetProfile',
@description = 'Profile to manage overdue timesheet reminders.'

-- Add service account to profile
EXECUTE msdb.dbo.sysmail_add_profileaccount_sp
@profile_name = 'TimeSheetProfile',
@account_name = 'TimeSheetEmailAccount',
@sequence_number = 1

-- Set principals
EXECUTE msdb.dbo.sysmail_add_principalprofile_sp
@profile_name = 'TimeSheetProfile',
@principal_name = 'public',
@is_default = 1;

-- Send test message to confirm settings
declare @body1 varchar(100)
set @body1 = 'Sent from: ' + @@servername
EXEC msdb.dbo.sp_send_dbmail @recipients = 'troy.forster@gmail.com',
@subject = 'DBMail Configuration Confirmation',
@body = @body1,
@body_format = 'HTML';