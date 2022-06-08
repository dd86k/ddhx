@ECHO OFF

FOR /F "tokens=* USEBACKQ" %%F IN (`git describe --dirty`) DO (
	SET GIT_DESCRIPTION=%%F
)
ECHO GIT_DESCRIPTION: %GIT_DESCRIPTION%

SET OUT=src\gitinfo.d

ECHO // NOTE: This file was generated automatically. > %OUT%
ECHO module gitinfo^; >> %OUT%
ECHO /// Project current version described by git. >> %OUT%
ECHO enum GIT_DESCRIPTION = "%GIT_DESCRIPTION%"^; >> %OUT%