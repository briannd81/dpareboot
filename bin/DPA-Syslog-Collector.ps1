# Developer:   CDANG
#
# Description: Send critical info to syslog
#
# Associate Scripts:
#
#              1. DPA-Reboot.ps1
#              2. DPA-Log-Rotation.ps1
#              3. DPA-Syslog-Collector.ps1
#
#
#
###################################################
#
# CONVENTIONS USE IN THIS SCRIPT: 
#
# - Global Vars: starts with _ and in CAPS
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
. "..\lib\common.ps1"


###################################################
#                                                 #
#                  FUNCTIONS                      #
#                                                 #
###################################################



###################################################
#                                                 #
#                     MAIN                        #
#                                                 #
###################################################

# set these first
${_SCRIPT_DIR} = Get-Script-Dir #script is in bin
${_APP_DIR} = Split-Path -Parent ${_SCRIPT_DIR} # one level up from bin
${_SCRIPT_NAME_NO_EXT} = Get-ScriptName-NoExt
${_CONFIG_DIR} = ${_APP_DIR} + "\etc"
${_CONFIG_FILE} = ${_CONFIG_DIR} + "\" + "settings.conf"
${_CONFIG_FILE_SHORTNAME} = Split-Path -Leaf ${_CONFIG_FILE}

# load from config (optional fields)
$_LOG_DIR = If ( (Load-Config "LOG_DIR") -ne $null ) {Load-Config "LOG_DIR"} Else {$_APP_DIR + "\var\log"}
$_LOCK_DIR = If ( (Load-Config "LOCK_DIR") -ne $null ) {Load-Config "LOCK_DIR"} Else {$_APP_DIR + "\var\run"}
$_TRACEBACK_DIR = If ( (Load-Config "TRACEBACK_DIR") -ne $null ) {Load-Config "TRACEBACK_DIR"} Else {$_LOG_DIR}
$_SYSLOG_DIR = If ( (Load-Config "SYSLOG_DIR") -ne $null ) {Load-Config "SYSLOG_DIR"} Else {$_LOG_DIR + "\syslog"}

# log and lock files
${_LOG_FILE} = ${_LOG_DIR} + '\' + ${_SCRIPT_NAME_NO_EXT} + ".log"
${_LOCK_FILE} = ${_LOCK_DIR} + '\' + ${_SCRIPT_NAME_NO_EXT} + ".lck"
${_LOCK_FILE_SHORTNAME} = Split-Path -Leaf ${_LOCK_FILE}

# stores non-terminating exceptions info
${_TRACEBACK_FILE} = ${_TRACEBACK_DIR} + '\' + ${_SCRIPT_NAME_NO_EXT} + ".traceback.log"
${_TRACEBACK_FILE_SHORTNAME} = Split-Path -Leaf ${_TRACEBACK_FILE}

# wrap everything inside to catch all exceptions
Try {

    # Check if there is an existing instance running
    If ( ! (Is-LockFile-Exist) ) {

        # Creates lock file
        Tee-Msg "Creating lock file ${_LOCK_FILE_SHORTNAME}"
        Create-Lock-File
 
        If ( (Is-ConfigFile-Exist)) {

            $MissingRequiredConfig = $False

            # load from config (required fields) and assign to global var
            #If ((Load-Config "LOST_FOUND_DIR") -ne $null) {$_LOST_FOUND_DIR = (Load-Config "LOST_FOUND_DIR")} Else {$MissingRequiredConfig = $True; Tee-Msg "NOT OK Validating LOST_FOUND_DIR exists in $_CONFIG_FILE_SHORTNAME"}
            
                                       
            If ( $MissingRequiredConfig -ne $True ) {

                Tee-Msg "Syslog: ${_SYSLOG_DIR}"
                Tee-Msg "Lost&Found: ${_LOST_FOUND_DIR}"

                $SyslogFileCount = (Get-ChildItem -Recurse "$_SYSLOG_DIR").Count

                Tee-Msg "Checking if there are message logs to send to syslog server"

                If ( $SyslogFileCount -gt 0 ) {

                    # locate archive files that are older than aging limit and remove            
                    ForEach ( $File in Get-ChildItem -Path "$_SYSLOG_DIR" ) {

                        $FileName = $File.Name
                        $FileFullName = $File.FullName

                        # cast array to string
                        $Msg = [String](Get-Content "$FileFullName")

                        Tee-Msg "Sending content of $FileFullName to syslog server"

                        # send message to centralized syslog
                        Send-SysLogMsg -Facility 3 -Level 3 -Category "DPA-Reboot" -Priority "M" -Message "$Msg"

                        Tee-Msg "Deleting $FileFullName"

                        Remove-Item -Force "$FileFullName"

                    }
                
                } Else {
                
                    Tee-Msg "There are no message logs"
                
                }

            } Else {

                Tee-Msg "Terminating program because one or more required fields are missing in config file $_CONFIG_FILE_SHORTNAME"

            }                



        } Else {

            # Log message
            Tee-Msg "Terminate program because config file $_CONFIG_FILE_SHORTNAME is missing."

        }

    } Else {

        # Log message
        Tee-Msg "Terminate program because lock file ${_LOCK_FILE_SHORTNAME} exists."

    }

} Catch {

      # Do not enclosed $_ in double-quotes to preserve its type ErrorRecord
      Log-To-Traceback $_

} Finally {

        # Perform cleanup, i.e. remove lock file
        Cleanup

}

Tee-Msg "---------------------------------------------------"