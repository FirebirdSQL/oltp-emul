Need only for WINDOWS.

This folder contain compressed binary of 'curl' for Windows 64 bit.
This utility is used in {OLTP_ROOT}\util\oltp-scheduled\oltp-scheduled.bat scenario
for two purposes:
1) download fresh FB snapshot from official site;
2) send e-mail with compressed snapshot for possible quick access to it later.

Extraction from .zip files will be done by %systemroot%\system32\cscript utility
(temporary .vbs script will be generated and applied every time).
