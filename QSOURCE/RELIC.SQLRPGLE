
       // Relic is an open-source package manager created by Liam Allan.
       // It may also go by these names:
       //   - Relic Package Manager
       //   - DWNPKG

       Ctl-Opt DftActGrp(*No) ActGrp(*NEW);

       dcl-pr Cmd int(10) extproc('system');
         cmdstring pointer value options(*string);
       end-pr;
       Dcl-s errmsgid char(7) import('_EXCP_MSGID');

       Dcl-Pr printf Int(10) ExtProc('printf');
         format Pointer Value Options(*String);
       END-PR;

       //*********************************************

       dcl-pr OpenFile pointer extproc('_C_IFS_fopen');
         *n pointer value;  //File name
         *n pointer value;  //File mode
       end-pr;

       dcl-pr ReadFile pointer extproc('_C_IFS_fgets');
         *n pointer value;  //Retrieved data
         *n int(10) value;  //Data size
         *n pointer value;  //Misc pointer
       end-pr;
       
       dcl-pr WriteFile pointer extproc('_C_IFS_fwrite');
         *n pointer value;  //Write data
         *n int(10) value;  //Data size
         *n int(10) value;  //Block size
         *n pointer value;  //Misc pointer
       end-pr;

       dcl-pr CloseFile extproc('_C_IFS_fclose');
         *n pointer value;  //Misc pointer
       end-pr;

       Dcl-C CMD_LEN 300;
    
       Dcl-Ds File_Temp Qualified Template;
         PathFile char(CMD_LEN);
         RtvData char(CMD_LEN);
         OpenMode char(5);
         FilePtr pointer inz;
       End-ds;
       
       Dcl-Ds gBuildFile  LikeDS(File_Temp);
       Dcl-Ds gStreamFile LikeDS(File_Temp);

       //*********************************************

       Dcl-C gRepoZip  'REPO.ZIP';
       Dcl-S gUser     Char(10)     Inz(*User);

       Dcl-S IFSLINK   Varchar(256); //Ending with /
       Dcl-s INTOLIB   Char(10);

       Dcl-S gSTMF  Ind;      //*On if output to streamfile
       Dcl-S gMode  Char(10); //Used for scanning build file
       Dcl-S gFails Int(3);

       Dcl-Ds gPackage Qualified;
         Name Varchar(32);
         Ver  Varchar(10);
       End-Ds;

       //*********************************************

       Dcl-Pi RELIC;
         pZIPLoc      Char(128) Const;
         pNewDir      Char(50)  Const;
         pLib         Char(10)  Const;
         pFetchOption Char(10)  Const;
         pLogOption   Char(10)  Const; //*DSP, *STMF
       END-PI;

       *InLR = *On;

       If (%Parms < 5);
         Print('Five parameters required.');
         Return;
       ENDIF;
        
       If (pFetchOption = '*FETCH');
         If (pZIPLoc = *Blank);
           Print('Location cannot be blank with *FETCH mode.');
           Return;
         Endif;
       Endif;
       
       If (pLib = *Blank);
         Print('Library cannot be blank.');
         Return;
       ENDIF;
       
       gSTMF = (pLogOption = '*STMF');

       //*********************************************

       INTOLIB  = pLib;
       IFSLINK  = '';

       gFails   = 0;
       
       If (gSTMF);
         gSTMF = LOG_Prepare();
         If (gSTMF = *Off);
           Print('Failed to create log with PLOG(*STMF).');
         Endif;
       Endif;

       If (BUILD_Prepare());
         If (gFails = 0);
           Print('Built from ' + %Trim(pZIPLoc) + ' sucessfully.');
           If (pFetchOption <> '*BUILDONLY');
             BUILD_Command('RMDIR DIR(''' + IFSLINK + ''') SUBTREE(*ALL)');
           Endif;
         Else;
           Print('Attempted to build..');
           Print(' > error count: ' + %Char(gFails));
           Print(' > directory not deleted');
         ENDIF;
       Endif;
       
       If (gSTMF);
         LOG_Close();
       Endif;
       
       Return;

       //*********************************************

       Dcl-Proc Print;
         Dcl-Pi Print;
           pValue Char(128) Value;
         END-PI;
        
         pValue = %TrimR(pValue) + x'25';
         
         If (gSTMF);
           WriteFile(%Addr(pValue)
                    :%Len(%TrimR(pValue))
                    :1
                    :gStreamFile.FilePtr);
         Else;
           printf(%Trim(pValue));
         Endif;
         
       End-Proc;

       //*********************************************

       //FILE_Download will now just
       //download the repo ZIP to the IFS.
       Dcl-Proc FILE_Download;
         Dcl-Pi *N Ind;
           pLocation Varchar(128) Const; //File
         END-PI;

         Dcl-S lFile SQLTYPE(BLOB_FILE);

         //Will download to Current Directory
         lFile_Name = IFSLINK + gRepoZip;
         lFile_NL   = %Len(%TrimR(lFile_Name));
         lFile_FO   = SQFOVR;

         Exec SQL
           SELECT SYSTOOLS.HTTPGETBLOB(:pLocation, '') lFile_DATA
           INTO :lFile
           FROM SYSIBM.SYSDUMMY1;

         Return (SQLSTATE = '00000');

       END-PROC;

       //*********************************************

       Dcl-Proc BUILD_Prepare;
         Dcl-Pi *N Ind End-Pi;

         Dcl-S lBuild   Varchar(CMD_LEN);
         Dcl-S lComment Ind;
         Dcl-S lComTxt  Char(2);

         gPackage.Name = %Trim(pNewDir);
         gPackage.Ver  = '1';

         Select;

           // Only download if needed; allow for local build-only
           When (pFetchOption = '*FETCH');
             //Download ZIP
             If (FILE_Download(%Trim(pZIPLoc)) = *Off);
               Print('Failed to download ZIP.');
               Return *Off;
             Else;
               Print('ZIP downloaded..');
             ENDIF;

             //Extract the ZIP file
             BUILD_Command('QSH CMD(''jar xf ' + IFSLINK + gRepoZip + ''')');
             BUILD_Command('RMVLNK OBJLNK(''' + IFSLINK + gRepoZip + ''')');

           // Use *buildonly if ZIP already exists.
           When (pFetchOption = '*BUILDONLY');
             Print('Not downloading ZIP (*BUILDONLY)');

         ENDSL;

         //Use the new folder incase it extracts into a folder
         If (pNewDir <> *Blank);
           IFSLINK += %Trim(pNewDir) + '/';
         ENDIF;

         //Process the build file
         gBuildFile.PathFile = IFSLINK + 'build.txt' + x'00';
         gBuildFile.OpenMode = 'r' + x'00';
         gBuildFile.FilePtr  = OpenFile(%addr(gBuildFile.PathFile)
                                       :%addr(gBuildFile.OpenMode));

         If (gBuildFile.FilePtr = *null);
           Print('Failed to read build file.');
           Return *Off;
         EndIf;

         //When lComment = *On, ignore line
         lComment = *Off;

         dow  (ReadFile(%addr(gBuildFile.RtvData)
                       :%Len(gBuildFile.RtvData)
                       :gBuildFile.FilePtr) <> *null);
                       
           gBuildFile.RtvData = %Trim(gBuildFile.RtvData);
           If (%Subst(gBuildFile.RtvData:1:1) = x'25');
             Iter;
           ENDIF;

           gBuildFile.RtvData = %xlate(x'00':' ':gBuildFile.RtvData);//End of record null
           gBuildFile.RtvData = %xlate(x'25':' ':gBuildFile.RtvData);//Line feed (LF)
           gBuildFile.RtvData = %xlate(x'0D':' ':gBuildFile.RtvData);//Carriage return (CR)
           gBuildFile.RtvData = %xlate(x'05':' ':gBuildFile.RtvData);//Tab
           lBuild = %Trim(gBuildFile.RtvData);

           If (lBuild = *Blank);
             Iter;
           ENDIF;

           If (%Len(lBuild) > 2);
             lComTxt = %Subst(lBuild:1:2);
             Select;
               When (lComTxt = '//');
                 Iter;
               When (lComtxt = '/*');
                 lComment = *On;
             ENDSL;

             lComTxt = %Subst(lBuild:%Len(lBuild)-1:2);
             If (lComTxt = '*/');
               lComment = *Off;
               Iter;
             ENDIF;
           ENDIF;

           If (lComment = *On);
             Iter;
           ENDIF;

           Select;

             When (lBuild = 'dirs:');
               Print('Directories directive not supported in build file.');

             When (lBuild = 'files:');
               Print('Files directive not supported in build file.');

             When (lBuild = 'name:');
               gMode = '*NAME';

             When (lBuild = 'version:');
               gMode = '*VER';

             when (lBuild = 'licenses:');
               Print('License mode currently not supported.');
               gMode = '*LIC';

             When (lBuild = 'build:');
               gMode = '*BUILD';

             Other;
               Select;
                 When (gMode = '*NAME');
                   gPackage.Name = %Trim(lBuild);

                 When (gMode = '*VER');
                   gPackage.Ver = %Trim(lBuild);

                 When (gMode = '*BUILD');
                   BUILD_Command(lBuild);

               ENDSL;

           ENDSL;

           gBuildFile.RtvData = ' ';
         enddo;

         CloseFile(gBuildFile.FilePtr);

         Return *On;
       End-Proc;

       //*********************************************

       Dcl-Proc BUILD_Command;
         Dcl-Pi *N;
           pCmd Char(CMD_LEN) Value;
         END-PI;

         pCmd = %ScanRpl('&INTOLIB':%Trim(INTOLIB):pCmd);
         pCmd = %ScanRpl('&DIR/':%Trim(IFSLINK):pCmd);
         pCmd = %ScanRpl('&NAME':%Trim(gPackage.Name):pCmd);
         pCmd = %ScanRpl('&VER':%Trim(gPackage.Ver):pCmd);
         pCmd = %ScanRpl('&USER':%Trim(gUser):pCmd);

         Monitor;
           If (Cmd(pCmd) = 1);
             gFails += 1;
             Print(%Subst(pCmd:1:52) + ' ...');
             Print('> ' + errmsgid);
             Print(*Blank);
           ENDIF;
         On-Error *All;
           gFails += 1;
           Print(%Subst(pCmd:1:52) + ' ...');
           Print('> Caused program crash');
           Print(*Blank);
         Endmon;
       END-PROC;

       //*********************************************
       
       Dcl-Proc LOG_Prepare;
         Dcl-Pi *N Ind End-Pi;
         gStreamFile.PathFile = IFSLINK + %char(%timestamp) + x'00';
         gStreamFile.OpenMode = 'ab' + x'00';
         gStreamFile.FilePtr  = OpenFile(%addr(gStreamFile.PathFile)
                                        :%addr(gStreamFile.OpenMode));
                                        
         Return (gStreamFile.FilePtr <> *null);
         //Returns *on if it failed to open
       End-Proc;

       //*********************************************
       
       Dcl-Proc LOG_Close;
         CloseFile(gStreamFile.FilePtr);
       End-Proc;
