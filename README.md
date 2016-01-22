couchdb-d, a CouchDB client for the D programming language
================

Basic usage
-----------

Add couchdb-d to your `dub.json` and import couch.

CouchDB is structured as a service hosting multiple databases. So first you connect to CouchDB, then
you select a database:

```D
auto client = new CouchClient("https://database-server.local");
auto db = client.database("comments");
```

Now you can save, retrieve, and delete documents:

```D
auto doc = `{"hello": "CouchDB!"}`.parseJSON;
db.create(doc);
auto doc2 = db.get(doc["_id"].str);
writeln("Now we're using ", doc2["hello"].str);
db.remove(doc2);
```

Intermediate querying
---------------------

The reason you're using CouchDB rather than a key/value store is querying.

CouchDB requires queries to be precreated and stored in design docs. To create a design doc:

```D
auto designDoc = new DesignDoc(db, "myDesignDoc");
```

Probably the most useful part of a design doc is defining a view. Views are Javascript functions:

```D
designDoc.createView("byEmail", `
function(doc) {
	emit(doc.email, 1);
}
`);
designDoc.save;
```

Do make sure to savev the design doc after modifying it.

Querying a view is straightforward:

```D
QueryOptions o = {key: "bob.dobbs@subgenius.org", limit: 1};
auto results = designDoc.view("byEmail").query(o);
foreach (document; results) {
	writeln(document["name"].str, " is a subgenius");
}
```

Queries are implicitly paginated using efficient ID-based pagination. You can control this using
`QueryOptions.resultsPerPage`. If you want explicit pagination, the pattern is relatively
straightforward:

```D
enum pageSize = 100;
QueryOptions o = {key: "butter", resultsPerPage: pageSize + 1, limit: pageSize + 1};
auto results = designDoc.view("byIngredient").query(o).array;
display(results[0..$-1]);
nextDocumentID = results[$-1]["id"];
```
