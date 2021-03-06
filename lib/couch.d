module couch;

import url;

import std.algorithm;
import std.conv : to;
import std.json;
import std.string : format;
import std.uuid;

// std.json is unsafe until about 2.072.0. Until then, @trusted everything!
//@safe:
@trusted:

/**
 * A Transport is an HTTP client used for communication with CouchDB.
 */
interface Transport
{
    /// Peform an HTTP GET request.
    string get(URL url);
    /// Peform an HTTP PUT request.
    string put(URL url, string contents);
    /// Peform an HTTP DELETE request.
    string delete_(URL url, string contents = "");
}

class CurlTransport : Transport
{
    import curl = std.net.curl;

    string get(URL url)
    {
        return perform(url, "", curl.HTTP.Method.get);
    }

    string put(URL url, string contents)
    {
        return perform(url, contents, curl.HTTP.Method.put);
    }

    string delete_(URL url, string contents = "")
    {
        return perform(url, contents, curl.HTTP.Method.del);
    }

    private string perform(URL url, string contents, curl.HTTP.Method method) @trusted
    {
        import std.array;

        auto c = curl.HTTP(url.toString);
        c.method = method;
        Appender!string output;
        size_t sent = 0;
        c.onSend = (buf) {
            if (contents.length <= sent)
            {
                return 0;
            }
            auto len = contents.length - sent;
            if (len > buf.length)
            {
                len = buf.length;
            }
            buf[0 .. len] = cast(void[]) contents[sent .. sent + len];
            sent += len;
            return len;
        };
        c.onReceive = (x) { output ~= cast(char[]) x; return x.length; };
        auto code = c.perform(curl.ThrowOnError.no);
        if (code != 0)
        {
            throw new CouchException(
                format("Request failed. Error code: %d. Response:\n%s", code, output.data));
        }
        if (c.statusLine.code >= 300)
        {
            throw new CouchException(
                format("Request failed. Error code: %d. Reason: %s. Response:\n%s",
                c.statusLine.code, c.statusLine.reason, output.data));
        }
        return cast(string) output.data;
    }
}

/// An error code describing a Couch issue.
enum CouchErrorCode
{
    None,
    Unknown,
    NotFound,
    InvalidDocument,
    UnexpectedType,
    MissingProperty
}

/// An exception thrown when the CouchDB client is misused.
class CouchError : Error
{
public:
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}

/// An exception thrown when we have troubles with CouchDB.
class CouchException : Exception
{
private:
    CouchErrorCode _error;

public:
    this(string msg, CouchErrorCode error = CouchErrorCode.Unknown,
        string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
        _error = error;
    }

    @property CouchErrorCode error() pure nothrow const
    {
        return _error;
    }

    override string toString() const
    {
        return format("%s: %s", this.error.to!string, this.msg);
    }

}

/// A struct representing the result of manipulating a document.
struct DocumentResult
{
    /// The document ID.
    string id;
    /// The document revision.
    string revision;
    /// Whether the operation succeeded.
    bool ok;

    this(JSONValue value)
    {
        id = value["id"].str;
        revision = value["rev"].str;
        ok = value["ok"].type == JSON_TYPE.TRUE;
    }
}

/// Order for db query results.
enum Order
{
    /// Ordered lowest to highest, eg [1, 2, 3, 4, 5]. Default.
    Ascending,

    /// Ordered highest to lowest, eg [5, 4, 3, 2, 1].
    Descending,
}

/**
  * A view is an index. It's defined within the context of a design document.
  *
  * Views are defined by the view function, which maps a document to a value and a weight.
  * For many purposes, you can ignore the weight element and simply set it to a constant, such as 1.
  *
  * Once you have defined a view, you can query for documents according to the values your function
  * emitted for them.
  *
  * Example view function:
  * ---
  * // view 'ingredients' in design doc 'recipes'
  * function (doc) {
  *   if (doc.type == 'recipe') {
  *     doc.ingredients.forEach(function(ingredient) {
  *       emit(ingredient.name, 1);
  *     })
  *   }
  * }
  * ---
  *
  * Then we can use this to find all recipes using hartshorn:
  * ---
  * auto view = connection.db("recipes").designDoc("recipes").view("ingredients");
  * foreach (recipe; view.query({key: "hartshorn"})) {
  *   writeln(recipe["name"].str);
  * }
  * ---
  *
  * And that will show us a selection of cookies and pancakes from Scandinavia.
  */
class View
{
    private DesignDoc _doc;
    private string _name;

    /** The map function that defines this view. */
    string map;
    /** The reduce function that defines this view. */
    string reduce;

    this(DesignDoc doc, string name)
    {
        _doc = doc;
        _name = name;
    }

