unit wlenmeta;
{$mode objfpc}{$H+}
interface
const EnrollDDL='CREATE TABLE _wl_enrol(userId TEXT PRIMARY KEY,tokenKey TEXT NOT NULL UNIQUE,binding TEXT NOT NULL,secret TEXT NOT NULL,created INTEGER NOT NULL CHECK(created>=0),expires INTEGER NOT NULL CHECK(expires>created),credentialRef TEXT NOT NULL,username TEXT NOT NULL,method TEXT NOT NULL,services TEXT NOT NULL,admin TEXT NOT NULL) STRICT';
implementation
end.
