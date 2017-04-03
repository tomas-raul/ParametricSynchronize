program ParametricSynchronize_PreCompiler;
uses
   sysutils,
   classes,
   strutils,
   typinfo,
   fileutil,
   ucmdline,
   StringUtils,
   uIOFile_v4,
   regexpr,
   SuperObject;

type
  tParam =
  record
    Name : string;
    Typ  : string;
  end;

  tMethod =
    record
      Name : string;
      Params : array of tParam;
    end;

  tMethods = array of tMethod;

var
  InputFileName : string;
  PropertyDefinitionFile : string;
  MethodDefinitionFile : string;
  MethodImplementationFile : string;

  Class_Name : string; // name of class for which we generate, or class can be selected as class_PS flag

  MethodFlagName : string; // defaults to PS - so then method should be flaged as gen_PS (when more than one object, could be other for second objects)

  Default_Method_Suffix : string;
//  Switches

  Methods : tMethods;

procedure InitParameters;
begin
  MethodFlagName := getOptionS('mfn','Method-Flag-Name','compile methods tag with {gen_<Method-Flag-Name>}','PS');
  Class_Name := getOptionS('cn','Class-Name','to which class generated methods belongs, or class can be selected as class_<Method-Flag-Name> flag','');
  if Class_Name <> '' then Class_Name := Class_Name + '.';
  PropertyDefinitionFile := getOptionS('pdf','Property-Definition-File','name of needed variable definition .inc file, default <InputFileName>+_<Method-Flag-Name>_prop.inc','');
  MethodDefinitionFile := getOptionS('mdf','Method-Definition-File','when use .inc file for generated interface, this is filename for it, default <InputFileName>+_<Method-Flag-Name>_def.inc','');
  MethodImplementationFile := getOptionS('mif','Method-Implementation-File','when use .inc file for implementation, this is filename for it, default <InputFileName>+_<Method-Flag-Name>_impl.inc','');
  Default_Method_Suffix := getOptionS('dms','Default-Method-Suffix','default suffix for generated multi task methods f.e.: Write->Write_<Default-Method-Suffix>','_Synchronized');

  InputFileName := getFinalS('filename','input file for compilation','');

  if getOptionB('h','help','print help string - this list',false) then
  begin
     Writeln();
     Writeln(getHelpString);
     Halt();
  end;
  PropertyDefinitionFile := getOptionS('pdf','Property-Definition-File','name of needed variable definition .inc file, default <InputFileName>+_<Method-Flag-Name>_prop.inc',ChangeFileExt(InputFileName,'_'+MethodFlagName+'_prop.inc'));
  MethodDefinitionFile := getOptionS('mdf','Method-Definition-File','when use .inc file for generated interface, this is filename for it, default <InputFileName>+_<Method-Flag-Name>_def',ChangeFileExt(InputFileName,'_'+MethodFlagName+'_def.inc'));
  MethodImplementationFile := getOptionS('mif','Method-Implementation-File','when use .inc file for implementation, this is filename for it, default <InputFileName>+_<Method-Flag-Name>_impl',ChangeFileExt(InputFileName,'_'+MethodFlagName+'_impl.inc'));
end;

procedure WriteParameters;
var tp : string;
begin
  Writeln('Input file                       : ' + InputFileName);

  Writeln('Property definition .inc file    : ' + PropertyDefinitionFile);
  Writeln('Method definition .inc file      : ' + MethodDefinitionFile);
  Writeln('Method implementation .inc file  : ' + MethodImplementationFile);
  Writeln;
  Writeln('Method selection flag            : ' + MethodFlagName);
  Writeln('Name of class                    : ' + Class_Name);
  Writeln('Default method suffix            : ' + Default_Method_Suffix);
  Writeln;


end;

var input : string;
    output : string;
    inter : string;
    impl : string;


procedure LoadDataFromSource(const filename : string);
var input : string;

  procedure FindIncludes(const str : string);
  var
     RE: TRegExpr;
     fn : string;
     newfn : string;
  begin
    RE := TRegExpr.Create;
    try
    	RE.Expression := '{\$(I|INCLUDE)[ ]+([\w\.\\]+)}';
        RE.ModifierG := false;
        RE.ModifierI := true;