    /**
	  * List items in this view using the named, predefined list function.
	  *
	  * List functions are arbitrary transformations on a document that yield strings.
	  *
	  * Params:
	  *   listName = The name of the list function to use. It must be already saved in this design
	  *              document.
	  *   options  = Query options; see the QueryOptions struct documentation for details.
	  * Returns:
	  *   A CouchImplicitlyPaginatedRange whose values are string JSONValues.
	  */
    CouchImplicitlyPaginatedRange list(string listName, QueryOptions options)
    {
        auto url = _doc.url;
        url.path ~= format("/_list/%s/%s", listName, _name);
        options.addQueryParameters(url);
        auto transport = _doc.db.client.transport;
        assert(transport !is null);
        return CouchImplicitlyPaginatedRange(url, transport, options.startKey);
    }

    /**
	  * Query results from this view.
	  *
	  * This yields documents included in this view as JSONValues.
	  *
	  * Params:
	  *   options = Query options; see the QueryOptions struct documentation for details.
	  */
    CouchImplicitlyPaginatedRange query(QueryOptions options = QueryOptions.init)
    {
        auto url = _doc.url;
        url.path ~= format("/_view/%s", _name);
        options.addQueryParameters(url);
        auto transport = _doc.db.client.transport;
        assert(transport !is null);
        return CouchImplicitlyPaginatedRange(url, transport, options.startKey);
    }

    JSONValue toJSON()
    {
        JSONValue v;
        if (map)
        {
            v["map"] = map;
        }
        if (reduce)
        {
            v["reduce"] = reduce;
        }
        return v;
    }
}

/**
  * Options for executing a query.
  *
  * This controls what subset of a database or view you retrieve, the order of traversal, and so
  * forth.
  */
struct QueryOptions
{
    /// The sole key to get results for. Assumes startKey is null.
    string key = null;

    /// The first key to get results for. Assumes key is null.
    string startKey = null;

    /// The order to scan through documents in.
    Order order = Order.Ascending;

    /** The maximum number of results to fetch, or ulong.max for unlimited.
	  * If you have more than 2**64-1 documents that you wish to scan, you have other problems.
	  */
    ulong limit = ulong.max;

    /** The number of results to retrieve per page.
	  * Pagination is hidden; this is a performance option.
	  */
    ulong resultsPerPage = 100;

    /** Whether to include full documents in contexts that would not normally include them.
	  *
	  * When querying a view, for instance, the default is to return only the final results of the
	  * view. For a typical map-only view, for instance, this will be tuples consisting of the keys
	  * and values you emitted and a special field "id", indicating the ID of the relevant document.
	  */
    bool includeDocuments;

    package void addQueryParameters(ref URL url) const
    {
        if (key != "" && startKey != "")
        {
            throw new CouchError(
                "Your query options specified both 'key' and 'startKey', but these " ~ "options are mutually exclusive. startKey indicates that the query will take keys " ~ "starting at the given value and continuing onward, while key indicates that the query " ~ "will take keys only of the given value. You probably want to specify only the 'key' " ~ "field.");
        }
        url.queryParams.overwrite("limit", min(resultsPerPage + 1, limit).to!string);
        url.queryParams.overwrite("descending", (order == Order.Descending).to!string);
        if (key != "")
        {
            url.queryParams.overwrite("key", key);
        }
        if (startKey != "")
        {
            url.queryParams.overwrite("startKey", startKey);
        }
        if (order != Order.Ascending)
        {
            url.queryParams.overwrite("descending", "true");
        }
        if (includeDocuments)
        {
            url.queryParams.overwrite("include_docs", "true");
        }
    }
}

/**
  * A range over database values. It is paginated but does not expose pagination to end users.
  *
  * Because it is possible to modify the database while iterating, it is possible that `.empty` will
  * return false but `.popFront` will fail to retrieve any results (and throw a RangeError).
  */
struct CouchImplicitlyPaginatedRange
{
    private
    {
        URL url;
        Transport transport;
        JSONValue[] currentPage;
        ulong totalResults;
        string nextResultKey;
        string nextResultDocID;
        int resultInCurrentPage;
        bool inLastPage = false;
        ulong resultsReturned;
        ulong maxResults;
    }

    package this(URL base, Transport transport, string startKey = null, ulong maxResults = ulong.max)
    in
    {
        assert(transport !is null);
    }
    body
    {
        url = base;
        this.transport = transport;
        nextResultKey = startKey;
        loadNextPage;
        this.maxResults = maxResults > 0 ? maxResults : ulong.max;
    }

    ///
    typeof(this) save()
    {
        auto other = this;
        return other;
    }

    ///
    JSONValue front() const
    {
        return currentPage[resultInCurrentPage];
    }

