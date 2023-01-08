class ToshoFeedFile {
    has Str $.filename is required;
    has Str $.md5 is required;
    has Str @.zippy-share-urls is required;
}

class ToshoFeedEntry {
    has Str $.tosho-id is required;
    has Str $.name is required;
    has Str $.status is required;  # processing, complete
    has ToshoFeedFile @.files;

    #method new-from-feed(%item --> ToshoFeedEntry) {
    #    my @files = %item<files>
    #    self.new(   tosho-id    => %item<tosho_id>,
    #                name        => %item<title>,
    #                status      => %item<status>,
    #}

    method elems { @!files.elems }
    #method urls { @!files.map(*.
}

use Cro::HTTP::Client;
use Cro::Uri;

class X::Tosho::NotFound is Exception { has Str $.name }

my $web-client = Cro::HTTP::Client.new(base-uri => 'https://feed.animetosho.org/json',
                                       timeout => { connection => 10, headers => 10 });

# Look up a tosho torrent id given a title
class TitleToToshoId does Associative {
    my $max-page-tries = 10;

    has Int %!index;
    has Int $!max-id;
    has Int $!min-id;
    has Int $!last-page-retrieved = -1;

    submethod BUILD(:$!max-id = 0, :$!min-id = 0) { }

    submethod TWEAK() {
        self.get-feed-page(1);
    }

    multi method AT-KEY( ::?CLASS:D: Str $name --> Int) {
        say "Looking up ID for name $name...";
        my $page-tries = $max-page-tries;
        my $page = $!last-page-retrieved == 1 ?? 2 !! $!last-page-retrieved;

        # This is not thread-safe yet, but it should be ok as long
        # as it's only used from the user-input loop
        if not %!index{$name}:exists {
            say "    Refreshing feed page 1...";
            self.get-feed-page(1);
            while (not %!index{$name}:exists) and ($page-tries-- > 0) {
                say "    Refreshing feed page $page...";
                self.get-feed-page($page++);
            }
        }
        say "    Done refreshing feed";

        X::Tosho::NotFound.new(:$name).throw if not %!index{$name}:exists;
            
        %!index{$name};
    }

    method get-feed-page(Int $page) {
        my $num-retries = 5;
        my $success = False;

        while $num-retries > 0 {
            #my $url = Cro::Uri.parse($page == 1 ?? $base-url !! $base-url ~ "?page=$page");

            say "Updating from feed page $page";
            my $response = await ( $page == 1 ?? $web-client.get('') !! $web-client.get('', query => { page => $page }) );
            say "Feed page $page { $response.request.uri } response { $response.status }";

            my $data = await $response.body();

            for @$data -> $item {
                say "  $item<title> => $item<id>";
                %!index{$item<title>} = $item<id>;
            }

            $!last-page-retrieved = $page if $page > $!last-page-retrieved;

            CATCH {
                when X::Cro::HTTP::Client::Timeout {
                    $*ERR.say: "***** Timeout when getting feed page { $page }: $_";
                    $num-retries--;
                    redo;
                }
                default {
                    $*ERR.say: "*** Exception when refreshing feed page $page, was a { $_.^name }", $_;
                    last;
                }
            }

            return;
        }
    }
}