//        Writeln('Running RE on string('+IntToStr(length(str))+')');
    	if RE.Exec(str) then
        begin
    		repeat
                  fn := RE.Match[2];

                  newfn := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFilePath(filename)) + fn);
//                  Writeln('Found $I : ' + fn + ' which should be ' + newfn);
                  if (fn <> PropertyDefinitionFile) and (fn <> MethodDefinitionFile) and (fn <> MethodImplementationFile) then
                  LoadDataFromSource(newfn);
    		until not RE.ExecNext;
    	end;
    finally
    	RE.Free;
    end;
  end;

  procedure FindClassName(const str : string);
  var
     RE: TRegExpr;
     cn : string;
  begin
    if Class_Name <> '' then Exit;
    RE := TRegExpr.Create;
    try
    	RE.Expression := '([a-z_1-90]+)[ ]*=[ ]*class(\([a-z_1-90]+\)){0,1}[ ]*\{class_'+MethodFlagName+'\}';
        RE.ModifierG := false;
        RE.ModifierI := true;
//        Writeln('Running RE on string('+IntToStr(length(str))+')');
    	if RE.Exec(str) then
        begin
    		repeat
                  cn := RE.Match[1];
                  Writeln('Found class name : ' + cn);
                  Class_Name := cn + '.';
    		until not RE.ExecNext;
    	end;
    finally
    	RE.Free;
    end;
  end;

  procedure FindMethods(const str : string);
  var
     RE, REp: TRegExpr;
     fn, params, param : string;
     mn : string;
     method : string;
     par : tParam;
     meth : tMethod;

     procedure AddParam(par : tParam);
     begin
        setLength(meth.Params,length(meth.Params)+1);
        meth.Params[high(meth.Params)] := par;
     end;

     procedure AddMethod(meth : tMethod);
     begin
       setLength(methods,length(methods)+1);
       methods[high(methods)] := meth;
     end;

  begin
    RE := TRegExpr.Create;
    RE.Expression := 'procedure ([a-z_1-90]*)[ ]*(\((.*)\)){0,1}[ ]*;[ ]*\{gen_'+MethodFlagName+'\}';
    REp := TRegExpr.Create;
    REp.Expression:='((const|var)[ ]){0,1}[ ]*([a-z_]+)[ ]*:[ ]*([a-z_]+);';
    try
        RE.ModifierG := false;
        RE.ModifierI := true;
        REp.ModifierG := false;
        REp.ModifierI := true;
    	if RE.Exec(str) then
        begin
    		repeat
                  method := '';
                  SetLength(meth.Params,0);
                  mn := RE.Match[1];
                  params := RE.Match[3];
                  params := ReplaceStr(params,#13,'');
                  params := ReplaceStr(params,#10,'');
                  params := ReplaceStr(params,'  ',' ');
                  if params <> '' then params += ';';

                  meth.Name:=mn;

                  method += mn + '(';
                  if REp.Exec(params) then
                  begin
                     repeat
                       method += REp.Match[4] + ',';
                       par.Name:=REp.Match[3];
                       par.Typ:= REp.Match[4];
                       AddParam(par);
                     until not REp.ExecNext;
                     method := copy(method,1,length(method)-1);
                  end;
                  method += ');';
                  writeln('Found method : '+method);
                  AddMethod(Meth);

    		until not RE.ExecNext;
    	end;
    finally
        REp.Free;
    	RE.Free;
    end;
  end;

begin
  Writeln('Loading ' + filename);
  input := getFile(filename);
  if input = '' then
  begin
     Writeln('Input file ' + filename + ' not found or empty, halt..');
     Halt;
  end;

  FindClassName(input);
  FindMethods(input);
  FindIncludes(input);

end;

procedure Generate_Property_Definition();
var i : integer;
    meth : tMethod;
    p : integer;
    par : tParam;
    par_str : string;
    res : string;
    fn : string;

begin
   res := '';
   for i := low(methods) to high(methods) do
   begin
      meth := methods[i];
      par_str := '';
      if length(meth.Params) > 0 then
      begin
         for p := low(meth.Params) to high(meth.Params) do
         begin
            par := meth.Params[p];
            par_str += ' _PS' + Class_Name + '_' + meth.Name + '_' + par.Name + ' : ' + par.Typ + '; ' + LineEnding;
         end;
      end;

      res += LineEnding;
   end;
   res += LineEnding;

   fn := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFilePath(InputFileName)) + PropertyDefinitionFile);
   Writeln('Saving ' + fn);
   SetFile(fn,res);
