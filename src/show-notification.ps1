<#
.SYNOPSIS
    Sends a Windows toast notification for Claude Code hooks.
.DESCRIPTION
    Uses the native WinRT toast notification API — zero dependencies.
    On first run, registers a Start Menu shortcut with the required
    AppUserModelID so that toast notifications are routed correctly.
.PARAMETER Title
    Title text shown on the first line of the toast.
.PARAMETER Message
    Body text shown on the second line of the toast.
.PARAMETER Sound
    Audio cue alias. Supported values:
      Default, IM, Mail, Reminder, SMS, Alarm, Silent.
    Prepended with "ms-winsoundevent:Notification." automatically.
.EXAMPLE
    powershell -File show-notification.ps1 -Title "Claude Code" -Message "Done" -Sound "Default"
.NOTES
    Part of the claude-notifier project — deployed to ~/.claude/scripts/
    by deploy.ps1 and invoked by Claude Code hooks.
#>

param(
    [string]$Title   = "Claude Code",
    [string]$Message = "Task completed",
    [string]$Sound   = "Default"
)

$ErrorActionPreference = "Stop"
$AppId = "ClaudeCode.Notifier"
$LogFile = "$env:TEMP\claude-notifier.log"

function Write-Log {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    "[$ts] $Msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# ═══════════════════════════════════════════════════════════════════════════
# One-time AppUserModelID registration
# ═══════════════════════════════════════════════════════════════════════════
# Windows requires a registered AppUserModelID for toast notifications from
# non-packaged (desktop) applications.  We create a Start Menu shortcut with
# the AppUserModelID property set via COM interop.  This is a one-time cost
# (~200 ms); subsequent invocations skip it entirely.

function Register-AppUserModelID {
    # Use the *user* Start Menu (no admin required), not the All Users one
    $programsDir  = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    $shortcutPath = Join-Path $programsDir "Claude Code Notification.lnk"

    if (Test-Path $shortcutPath) { return }

    if (-not (Test-Path $programsDir)) {
        New-Item -ItemType Directory -Path $programsDir -Force | Out-Null
    }

    try {
        # Create the shortcut via WScript.Shell
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($shortcutPath)
        $sc.TargetPath       = (Get-Command powershell.exe).Source
        $sc.Arguments        = '-NoProfile -Command "exit"'
        $sc.WorkingDirectory = "%USERPROFILE%"
        $sc.Save()

        # Use C# P/Invoke to write the AppUserModelID property on the .lnk
        $csharp = @'
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("00021401-0000-0000-C000-000000000046")]
internal class ShellLink { }

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("000214F9-0000-0000-C000-000000000046")]
internal interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszFile, int cchMaxPath, out IntPtr pfd, uint fFlags);
    void GetIDList(out IntPtr ppidl);
    void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszFile, int cchMaxName);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszDir, int cchMaxPath);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszArgs, int cchMaxPath);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
    void GetHotkey(out ushort pwHotkey);
    void SetHotkey(ushort wHotkey);
    void GetShowCmd(out int piShowCmd);
    void SetShowCmd(int iShowCmd);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszIconPath, int cchIconPath, out int piIcon);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
    void Resolve(IntPtr hwnd, uint fFlags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
}

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
internal interface IPropertyStore {
    uint GetCount(out uint cProps);
    uint GetAt(uint iProp, out PROPERTYKEY pkey);
    uint GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
    uint SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
    uint Commit();
}

[StructLayout(LayoutKind.Sequential)]
internal struct PROPERTYKEY {
    public Guid fmtid;
    public uint pid;
}

[StructLayout(LayoutKind.Explicit)]
internal struct PROPVARIANT {
    [FieldOffset(0)] public ushort vt;
    [FieldOffset(8)] public IntPtr pwszVal;
}

public static class ShortcutHelper {
    private static readonly PROPERTYKEY AppUserModelIDKey = new PROPERTYKEY {
        fmtid = new Guid("{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}"),
        pid = 5
    };

    public static void SetAppUserModelID(string shortcutPath, string appId) {
        var shellLink = (IShellLinkW)new ShellLink();
        var persistFile = (System.Runtime.InteropServices.ComTypes.IPersistFile)shellLink;
        persistFile.Load(shortcutPath, 0);

        var propertyStore = (IPropertyStore)shellLink;
        var propKey = AppUserModelIDKey;
        var handle = GCHandle.Alloc(appId, GCHandleType.Pinned);
        try {
            var pv = new PROPVARIANT { vt = 31, pwszVal = handle.AddrOfPinnedObject() };
            propertyStore.SetValue(ref propKey, ref pv);
            propertyStore.Commit();
        }
        finally { handle.Free(); }

        persistFile.Save(shortcutPath, false);
    }
}
'@
        Add-Type -TypeDefinition $csharp -ErrorAction Stop
        [ShortcutHelper]::SetAppUserModelID($shortcutPath, $AppId)
    }
    catch {
        Write-Warning "Failed to register AppUserModelID: $_"
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Toast notification
# ═══════════════════════════════════════════════════════════════════════════

function Show-Toast {
    param([string]$Title, [string]$Message, [string]$SoundAlias)

    try {
        # Load WinRT types (may throw if not on a supported Windows version)
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        # Xml-escape the user-provided strings
        $safeTitle   = [System.Security.SecurityElement]::Escape($Title)
        $safeMessage = [System.Security.SecurityElement]::Escape($Message)

        $audio = if ($SoundAlias -eq "Silent") {
            "<audio silent='true' />"
        }
        else {
            "<audio src='ms-winsoundevent:Notification.$SoundAlias' />"
        }

        $xmlText = @"
<toast duration="short">
    <visual>
        <binding template="ToastGeneric">
            <text>$safeTitle</text>
            <text>$safeMessage</text>
        </binding>
    </visual>
    $audio
</toast>
"@

        $xmlDoc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xmlDoc.LoadXml($xmlText)

        $toast = New-Object Windows.UI.Notifications.ToastNotification $xmlDoc
        $toast.ExpirationTime = [DateTime]::Now.AddMinutes(1)

        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
        Write-Log "TOAST OK: Title='$Title' Message='$Message' Sound='$SoundAlias'"
    }
    catch {
        Write-Log "TOAST FAIL: $_"
        try { [Console]::Beep(800, 200) } catch { }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

Write-Log "START: Title='$Title' Message='$Message' Sound='$Sound'"
Register-AppUserModelID
Show-Toast -Title $Title -Message $Message -SoundAlias $Sound
Write-Log "END"
