# Advantage Missing Timesheet Entry Monitor

Send automatic email reminders to staff members who have not recorded a specific minimum amount of time. Tested against version n of Advantage Agency Software [http://gotoadvantage.com/](http://gotoadvantage.com/)



## Installation

Installing requires configuring your SQL Server instance to support sending email. Once this is done you will add a new stored procedure and configure SQL Server Agent to execute the stored procedure once every 24 hours.

Note that these instructions assume you have a working knowledge of SQL Server as well as sufficient permissions to perform the following steps. 

Also note that while the stored procedure does not write back to the database it is still advisable that you perform a full backup before continuing.

### Gather Required Information
1. Your SMTP server information
2. A suitable service email account including credentials
3. The number of hours that will be the threshold at which emails will be sent 

### Configure SQL Server for DB Mail
Open a new blank query against your database and copy and paste the content of dbmail-configuration.sql. Before executing the query be sure to change the values in sysmail_add_account_sp section and test section.

Run the query and if no errors are encountered you should receive a confirmation email to the account you specified. 

### Install Stored Procedure

### Configure SQL Server Agent

## Roadmap
1. Basic monitoring and sending of email once every 24 hours 
2. Support weekdays so that reminders are not sent on weekends
3. Support groups such that certain classification of users can be eliminated from the monitoring process