module couched;

import std.conv : to;
import std.json;
import curl = std.net.curl;
import std.string : format;
import std.uri;
import std.uuid;


enum CouchError {
	None,
	Unknown,
	NotFound,
	InvalidDocument,
	UnexpectedType,
	MissingProperty
}

struct DocumentResult {
	string id;
	string revision;
	bool ok;
	
	this(JSONValue value) {
		id = value["id"].str;
		revision = value["rev"].str;
		ok = value["ok"].type == JSON_TYPE.TRUE;
	}
}

class CouchException : Exception
{
	private:
		CouchError _error;

	public:
		this(string msg, CouchError error = CouchError.Unknown, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
			super(msg, file, line, next);
			_error = error;
		}

		@property CouchError error() pure nothrow {
			return _error;
		}

		override string toString() {
			return std.string.format("%s: %s", this.error.to!string, this.msg);
		}

}

/**
	* A CouchDB database.
	*
	* This represents a single named database within a CouchDB instance.
	*/
class CouchDatabase {
	private string _name;
	private CouchClient _client;

	private string _documentPath(string uuid) {
		return _client.uri ~ "/" ~ _name ~ "/" ~ uuid;
	}

	package this(CouchClient client, string name) {
		_client = client;
		_name = name;
	}

	/**
		* Insert the given JSON document into the database.
		*
		* Params:
		*   uuid  = the ID of the object to insert.
		*   value = the value to insert into the database.
		* Returns:
		*   The input JSON value with added _rev and _id fields, representing the document's new
		*   revision number and ID respectively.
		*/
	DocumentResult create(UUID uuid, ref JSONValue value) {
		return create(uuid.toString, value);
	}

	/**
		* Insert the given JSON document into the database.
		*
		* Params:
		*   uuid  = the ID of the object to insert.
		*   value = the value to insert into the database.
		* Returns:
		*/
	DocumentResult create(string uuid, ref JSONValue value) {
		auto response = cast(string) curl.put(_documentPath(uuid), value.toString);
		auto resp = parseJSON(response);
		value["_rev"] = resp["rev"];
		value["_id"] = resp["id"];
		return DocumentResult(resp);
	}

	/**
		* Insert the given JSON document into the database, creating a new ID for it.
		*
		* Params:
		*   value = the value to insert into the database.
		* Returns:
		*   The input JSON value with added _rev and _id fields, representing the document's new
		*   revision number and ID respectively.
		*/
	DocumentResult create(ref JSONValue value) {
		return create(randomUUID, value);
	}

	/**
		* Update the given JSON document in the database.
		*
		* Params:
		*   value = the value to insert into the database. It must have a valid _id field.
		* Returns:
		*   The input JSON value with added _rev and _id fields, representing the document's new
		*   revision number and ID respectively.
		*/
	DocumentResult update(JSONValue value) {
		return create(value["_id"].str, value);
	}

	/**
		* Remove the given document from the database.
		*
		* This marks the document as deleted but does not expunge it from the database. It instead adds
		* a revision that marks the document as deleted. With this method, it also removes all fields
		* besides the document ID and revision and deleted flag.
		*
		* You can also delete a document (without removing its other fields) by adding an entry
		* "_deleted": true to the document root.
		*
		* If you need the document entirely expunged from the database, use the `purge` option.
		*
		* Params:
		*   value = The document to delete.
		* Returns:
		*   A json document of the form
		*   {"id": "document id", "rev": "document revision", "ok": true|false}
		*   indicating the success or failure.
		*/
	DocumentResult remove(JSONValue value) {
		auto uuid = value["_id"].str;
		auto revision = value["_rev"].str;
		auto http = curl.HTTP(_documentPath(uuid) ~ "?rev=" ~ revision);
		http.method = curl.HTTP.Method.del;
		ubyte[] data;
		http.onReceive = (chunk) {
			data ~= chunk;
			return chunk.length;
		};
		http.perform;
		return DocumentResult(parseJSON(cast(string)data));
	}

	/**
		* Get the document stored in the database with the given ID.
		*/
	JSONValue get(string uuid) {
		return parseJSON(curl.get(_documentPath(uuid)));
	}

	/**
		* Create this database.
		*/
	JSONValue createDatabase() {
		return parseJSON(curl.put(_client.uri ~ "/" ~ _name, []));
	}

	/**
		* Delete this database.
		*/
	JSONValue deleteDatabase() {
		auto http = curl.HTTP(_client.uri ~ "/" ~ _name);
		http.method = curl.HTTP.Method.del;
		ubyte[] data;
		http.onReceive = (chunk) {
			data ~= chunk;
			return chunk.length;
		};
		http.perform;
		return parseJSON(cast(string)data);
	}
}

class CouchClient {
	private string _uri;

	this(string uri) {
		_uri = uri;
	}

	@property string uri() nothrow pure {
		return _uri;
	}

	void ensure(string name) {
		curl.put(_uri ~ "/" ~ name, []);
	}

	string[] databases() {
		auto s = curl.get(_uri ~ "/_all_dbs");
		auto j = parseJSON(s).array;
		auto dbNames = new string[j.length];
		foreach (i, name; j) {
			dbNames[i] = name.str;
		}
		return dbNames;
	}

	/**
		* Get the named database.
		*
		* This doesn't check for the existence of the database. Good luck!
		*/
	CouchDatabase opIndex(string name)
	in {
		assert(name, "name is required");
	}
	body {
		return new CouchDatabase(this, name);
	}
}
