unit byteinterpreter;

{$MODE Delphi}

interface

uses windows, LCLIntf, sysutils, symbolhandler, CEFuncProc, NewKernelHandler, math, CustomTypeHandler;

type TAutoGuessEvent=function (address: ptruint; originalVariableType: TVariableType): TVariableType of object;

function isHumanReadableInteger(v: integer): boolean; //returns false if it's not an easy readable integer

function FindTypeOfData(address: ptrUint; buf: pbytearray; size: integer; CustomType: PCustomType=nil):TVariableType;
function DataToString(buf: PByteArray; size: integer; vartype: TVariableType): string;
function readAndParsePointer(buf: pbytearray; variableType: TVariableType; customtype: TCustomType=nil; showashexadecimal: Boolean=false; showAsSigned: boolean=false; bytesize:integer=1): string;
function readAndParseAddress(address: ptrUint; variableType: TVariableType; customtype: TCustomType=nil; showashexadecimal: Boolean=false; showAsSigned: boolean=false; bytesize:integer=1): string;
procedure ParseStringAndWriteToAddress(value: string; address: ptruint; variabletype: TVariabletype; hexadecimal: boolean=false; customtype: TCustomType=nil);

var onAutoGuessRoutine: TAutoGuessEvent;


implementation

procedure ParseStringAndWriteToAddress(value: string; address: ptruint; variabletype: TVariabletype; hexadecimal: boolean=false; customtype: TCustomType=nil);
{
Function to wrap all the occasional writing in
}
var v: qword;
    s: single;
    d: double;
    x: dword;

    i: integer;
    ba: PByteArray;

    b: tbytes;
    us: Widestring;
begin
  if hexadecimal and (variabletype in [vtsingle, vtDouble]) then
  begin
    if variabletype=vtSingle then
      variabletype:=vtDword
    else
      variabletype:=vtQword;
  end;

  if variabletype=vtByteArray then
  begin
    setlength(b,0);
    ConvertStringToBytes(value, hexadecimal, b);
    getmem(ba, length(b));
    try
      for i:=0 to length(b)-1 do
      begin
        if (b[i]>=0) then
          WriteProcessMemory(processhandle, pointer(address+i), @b[i], 1, x);
      end;
    finally
      freemem(ba);
    end;

    setlength(b,0);
  end
  else
  begin
    if variabletype in [vtSingle, vtDouble] then
    begin
      d:=StrToFloat(value);
      s:=d;
    end
    else
    begin
      if not (variabletype in [vtString, vtUnicodeString]) then
      begin
        if hexadecimal then
          value:='$'+value;

        v:=StrToQWordEx(value);
      end;
    end;

    case variabletype of
      vtByte: WriteProcessMemory(processhandle, pointer(address), @v, 1, x);
      vtWord: WriteProcessMemory(processhandle, pointer(address), @v, 2, x);
      vtDWord: WriteProcessMemory(processhandle, pointer(address), @v, 4, x);
      vtQWord: WriteProcessMemory(processhandle, pointer(address), @v, 8, x);
      vtSingle: WriteProcessMemory(processhandle, pointer(address), @s, 4, x);
      vtDouble: WriteProcessMemory(processhandle, pointer(address), @d, 8, x);

      vtString: WriteProcessMemory(processhandle, pointer(address), @value[1], length(value), x);
      vtUnicodeString:
      begin
        us:=value;
        WriteProcessMemory(processhandle, pointer(address), @us[1], length(us)*2, x);
      end;

      vtCustom:
      begin
        getmem(ba, customtype.bytesize);
        try
          if ReadProcessMemory(processhandle, pointer(address), ba, customtype.bytesize, x) then
          begin
            if customtype.scriptUsesFloat then
              customtype.ConvertFloatToData(s, ba)
            else
              customtype.ConvertIntegerToData(v, ba);

            WriteProcessMemory(processhandle, pointer(address), ba, customtype.bytesize, x);
          end;
        finally
          freemem(ba);
        end;
      end;
    end;

  end;



