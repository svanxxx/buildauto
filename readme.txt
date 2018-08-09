run next command as administrator to enable running scripts in your system:

Set-ExecutionPolicy RemoteSigned
Set-ExecutionPolicy Unrestricted
Set-ExecutionPolicy bypass

Known Issues:
“get-wmiobject win32_process -computername” gets error “Access denied , code 0x80070005”
To resolve:
1.Launch "wmimgmt.msc"
2.Right-click on "WMI Control (Local)" then select Properties
3.Go to the "Security" tab and select "Security" then "Advanced" then "Add"
4.Select the user name(s) or group(s) you want to grant access to the WMI and click ok
5.Grant the required permissions, I recommend starting off by granting all permissions to ensure that access is given, then remove permissions later as necessary.
6.Ensure the "Apply to" option is set to "This namespace and subnamespaces"
7.Save and exit all prompts
8.Add the user(s) or group(s) to the Local "Distributed COM Users" group. Note: The "Authenticated Users" and "Everyone" groups cannot be added here, so you can alternatively use the "Domain Users" group.

From:https://stackoverflow.com/questions/14952833/get-wmiobject-win32-process-computername-gets-error-access-denied-code-0x8