unit wlavatar;

{
  WeKan-Lite — the address a browser loads an uploaded avatar from: WeKan's
  models/lib/avatarDisplayUrl.js.

  profile.avatarUrl is stored in more than one shape: /cdn/storage/avatars/<id>,
  the same under an older ROOT_URL path (/wekan/cdn/...), absolute with an
  older host, or CollectionFS's /cfs/files/avatars/<id>. Drawn as stored, an
  avatar is outside WeKan on a sub-path install, and an absolute one fails
  when the browser reaches WeKan by another name. So the stored value is a
  NAME: whatever host or path stood before the avatar path is dropped and
  the path WeKan is served under now is put in its place. Anything that is
  not a WeKan avatar is returned unchanged.

  Pure: tests/avatar.py checks it.
}

{$mode objfpc}{$H+}

interface

// Stored: the profile's avatarUrl. Prefix: the path WeKan is served under
// ('' at the root, '/wekan' under a sub-path).
function AvatarDisplayUrl(const Stored, Prefix: string): string;

implementation

uses SysUtils, StrUtils;

// Whether S is a host and/or a plain path: (https?://[^/?#]+)?(/[^?#]*)?
function HostAndPath(const S: string): Boolean;
var i: Integer;
begin
  i := 1;
  if (Copy(S, 1, 7) = 'http://') or (Copy(S, 1, 8) = 'https://') then
  begin
    i := Pos('://', S) + 3;
    if (i > Length(S)) or (S[i] in ['/', '?', '#']) then Exit(False);
    while (i <= Length(S)) and not (S[i] in ['/', '?', '#']) do Inc(i);
  end;
  if i > Length(S) then Exit(True);
  if S[i] <> '/' then Exit(False);
  Result := (Pos('?', S) = 0) and (Pos('#', S) = 0);
end;

function AvatarDisplayUrl(const Stored, Prefix: string): string;
const Paths: array[0..1] of string = ('/cdn/storage/avatars/', '/cfs/files/avatars/');
var At, First, k, Stop: Integer; Before, Root: string;
begin
  Result := Stored;
  First := 0;
  for k := 0 to High(Paths) do
  begin
    At := PosEx(Paths[k], Stored, 1);
    // The name after it must not be empty: [^?#]+
    while (At > 0) and ((At + Length(Paths[k]) > Length(Stored)) or
      (Stored[At + Length(Paths[k])] in ['?', '#'])) do
      At := PosEx(Paths[k], Stored, At + 1);
    if (At > 0) and ((First = 0) or (At < First)) then First := At;
  end;
  if First = 0 then Exit;
  Before := Copy(Stored, 1, First - 1);
  // An avatar path inside some other URL's query is not WeKan's avatar.
  if (Pos('?', Before) > 0) or (Pos('#', Before) > 0) then Exit;
  if (Before <> '') and not HostAndPath(Before) then Exit;
  Stop := First;
  while (Stop <= Length(Stored)) and not (Stored[Stop] in ['?', '#']) do Inc(Stop);
  Root := Prefix;
  while (Root <> '') and (Root[Length(Root)] = '/') do Delete(Root, Length(Root), 1);
  Result := Root + Copy(Stored, First, Stop - First);
end;

end.