    ///
    JSONValue popFront()
    {
        // We loaded K + 1 results for the page when we actually want K results per page. The +1 is just
        // for fast pagination. Except on the last page, we need to include it.
        if (!inLastPage && resultInCurrentPage + 1 >= currentPage.length)
        {
            loadNextPage();
        }
        resultsReturned++;
        auto value = currentPage[resultInCurrentPage];
        resultInCurrentPage++;
        return value;
    }

    ///
    bool empty() const
    {
        return inLastPage && (resultInCurrentPage >= currentPage.length
            || resultsReturned >= maxResults);
    }

    /** The total number of results in this query.
	  *
	  * If documents relevant to this query are modified during iteration, this value might change.
	  * For instance, if this query is searching for recipes that use hartshorn and someone adds a new
	  * one after you load the first page of results, when you load the second page, you will see
	  * numResults updated to reflect the new document.
	  *
	  * This may be larger than the limit you provided. In that case, this range will only be over the
	  * amount you specified, but you could provide a larger limit in order to fetch more.
	  */
    @property long numResults() const
    {
        return totalResults;
    }

    private void loadNextPage()
    {
        resultInCurrentPage = 0;
        if (nextResultKey.length > 0)
        {
            url.queryParams.overwrite("startkey", nextResultKey);
        }
        if (nextResultDocID.length > 0)
        {
            url.queryParams.overwrite("startkey_docid", nextResultDocID);
        }
        auto doc = transport.get(url).parseJSON;
        // We update this every time because it might have changed.
        totalResults = doc["total_rows"].integer;
        currentPage = doc["rows"].array;
        inLastPage = doc["offset"].integer + currentPage.length >= totalResults;
        if (currentPage.length == 0)
        {
            nextResultDocID = null;
            nextResultKey = null;
        }
        else
        {
            auto last = currentPage[$ - 1];
            nextResultDocID = last["id"].str;
            nextResultKey = last["key"].str;
        }
    }
}

/**
  * A DesignDoc is a collection of indices, stored queries, and materialized views.
  *
  * In a normal relational database, you can issue arbitrary queries, and the database will execute
  * them immediately. It will use an index if it can and will otherwise scan your entire database.
  * This can, naturally, be rather slow.
  *
  * In CouchDB, in order to prevent slow queries from happening, you are not allowed to execute
  * queries directly. Instead, you must create a design document containing that query. CouchDB will
  * create and maintain an index for it.
  *
  * You can do pretty much anything you want inside these (much like SQL, but with some of the
  * antipatterns further enshrined). While people joke about websites run directly from SQL
  * databases and stored procedures, that is much easier to achieve using CouchDB design documents.
  */
class DesignDoc
{
    private CouchDatabase _db;
    private string _name;
    private URL _url;

    /**
	  * Create a design document.
	  *
	  * Params:
	  *   db   = The database this design document applies to.
	  *   name = The name of this design document. Names must be unique within a database.
	  */
    this(CouchDatabase db, string name)
    {
        _db = db;
        _name = name;
        _url = _db.url;
        _url.path ~= "/_design/" ~ name;
    }

    /// The database this design doc applies to.
    @property CouchDatabase db() nothrow pure
    {
        return _db;
    }

    /// The name of this design doc.
    @property string name() nothrow pure
    {
        return _name;
    }

    URL url()
    {
        return _url;
    }

    View createView(string name, string map = null, string reduce = null)
    {
        if (name in views)
        {
            throw new CouchError("The view " ~ name ~ " already exists, and you are adding it again.");
        }
        auto view = new View(this, name);
        view.map = map;
        view.reduce = reduce;
        views[name] = view;
        return view;
    }

    /** Save this DesignDoc to the database.
	  *
	  * You *must* call this before using the related views.
	  */
    void save()
    {
        import std.stdio;

        auto js = this.toJSON;
        writeln("saving to ", url, " design doc: ", js);
        _db.client.transport.put(url, js);
    }

    string toJSON()
    {
        JSONValue value;
        value["language"] = "javascript";
        JSONValue views;
        foreach (k, v; this.views)
        {
            views[k] = v.toJSON;
        }
        value["views"] = views;
        return value.toString;
    }

    /**
	  * A collection of filter functions this view uses.
	  *
	  * Filters, obviously, filter out documents to determine which ones this view can show.
	  * For instance, if you have a site for recipes and want to quickly show which recipes call for
	  * quail's eggs, you can write a filter that checks a recipe document for its ingredients.
	  *
	  * See http://docs.couchdb.org/en/1.6.1/couchapp/ddocs.html for details.
	  */
    string[string] filters;

    /**
	  * A collection of show functions this view uses.
	  *
	  * A show function is a mapping from a database document to a document that the view will return.
	  * For instance, if have a blog and want to show a blurb about post N-1 from post N, you can use
	  * a show to grab just that blurb.
	  *
	  * A show function operates on just one document.
	  *
	  * See http://docs.couchdb.org/en/1.6.1/couchapp/ddocs.html for details.
	  */
    string[string] shows;

