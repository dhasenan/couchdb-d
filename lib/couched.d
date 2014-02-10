module couched;
import heaploop.networking.http;
import http.parser.core;
import std.stdio : writeln;
import std.json;

public:

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

    package:
        this(CouchedClient client, string name) {
            _client = client;
            _name = name;
        }
    public:
        JSONValue create(string uuid, const JSONValue * value) {
           string valueText = value.toJSON;
           ubyte[] valueData = cast(ubyte[])valueText;
           auto content = new UbyteContent(valueData);
           auto response = _client._client.put("/" ~ _name ~ "/" ~ uuid, content);
           ubyte[] data;
           response.read ^ (chunk) {
               data ~= chunk.buffer;
           };
           string res = cast(string)data;
           return res.parseJSON;
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
