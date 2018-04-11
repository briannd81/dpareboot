# dpareboot
Reboot EMC Avamar DPA App and Database servers gracefully

EMC Data Protection Advisor (DPA) is a critical process for monitoring and reporting of Avamar backups. 
This script ensures the DPA Datastore and Application servers and their associated services are rebooted
in an orderly and graceful way to prevent database corruption resulting impairment of the reporting and monitoring processes.

Script implemented the following workflow to prevent database corruption:

1. Stop App Service
2. Check App service enters Stopped state
3. Stop Datastore Service
4. Check Datastore Service enters Stopped state
5. Reboot Datastore Server
6. Check Datastore Service enters Running state after reboot
7. Reboot App Server
8. Check App Service enters Running state after reboot

The script accepts a single mandatory parameter to determine which part gets executed.
This parameter accepts value Db, App or All. The Db value executes steps #1-5, App #6-8, and All #1-8.
    
.PARAMETER Server
The Serverparameter accepts value Db, App or All. The Db value executes steps #1-5, App #6-8, and All #1-8.

1. Stop App Service
2. Check App service enters Stopped state
3. Stop Datastore Service
4. Check Datastore Service enters Stopped state
5. Reboot Datastore Server
6. Check Datastore Service enters Running state after reboot
7. Reboot App Server
8. Check App Service enters Running state after reboot

.EXAMPLE
1. Stop App service, Datastore service and reboot Datastore server

DPA-Graceful-Reboot -Server Db

2. Reboot App server

DPA-Graceful-Reboot -Server App

3. Stop all App and Datastore services and reboot both servers

DPA-Graceful-Reboot -Server All
