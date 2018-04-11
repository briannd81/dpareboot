<#
.SYNOPSIS
This script reboots DPA servers in an orderly fashion to prevent database corruption.

.DESCRIPTION
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

#>

# Developer:   CDANG
#
# Description: This is the core processing script for DPA reboot
#
# Associating Scripts:
#
#       1. Processing.ps1
#       2. LogsRotation.ps1
#       3. SyslogCollector.ps1
#
#
###################################################
#
# CONVENTIONS USE IN THIS SCRIPT: 
#
# - Global Vars: starts with _ and in CAPS
# - Script Arguments: starts with SCRIPT_ARG
#
###################################################

###################################################
#
# SCRIPT PARAM

PARAM (
    [ValidateSet('App','Db','All')]
    [string]$Server = $(throw "-Server is required.")
)


#
#
###################################################

###################################################
#
# GLOBAL CONFIG
#
# - Put things to run before start of main()
#
###################################################

# Using "Stop" to enable handling of the exception via Try/Catch for non-terminating errors
# The program terminates if the exception is not caught
$ErrorActionPreference = "Stop"

# Load common library
# Use absolute path if not executing from command line
. "D:\DPA-Reboot\lib\common.ps1"

###################################################
#                                                 #
#                  FUNCTIONS                      #
#                                                 #
###################################################
<#
  Get machine last reboot time
  Input: Servername
  Return: None
#>
Function Get-Last-Reboot() {

    Param([String]$Server)

    $WmiObj = gwmi win32_operatingsystem -ComputerName $Server
    $LastReboot = $WmiObj.ConvertToDateTime($WmiObj.LastBootupTime)

    Return $LastReboot
    
}

<#
  Get service status and update reference variable
  Input: ServiceName, ServerName, ServiceObj
  Return: None
#>
Function Get-Service-Obj([String]$Service, [String]$Server, [Ref]$RefServiceObj) {

    $Counter = 0
    $ServiceObj = $Null

    While ($Counter -le $SvcRetryMax) {                           

        Try {

            $ServiceObj = Get-Service -Name "$Service" -ComputerName "$Server"

        } Catch {

            # ignore due to occasional connection issue
        }

        If ($ServiceObj -eq $Null) {
        
            Tee-Msg "[$Counter/$SvcRetryMax]: unable to get service status. Re-try in $SvcRetryInterval seconds"
        
            $Counter += $SvcRetryInterval
            Sleep $SvcRetryInterval

        } Else {

            # got service name, break out of while loop
            Break

        }

     }

     # update reference variable's value
     $RefServiceObj.Value = $ServiceObj

}


<#
  Reboots App Server
  Input: Servername
  Return: None
