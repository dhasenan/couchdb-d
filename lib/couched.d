module couched;
import heaploop.networking.http;
import http.parser.core;
import std.conv : to;
import std.stdio : writeln;
import std.string : format;
import std.json;

private:

void checkResponse(const ref JSONValue resp, string file = __FILE__, size_t line = __LINE__) {
    if(resp.type == JSON_TYPE.OBJECT) {
        JSONValue errorValue;
        if("error" in resp.object) {
            errorValue = resp.object["error"];
        }
        if(errorValue != JSONValue.init && errorValue.type == JSON_TYPE.STRING) {
            string errorString = errorValue.str;
            string reasonString;
            JSONValue reasonValue;
            if("reason" in resp.object) { 
                reasonValue = resp.object["reason"];
            }
            if(reasonValue != JSONValue.init && reasonValue.type == JSON_TYPE.STRING) {
                reasonString = reasonValue.str;
            }
            CouchedError error;
            switch(errorString) {
                case "not_found":
                    error = CouchedError.NotFound;
                    break;
                default:
                    error = CouchedError.Unknown;
                    break;
            }
            throw new CouchedException("%s: %s".format(errorString, reasonString), error, file, line);
        }
    }
}

public:

enum CouchedError {
    None,
    Unknown,
    NotFound,
    InvalidDocument
}

class CouchedException : Exception
{
    private:
        CouchedError _error;

    public:
        this(string msg, CouchedError error = CouchedError.Unknown, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
            super(msg, file, line, next);
            _error = error;
        }

        @property CouchedError error() pure nothrow {
            return _error;
        }

        override string toString() {
            return std.string.format("%s: %s", this.error.to!string, this.msg);
        }

}

class CouchedDatabaseManager {
    private:
        CouchedClient _client;

    package:
        this(CouchedClient client) {
            _client = client;
        }

    public:
        void ensure(string name) {
            _client._client.put("/" ~ name);
        }

        CouchedDatabase opIndex(string name)
            in {
                assert(name, "name is required");
            }
            body {
                return new CouchedDatabase(_client, name);
            }

            CouchedDatabase opDispatch(string name)()
            {
               return this[name]; 
            }
}

class CouchedDatabase {
    private:
        string _name;
        CouchedClient _client;

        string _documentPath(string uuid) {
            return "/" ~ _name ~ "/" ~ uuid;
        }

    package:
        this(CouchedClient client, string name) {
            _client = client;
            _name = name;
        }
    public:
        JSONValue update(const ref JSONValue value) {
            string uuid;
            if(value.type == JSON_TYPE.OBJECT) {
                if("_id" in value.object) {
                    JSONValue idValue = value.object["_id"];
                    uuid = idValue.str;
                } else {
                    throw new CouchedException("document doesn't contain _id property", CouchedError.InvalidDocument);
                }
            } else {
                throw new CouchedException("document is not object", CouchedError.InvalidDocument);
            }
            return create(uuid, value);
        }

        JSONValue create(string uuid, const ref JSONValue value) {
           string valueText = (&value).toJSON;
           ubyte[] valueData = cast(ubyte[])valueText;
           auto content = new UbyteContent(valueData);
           auto response = _client._client.put(_documentPath(uuid), content);
           ubyte[] data;
           response.read ^ (chunk) {
               data ~= chunk.buffer;
           };
           string res = cast(string)data;
           JSONValue resp = res.parseJSON;
           resp.checkResponse();
           return resp;
        }

        JSONValue get(string uuid) {
            auto response = _client._client.get(_documentPath(uuid));
            ubyte[] data;
            response.read ^ (chunk) {
                data ~= chunk.buffer;
            };
            string res = cast(string)data;
            JSONValue resp = res.parseJSON;
            resp.checkResponse();
            return resp;
        }

        void ensure() {
            _client.databases.ensure(_name);
        }
}

class CouchedClient {
    private:
        Uri _uri;
        CouchedDatabaseManager _databases;

    package:
        HttpClient _client;

    public:
        this(string uri) {
            this(Uri(uri));
        }
        this(Uri uri) {
            _uri = uri;
            _client = new HttpClient(_uri);
            _databases = new CouchedDatabaseManager(this);
        }

        @property {
            Uri uri() nothrow pure {
                return _uri;
            }

            CouchedDatabaseManager databases() nothrow pure {
                return _databases;
            }

        }
}