end;

function readAndParsePointer(buf: pbytearray; variableType: TVariableType; customtype: TCustomType=nil; showashexadecimal: Boolean=false; showAsSigned: boolean=false; bytesize:integer=1): string;
var
    x: dword;
    i: integer;

    s: pchar;
    ws: PWideChar;
begin
  result:='???';
  case variableType of
    vtByte:
    begin
      if showashexadecimal then
        result:=inttohex(buf[0],2)
      else
      begin
        if showAsSigned then
          result:=inttostr(shortint(buf[0]))
        else
          result:=inttostr(buf[0]);
      end;
    end;

    vtWord:
    begin
      if showashexadecimal then
        result:=inttohex(pword(@buf[0])^,4)
      else
      begin
        if showAsSigned then
          result:=inttostr(pSmallInt(@buf[0])^)
        else
          result:=inttostr(pword(@buf[0])^);
      end;
    end;

    vtDWord:
    begin
      if showashexadecimal then
        result:=inttohex(pdword(@buf[0])^,8)
      else
      begin
        if showAsSigned then
          result:=inttostr(pinteger(@buf[0])^)
        else
          result:=inttostr(pdword(@buf[0])^);
      end;
    end;

    vtQword:
    begin
      if showashexadecimal then
        result:=inttohex(PQWord(@buf[0])^,8)
      else
      begin
        if showAsSigned then
          result:=inttostr(PInt64(@buf[0])^)
        else
          result:=inttostr(pqword(@buf[0])^);
      end;
    end;

    vtSingle:
    begin
      if showashexadecimal then
        result:=inttohex(pdword(@buf[0])^,8)
      else
        result:=floattostr(psingle(@buf[0])^);
    end;

    vtDouble:
    begin
      if showashexadecimal then
        result:=inttohex(pqword(@buf[0])^,16)
      else
        result:=floattostr(pdouble(@buf[0])^);
    end;

    vtString:
    begin
      getmem(s, bytesize+1);
      CopyMemory(s, buf, bytesize);
      s[bytesize]:=#0;
      result:=s;
    end;

    vtUnicodeString:
    begin
      getmem(ws, bytesize+2);
      copymemory(ws, buf, bytesize);
      ws:=PWideChar(buf);
      try
        pbytearray(ws)[bytesize+1]:=0;
        pbytearray(ws)[bytesize]:=0;
        result:=ws;
      finally
        freemem(ws);
      end;
    end;

    vtByteArray:
    begin
      result:='';
      if showashexadecimal then
      begin
        for i:=0 to bytesize-1 do
          result:=result+inttohex(buf[i],2)+' ';
      end
      else
      begin
        for i:=0 to bytesize-1 do
        begin
          if showAsSigned then
            result:=result+IntToStr(shortint(buf[i]))+' '
          else
            result:=result+IntToStr(byte(buf[i]))+' '
        end;
      end;
    end;

    vtCustom:
    begin
      if customtype<>nil then
      begin
        if showashexadecimal and (customtype.scriptUsesFloat=false) then
          result:=inttohex(customtype.ConvertDataToInteger(buf),8)
        else
        begin
          if customtype.scriptUsesFloat then
            result:=FloatToStr(customtype.ConvertDataToFloat(buf))
          else
            result:=IntToStr(customtype.ConvertDataToInteger(buf));
        end;
      end;
    end;
  end;
end;

function readAndParseAddress(address: ptrUint; variableType: TVariableType; customtype: TCustomType=nil; showashexadecimal: Boolean=false; showAsSigned: boolean=false; bytesize:integer=1): string;
var buf: array [0..7] of byte;
    buf2: pbytearray;
    x: dword;
    i: integer;

    s: pchar;
    ws: PWideChar;
