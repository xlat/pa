@echo off
::prepare VAR ENV PA_SHARED_CMD containing SHARED batch file that will be filled by the pa.pl script
set PA_SHARED_SUFFIX=%RANDOM%x
set PA_SHARED_CMD=%TEMP%\pa-set-env-%PA_SHARED_SUFFIX%.cmd
set PA_SHARED_SUFFIX=
if exist %PA_SHARED_CMD%  del /F /Q %PA_SHARED_CMD%
perl %~dp0\pa.pl %*
::if exist %PA_SHARED_CMD%  type %PA_SHARED_CMD%
if exist %PA_SHARED_CMD%  call %PA_SHARED_CMD%
if exist %PA_SHARED_CMD%  del /F /Q %PA_SHARED_CMD%
set PA_SHARED_CMD=