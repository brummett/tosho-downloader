use Cro::HTTP::Client;
use Cro::Uri;


# Look up a tosho torrent id given a title from the raw/linear JSON feed API
class ToshoFeed  {
    has $web-client = Cro::HTTP::Client.new(base-uri => 'https://feed.animetosho.org/json',
                                            :http<1.1>,
                                            timeout => { connection => 10, headers => 10 });
    has Int %!index;
    has Int $!max-id;
    has Int $!min-id;
    has Int $!last-page-retrieved = -1;

    submethod BUILD(:$!max-id = 0, :$!min-id = 0) { }

    submethod TWEAK() {
        self.get-feed-page(1);
    }

    method search-for(Str $name --> Int) {
        say "Looking up ID for name $name...";
        my $page-tries = 10;
        my $page = $!last-page-retrieved == 1 ?? 2 !! $!last-page-retrieved;

        # This is not thread-safe yet, but it should be ok as long
        # as it's only used from the user-input loop
        if not %!index{$name}:exists {
            say "    Refreshing feed page 1...";
            self.get-feed-page(1);
            until (%!index{$name}:exists) or ($page-tries-- <= 0) {
                say "    Refreshing feed page $page...";
                self.get-feed-page($page++);
            }
        }
        say "    Done refreshing feed";

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
                %!index{$item<title>} = $item<id>;
            }
            say "    { $data.elems } items";

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