begin
  result:='???';
  case variableType of
    vtByte:
    begin
      if ReadProcessMemory(processhandle,pointer(address),@buf[0],1,x) then
        result:=readAndParsePointer(@buf[0], variabletype, customtype, showashexadecimal, showAsSigned, bytesize);

    end;

    vtWord:
    begin
      if ReadProcessMemory(processhandle,pointer(address),@buf[0],2,x) then
        result:=readAndParsePointer(@buf[0], variabletype, customtype, showashexadecimal, showAsSigned, bytesize);
    end;

    vtDWord:
    begin
      if ReadProcessMemory(processhandle,pointer(address),@buf[0],4,x) then
        result:=readAndParsePointer(@buf[0], variabletype, customtype, showashexadecimal, showAsSigned, bytesize);
    end;

    vtQword:
    begin
      if ReadProcessMemory(processhandle,pointer(address),@buf[0],8,x) then
        result:=readAndParsePointer(@buf[0], variabletype, customtype, showashexadecimal, showAsSigned, bytesize);
    end;

    vtSingle:
    begin
      if ReadProcessMemory(processhandle,pointer(address),@buf[0],4,x) then
        result:=readAndParsePointer(@buf[0], variabletype, customtype, showashexadecimal, showAsSigned, bytesize);
    end;

    vtDouble:
    begin
      if ReadProcessMemory(processhandle,pointer(address),@buf[0],8,x) then
        result:=readAndParsePointer(@buf[0], variabletype, customtype, showashexadecimal, showAsSigned, bytesize);
    end;

    vtString:
    begin
      getmem(buf2, bytesize+1);
      try
        if ReadProcessMemory(processhandle,pointer(address),buf2,bytesize,x) then
          result:=readAndParsePointer(buf2, variabletype, customtype, showashexadecimal, showAsSigned, bytesize);
      finally
        freemem(s);
      end;
    end;

    vtUnicodeString:
    begin
      getmem(buf2, bytesize+2);
      try

        if ReadProcessMemory(processhandle,pointer(address),buf2,bytesize,x) then
          result:=readAndParsePointer(buf2, variabletype, customtype, showashexadecimal, showAsSigned, bytesize);


      finally
        freemem(buf2)
      end;

    end;

    vtByteArray:
    begin
      getmem(buf2, bytesize);
      try
        if ReadProcessMemory(processhandle,pointer(address),buf2,bytesize,x) then
          result:=readAndParsePointer(buf2, variabletype, customtype, showashexadecimal, showAsSigned, bytesize);
      finally
        freemem(buf2);
      end;
    end;

    vtCustom:
    begin
      if customtype<>nil then
      begin
        getmem(buf2, customtype.bytesize);
        try
          if ReadProcessMemory(processhandle,pointer(address),buf2,customtype.bytesize,x) then
            result:=readAndParsePointer(buf2, variabletype, customtype, showashexadecimal, showAsSigned, bytesize);

        finally
          freemem(buf2);
        end;
      end;
    end;
  end;
end;


