unit wlseen;
{$mode objfpc}{$H+}
interface
// Digests only. Retained after token/user removal and source rebinding so a
// missing local credential cannot later be mistaken for a never-adopted bearer.
const SeenDDL='CREATE TABLE _wl_seen(hashedToken TEXT PRIMARY KEY NOT NULL) STRICT';
implementation
end.