end;

procedure Generate_Method_Definition();
var i : integer;
    meth : tMethod;
    p : integer;
    par : tParam;
    par_str : string;
    res : string;
    fn : string;

begin
   res := '';
   for i := low(methods) to high(methods) do
   begin
      meth := methods[i];
      par_str := '';
      if length(meth.Params) > 0 then
      begin
         for p := low(meth.Params) to high(meth.Params) do
         begin
            par := meth.Params[p];
            par_str += ' const ' + par.Name + ' : ' + par.Typ + '; ';
         end;
         par_str := copy(par_str,1,length(par_str)-2);
      end;

      res += ' procedure ' + meth.Name + Default_Method_Suffix +  '(' + par_str + ');' + LineEnding;
      res += ' procedure ' + '_INTERNAL_' + meth.Name + Default_Method_Suffix +  '();' + LineEnding;

      res += LineEnding;
   end;
   res += LineEnding;

   fn := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFilePath(InputFileName)) + MethodDefinitionFile);
   Writeln('Saving ' + fn);
   SetFile(fn,res);
end;

procedure Generate_Method_Implementation();
var i : integer;
    meth : tMethod;
    p : integer;
    par : tParam;
    SaveToTemp, useTemp, par_str2 : string;
    res : string;
    fn : string;

begin
   res := '';
   for i := low(methods) to high(methods) do
   begin
      meth := methods[i];
      SaveToTemp := '';
      useTemp := '';
      par_str2 := '';
      if length(meth.Params) > 0 then
      begin
         for p := low(meth.Params) to high(meth.Params) do
         begin
            par := meth.Params[p];
//            par_str += ' _PS' + Class_Name + '_' + meth.Name + '_' + par.Name + ' : ' + par.Typ + '; ' + LineEnding;

            SaveToTemp += ' _PS' + Class_Name + '_' + meth.Name + '_' + par.Name + ' := ' + par.Name + ';' + LineEnding;

            useTemp += ' _PS' + Class_Name + '_' + meth.Name + '_' + par.Name + ',';

            par_str2 += ' const ' + par.Name + ' : ' + par.Typ + ';';
         end;
         useTemp := copy(useTemp,1,length(useTemp)-1);
         par_str2 := copy(par_str2,1,length(par_str2)-1);
      end;

      res += ' procedure ' + Class_Name + meth.Name + Default_Method_Suffix  + '(' + par_str2 + ');' + LineEnding;
      res += ' begin' + LineEnding;
      if SaveToTemp <> '' then
         res += '    ' + SaveToTemp;
      res += '    tThread.CurrentThread.Synchronize(tThread.CurrentThread,@'+'_INTERNAL_' + meth.Name + Default_Method_Suffix+');' + LineEnding;
      res += ' end;' + LineEnding;
      res += ' procedure ' + Class_Name + '_INTERNAL_' + meth.Name + Default_Method_Suffix  + '();' + LineEnding;
      res += ' begin' + LineEnding;
      res += '    ' + meth.Name +'('+ useTemp +');' + LineEnding;
      res += ' end;' + LineEnding;

      res += LineEnding;
   end;
   res += LineEnding;

  fn := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFilePath(InputFileName)) + MethodImplementationFile);
  Writeln('Saving ' + fn);
  SetFile(fn,res);
end;

begin
   Writeln('ParametricSynchronize_PreCompiler - v0.1 - build on ' + {$I %DATE%} + ' ' + {$I %TIME%});
   InitParameters();
   WriteParameters();
   output := ''; inter := ''; impl := '';
   LoadDataFromSource(InputFileName);
   Writeln('Data loaded..');
   Writeln('Found ' + IntToStr(length(methods)) + ' methods');
   if length(methods) = 0 then
   begin
      Writeln('Halt');
      Halt;
   end;
   Generate_Property_Definition();
   Generate_Method_Definition();
   Generate_Method_Implementation();
   Writeln('All work done ok');

//   Readln();
end.