#>
Function Reboot-App-Server() {

    ################################################
    # Step 4: Check Reboot DB Service After Reboot #
    ################################################

    $IsDbServiceRunning = $False
    $Counter = 0

    Tee-Msg "Checking if DB Service is running after server reboot"

    # check if service is stopped after reboot
    While ($Counter -le $SvcRetryMax) {                           

        # may throw an error if server is still booting up
        Try {

            $DbServiceStatus = (Get-Service -Name "$DbServiceName" -ComputerName "$DbSvr").Status

        } Catch {

            # ignore server still booting up

        }

        If ($DbServiceStatus -ieq "Running") {
                        
            $IsDbServiceRunning = $True
            Break
                            
        } Else {

            Tee-Msg "[${Counter}/$SvcRetryMax]: DB service state is $DbServiceStatus. Retry in $SvcRetryInterval seconds."
            Sleep $SvcRetryInterval
            $Counter += $SvcRetryInterval

        }

    }

    # if DB Service is running after reboot
    If ($IsDbServiceRunning -eq $True) {

        Tee-Msg "OK DB Service is Running"

        #############################
        # Step 5: Reboot App Server #
        #############################


        # get service object
        $AppServiceObj = $Null
        Get-Service-Obj ($AppServiceName) ($AppSvr) ([Ref]$AppServiceObj)
        $AppServiceStatus = If($AppServiceObj -ne $Null){$AppServiceObj.Status}Else{$Null}

        Tee-Msg "App service state is $AppServiceStatus"
                
        If ($AppServiceStatus -ieq "running" ) {

            # stop app service if it hasn't been stopped earlier

            $Counter = 0
            $IsAppServiceStopped = $False

            Tee-Msg "Stopping App service in $SvcRetryInterval seconds"
            Sleep $SvcRetryInterval

            # issue the service stop command here
            $AppServiceObj | Stop-Service

            # check if service is stopped
            While ($Counter -le $SvcRetryMax) {

                # check service in try/catch block due to occasional connection issue
                Try {
                    
                    $AppServiceStatus = (Get-Service -Name "$AppServiceName" -ComputerName "$AppSvr").Status

                } Catch {                  
                    # do nothing
                }

                If ($AppServiceStatus -ieq "Stopped") {
                        
                    $IsAppServiceStopped = $True
                    Break
                            
                } Else {

                    Tee-Msg "[${Counter}/$SvcRetryMax]: App service state is $AppServiceStatus. Retry in $SvcRetryInterval seconds."
                    Sleep $SvcRetryInterval
                    $Counter += $SvcRetryInterval

                }

            }

            # check if APP service is stopped
            If ($IsAppServiceStopped -eq $True) {
                    
                Tee-Msg "OK App service stopped successfully"

            } Else {

                Tee-Msg "NOT OK Failed to top App service"

            }

        } Else {
                
            Tee-Msg "App service state is not running. It might have been stopped through normal reboot procedures."

        }

        # get last reboot time
        $AppSvrLastRebootBefore = Get-Last-Reboot "$AppSvr"

        # reboot datastore
        Tee-Msg "Notify users App server going for reboot in $TimeToReboot seconds"

        # notify users of reboot
        Notify-Reboot "$AppSvr"
                                
        # save background job to an object so we can reference the job later as needed
        $AppSvrRestartObj = Restart-Computer -Force -AsJob -ComputerName $AppSvr
        #$AppSvrRestartObj = Invoke-Command -ComputerName $AppSvr -ScriptBlock {Restart-Computer -Force} -AsJob

        ################################################
        # Script stops here if it runs from App Server #
        ################################################

        $AppSvrRebootStatus = $False
        $Counter = 0

        # get reboot status
        While ($Counter -le $RebootRetryMax) {
                                                             
            # Get-Last-Reboot may throw RPC error as server in reboot cycle
            # so test server connection first
            If(Test-Connection -Quiet -ComputerName $AppSvr) {                                    

                # may throw an error if shutdown is in progress
                Try {

                    $AppSvrLastRebootAfter = Get-Last-Reboot "$AppSvr"

                } Catch {

                    # ignore server shutdown in progress

                }


                If ($AppSvrLastRebootAfter -gt $AppSvrLastRebootBefore) {
                                        
                    $AppSvrRebootStatus = $True
                    Break

                } Else {
                                        
                    Tee-Msg "[${Counter}/$RebootRetryMax]: App Server pending reboot. Retry in $RebootRetryInterval seconds"

                }
                                                                                
            } Else {
                                    
                Tee-Msg "[${Counter}/$RebootRetryMax]: App server unreachable because it may be booting up. Retry in $RebootRetryInterval seconds"
                                                                                                                                                    
            }

            $Counter += $RebootRetryInterval
                                
        }#while
                                        
        # check reboot status
        If ($AppSvrRebootStatus -eq $True) {

            Tee-Msg "OK App Server rebooted successfully"

            ##########################################
            # Step 6: Check App Service After Reboot #
            ##########################################

            $IsAppServiceRunning = $False
            $Counter = 0

            Tee-Msg "Checking if App Service is running after server reboot"

            # check if service is stopped after reboot
            While ($Counter -le $SvcRetryMax) {                           

                Try {

                    $AppServiceStatus = (Get-Service -Name "$AppServiceName" -ComputerName "$AppSvr").Status

                } Catch {

                    # ignore server still booting

                }

                If ($AppServiceStatus -ieq "Running") {
                        
                    $IsAppServiceRunning = $True
                    Break
                            
                } Else {

                    Tee-Msg "[${Counter}/$SvcRetryMax]: App service state is $AppServiceStatus. Retry in $SvcRetryInterval seconds."
                    Sleep $SvcRetryInterval
                    $Counter += $SvcRetryInterval

                }

            }

            # check App Service is running
            If ($IsAppServiceRunning -eq $True) {

                Tee-Msg "OK App Service is running after reboot"

            } Else {                                        

                Tee-Msg "NOT OK App Service is not running after reboot"

            }

        } Else {

            Tee-Msg "NOT OK Failed to reboot App server"

        }

    } Else {                                        

        Tee-Msg "NOT OK DB Service is not running after reboot"

    }

}


