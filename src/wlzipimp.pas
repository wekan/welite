unit wlzipimp;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses Classes, fpjson;

function ZipAttachmentName(const Value: string; Used: TStringList): string;
function ReadBoardZip(const Bytes: RawByteString): TJSONObject;
function ReadTrelloZip(const Bytes: RawByteString): TJSONObject;
function ReadMarkdownZip(const Bytes: RawByteString): TJSONArray;

implementation

uses SysUtils, StrUtils, zipper, jsonparser, base64;

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
  if Markdown then
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

function ReadMarkdownZip(const Bytes: RawByteString): TJSONArray;
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
        if not (AnsiEndsText('.md',Name) or AnsiEndsText('.markdown',Name)) then Continue;
        if Reader.ReadEntry(Name,Content) then Result.Add(TJSONObject.Create(['name',Name,'text',Content]));
      end;
    except Result.Free; raise; end;
  finally Archive.Free; Reader.Free; end;
end;

function ReadTrelloZip(const Bytes: RawByteString): TJSONObject;
var Archive: TUnZipper; Reader: TBoardZipReader; Raw: RawByteString; Data, Cards, Attachments, Files: TJSONData;
  Card, Attachment: TJSONObject; I,J: Integer; Name: string; Used: TStringList;
begin
  if (Length(Bytes)=0) or (Length(Bytes)>MaxArchive) then raise EConvertError.Create('Invalid Trello ZIP size');
  Archive:=TUnZipper.Create; Reader:=TBoardZipReader.Create(Bytes); Used:=TStringList.Create;
  Data:=nil;
  try
    Reader.Trello:=True;
    Archive.OnOpenInputStream:=@Reader.OpenInput;
    Archive.OnCloseInputStream:=@Reader.CloseInput;
    Archive.OnCreateStream:=@Reader.CreateEntry;
    Archive.OnDoneStream:=@Reader.FinishEntry;
    Archive.UnZipAllFiles;
    if not Reader.ReadEntry('board.json',Raw) then raise EConvertError.Create('Missing Trello board JSON');
    Data:=GetJSON(Raw);
    if not (Data is TJSONObject) then raise EConvertError.Create('Invalid Trello board');
    Cards:=TJSONObject(Data).Find('cards');
    if not (Cards is TJSONArray) then raise EConvertError.Create('Invalid Trello cards');
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
        if Reader.ReadEntry(AttachmentPrefix+ZipAttachmentName(Name,Used),Raw) then
          Attachment.Add('file',EncodeStringBase64(Raw));
      end;
    end;
    Result:=TJSONObject(Data); Data:=nil;
  finally Data.Free; Used.Free; Reader.Free; Archive.Free; end;
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
