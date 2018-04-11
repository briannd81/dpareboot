# collection of shared functions used O365License scripts


<#
  Check if there is an existing lock file
  Input: None
  Return: Boolean
#>
Function Is-LockFile-Exist() {

  $LockFileExist = If ( Test-Path "$_LOCK_FILE" ) {$True} Else {$False}
  Return $LockFileExist

}

<#
  Check if config file exists
  Input: None
  Return: Boolean
#>
Function Is-ConfigFile-Exist() {

  $ConfigFileExist = If ( Test-Path "$_CONFIG_FILE" ) {$True} Else {$False}
  Return $ConfigFileExist

}


<#
  Creates lock file
  Input: None
  Return: None
#>
Function Create-Lock-File() {

  If (!(Test-Path -Path "$_LOCK_FILE")) {

    # Test-Path is typically good enough to avoid file exists exception
    # The Try/Catch is use in case of permission
    Try {
      
      New-Item -ItemType File "$_LOCK_FILE" | Out-Null

    } Catch {

      # Do not enclosed $_ in double-quotes to preserve its type ErrorRecord
      Log-To-Traceback $_

    }

  }

}


<#
  Get current date in dd/mm/yyyy hh:mm:ss
  Input: None
  Return: Date
#>

Function Get-Current-Date() {
 
  return Get-Date -Format G

}


<#
  Display message to output and/or log file
  Input: String, Boolean
  Return: None
#>
Function Tee-Msg ($Msg) {

    $Date = Get-Current-Date

    # Write to terminal
    Write-Output "$Date `t $Msg"

    # Write to log
    Write-Output "$Date `t $Msg" | Add-Content -Path $_LOG_FILE

}

<#
  Generate ticket and log exception detail to standard, traceback and syslog
  Input: ErrorRecord or String, Boolean
  Return: None
#>
Function Log-To-Traceback ($Msg) {

    # generate ticket id for this exception
    $TicketId = Get-Ticket-Id

    # log ticket id to caller's log
    $RaiseExeptionMsg = "Ticket $TicketId is raised due to an Exception and logged to to $_TRACEBACK_FILE_SHORTNAME"
    Tee-Msg "$RaiseExeptionMsg"

    # use the following hack to get the multi-line string into traceback log
    If ( $Msg.GetType().Name -like "errorrecord" ) {

        $Msg = $Msg.ToString() + $Msg.InvocationInfo.PositionMessage

    }

    # get current formatted date
    $Date = Get-Current-Date

    # write message to caller's traceback log
    Write-Output "$Date `t Ticket ID $TicketId" | Add-Content -Path $_TRACEBACK_FILE
    Write-Output "$Msg" | Add-Content -Path $_TRACEBACK_FILE

    # create new file using ticket id as the name and log the exception message to the file
    # syslog collector script picks sends the exception to central syslog then deletes the file
    $SyslogExt = ".log"
    $SyslogFullName = "$_SYSLOG_DIR\$TicketId" + "$SyslogExt"
    New-Item -ItemType File -Path $SyslogFullName | Out-Null
    Write-Output("$Date `t EPD script ${_SCRIPT_NAME_NO_EXT}.ps1 created ticket ID $TicketId for the exception caught - " + $Msg) | Add-Content -Path $SyslogFullName

}

<#
  Return this script name without the extension
  Input: None
  Return: String
#>
Function Get-ScriptName-NoExt() {

    $ScriptName = $MyInvocation.ScriptName.Split("\")[-1]
    return $ScriptName.Substring(0, $ScriptName.LastIndexOf('.'))

}

<#
  Return this script directory
  Input: None
  Return: String
#>
Function Get-Script-Dir() {

    $ScriptDir = $MyInvocation.PSScriptRoot
    return $ScriptDir

}


<#
  Generate and return a new and unique id that can be used to assign to an exception for traceback log
  Input: None
  Return: Int
#>
Function Get-Ticket-Id() {
    
    $ID = [guid]::NewGuid()
    return $ID

}

<#
  Perform cleanup such as removing lock file
  Input: String
  Return: None
#>
Function Cleanup() {

    Tee-Msg "Removing lock file $_LOCK_FILE_SHORTNAME"
    Remove-Item -Path "$_LOCK_FILE" -Force

}

<#
  Load value from configuration file
  Input: String
  Return: None
#>
Function Load-Config($Field) {

    $Value = Select-String -Path "$_CONFIG_FILE" -Pattern "^$Field"

    If ( $Value -ne $null ) {

        If ( $Value.ToString().Split('=').Length -eq 2 ) {

            $Value = $Value.ToString().Split('=')[1].Trim().Replace('"','').Replace("'","")

        } Else {

            $Value = $null

        }

    }
   
    Return $Value

}