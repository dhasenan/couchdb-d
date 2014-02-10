import heaploop.looping;
import couched;
import std.json;
import std.stdio : writeln;

void main() {
    loop ^^ {
        auto client = new CouchedClient("http://127.0.0.1:5984");
        CouchedDatabase db = client.databases.albums;
        db.ensure();

        JSONValue album = parseJSON(q{
            {
                "name": "HurryUp, We're Dreaming",
                "artist_name": "M83"        
            }
        });
        JSONValue response = db.create("hurryup-m83", &album);
        writeln("create response: ", toJSON(&response));
    };
}
