use Cro::HTTP::Client;
use Cro::Uri;

class ToshoFeedSearch {

    has $!web-client = Cro::HTTP::Client.new(
                            base-uri => 'https://feed.animetosho.org/json',
                            :http<1.1>,
                            timeout => { connection => 10, headers => 10 });

    method search-for(Str $query --> Int) {
        my $num-retries = 5;
        while ($num-retries > 0) {
            say "Searching for: $query";
            my $response = await $!web-client.get('', query => { q => $query });
            say "Search response { $response.status }";

            my @results = await $response.body();
            if @results.elems > 1 {
                say "There were { @results.elems } results:";
                for @results -> $result {
                    say "{ $result<id> }: { $result<title> }"
                }
                return;

            } elsif @results.elems == 0 {
                note "No results for \"$query\"";
                return;

            } else {
                return @results[0]<id>.Int;
            }

            CATCH {
                when X::Cro::HTTP::Client::Timeout {
                    $*ERR.say: "***** Timeout when searching for \"$query\": $_";
                    $num-retries--;
                    redo;
                }
                default {
                    $*ERR.say: "*** Exception { $_.^name } when searching for \"$query\": $_";
                    last;
                }
            }
        }
    }
}

