unit wlseed;
{$mode objfpc}{$H+}
{$CODEPAGE UTF8}
interface
uses SysUtils,Classes;
const MaxSeedBytes=16*1024*1024;
type TSeedLookup=function(const Name:string;out SQL:string):Boolean;
var EmbeddedSeedLookup:TSeedLookup=nil;
// An explicit file wins and never silently falls back. Embedded defaults belong
// to the executable; ordinary disk builds retain their ordered file candidates.
function LoadSeedSQL(const Name,OverrideFile:string;const Defaults:array of string;
  out SQL:string):Boolean;
implementation
function ValidSQL(var Text:string):Boolean;
begin
  Result:=False;
  if (Length(Text)>MaxSeedBytes) or (Pos(#0,Text)>0) then Exit;
  if (Length(Text)>=3) and (Ord(Text[1])=$EF) and (Ord(Text[2])=$BB) and
    (Ord(Text[3])=$BF) then Delete(Text,1,3);
  Result:=Trim(Text)<>'';
end;
function ReadFileSQL(const FileName:string;out SQL:string):Boolean;
var Stream:TFileStream;Candidate:string;
begin
  Result:=False;SQL:='';
  try
    Stream:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyNone);
    try
      if (Stream.Size<=0) or (Stream.Size>MaxSeedBytes) then Exit;
      SetLength(Candidate,SizeInt(Stream.Size));
      Stream.ReadBuffer(Candidate[1],Length(Candidate));
    finally Stream.Free;end;
    if not ValidSQL(Candidate) then Exit;
    SQL:=Candidate;Result:=True;
  except Result:=False;end;
end;
function LoadSeedSQL(const Name,OverrideFile:string;const Defaults:array of string;
  out SQL:string):Boolean;
var i:Integer;Candidate:string;
begin
  Result:=False;SQL:='';
  if (Name<>'schema.sql') and (Name<>'designer.sql') then Exit;
  if OverrideFile<>'' then Exit(ReadFileSQL(OverrideFile,SQL));
  if Assigned(EmbeddedSeedLookup) then
  begin
    try
      if not EmbeddedSeedLookup(Name,Candidate) or not ValidSQL(Candidate) then Exit;
      SQL:=Candidate;Result:=True;
    except Result:=False;end;
    Exit;
  end;
  for i:=Low(Defaults) to High(Defaults) do
    if FileExists(Defaults[i]) then Exit(ReadFileSQL(Defaults[i],SQL));
end;
end.
