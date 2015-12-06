module app;

import std.json;
import std.stdio;
import std.uuid;

import couch;

void main() {
	JSONValue j;
	j["hell"] = "world";
	string uri = "http://localhost:5984";
	auto couch = new CouchClient(uri);
	writeln(couch.databases);
	auto db = couch["tempy"];
	try {
		db.deleteDatabase;
	} catch {}
	db.createDatabase;
	scope (exit) db.deleteDatabase;
	JSONValue doc = ["hello": "world"];
	auto resp = db.create(doc);
	if (!resp.ok) {
		writeln("write failed");
	}
	auto doc2 = db.get(resp.id);
	writeln(doc2.toString);

	auto designDoc = new DesignDoc(db, "dd");
	auto view = designDoc.createView("hello", `
		function(doc) {
			emit(doc.hello, 1);
		}
		`);
	try {
		designDoc.save;
	} catch (Exception ex) {
		writeln("caught exception");
		return;
	}
	QueryOptions o;
	foreach (d; view.query(o)) {
		writeln(d["id"].str);
	}
}
