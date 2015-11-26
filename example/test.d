module test;

import std.json;
import std.stdio;
import std.uuid;

import couched;

void main() {
	string uri = "http://localhost:5984";
	auto couch = new CouchClient(uri);
	writeln(couch.databases);
	auto db = couch["tempy"];
	db.createDatabase;
	scope (exit) db.deleteDatabase;
	JSONValue doc = ["hello": "world"];
	auto resp = db.create(doc);
	if (!resp.ok) {
		writeln("write failed");
	}
	auto doc2 = db.get(resp.id);
	writeln(doc2.toString);
}
