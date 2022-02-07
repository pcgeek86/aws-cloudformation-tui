using namespace System.Management.Automation.Host

function Move-Cursor {
  [CmdletBinding()]
  param ([int] $X, [int] $Y)
  $Host.UI.RawUI.CursorPosition = @{ X = $X; Y = $Y }
}

class CloudFormationStackList {
  [int] $Width = 35
  [object[]] $StackList
  [int] $SelectedStack = 0

  [void] DrawBox() {    
    $Height = $global:Host.UI.RawUI.BufferSize.Height
    Move-Cursor -X 0 -Y 0
    Write-Host -NoNewline -Object ("`e[38;2;222;165;80m`u{2554}{0}`u{2557}`e[0m" -f ("`u{2550}"*($this.Width-2)))
    1..($Height-2) | % {
      Move-Cursor -X 0 -Y $PSItem
      Write-Host -NoNewline -Object ("`e[38;2;222;195;80m`u{2551}{0}`u{2551}`e[0m" -f (' '*($this.Width-2)))
    }
    Move-Cursor -X 0 -Y ($Height-1)
    Write-Host -NoNewline -Object ("`e[38;2;222;165;80m`u{255a}{0}`u{255d}`e[0m" -f ("`u{2550}"*($this.Width-2)))
  }

  [void] RefreshStacks() {
    $this.StackList = Get-CFNStack
  }

  CloudFormationStackList() {
    $this.RefreshStacks()
  }

  [void] FixSelectedItem() {
    if ($this.SelectedStack -ge ($this.StackList.Count-1)) { $this.SelectedStack = $this.StackList.Count - 1; }
  }

  [void] NavigateUp() {
    #Add-Content -Path "$PSCommandPath.Log" -Value ('{0}: Selected stack ID is: {1}' -f (Get-Date -Format s), $this.SelectedStack)
    if ($this.SelectedStack -eq 0 -or !$this.StackList) { return }
    $this.SelectedStack -= 1
    $this.ListStacks()
  }

  [void] NavigateDown() {
    if ($null -eq $this.StackList) { return }
    $this.SelectedStack += 1
    $this.ListStacks()
  }

  [void] ListStacks() {
    $this.FixSelectedItem()
    Add-Content -Path "$PSCommandPath.Log" -Value ('{0}: Selected stack ID is: {1}' -f (Get-Date -Format s), $this.SelectedStack)
    $LineNumber = 2
    Move-Cursor -X 3 -Y $LineNumber
    #$this.SelectedStack = $this.StackList.Count -gt 0 ? 0 : $null
    $FailedStates = @(
      'DELETE_FAILED'
      'CREATE_FAILED'
      'ROLLBACK_FAILED'
      'UPDATE_FAILED'
      'UPDATE_ROLLBACK_FAILED'
      'IMPORT_ROLLBACK_FAILED'
      'ROLLBACK_COMPLETE'
    )
    foreach ($Stack in $this.StackList) {
      if ($Stack.StackName -eq $this.StackList[$this.SelectedStack].StackName) {
         Write-Host -NoNewLine -Object "`e[7m"
      }
      $Text = $Stack.StackStatus.Value -in $FailedStates ? "`e[38;2;230;0;0m`u{f663}`e[38;2;255;255;255m" : "`e[38;2;0;220;0m`u{f65f}`e[38;2;255;255;255m"
      $Text += ' {0}' -f $Stack.StackName.SubString(0,25)
      Write-Host -NoNewline -Object $Text
      if ($Stack -eq $this.StackList[$this.SelectedStack]) {
        Write-Host -NoNewLine -Object "`e[27m"
      }
      $LineNumber += 1
      Move-Cursor -X 3 -Y $LineNumber
    }
  }

  [void] Render() {
    $this.DrawBox()
    $this.ListStacks()
  }
  [void] Delete() {
    Remove-CFNStack -StackName $this.StackList[$this.SelectedStack].StackName -Force
  }
}

class StackDetails {
  [void] Render() {

  }
}

class TerminalApp {
  [string] $CurrentAWSRegion = 'us-west-2'
  [CloudFormationStackList] $StackList
  [bool] $ShouldRender = $true
  [Size] $WindowSize = $global:Host.UI.RawUI.WindowSize

  [void] DrawBoxes() {
    $global:Host.UI.RawUI.CursorPosition = @{ X = 0; Y = 0 }
    #Write-Host -Object (''*($global:Host.UI.RawUI.BufferSize.Width)) -NoNewline
  }

  [void] DrawTime() {
    $Text = (Get-Date -Format s)
    $ColoredText = "`e[48;2;0;160;240;m`e[38;2;210;255;255m{0}`e[0m" -f $Text
    Move-Cursor -Y ($global:Host.UI.RawUI.BufferSize.Height-1) -X ($global:Host.UI.RawUI.BufferSize.Width-$Text.Length)
    Write-Host -NoNewline -Object $ColoredText
  }

  [void] CreateCloudFormationStack() {
    $Template = @'
Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.55.0.0/16
'@
    $StackName = [System.Text.Encoding]::UTF8.GetString((1..35 | % { Get-Random -InputObject (65..90) }))
    New-CFNStack -StackName $StackName -TemplateBody $Template
  }

  [void] WindowResized() {
    if ($this.WindowSize -ne $global:Host.UI.RawUI.WindowSize) {
      Clear-Host
      $this.ShouldRender = $true
      $this.WindowSize = $global:Host.UI.RawUI.WindowSize
    }
  }

  [void] Start() {

    [System.Console]::CursorVisible = $false
    Clear-Host
    $this.DrawBoxes()

    $this.StackList = [CloudFormationStackList]::new()

    while ($true) {
      Start-Sleep -Milliseconds 40

      if ($this.ShouldRender) {
        $this.StackList.Render()
        $this.DrawTime()
        $this.ShouldRender = $false
      }
      $Key = $global:Host.UI.RawUI.KeyAvailable ? $global:Host.Ui.RawUI.ReadKey('NoEcho,IncludeKeyDown') : $null
    
      if ($Key) {
        switch ($Key.VirtualKeyCode) {
          38 {
            $this.StackList.NavigateUp()
            break
          }
          40 {
            $this.StackList.NavigateDown()
            break
          }
          46 { # Delete key
            $this.StackList.Delete()
            break
          }
          68 {
            if ($Key.ControlKeyState -eq 8) {
              $this.CreateCloudFormationStack()
              $this.ShouldRender = $true
            }
            break
          }
          82 { # CTRL + R
            if ($Key.ControlKeyState -eq 8) {
              $this.StackList.RefreshStacks()
              Clear-Host
              $this.ShouldRender = $true
            }
          }
          default {
            if ($Key.Character -ne "`u{0000}") {
              
            }
          }
        }
        Add-Content -Path "$PSCommandPath.Log" -Value ('{0}: {1}' -f (Get-Date -Format s), ($Key | ConvertTo-Json -Compress))
      }
    
      $this.WindowResized()

      Add-Content -Path "$PSCommandPath.Log" -Value ('{0}: Rendered' -f (Get-Date -Format s))
    }
  }
}

[TerminalApp]::new().Start()
