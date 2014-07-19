import heaploop.looping;
import couched;
import std.stdio : writeln;
import std.algorithm;
import medea;

void main(string[] args) {
    loop ^^= {
        auto client = new CouchedClient("http://127.0.0.1:5984");
        CouchedDatabase db = client.databases.albums;
        db.ensure();

        bool shouldUpdate = true;
        ObjectValue existingAlbum;
        try {
            existingAlbum = db.get("hurryup-m83");
            writeln("Album already exists");
        } catch(CouchedException cex) {
            if(cex.error == CouchedError.NotFound) {
                shouldUpdate = false;
                writeln("Album doesn't exists");
            } else {
                throw cex;
            }
        }
        if(shouldUpdate) {
            writeln("Updating");
            ObjectValue response = db.update(existingAlbum);
            writeln("update response: ", response.toJSONString());
        } else {
            writeln("creating");
            ObjectValue album = cast(ObjectValue)parse(q{
                {
                    "name": "HurryUp, We're Dreaming",
                    "artist_name": "M83"        
                }
            });
            ObjectValue response = db.create("hurryup-m83", album);
            writeln("create response: ", response.toJSONString());
        }
        writeln("Optional Behavior");
        if(args.canFind("deleting")) {
            db.delete_(existingAlbum);
            writeln("Deleted");
        }
    };
}
