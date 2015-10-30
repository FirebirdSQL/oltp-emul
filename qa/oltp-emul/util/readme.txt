Note only for running test script from WINDOWS machines.
====

This folder is added to `PATH` environment variable in oltp_isql_run_worker.bat.
Utility 'mtee.exe' ( http://www.commandline.co.uk/mtee/ ) can be placed in this 
folder in order to write timestamp in the error logs during test work.

Also you can put here console utility postie.exe in order to send report to desired e-mail.
Sample of command arguments for this executable can be seen in oltpNN_config.win (Windows only).

Command in oltp_isql_run_worker.bat that uses mtee:

if .%use_mtee%.==.1. (
  set run_isql=%fbc%\isql %dbconn% -now -q -n -pag 9999 -i %sql% %dbauth% 2^>^&1 1^>^>%log% ^| mtee /t/+ %err% ^>nul
) else (
  . . .
)