<#
  Notify all users server going for reboot in x seconds and sleep for x seconds
  Input: Servername
  Return: None
#>
Function Notify-Reboot() {

    Param([String]$Server)

    # notify remote pc
    Invoke-Command -ComputerName $Server -ScriptBlock {msg * "Alert: rebooting server in " @args $TimeToReboot " seconds for maintenance - LAN Admin"} -ArgumentList $TimeToReboot

    Sleep $TimeToReboot

}


###################################################
#                                                 #
#                     MAIN                        #
#                                                 #
###################################################

# set these first
Set-Variable _SCRIPT_DIR -Option Constant -Value (Get-Script-Dir)
Set-Variable _APP_DIR -Option Constant -Value (Split-Path -Parent $_SCRIPT_DIR) # one level up from bin
Set-Variable _SCRIPT_NAME_NO_EXT -Option Constant -Value (Get-ScriptName-NoExt)
Set-Variable _CONFIG_DIR -Option Constant -Value ($_APP_DIR + "\etc")
Set-Variable _CONFIG_FILE -Option Constant -Value ($_CONFIG_DIR + "\settings.conf")
Set-Variable _CONFIG_FILE_SHORTNAME -Option Constant -Value (Split-Path -Leaf $_CONFIG_FILE)

# load from config (optional fields)
$TMP_LOG_DIR = If ( (Load-Config "LOG_DIR") -ne $null ) {Load-Config "LOG_DIR"} Else {$_APP_DIR + "\var\log"}
Set-Variable _LOG_DIR -Option Constant -Value $TMP_LOG_DIR
$TMP_RUN_DIR = If ( (Load-Config "RUN_DIR") -ne $null ) {Load-Config "RUN_DIR"} Else {$_APP_DIR + "\var\run"}
Set-Variable _RUN_DIR -Option Constant -Value $TMP_RUN_DIR
$TMP_TRACEBACK_DIR = If ( (Load-Config "TRACEBACK_DIR") -ne $null ) {Load-Config "TRACEBACK_DIR"} Else {$_LOG_DIR}
Set-Variable _TRACEBACK_DIR -Option Constant -Value $TMP_TRACEBACK_DIR
$TMP_SYSLOG_DIR = If ( (Load-Config "SYSLOG_DIR") -ne $null ) {Load-Config "SYSLOG_DIR"} Else {$_LOG_DIR + "\syslog"}
Set-Variable _SYSLOG_DIR -Option Constant -Value $TMP_SYSLOG_DIR
$TMP_LOG_ARCHIVE_DIR = If ( (Load-Config "LOG_ARCHIVE_DIR") -ne $null ) {Load-Config "LOG_ARCHIVE_DIR"} Else {$_LOG_ARCHIVE_DIR + "\archivelog"}
Set-Variable _LOG_ARCHIVE_DIR -Option Constant -Value $TMP_LOG_ARCHIVE_DIR

