<#
    .SYNOPSIS
		Takes VMs from vCenter and imports them in PRTG

    .DESCRIPTION

    .NOTES  
        Author     : LeSnowTiger
        Version    : 1.0     
    
#>

Param(
    [string] $PRTGServer = 'prtg.example.com',
	[string] $PRTGUserName = 'apiuser',
	[string] $Passhash = 'PWHASHHERE',
	[string] $VIServer = 'vcenter.example.com'
)

function Add-ServertoPRTG{
    Param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline=$true
        )]
        $VM,
        [Parameter(Mandatory=$true)]
        $Tag,
        [string] $Template = "_Win_Default",
        [string] $Icon = "C_OS_Win.png",
        [switch] $IsLinux
    )
    


    #Check if VM is Prod
    if($VM.Name -match "VM.*PROD[0-9][0-9]"){
        #Get Correct Group in PRTG
        switch($Tag.Name){
            "IT"			{
							    if($IsLinux){
								    $Destination = Get-Probe "Probe01" | Get-Group "VM" | Get-Group "Linux"
							    }else{
								    $Destination = Get-Probe "Probe01" | Get-Group "VM" | Get-Group "Windows"
							    }
							}
            "Citrix"        {$Destination = Get-Probe "Probe01" | Get-Group "Citrix"}
            "Network"       {$Destination = Get-Probe "Probe02"}
            "Environmental" {$Destination = Get-Probe "Probe02" | Get-Group "Environmental Monitoring"}
            default         {Throw "Tag ($($Tag.Name)) does not exist."}
        }
    }
    #Check if VM is Test
    elseif($VM.Name -match "VM.*TEST[0-9][0-9]"){
        $Destination = Get-Probe "Test Monitoring" 
    }
    else{
        Throw "VM Name is neither Prod nor Test"
    }

	#Get Device template
    $DeviceTemplatetoUse = Get-DeviceTemplate $Template
    $Device = $Destination | Add-Device -Name ($VM.Name + ".example.com") -Host ($VM.Name + ".example.com") -AutoDiscover -Template ($DeviceTemplatetoUse)
    #Set Device Icon 
    $Device | Set-ObjectProperty -RawProperty 'deviceicon_' -RawValue $Icon -Force

    #Start sleep so PRTG does not get overloaded
    Start-Sleep -Seconds 5
}



#Check if PRTG API is installed and load or install it
if(!(Get-Module prtgapi)){
	try{
		Import-Module prtgapi -ErrorAction Stop
	}
	catch{
		Install-Package PrtgAPI -Scope CurrentUser
	}
}

#Check if powercli are imported
if(!(Get-Module "vmware.powercli")){
    Import-Module "vmware.powercli"
}

try{
    #Create Backup from PRTG Config File
    Copy-Item -Path "PATHTOPRTGCONFIG\PRTG Configuration.dat" `
    -Destination "PATHTOPRTGBACKUP\Configuration Auto-Backups\$(Get-Date -Format "yyyy-MM-dd")_PRTGConfig.dat"   

    #Conncet with vCenter
    Connect-VIServer -Server $VIServer -Force

    #Connect with PRTG
    Connect-PrtgServer $PRTGServer (New-Credential $PRTGUserName $Passhash) -PassHash -Verbose -Force

    #Get all turned on WindowsServer from vCenter
    $VMs = Get-VM | Where-Object {$_.Guest.OSFullName -like "*Windows Server*"}
    $VMs = $VMs | Where-Object {$_.PowerState -eq "PoweredOn"}
	
	#Loop through every vm and check if it already exist
    try{
        foreach($VM in $VMs){
            if(!(Get-Device ($VM.Name + ".example.com"))){
                try{
                    $Tag = $VM | Get-TagAssignment -Category Owner | Select-Object -ExpandProperty Tag
                    $VM | Add-ServertoPRTG -Tag $Tag
                }catch{
                    Write-Host $_.Exception.Messag
                }
            }
        }
    }catch{
        Write-Host $_.Exception.Message
    }


    #Get all Linux Server
    $VMs = Get-VM | Where-Object {$_.Guest.OSFullName -like "*linux*" -or $_.Guest.OSFullName -like "*centos*" -or $_.Guest.OSFullName -like "*red hat*" -or $_.Guest.OSFullName -like "*Photon OS*" -or $_.Guest.OSFullName -like "*FreeBSD*"}
    $VMs = $VMs | Where-Object {$_.PowerState -eq "PoweredOn"}
    
	#Loop through every vm and check if it already exist
	try{
        foreach($VM in $VMs){
            if(!(Get-Device ($VM.Name + ".example.com"))){
                $Tag = $VM | Get-TagAssignment -Category Owner | Select-Object -ExpandProperty Tag
                $VM | Add-ServertoPRTG -Tag $Tag -IsLinux -Template "_Linux_V1" -Icon "C_OS_Linux.png"
            }
        }
    }catch{
        Write-Host $_.Exception.Message
    }
}
catch{
    #Placeholder
}finally{
    Disconnect-VIServer -Confirm:$false
    Disconnect-PrtgServer
}