    /**
	  * A collection of list functions this view uses.
	  *
	  * A list function is a mapping from a database document to a document that the view will return.
	  * For instance, if you have a site for recipes and want to quickly show a brief description of
	  * each recipe along with a link from the search page, your show function can yield just the
	  * first few words of the description and the URL, meaning the database doesn't have to send as
	  * much to you.
	  *
	  * List is much like show, but it queries across documents that the view will yield.
	  *
	  * See http://docs.couchdb.org/en/1.6.1/couchapp/ddocs.html for details.
	  */
    string[string] lists;

    /**
	  * A collection of update functions this view uses.
	  *
	  * An update function mutates the database -- either by updating existing documents, by creating
	  * new ones, or deleting existing ones.
	  *
	  * See http://docs.couchdb.org/en/1.6.1/couchapp/ddocs.html for details.
	  */
    string[string] updates;

    View[string] views;
}

/**
  * A CouchDB database.
  *
  * This represents a single named database within a CouchDB instance.
  */
class CouchDatabase
{
    private string _name;
    package CouchClient client;
    private URL _url;

    private URL _documentPath(string uuid)
    {
        return _url ~ uuid;
    }

    package this(CouchClient client, string name)
    {
        this.client = client;
        _name = name;
        _url = client.url ~ _name;
    }

    package URL url()
    {
        return _url;
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
    DocumentResult create(UUID uuid, ref JSONValue value)
    {
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
    DocumentResult create(string uuid, ref JSONValue value)
    {
        auto response = cast(string) client.transport.put(_documentPath(uuid), value.toString);
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
    DocumentResult create(ref JSONValue value)
    {
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
    DocumentResult update(JSONValue value)
    {
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
    DocumentResult remove(JSONValue value)
    {
        auto uuid = value["_id"].str;
        auto url = _documentPath(uuid);
        url.query["rev"] = value["_rev"].str;
        url.queryParams.overwrite("rev", value["_rev"].str);
        return DocumentResult(parseJSON(client.transport.delete_(url)));
    }

    /**
	  * Get the document stored in the database with the given ID.
	  */
    JSONValue get(string uuid)
    {
        return parseJSON(client.transport.get(_documentPath(uuid)));
    }

    /**
		* Get all documents in the database.
		*
		* Params:
		*   options = the QueryOptions for this query.
		* Returns:
		*   A range over the documents in the database.
		*/
    CouchImplicitlyPaginatedRange allDocs(QueryOptions options = QueryOptions.init)
    {
        auto u = this.url;
        u.path ~= "_all_docs";
        options.addQueryParameters(u);
        auto transport = client.transport;
        assert(transport !is null);
        return CouchImplicitlyPaginatedRange(u, transport, options.startKey);
    }

    /**
	  * Create this database.
	  */
    JSONValue createDatabase()
    {
        return parseJSON(client.transport.put(client.url ~ _name, ""));
    }

    /**
	  * Delete this database.
	  */
    JSONValue deleteDatabase()
    {
        return parseJSON(client.transport.delete_(client.url ~ _name));
    }
}

/**
  * CouchClient is a logical CouchDB connection.
  *
  * To start with, you create a CouchClient. Then you use that to access databases.
  */
class CouchClient
{
    private URL _url;
    private Transport _transport;

    ///
    this(string url)
    {
        _url = url.parseURL;
    }

    ///
    this(URL url)
    {
        _url = url;
    }

    package @property URL url() nothrow pure
    {
        return _url;
    }

    /**
		* Select the transport that will be used to make requests to the Couch database.
		*
		* The default is to use std.net.curl. You can substitute another to use, for instance, vibe.d as
		* the HTTP transport system.
		*/
    @property Transport transport(Transport value)
    in
    {
        assert(value !is null);
    }
    body
    {
        _transport = value;
        return _transport;
    }

    package @property Transport transport() 
    out (result)
    {
        assert(result !is null);
    }
    body
    {
        if (_transport is null)
        {
            _transport = new CurlTransport;
        }
        return _transport;
    }

    /// Ensure that there exists a database with the given name.
    void ensure(string name)
    {
        transport.put(_url ~ name, "");
    }

    /// List databases in this CouchDB instance.
    string[] databases()
    {
        auto s = transport.get(_url ~ "/_all_dbs");
        auto j = parseJSON(s).array;
        auto dbNames = new string[j.length];
        foreach (i, name; j)
        {
            dbNames[i] = name.str;
        }
        return dbNames;
    }

    /**
	  * Get the named database.
	  *
	  * This doesn't check for the existence of the database.
	  */
    CouchDatabase database(string name)
    in
    {
        assert(name, "name is required");
    }
    body
    {
        return new CouchDatabase(this, name);
    }
}
