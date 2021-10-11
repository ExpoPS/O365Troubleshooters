<# 1st requirement install the module O365 TS
Import-Module C:\Users\alexaca\Documents\GitHub\O365Troubleshooters\O365Troubleshooters.psm1 -Force
# 2nd requirement Execute set global variables
Set-GlobalVariables
# 3rd requirement to start the menu
Start-O365TroubleshootersMenu
#>

<#

        .SYNOPSIS

        Get a report of mailbox folder permissions for one or more mailboxes



        .DESCRIPTION

        Get a report of mailbox folder permissions for one or more mailboxes...



        .EXAMPLE

        If we check a mailbox for folder permissions, we can find out if any of the default folders have modified default permissions and someone else has access to the contents of those folders

        

        .LINK

        Online documentation: https://aka.ms/O365Troubleshooters/CheckMailboxFolderPermissions



    #>

function Get-AllDefaultUserMailboxFolderPermissions {

    param(
        [System.Collections.ArrayList]$MBXs,
        [bool]$isDefaultFolder)
    
    
    $rights = New-Object -TypeName "System.Collections.ArrayList"
    $foldersForAllMbx = @()
    
    foreach ($MBX in $MBXs) {
        #Extracting the Name attribute for the mailbox
        $alias = (Get-Mailbox $MBX).Name.ToString()
        #Extracting the Primary SMTP Address for the mailbox
        $SMTP = (Get-Mailbox $MBX).PrimarySMTPAddress.ToString()
        #Getting all mailbox folders list
        if ($isDefaultFolder -eq $true) {
            [System.Collections.ArrayList]$folders = get-mailbox $MBX | Get-MailboxFolderStatistics | Where-Object FolderType -ne "User Created" | select Identity, @{Name = 'Alias'; Expression = { $alias } } , @{Name = 'SMTP'; Expression = { $SMTP } } 
        }
        else {
            [System.Collections.ArrayList]$folders = get-mailbox $MBX | Get-MailboxFolderStatistics | select Identity, @{Name = 'Alias'; Expression = { $alias } } , @{Name = 'SMTP'; Expression = { $SMTP } } 
        }
        $foldersForAllMbx += $folders

        #With below 2 command lines I am attempting to get the Top of Information Store folder permission as well in the mailbox.
            $MBRightsRoot = Get-MailboxFolderPermission -Identity "$MBX" -ErrorAction Stop
            $MBRightsRoot = $MBRightsRoot | Select FolderName, User, AccessRights, @{Name = 'SMTP'; Expression = { $SMTP } }
            $null = $rights.Add($MBRightsRoot)

    }
    
    
        
        
    #Adjusting the folder Identity values obtained by previous command, to comply with the Get-MailboxFolderPermission cmdlet required format. Getting the folder permissions as well.
    foreach ($folder in $foldersForAllMbx) {
        $foldername = $folder.Identity.ToString().Replace([char]63743, "/").Replace($folder.alias, $folder.SMTP + ":")
        try {
            $MBrights = Get-MailboxFolderPermission -Identity "$foldername" -ErrorAction Stop
            [System.Collections.ArrayList]$MBrights = $MBrights | Select FolderName, User, AccessRights, @{Name = 'SMTP'; Expression = { $SMTP } 
        }
                
            $null = $rights.Add($MBrights)
           
        }
        Catch {}
    }
    return ($rights)
}
    
# connect
Clear-Host
$Workloads = "exo"
Connect-O365PS $Workloads

# logging
$CurrentProperty = "Connecting to: $Workloads"
$CurrentDescription = "Success"
write-log -Function "Connecting to O365 workloads" -Step $CurrentProperty -Description $CurrentDescription 

$ts = get-date -Format yyyyMMdd_HHmmss
$ExportPath = "$global:WSPath\MailboxDiagnosticLogs_$ts"
mkdir $ExportPath -Force | out-null


$allMBX = Get-ExoMailbox -Filter "RecipientTypeDetails -eq 'UserMailbox' -or RecipientTypeDetails -eq 'SharedMailbox'" | select DisplayName, PrimarySmtpAddress, UserPrincipalName
Write-Host "Warning: Please keep in mind that the more mailboxes are selected, this will affect the performance of the script" -ForegroundColor Yellow
$choice = Read-Host "Please select the mailboxes that need to be checked (press Enter to display the list of mailboxes)"
$allMBXInitialCount = $allMBX.Count
[Array]$allMBX = ($allMBX | select DisplayName, PrimarySmtpAddress, UserPrincipalName | Out-GridView -PassThru -Title "Select one or more..").PrimarySmtpAddress
$allMBXSelectedCount = $allMBX.Count
    
If ($allMBXSelectedCount -eq 0) {
    # go to the menu or get again all mbx
}
    
Write-Host "Warning: Depending on the number of mailboxes selected, running the script to check all folders, might give a timeout" -ForegroundColor Yellow
#$choice = Read-Host "Do you want to check all folders or only default ones? Input '1' for 'All folders' or '2' for 'Default folders'"
$choice = Get-Choice -Options 'All Folders', 'Default Folders'   
if ($choice -eq "d") {
    $isDefaultFolder = $true
}
elseif ($choice -eq "a") {
    $isDefaultFolder = $false
}
    
$rights = Get-AllDefaultUserMailboxFolderPermissions -MBXs $allMBX -isDefaultFolder $isDefaultFolder

$ExportRights = $rights | % { $_ }

$ExportRights | Export-Csv $ExportPath\Mailbox_Folder_Permissions_$ts.csv -NoTypeInformation

<#
#Create the collection of sections of HTML

$TheObjectToConvertToHTML = New-Object -TypeName "System.Collections.ArrayList"

foreach ($mailbox in $allMBX)
{

    [string]$SectionTitle = "Information for the following mailbox: $($mailbox.PrimarySmtpAddress)"

    [string]$Description = "We take a look at the mailbox default folder permissions"

    $ExportRightsCurrentMbx = $ExportRights | ? SMTP -eq  $mailbox.PrimarySmtpAddress | select * -ExcludeProperty SMTP



    [PSCustomObject]$ListOfOriginalAndDecodedUrlsHtml = Prepare-ObjectForHTMLReport -SectionTitle $SectionTitle -SectionTitleColor "Red" -Description $Description -DataType "String" -EffectiveDataString " "

    $null = $TheObjectToConvertToHTML.Add($ListOfOriginalAndDecodedUrlsHtml)

}



#Build HTML report out of the previous HTML sections

[string]$FilePath = $ExportPath + "\DecodeSafeLinksUrl.html"

Export-ReportToHTML -FilePath $FilePath -PageTitle "Microsoft Defender for Office 365 Safe Links Decoder" -ReportTitle "Microsoft Defender for Office 365 Safe Links Decoder" -TheObjectToConvertToHTML $TheObjectToConvertToHTML

#Ask end-user for opening the HTMl report

$OpenHTMLfile = Read-Host "Do you wish to open HTML report file now?`nType Y(Yes) to open or N(No) to exit!"

if ($OpenHTMLfile.ToLower() -like "*y*") {

    Write-Host "Opening report...." -ForegroundColor Cyan

    Start-Process $FilePath

}

#endregion ResultReport

   

# Print location where the data was exported

Write-Host "`nOutput was exported in the following location: $ExportPath" -ForegroundColor Yellow 
#>

Read-Key
# Go back to the main menu
Start-O365TroubleshootersMenu