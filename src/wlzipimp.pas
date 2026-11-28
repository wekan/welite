unit wlzipimp;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses Classes, fpjson;

function ZipAttachmentName(const Value: string; Used: TStringList): string;
function ReadBoardZip(const Bytes: RawByteString): TJSONObject;
function ReadWorkbookRows(const Bytes: RawByteString; SheetNames: TStrings = nil; Date1904: PBoolean = nil): TJSONArray;
function ReadZipMember(const Bytes:RawByteString; const Name:string; out Content:RawByteString):Boolean;
function ReadTrelloZip(const Bytes: RawByteString): TJSONArray;
function ReadMarkdownZip(const Bytes: RawByteString; IncludeTables:Boolean=False; IncludeIssues:Boolean=False): TJSONArray;

implementation

uses SysUtils, StrUtils, zipper, jsonparser, base64, DOM, XMLRead;

const
  MaxArchive = 64 * 1024 * 1024;
  MaxEntry = 32 * 1024 * 1024;
  MaxEntries = 4096;
  AttachmentPrefix = 'attachments/';

type
  TZipEntryStream = class(TMemoryStream)
    Limit: Int64;
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

  TBoardZipReader = class
    Input: TStringStream;
    Files: TStringList;
    Total: Int64;
    Markdown, Trello: Boolean;
    constructor Create(const Bytes: RawByteString);
    destructor Destroy; override;
    procedure OpenInput(Sender: TObject; var Stream: TStream);
    procedure CloseInput(Sender: TObject; var Stream: TStream);
    procedure CreateEntry(Sender: TObject; var Stream: TStream; Item: TFullZipFileEntry);
    procedure FinishEntry(Sender: TObject; var Stream: TStream; Item: TFullZipFileEntry);
    function ReadEntry(const Name: string; out Bytes: RawByteString): Boolean;
  end;

