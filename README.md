# Pinger - crontab curl requests & email on failure
This is a docker container to run a curl script that will 'ping' your server/endpoint on a regular basis. If the expected response does not come back, an email will be sent to you.

This was designed to work with a Zoho mail account.  It may work with many others.

## 'Pinger' Docker Compose file
- Specifying a 'pinger.env' file for your private information
- Set Env Vars to configure 
	- Ping (curl) URI & expected response
	- Mail Relay login credentials
	- Ping interval (& threshold for failure email)
	- Failure email destination address
- History can be saved as a csv file in /var/log/pinger. File has two fields, with format:
	- Unix Timestamp
	- 1 (endpoint up) or 0 (endpoint down)