# log and lock files
Set-Variable _LOG_FILE -Option Constant -Value ($_LOG_DIR + '\' + $_SCRIPT_NAME_NO_EXT + ".log")
Set-Variable _LOCK_FILE -Option Constant -Value ($_RUN_DIR + '\' + $_SCRIPT_NAME_NO_EXT + ".lck")
Set-Variable _LOCK_FILE_SHORTNAME -Option Constant -Value (Split-Path -Leaf $_LOCK_FILE)

# stores non-terminating exceptions info
Set-Variable _TRACEBACK_FILE -Option Constant -Value ($_TRACEBACK_DIR + '\' + $_SCRIPT_NAME_NO_EXT + ".traceback.log")
Set-Variable _TRACEBACK_FILE_SHORTNAME -Option Constant -Value (Split-Path -Leaf $_TRACEBACK_FILE)

# script argument
Set-Variable SCRIPT_ARG_SERVER -Option Constant -Value $Server


Tee-Msg "---------------------------------------------------"


exit

# wrap everything inside to catch all exceptions
Try {

    # Check if there is an existing instance running
    If ( ! (Is-LockFile-Exist) ) {

        # Creates lock file
        Tee-Msg "Creating lock file ${_LOCK_FILE_SHORTNAME}"
        Create-Lock-File
 
        If ( (Is-ConfigFile-Exist)) {

            $HasRequiredConfig = $True

            # load required fields from config and assign to global var
            If ((Load-Config "DPA_APP_SVR") -ne $null) {$_DPA_APP_SVR = (Load-Config "DPA_APP_SVR")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating DPA_APP_SVR exists in $_CONFIG_FILE_SHORTNAME"}
            If ((Load-Config "DPA_DB_SVR") -ne $null) {$_DPA_DB_SVR = (Load-Config "DPA_DB_SVR")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating DPA_DB_SVR exists in $_CONFIG_FILE_SHORTNAME"}
            If ((Load-Config "DPA_APP_SVC_NAME") -ne $null) {$_DPA_APP_SVC_NAME = (Load-Config "DPA_APP_SVC_NAME")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating DPA_APP_SVC_NAME exists in $_CONFIG_FILE_SHORTNAME"}
            If ((Load-Config "DPA_DB_SVC_NAME") -ne $null) {$_DPA_DB_SVC_NAME = (Load-Config "DPA_DB_SVC_NAME")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating DPA_DB_SVC_NAME exists in $_CONFIG_FILE_SHORTNAME"}
            If ((Load-Config "SVC_RETRY_MAX") -ne $null) {$_SVC_RETRY_MAX = (Load-Config "SVC_RETRY_MAX")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating SVC_RETRY_MAX exists in $_CONFIG_FILE_SHORTNAME"}
            If ((Load-Config "SVC_RETRY_INTERVAL") -ne $null) {$_SVC_RETRY_INTERVAL = (Load-Config "SVC_RETRY_INTERVAL")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating SVC_RETRY_INTERVAL exists in $_CONFIG_FILE_SHORTNAME"}
            If ((Load-Config "REBOOT_RETRY_MAX") -ne $null) {$_REBOOT_RETRY_MAX = (Load-Config "REBOOT_RETRY_MAX")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating REBOOT_RETRY_MAX exists in $_CONFIG_FILE_SHORTNAME"}
            If ((Load-Config "REBOOT_RETRY_INTERVAL") -ne $null) {$_REBOOT_RETRY_INTERVAL = (Load-Config "REBOOT_RETRY_INTERVAL")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating REBOOT_RETRY_INTERVAL exists in $_CONFIG_FILE_SHORTNAME"}
            If ((Load-Config "TIME_TO_REBOOT") -ne $null) {$_TIME_TO_REBOOT = (Load-Config "TIME_TO_REBOOT")} Else {$HasRequiredConfig = $False; Tee-Msg "NOT OK Validating TIME_TO_REBOOT exists in $_CONFIG_FILE_SHORTNAME"}
                                       
            If ( $HasRequiredConfig -eq $True ) {

                # print DPA servers and service names
                Tee-Msg "DPA App Server: $_DPA_APP_SVR"
                Tee-Msg "DPA DB Server: $_DPA_DB_SVR"
                Tee-Msg "DPA App Service: $_DPA_APP_SVC_NAME"
                Tee-Msg "DPA DB Service: $_DPA_DB_SVC_NAME"

                #########################################
                # Step 1: Stop DPA APP Service          #
                #########################################

                # variables for service check
                $SvcRetryMax = $_SVC_RETRY_MAX
                $SvcRetryInterval = $_SVC_RETRY_INTERVAL

                # variables for server reboot check
                $RebootRetryMax = $_REBOOT_RETRY_MAX
                $RebootRetryInterval = $_REBOOT_RETRY_INTERVAL

                # time to reboot
                $TimeToReboot = $_TIME_TO_REBOOT

                # variables for DPA APP services
                $AppSvr = "$_DPA_APP_SVR"
                $AppServiceName = "$_DPA_APP_SVC_NAME"
                $AppServiceObj = $Null
                Get-Service-Obj ($AppServiceName) ($AppSvr) ([Ref]$AppServiceObj)
                $AppServiceStatus = If($AppServiceObj -ne $Null){$AppServiceObj.Status}Else{$Null}

                # variables for DPA DB services
                $DbSvr = "$_DPA_DB_SVR"
                $DbServiceName = "$_DPA_DB_SVC_NAME"
                $DbServiceObj = $Null
                Get-Service-Obj ($DbServiceName) ($DbSvr) ([Ref]$DbServiceObj)
                $DbServiceStatus = If($DbServiceObj -ne $Null){$DbServiceObj.Status}Else{$Null}
                
                If ($SCRIPT_ARG_SERVER -eq "App") {

                    ################################################################################
                    # reboot app server only, i.e. use this option as startup script for Db server #
                    ################################################################################
                    
                    Reboot-App-Server

                } Else {

                    # check if app service is in Stopped state
                    Tee-Msg "App service state is $AppServiceStatus"

                    ########################################################################################################
                    # reboot db server and app (if All argument is passed to script), i.e. use this option for wsus reboot #
                    ########################################################################################################

                    If ($AppServiceStatus -ieq "running" ) {

                        $Counter = 0
                        $IsAppServiceStopped = $False

                        Tee-Msg "Stopping App service in $SvcRetryInterval seconds"
                        Sleep $SvcRetryInterval

                        # issue the service stop command here
                        $AppServiceObj = $Null
                        Get-Service-Obj ($AppServiceName) ($AppSvr) ([Ref]$AppServiceObj)
                        If($AppServiceObj -ne $Null){$AppServiceObj | Stop-Service}

                        # check if service is stopped
                        While ($Counter -le $SvcRetryMax) {

                            $AppServiceStatus = (Get-Service -Name "$AppServiceName" -ComputerName "$AppSvr").Status

                            If ($AppServiceStatus -ieq "Stopped") {
                        
                                $IsAppServiceStopped = $True
                                Break
                            
                            } Else {

                                Tee-Msg "[${Counter}/$SvcRetryMax]: App service state is $AppServiceStatus. Retry in $SvcRetryInterval seconds."
                                Sleep $SvcRetryInterval
                                $Counter += $SvcRetryInterval

                            }

                        }

                        # check if APP service is stopped
                        If ($IsAppServiceStopped -eq $True) {
                    
                            Tee-Msg "OK App service stopped successfully"


                            ####################################
                            # Step 2: Stop DB Service          #
                            ####################################

                            # variables for DB services
                            $DbSvr = "$_DPA_DB_SVR"
                            $DbServiceName = "$_DPA_DB_SVC_NAME"
                            $DbServiceObj = $Null
                            Get-Service-Obj ($DbServiceName) ($DbSvr) ([Ref]$DbServiceObj)
                            $DbServiceStatus = If($DbServiceObj -ne $Null){$DbServiceObj.Status}Else{$Null}

                            # check if db service is in Stopped state
                            Tee-Msg "DB service state is $DbServiceStatus"
                
                            If ($DbServiceStatus -ieq "running" ) {

                                $Counter = 0
                                $IsDbServiceStopped = $False

                                Tee-Msg "Stopping DB service in $SvcRetryInterval seconds"
                                Sleep $SvcRetryInterval

                                # issue the service stop command here                                
                                $DbServiceObj | Stop-Service

                                # check if service is stopped
                                While ($Counter -le $SvcRetryMax) {                           

                                    $DbServiceStatus = (Get-Service -Name "$DbServiceName" -ComputerName "$DbSvr").Status

                                    If ($DbServiceStatus -ieq "Stopped") {
                        
                                        $IsDbServiceStopped = $True
                                        Break
                            
                                    } Else {

                                        Tee-Msg "[${Counter}/$SvcRetryMax]: DB service state is $DbServiceStatus. Retry in $SvcRetryInterval seconds."
                                        Sleep $SvcRetryInterval
                                        $Counter += $SvcRetryInterval

                                    }

                                }

                                # check if DB service is stopped
                                If ($IsDbServiceStopped -eq $True) {

                                    Tee-Msg "OK DB service stopped successfully"
                    
                                    #####################################
                                    # Step 3: Reboot DB Server          #
                                    #####################################

                                    # get last reboot time
                                    $DbSvrLastRebootBefore = Get-Last-Reboot "$DbSvr"

                                    # reboot datastore
                                    Tee-Msg "Notify users DB server going for reboot in $TimeToReboot seconds"

                                    # notify users server going for reboot
                                    Notify-Reboot "$DbSvr"

                                    # if db server running this script, clean up lock file before reboot
                                    # so it can continue processing app server after booting up
                                    If ( (($env:COMPUTERNAME + '.' + $env:USERDNSDOMAIN) -ieq "$DbSvr") -or (($env:COMPUTERNAME) -ieq "$DbSvr") ) {
                                        cleanup
                                    }

                                    # save background job to an object so we can reference the job later as needed
                                    $DbSvrRestartObj = Restart-Computer -Force -AsJob -ComputerName $DbSvr
                                    #$DbSvrRestartObj = Invoke-Command -ComputerName $DbSvr -ScriptBlock {Get-Service -Force} -AsJob

                                    $DbSvrRebootStatus = $False
                                    $Counter = 0

                                    While ($Counter -le $RebootRetryMax) {
                                                             
                                        # Get-Last-Reboot may throw RPC error as server in reboot cycle
                                        # so test server connection first
                                        If(Test-Connection -Quiet -ComputerName $DbSvr) {                                    

                                            # may throw an error if shutdown is in progress
                                            Try {

                                                $DbSvrLastRebootAfter = Get-Last-Reboot "$DbSvr"

                                            } Catch {

                                                # ignore server booting up

                                            }

                                            If ($DbSvrLastRebootAfter -gt $DbSvrLastRebootBefore) {
                                        
                                                $DbSvrRebootStatus = $True
                                                Break

                                            } Else {
                                        
                                                Tee-Msg "[${Counter}/$RebootRetryMax]: DB Server pending reboot. Retry in $RebootRetryInterval seconds"

                                            }
                                                                                
                                        } Else {
                                    
                                            Tee-Msg "[${Counter}/$RebootRetryMax]: DB server unreachable because it may be booting up. Retry in $RebootRetryInterval seconds"
                                                                                                                                                    
                                        }

                                        $Counter += $RebootRetryInterval
                                
                                    }#while
                                
                                    # check reboot status
                                    If ($DbSvrRebootStatus -eq $True) {

                                        Tee-Msg "OK DB Server rebooted successfully"

                                        # reboot server if All argument is passed to script
                                        If ($SCRIPT_ARG_SERVER -eq "All") {
                                            Reboot-App-Server
                                        }

                                    } Else {

                                        Tee-Msg "NOT OK Failed to reboot DB server"

                                    }
                                                             
                                } Else {
                    
                                    Tee-Msg "NOT OK Failed to stop DB service"

                                }
                    
                            } ElseIf ($DbServiceStatus -ieq "stopped") {
    
                                # notify admin since service stopped by an external process
                                Tee-Msg "NOT OK DB service is stopped by an external process. Notify admin."

                            } Else {

                                Sleep 5
                                Write-Output "NOT OK DB service state is neither running nor stopped. Notify admin."

                            }

                        } Else {
                    
                            Tee-Msg "NOT OK Failed to stop App service"

                        }
                    
                    } ElseIf ($AppServiceStatus -ieq "stopped") {
    
                        # notify admin since service stopped by an external process
                        Tee-Msg "NOT OK App service is stopped by an external process. Notify admin."

                    } Else {

                        Sleep 5
                        Tee-Msg "NOT OK App service state is neither running nor stopped. Notify admin."

                    }

                }

            } Else {

                Tee-Msg "NOT OK Terminate program because one or more required fields are missing in config file $_CONFIG_FILE_SHORTNAME"

            }

        } Else {

            # Log message
            Tee-Msg "NOT OK Terminate program because config file $_CONFIG_FILE_SHORTNAME is missing."

        }

    } Else {

        # Log message
        Tee-Msg "NOT OK Terminate program because lock file $_LOCK_FILE_SHORTNAME exists."

    }

} Catch {

      # Do not enclosed $_ in double-quotes to preserve its type ErrorRecord
      Log-To-Traceback $_

} Finally {

      # Perform cleanup, i.e. remove lock file
      Cleanup

}