function ZipAttachmentName(const Value: string; Used: TStringList): string;
var C: Char; Name, Stem, Extension: string; Dot, Number: Integer;
begin
  Name := '';
  for C in Value do
    if (C < ' ') or (C in ['/', '\', ':', '*', '?', '"', '<', '>', '|', #127]) then Name := Name + '-'
    else Name := Name + C;
  Name := Trim(Name);
  while (Name <> '') and (Name[Length(Name)] = '.') do Delete(Name, Length(Name), 1);
  if Name = '' then Name := 'download';
  Dot := RPos('.', Name);
  if Dot > 1 then
  begin
    Stem := Copy(Name, 1, Dot - 1);
    Extension := Copy(Name, Dot, MaxInt);
  end
  else
  begin
    Stem := Name;
    Extension := '';
  end;
  Result := Name;
  Number := 0;
  while Used.IndexOf(Result) >= 0 do
  begin
    Inc(Number);
    Result := Stem + '-' + IntToStr(Number) + Extension;
  end;
  Used.Add(Result);
end;

function TZipEntryStream.Write(const Buffer; Count: Longint): Longint;
begin
  if (Count < 0) or (Position + Count > Limit) then raise EConvertError.Create('ZIP entry exceeds its size');
  Result := inherited Write(Buffer, Count);
end;

constructor TBoardZipReader.Create(const Bytes: RawByteString);
begin
  inherited Create;
  Input := TStringStream.Create(Bytes);
  Files := TStringList.Create;
  Files.OwnsObjects := True;
  Files.CaseSensitive := True;
  Files.Sorted := True;
end;

destructor TBoardZipReader.Destroy;
begin
  Files.Free;
  Input.Free;
  inherited Destroy;
end;

procedure TBoardZipReader.OpenInput(Sender: TObject; var Stream: TStream);
begin
  Input.Position := 0;
  Stream := Input;
end;

procedure TBoardZipReader.CloseInput(Sender: TObject; var Stream: TStream);
begin
  Stream := nil;
end;

procedure TBoardZipReader.CreateEntry(Sender: TObject; var Stream: TStream; Item: TFullZipFileEntry);
var Name, Leaf: string; Data: TZipEntryStream;
begin
  Name := Item.ArchiveFileName;
  if Trello then
  begin
    if Item.IsLink or (Name='') or (Pos(#0,Name)>0) or (Pos('\',Name)>0) or (Pos(':',Name)>0) or
      AnsiStartsStr('/',Name) or (Pos('/../','/'+Name+'/')>0) or (Pos('/./','/'+Name+'/')>0) or
      (Pos('//',Name)>0) then raise EConvertError.Create('Invalid ZIP entry');
  end
  else if Markdown then
  begin
    if Item.IsLink or (Pos(#0,Name)>0) or (Pos('\',Name)>0) or AnsiStartsStr('/',Name) or
      (Pos('/../','/'+Name+'/')>0) then raise EConvertError.Create('Invalid ZIP entry');
  end
  else
  begin
    Leaf := Copy(Name, Length(AttachmentPrefix) + 1, MaxInt);
    if Item.IsLink or (Pos(#0, Name) > 0) or
      ((Name <> 'wekan.json') and (not Trello or (Name <> 'board.json')) and (Name <> AttachmentPrefix) and
        (not AnsiStartsStr(AttachmentPrefix, Name) or (Leaf = '') or
          (Leaf = '.') or (Leaf = '..') or (Pos('/', Leaf) > 0) or
          (Pos('\', Leaf) > 0) or (Pos(':', Leaf) > 0))) then raise EConvertError.Create('Invalid ZIP entry');
  end;
  if (Item.Size < 0) or (Item.Size > MaxEntry) or (Files.Count >= MaxEntries) or
    (Total + Item.Size > MaxArchive) or (Files.IndexOf(Name) >= 0) then
    raise EConvertError.Create('Invalid ZIP entry size or name');
  Inc(Total, Item.Size);
  Data := TZipEntryStream.Create;
  Data.Limit := Item.Size;
  Files.AddObject(Name, Data);
  // The reader must never fall back to extracting an entry to disk.
  Stream := Data;
end;

procedure TBoardZipReader.FinishEntry(Sender: TObject; var Stream: TStream; Item: TFullZipFileEntry);
begin
  if (Stream <> nil) and (Stream.Size <> Item.Size) then raise EConvertError.Create('Incomplete ZIP entry');
end;

function TBoardZipReader.ReadEntry(const Name: string; out Bytes: RawByteString): Boolean;
var Index: Integer; Data: TMemoryStream;
begin
  Bytes := '';
  if not Files.Find(Name, Index) then Exit(False);
  Data := TMemoryStream(Files.Objects[Index]);
  SetLength(Bytes, Data.Size);
  if Data.Size > 0 then Move(Data.Memory^, Bytes[1], Data.Size);
  Result := True;
end;

function ReadMarkdownZip(const Bytes: RawByteString; IncludeTables,IncludeIssues:Boolean): TJSONArray;
var Archive: TUnZipper; Reader: TBoardZipReader; I: Integer; Name, Content: RawByteString;
begin
  if (Length(Bytes)=0) or (Length(Bytes)>MaxArchive) then raise EConvertError.Create('Invalid ZIP size');
  Archive:=TUnZipper.Create;
  Reader:=TBoardZipReader.Create(Bytes);
  Result:=TJSONArray.Create;
  try
    try
      Reader.Markdown:=True;
      Archive.OnOpenInputStream:=@Reader.OpenInput;
      Archive.OnCloseInputStream:=@Reader.CloseInput;
      Archive.OnCreateStream:=@Reader.CreateEntry;
      Archive.OnDoneStream:=@Reader.FinishEntry;
      Archive.UnZipAllFiles;
      for I:=0 to Reader.Files.Count-1 do
      begin
        Name:=Reader.Files[I];
        if AnsiStartsStr('__MACOSX/',Name) or AnsiStartsStr('._',ExtractFileName(Name)) then Continue;
        if not (AnsiEndsText('.md',Name) or AnsiEndsText('.markdown',Name) or
          (IncludeTables and (AnsiEndsText('.csv',Name) or AnsiEndsText('.zip',Name))) or
          (IncludeIssues and (AnsiEndsText('.csv',Name) or AnsiEndsText('.json',Name) or AnsiEndsText('.xlsx',Name)))) then Continue;
        if Reader.ReadEntry(Name,Content) then
          if (IncludeTables and AnsiEndsText('.zip',Name)) or (IncludeIssues and AnsiEndsText('.xlsx',Name)) then
            Result.Add(TJSONObject.Create(['name',Name,'zipBase64',EncodeStringBase64(Content)]))
          else Result.Add(TJSONObject.Create(['name',Name,'text',Content]));
      end;
    except Result.Free; raise; end;
  finally Archive.Free; Reader.Free; end;
end;

function ReadWorkbookRows(const Bytes: RawByteString; SheetNames: TStrings; Date1904: PBoolean): TJSONArray;
var Archive:TUnZipper; Reader:TBoardZipReader; Shared:TStringList; Sheet, Row:TJSONArray;
  Xml:TXMLDocument; Node, Cells, Cell, Value:TDOMNode; I, Column, K:Integer;
  Name,Ref,Text,Kind:string; Raw:RawByteString;
  function XmlOf(const Content:RawByteString):TXMLDocument;
  var Stream:TStringStream;
  begin
    if (Pos(#0,Content)>0) or (Pos('<!DOCTYPE',Content)>0) or (Pos('<!ENTITY',Content)>0) then
      raise EConvertError.Create('Invalid workbook XML');
    Stream:=TStringStream.Create(Content);
    try ReadXMLFile(Result,Stream); finally Stream.Free; end;
  end;
begin
  if (Length(Bytes)=0) or (Length(Bytes)>MaxArchive) then raise EConvertError.Create('Invalid workbook size');
  Archive:=TUnZipper.Create; Reader:=TBoardZipReader.Create(Bytes); Shared:=TStringList.Create;
  Result:=TJSONArray.Create;
  try
    try
      Reader.Markdown:=True;
      Archive.OnOpenInputStream:=@Reader.OpenInput;
      Archive.OnCloseInputStream:=@Reader.CloseInput;
      Archive.OnCreateStream:=@Reader.CreateEntry;
      Archive.OnDoneStream:=@Reader.FinishEntry;
      Archive.UnZipAllFiles;
      if not Reader.ReadEntry('xl/workbook.xml',Raw) then raise EConvertError.Create('Missing workbook');
      if (SheetNames<>nil) or (Date1904<>nil) then
      begin
        if SheetNames<>nil then SheetNames.Clear;
        Xml:=XmlOf(Raw);
        try
          if Date1904<>nil then
          begin
            Date1904^:=False;
            Node:=Xml.DocumentElement.FindNode('workbookPr');
            if Node is TDOMElement then
            begin
              Text:=UTF8Encode(TDOMElement(Node).GetAttribute('date1904'));
              Date1904^:=(Text='1') or SameText(Text,'true');
            end;
          end;
          Cells:=Xml.DocumentElement.FindNode('sheets');
          if (Cells<>nil) and (SheetNames<>nil) then
          begin
            Node:=Cells.FirstChild;
            while Node<>nil do
            begin
              if (Node is TDOMElement) and ((Node.LocalName='sheet') or (Node.NodeName='sheet')) then
                SheetNames.Add(UTF8Encode(TDOMElement(Node).GetAttribute('name')));
              Node:=Node.NextSibling;
            end;
          end;
        finally Xml.Free; end;
      end;
      if Reader.ReadEntry('xl/sharedStrings.xml',Raw) then
      begin
        Xml:=XmlOf(Raw);
        try
          Node:=Xml.DocumentElement.FirstChild;
          while Node<>nil do
          begin
            if ((Node.LocalName='si') or (Node.NodeName='si')) then Shared.Add(UTF8Encode(Node.TextContent));
            Node:=Node.NextSibling;
          end;
        finally Xml.Free; end;
      end;
      for I:=1 to MaxEntries do
      begin
        Name:='xl/worksheets/sheet'+IntToStr(I)+'.xml';
        if not Reader.ReadEntry(Name,Raw) then Break;
        Xml:=XmlOf(Raw);
        try
          Cells:=Xml.DocumentElement.FindNode('sheetData');
          Sheet:=TJSONArray.Create; Result.Add(Sheet);
          if Cells=nil then Continue;
          Node:=Cells.FirstChild;
          while Node<>nil do
          begin
            if ((Node.LocalName='row') or (Node.NodeName='row')) then
            begin
              Row:=TJSONArray.Create; Sheet.Add(Row);
              Cell:=Node.FirstChild;
              while Cell<>nil do
              begin
                if ((Cell.LocalName='c') or (Cell.NodeName='c')) then
                begin
                  Ref:=UTF8Encode(TDOMElement(Cell).GetAttribute('r'));
                  Kind:=UTF8Encode(TDOMElement(Cell).GetAttribute('t'));
                  Column:=0; K:=1;
                  while (K<=Length(Ref)) and (Ref[K] in ['A'..'Z']) do
                  begin
                    Column:=Column*26+Ord(Ref[K])-Ord('A')+1;
                    if Column>16384 then raise EConvertError.Create('Invalid workbook cell');
                    Inc(K);
                  end;
                  if Column=0 then Column:=Row.Count+1;
                  if Column<=Row.Count then raise EConvertError.Create('Unordered workbook cell');
                  while Row.Count<Column-1 do Row.Add('');
                  Text:='';
                  if Kind='inlineStr' then Value:=Cell.FindNode('is') else Value:=Cell.FindNode('v');
                  if Value<>nil then Text:=UTF8Encode(Value.TextContent);
                  if Kind='s' then
                  begin
                    K:=StrToIntDef(Text,-1);
                    if (K<0) or (K>=Shared.Count) then raise EConvertError.Create('Invalid workbook string reference');
                    Text:=Shared[K];
                  end;
                  Row.Add(Text);
                end;
                Cell:=Cell.NextSibling;
              end;
            end;
            Node:=Node.NextSibling;
          end;
        finally Xml.Free; end;
      end;
      if Result.Count=0 then raise EConvertError.Create('Missing workbook sheets');
    except Result.Free; raise; end;
  finally Shared.Free; Reader.Free; Archive.Free; end;
end;

function ReadZipMember(const Bytes:RawByteString; const Name:string; out Content:RawByteString):Boolean;
var Archive:TUnZipper; Reader:TBoardZipReader;
begin
  if (Length(Bytes)=0) or (Length(Bytes)>MaxArchive) then raise EConvertError.Create('Invalid ZIP size');
  Archive:=TUnZipper.Create;
  Reader:=TBoardZipReader.Create(Bytes);
  try
    Reader.Markdown:=True;
    Archive.OnOpenInputStream:=@Reader.OpenInput;
    Archive.OnCloseInputStream:=@Reader.CloseInput;
    Archive.OnCreateStream:=@Reader.CreateEntry;
    Archive.OnDoneStream:=@Reader.FinishEntry;
    Archive.UnZipAllFiles;
    Result:=Reader.ReadEntry(Name,Content);
  finally Reader.Free; Archive.Free; end;
end;

function ReadTrelloZip(const Bytes: RawByteString): TJSONArray;
var Archive: TUnZipper; Reader: TBoardZipReader; Raw: RawByteString;
  Data, Cards, Attachments, Files: TJSONData;
  Board, Card, Attachment: TJSONObject; B, I, J: Integer;
  Name, Id, Member, Directory, Leaf, Candidate, Scope: string;
  Used, Paths, LegacyNames: TStringList; DirectoryCounts, ScopeOwners: TJSONObject; Scopes: TStringArray;

  function Parent(const Entry: string): string;
  var At: Integer;
  begin
    At:=RPos('/',Entry);
    Result:=Copy(Entry,1,At);
  end;

  function ScopesOf(const Entry: string): TStringArray;
  var Dir, Stem: string;
  begin
    Dir:=Parent(Entry);
    Stem:=Copy(Entry,1,Length(Entry)-5)+'/';
    Result:=[];
    if Copy(Entry,Length(Dir)+1,MaxInt)<>'board.json' then Result:=[Stem+AttachmentPrefix,Stem];
    if (DirectoryCounts.Get(Dir,0)=1) and ((Dir<>'') or (Paths.Count=1)) then
    begin
      Result:=Concat(Result,[Dir+AttachmentPrefix]);
      if Dir<>'' then Result:=Concat(Result,[Dir]);
    end;
  end;

  function FindFile(const Entry: string): Boolean;
  var Scope: string;
  begin
    Result:=False;
    if (Entry='') or (Entry='.') or (Entry='..') or (Pos('/',Entry)>0) or (Pos('\',Entry)>0) or
      (Pos(':',Entry)>0) or (Pos(#0,Entry)>0) then Exit;
    for Scope in Scopes do
    begin
      if ScopeOwners.Get(Scope,0)<>1 then Continue;
      Candidate:=Scope+Entry;
      if Used.IndexOf(Candidate)>=0 then Continue;
      if Reader.ReadEntry(Candidate,Raw) then
      begin
        Used.Add(Candidate);
        Exit(True);
      end;
    end;
  end;

begin
  if (Length(Bytes)=0) or (Length(Bytes)>MaxArchive) then raise EConvertError.Create('Invalid Trello ZIP size');
  Archive:=TUnZipper.Create; Reader:=TBoardZipReader.Create(Bytes);
  Used:=TStringList.Create; Paths:=TStringList.Create; LegacyNames:=TStringList.Create; DirectoryCounts:=TJSONObject.Create; ScopeOwners:=TJSONObject.Create;
  Result:=TJSONArray.Create;
  try
    try
      Used.CaseSensitive:=True;
      LegacyNames.CaseSensitive:=False;
      Reader.Trello:=True;
      Archive.OnOpenInputStream:=@Reader.OpenInput;
      Archive.OnCloseInputStream:=@Reader.CloseInput;
      Archive.OnCreateStream:=@Reader.CreateEntry;
      Archive.OnDoneStream:=@Reader.FinishEntry;
      Archive.UnZipAllFiles;
      for B:=0 to Reader.Files.Count-1 do
      begin
        Member:=Reader.Files[B];
        Directory:=Parent(Member);
        if not AnsiEndsText('.json',Member) or (Pos('/attachments/','/'+Directory)>0) then Continue;
        if not Reader.ReadEntry(Member,Raw) then Continue;
        Leaf:=Copy(Member,Length(Directory)+1,MaxInt);
        Data:=nil;
        try
          try Data:=GetJSON(Raw); except on E:EJSONParser do Data:=nil; end;
          if Data is TJSONObject then
          begin
            Board:=TJSONObject(Data);
            if (Trim(Board.Get('name',''))<>'') and (Board.Find('lists') is TJSONArray) and
              (Board.Find('cards') is TJSONArray) then
            begin
              Result.Add(Board);
              Data:=nil;
              Paths.Add(Member);
              DirectoryCounts.Integers[Directory]:=DirectoryCounts.Get(Directory,0)+1;
              Continue;
            end;
          end;
          if Leaf='board.json' then raise EConvertError.Create('Invalid Trello board');
        finally Data.Free; end;
      end;
      if Result.Count=0 then raise EConvertError.Create('Missing Trello board JSON');
      for Member in Paths do
        for Scope in ScopesOf(Member) do
          ScopeOwners.Integers[Scope]:=ScopeOwners.Get(Scope,0)+1;
      for B:=0 to Result.Count-1 do
      begin
        Scopes:=ScopesOf(Paths[B]);
        LegacyNames.Clear;
        Cards:=Result.Objects[B].Find('cards');
        for I:=0 to Cards.Count-1 do
        begin
          if not (Cards.Items[I] is TJSONObject) then raise EConvertError.Create('Invalid Trello card');
          Card:=TJSONObject(Cards.Items[I]); Attachments:=Card.Find('attachments');
          if not (Attachments is TJSONArray) then Continue;
          for J:=0 to Attachments.Count-1 do
          begin
            Files:=Attachments.Items[J];
            if not (Files is TJSONObject) then Continue;
            Attachment:=TJSONObject(Files);
            Name:=Attachment.Get('fileName',Attachment.Get('name',''));
            Attachment.Delete('file');
            if Name='' then Continue;
            Id:=Attachment.Get('id','');
            Leaf:=ZipAttachmentName(Name,LegacyNames);
            if ((Id<>'') and FindFile(Id+'_'+Name)) or FindFile(Name) or FindFile(Leaf) then
              Attachment.Add('file',EncodeStringBase64(Raw));
          end;
        end;
      end;
    except FreeAndNil(Result); raise; end;
  finally ScopeOwners.Free; DirectoryCounts.Free; LegacyNames.Free; Paths.Free; Used.Free; Reader.Free; Archive.Free; end;
end;

function ReadBoardZip(const Bytes: RawByteString): TJSONObject;
var Archive: TUnZipper; Reader: TBoardZipReader; Parsed, Data, ArchivePath: TJSONData;
  Board, Entry: TJSONObject; Attachments: TJSONArray; Used: TStringList;
  I: Integer; Content: RawByteString; Member, LegacyName: string;
begin
  Result := nil;
  if (Length(Bytes) = 0) or (Length(Bytes) > MaxArchive) then raise EConvertError.Create('Invalid ZIP size');
  Archive := TUnZipper.Create;
  Reader := TBoardZipReader.Create(Bytes);
  Used := TStringList.Create;
  Parsed := nil;
  try
    Archive.OnOpenInputStream := @Reader.OpenInput;
    Archive.OnCloseInputStream := @Reader.CloseInput;
    Archive.OnCreateStream := @Reader.CreateEntry;
    Archive.OnDoneStream := @Reader.FinishEntry;
    Archive.UnZipAllFiles;
    if not Reader.ReadEntry('wekan.json', Content) then raise EConvertError.Create('Missing board JSON');
    Parsed := GetJSON(Content);
    if not (Parsed is TJSONObject) then raise EConvertError.Create('Invalid board JSON');
    Board := TJSONObject(Parsed);
    Data := Board.Find('attachments');
    if Data <> nil then
    begin
      if not (Data is TJSONArray) then raise EConvertError.Create('Invalid board attachments');
      Attachments := TJSONArray(Data);
      for I := 0 to Attachments.Count - 1 do
      begin
        Entry := Attachments.Objects[I];
        LegacyName := AttachmentPrefix + ZipAttachmentName(Entry.Get('name', ''), Used);
        ArchivePath := Entry.Find('archivePath');
        if ArchivePath = nil then Member := LegacyName
        else if ArchivePath is TJSONString then Member := ArchivePath.AsString
        else raise EConvertError.Create('Invalid attachment archive path');
        if Member = '' then Continue;
        if not AnsiStartsStr(AttachmentPrefix, Member) then raise EConvertError.Create('Invalid attachment archive path');
        if Reader.ReadEntry(Member, Content) then
        begin
          Entry.Delete('file');
          Entry.Add('file', EncodeStringBase64(Content));
        end
        else if ArchivePath <> nil then raise EConvertError.Create('Missing attachment archive entry');
      end;
      for I := Attachments.Count - 1 downto 0 do
        if not (Attachments.Objects[I].Find('file') is TJSONString) then Attachments.Delete(I);
    end;
    Result := TJSONObject.Create;
    Result.Add('board', Board);
    Parsed := nil;
  finally
    Parsed.Free;
    Archive.Free;
    Reader.Free;
    Used.Free;
  end;
end;

end.