function DataToString(buf: PByteArray; size: integer; vartype: TVariableType): string;
{note: If type is of string unicode, the last 2 bytes will get set to 0, so watch what you're calling}
var tr: Widestring;
    i: integer;
    a: ptruint;

    tempbuf: pbytearray;
begin
  case vartype of
    vtByte: result:='(byte)'+inttohex(buf[0],2) + '('+inttostr(buf[0])+')';
    vtWord: result:='(word)'+inttohex(pword(buf)^,4) + '('+inttostr(pword(buf)^)+')';
    vtDword: result:='(dword)'+inttohex(pdword(buf)^,8) + '('+inttostr(pdword(buf)^)+')';
    vtQword: result:='(qword)'+inttohex(pqword(buf)^,16) + '('+inttostr(pqword(buf)^)+')';
    vtSingle: result:='(float)'+format('%.2f',[psingle(buf)^]);
    vtDouble: result:='(double)'+format('%.2f',[pdouble(buf)^]);
    vtString:
    begin
      getmem(tempbuf,size+1);
      copymemory(tempbuf,buf,size);

      try
        tempbuf[size]:=0;
        result:=pchar(tempbuf);
      finally
        freemem(tempbuf);
      end;
    end;

    vtUnicodeString:
    begin
      getmem(tempbuf,size+2);
      copymemory(tempbuf,buf,size);

      try
        tempbuf[size]:=0;
        tempbuf[size+1]:=0;
        tr:=PWideChar(tempbuf);
        result:=tr;

      finally
        freemem(tempbuf);
      end;
    end;

    vtPointer:
    begin
      if processhandler.is64bit then
        a:=ptruint(pqword(buf)^)
      else
        a:=ptruint(pdword(buf)^);

      result:='(pointer)'+symhandler.getNameFromAddress(a,true,true);


//      result:='(pointer)'+inttohex(pqword(buf)^,16) else result:='(pointer)'+inttohex(pdword(buf)^,8);
    end;

    else
    begin
      result:='(...)';
      for i:=0 to min(size,8)-1 do
        result:=result+inttohex(buf[i],2)+' ';

    end;
  end;
end;

function isHumanReadableInteger(v: integer): boolean;
begin
  //check if the value is a human usable value (between 0 and 10000 or dividable by at least 100)

  //Human readable if:
  //The value is in the range of -10000 and 10000
  //The value is dividable by 100

  result:=inrange(v, -10000, 10000) or ((v mod 100)=0);
end;

function FindTypeOfData(address: ptrUint; buf: pbytearray; size: integer; CustomType: PCustomType=nil):TVariableType;
{
takes the given address and memoryblock and converts it to a variable type based on some guesses

if CustomType is not nil it will also evaluate using the provided custom types (if the result is an unreadable dword)
}
var x: string;
    i: integer;
    isstring: boolean;
    e: integer;
    v: qword;
    f: single;

    floathasseperator: boolean;
    couldbestringcounter: boolean;
begin
  Set8087CW($133f); //disable floating point exceptions (multithreaded)
  SetSSECSR($1f80);

  //check if it matches a string
  result:=vtDword;

  try

    floathasseperator:=false;

    isstring:=true;
    couldbestringcounter:=true;
    i:=0;
    while i<4 do
    begin
      //check if the first 4 characters match with a standard ascii values (32 to 127)
      if (buf[i]<32) or (buf[i]>127) then
      begin
        isstring:=false;
        if i>0 then
          couldbestringcounter:=false;

        if not couldbestringcounter then break;
      end;
      inc(i);
    end;

    if isstring then
    begin
      result:=vtString;
      exit;
    end;

    if couldbestringcounter and ((buf[5]>=32) or (buf[5]<=127)) then //check if the 4th byte of the 'string' is a char or not
    begin
      //this is a string counter
      result:=vtByte;
      exit;
    end;


    //check if unicode
    isstring:=true;
    i:=0;
    if size>=8 then
    begin
      while i<8 do
      begin
        //check if the first 4 characters match with a standard ascii values (32 to 127)
        if (buf[i]<32) or (buf[i]>127) then
        begin
          isstring:=false;
          break;
        end;
        inc(i);
        if buf[i]<>0 then
        begin
          isstring:=false;
          break;
        end;
        inc(i);
      end;
    end else isstring:=false;

    if isstring then
    begin
      result:=vtUnicodeString;
      exit;
    end;


    i:=address mod 4;
    case i of
      1: //1 byte
      begin
        result:=vtByte;
        exit;
      end;

      2,3: //2 byte
      begin
        if (pword(@buf[0])^<255) or ((pword(@buf[0])^ mod 10)>0) then //less than 2 byte or not dividable by 10
          result:=vtByte
        else
          result:=vtWord;
        exit;
      end;
    end;

    if size>=processhandler.pointersize then
    begin
      //named addresses

      if processhandler.is64bit then
      begin
        if (address mod 8) = 0 then
          val('$'+symhandler.getNameFromAddress(pqword(@buf[0])^,true,true),v,e)
        else
          e:=0;
      end
      else
      begin
        val('$'+symhandler.getNameFromAddress(pdword(@buf[0])^,true,true),v,e);
      end;

      if e>0 then //named
      begin
        result:=vtPointer;
        exit;
      end;
    end;


    if (size>=2) and (size<4) then
    begin
      result:=vtWord;
      exit;
    end
    else
    if (size=1) then
    begin
      result:=vtByte;
      exit;
    end
    else
    if psingle(@buf[0])^<>0 then
    begin
      x:=floattostr(psingle(@buf[0])^);
      if (pos('E',x)=0) then  //no exponent
      begin
        //check if the value isn't bigger or smaller than 100000 or smaller than -100000
        if InRange(psingle(@buf[0])^, -100000.0, 100000.0) then
        begin

          if pos(DecimalSeparator,x)>0 then
            floathasseperator:=true;

          result:=vtSingle;

          if (length(x)<=4) or (not floathasseperator) then exit;  //it's a full floating point value or small enough to fit in 3 digits and a seperator (1.01, 1.1 ....)
        end;
      end;
    end;

    if (size>=8) then  //check if a double can be used
    begin
      if pdouble(@buf[0])^<>0 then
      begin
        x:=floattostr(pdouble(@buf[0])^);
        if (pos('E',x)=0) then  //no exponent
        begin
          //check if the value isn't bigger or smaller than 100000 or smaller than -100000
          if (pdouble(@buf[0])^<100000) and (pdouble(@buf[0])^>-100000) then
          begin
            if result=vtSingle then
            begin
              if pdouble(@buf[0])^>psingle(@buf[0])^ then exit; //float has a smaller value
            end;

            //if 4 bytes after this address is a float then override thise double to a single type
            if FindTypeOfData(address+4, @buf[4], size-4)=vtSingle then
              result:=vtSingle
            else
              result:=vtDouble;

            exit;
          end;
        end;
      end;
    end;

    //check if it's a pointer

    if processhandler.is64Bit then
    begin

      if (address mod 8 = 0) and isreadable(pqword(@buf[0])^) then
      begin
        result:=vtPointer;
        exit;
      end;
    end
    else
    begin
      if isreadable(pdword(@buf[0])^) then
      begin
        result:=vtPointer;

       // if inrange(pdword(@buf[0])^, $3d000000, $44800000)=false then //if it's not in this range, assume it's a pointer. Otherwise, could be a float
        exit;
      end;
    end;

    //if customtype is not nil check if the dword is humanreadable or not
    if (customtype<>nil) and (result=vtDword) and (isHumanReadableInteger(pdword(@buf[0])^)=false) then
    begin
      //not human readable, see if there is a custom type that IS human readable
      for i:=0 to customTypes.count-1 do
      begin
        if TCustomType(customtypes[i]).scriptUsesFloat then
        begin
          //float check
          f:=TCustomType(customtypes[i]).ConvertDataToFloat(@buf[0]);
          x:=floattostr(f);

          if (pos('E',x)=0) and (f<>0) and InRange(f, -100000.0, 100000.0) then
          begin
            result:=vtCustom;
            CustomType^:=customtypes[i];

            if (pos(DecimalSeparator,x)=0) then
              break; //found one that has no decimal seperator

          end;
        end
        else
        begin
          //dword check
          if isHumanReadableInteger(TCustomType(customtypes[i]).ConvertDataToInteger(@buf[0])) then
          begin
            result:=vtCustom;
            CustomType^:=customtypes[i];
            break;
          end;
        end;
      end;
    end;

  finally
    if assigned(onAutoGuessRoutine) then
      result:=onAutoGuessRoutine(address, result);

  end;
end;

end.
