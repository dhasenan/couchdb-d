module couched;
import heaploop.networking.http;
import http.parser.core;
import std.conv : to;
import std.stdio : writeln;
import std.string : format;
import std.exception : enforceEx;
import medea;

private:

void checkResponse(ObjectValue resp, string file = __FILE__, size_t line = __LINE__) {
        StringValue errorValue;
        if("error" in resp) {
            errorValue = cast(StringValue)resp["error"];
        }
        if(errorValue) {
            string errorString = errorValue.text;
            string reasonString;
            StringValue reasonValue;
            if("reason" in resp) { 
                reasonValue = cast(StringValue)resp["reason"];
            }
            if(reasonValue) {
                reasonString = reasonValue.text;
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
/*
void checkJSONType(string source, JSON_TYPE type)(ref const JSONValue value, string file = __FILE__, size_t line = __LINE__) {
    if(value.type != type) {
        throw new CouchedException(source ~ " is not of type JSON_TYPE." ~ type.to!string, CouchedError.UnexpectedType, file, line);
    }
}

JSONValue getJSONProperty(string source, string propertyName, JSON_TYPE type)(ref const JSONValue value, string file = __FILE__, size_t line = __LINE__) {
    value.checkJSONType!(source, JSON_TYPE.OBJECT)(file, line);
    if(propertyName !in value.object) {
        throw new CouchedException(source ~ " is missing property " ~ propertyName, CouchedError.MissingProperty, file, line);
    }
    JSONValue prop = value.object[propertyName];
    prop.checkJSONType!(propertyName, JSON_TYPE.STRING)(file, line);
    return prop;
}
*/
public:

enum CouchedError {
    None,
    Unknown,
    NotFound,
    InvalidDocument,
    UnexpectedType,
    MissingProperty
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
        ObjectValue update(ObjectValue value) {
            if(!value) {
                throw new CouchedException("Can't update null document", CouchedError.InvalidDocument);
            }
            string uuid;
            if("_id" in value) {
                StringValue idValue = cast(StringValue)value["_id"];
                uuid = idValue.text;
            } else {
                throw new CouchedException("document doesn't contain _id property", CouchedError.InvalidDocument);
            }
            return create(uuid, value);
        }

        ObjectValue create(string uuid, ObjectValue value) {
           string valueText = value.toJSONString;
           ubyte[] valueData = cast(ubyte[])valueText;
           auto content = new UbyteContent(valueData);
           auto response = _client._client.put(_documentPath(uuid), content);
           ubyte[] data;
           response.read ^= (chunk) {
               data ~= chunk.buffer;
           };
           string res = cast(string)data;
           ObjectValue resp = cast(ObjectValue)res.parse;
           resp.checkResponse();
           value["_rev"] = resp["rev"];
           value["_id"] = resp["id"];
           return resp;
        }

        ObjectValue delete_(ObjectValue value) {
           if(!!value) {
               throw new CouchedException("Can't update null document", CouchedError.InvalidDocument);
           }
           StringValue uuidObject = cast(StringValue)value["_id"];
           string uuid = uuidObject.text;

           StringValue revIdObject = cast(StringValue)value["_rev"];
           string revId = revIdObject.text;

           auto response = _client._client.send("DELETE", _documentPath(uuid) ~ "?rev=" ~ revId);
           ubyte[] data;
           response.read ^= (chunk) {
               data ~= chunk.buffer;
           };
           string res = cast(string)data;
           ObjectValue resp = cast(ObjectValue)res.parse;
           resp.checkResponse();
           return resp;
        }

        ObjectValue get(string uuid) {
            auto response = _client._client.get(_documentPath(uuid));
            ubyte[] data;
            response.read ^= (chunk) {
                data ~= chunk.buffer;
            };
            string res = cast(string)data;
            ObjectValue resp = cast(ObjectValue)res.parse;
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
